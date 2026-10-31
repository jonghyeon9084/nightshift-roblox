'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { hash, validateManifest } = require('./pipeline.cjs');
const { atomicJson, within } = require('./io.cjs');
const { acquireSingleton, DEFAULT_PORT } = require('./resident.cjs');

// Check the existing ancestor as well as the lexical path, so junctions cannot escape.
function workspacePath(root, relative) {
  if (typeof relative !== 'string' || !relative.trim()) throw Error('Invalid workspace path');
  const file = within(root, relative);
  let ancestor = file;
  for (;;) {
    try { fs.lstatSync(ancestor); break; }
    catch (error) { if (error.code !== 'ENOENT') throw error; ancestor = path.dirname(ancestor); }
  }
  within(root, fs.realpathSync(ancestor));
  return file;
}
const parse = text => JSON.parse(text.replace(/^\uFEFF/, ''));
async function appendPipeline({ root = path.resolve(__dirname, '../..'), extensionFile, port = DEFAULT_PORT, writeJson = atomicJson } = {}) {
  root = fs.realpathSync(root);
  // Same socket as resident.cjs: excludes running residents and simultaneous appends.
  const lock = await acquireSingleton(port);
  let backupDirectory;
  try {
    const directory = workspacePath(root, '.setup/runner');
    if (fs.existsSync(path.join(directory, 'runner.pid'))) throw Error('Runner PID file remains; confirm graceful stop before append');
    const manifestFile = workspacePath(root, 'tools/development-pipeline.json');
    const stateFile = workspacePath(root, '.setup/runner/state.json');
    const manifestText = fs.readFileSync(manifestFile, 'utf8'), stateText = fs.readFileSync(stateFile, 'utf8');
    const manifest = parse(manifestText), state = parse(stateText);
    validateManifest(manifest);
    if (state.manifestHash !== hash(JSON.stringify(manifest))) throw Error('Manifest hash mismatch; manual review of existing backups required');
    if (state.status !== 'stopped' || state.resumeStatus !== 'awaiting-review') throw Error('Append requires graceful stopped/resumeStatus=awaiting-review');
    if (state.stage !== manifest.stages.length || state.checkpoint || state.chatId || state.stageId || !Array.isArray(state.completedStages) || state.completedStages.length !== manifest.stages.length || !manifest.stages.every((stage, index) => state.completedStages[index]?.id === stage.id)) throw Error('Append requires every existing stage completed in order, with no in-flight checkpoint');
    const extension = parse(fs.readFileSync(workspacePath(root, extensionFile), 'utf8'));
    if (!extension || extension.version !== 1 || Object.keys(extension).some(key => !['version', 'maxWorkers', 'stages'].includes(key)) || !Array.isArray(extension.stages) || !extension.stages.length) throw Error('Invalid extension: expected version=1, nonempty stages, optional maxWorkers');
    const nextManifest = { ...manifest, ...(extension.maxWorkers === undefined ? {} : { maxWorkers: extension.maxWorkers }), stages: [...manifest.stages, ...extension.stages] };
    validateManifest(nextManifest);
    const maximum = nextManifest.maxWorkers ?? 3;
    for (const stage of nextManifest.stages) {
      workspacePath(root, stage.promptFile);
      for (const file of stage.requiredFiles) workspacePath(root, file);
    }
    for (const stage of extension.stages) {
      if (stage.adoptExisting) throw Error('Appended stages cannot adopt existing work');
      if (stage.participants.length > maximum) throw Error(`Stage ${stage.id} exceeds maxWorkers ${maximum}`);
      if (!fs.readFileSync(workspacePath(root, stage.promptFile), 'utf8').trim()) throw Error(`Empty stage prompt: ${stage.id}`);
    }
    const at = new Date().toISOString(), appendId = crypto.randomUUID();
    backupDirectory = workspacePath(root, `.setup/runner/backups/append-${appendId}`);
    fs.mkdirSync(backupDirectory, { recursive: true });
    fs.writeFileSync(path.join(backupDirectory, 'manifest.json'), manifestText, { flag: 'wx', mode: 0o600 });
    fs.writeFileSync(path.join(backupDirectory, 'state.json'), stateText, { flag: 'wx', mode: 0o600 });
    const manifestHash = hash(JSON.stringify(nextManifest));
    const details = { appendId, at, backupDirectory, previousManifestHash: state.manifestHash, manifestHash, stages: extension.stages.map(stage => stage.id), maxWorkers: maximum };
    fs.writeFileSync(path.join(backupDirectory, 'append.json'), JSON.stringify(details, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
    const event = kind => fs.appendFileSync(workspacePath(root, '.setup/runner/events.jsonl'), JSON.stringify({ kind, ...details }) + '\n', 'utf8');
    // Backups and recovery location are durable before either live file changes.
    event('pipeline-append-prepared');
    writeJson(manifestFile, nextManifest);
    const nextState = { ...state, status: 'ready', resumeStatus: null, reason: null, pid: null, manifestHash, stageId: extension.stages[0].id, idleSince: null, at, appendBackup: backupDirectory };
    writeJson(stateFile, nextState);
    event('pipeline-appended');
    return details;
  } catch (error) {
    if (backupDirectory) error.message += `; append backups: ${backupDirectory}. Review both files before retry; no automatic recovery`;
    throw error;
  } finally { await new Promise(resolve => lock.close(resolve)); }
}
if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.length !== 1) { console.error('Usage: node tools/runner/append.cjs <extension.json>'); process.exitCode = 1; }
  else appendPipeline({ extensionFile: args[0] }).then(result => console.log(JSON.stringify(result, null, 2))).catch(error => { console.error(error.code === 'EADDRINUSE' ? 'Resident runner or another append owns port 43823; stop gracefully before append' : error.message); process.exitCode = 1; });
}
module.exports = { appendPipeline, workspacePath };
