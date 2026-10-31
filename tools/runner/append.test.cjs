'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { appendPipeline, workspacePath } = require('./append.cjs');
const { hash, PipelineRunner } = require('./pipeline.cjs');
const { atomicJson, createStore } = require('./io.cjs');
const { acquireSingleton } = require('./resident.cjs');
const stage = (id, participants = ['NightShift-Test']) => ({ id, name: id, chatName: `NightShift-${id}`, participants, promptFile: 'prompt.txt', completionMarker: `[STAGE_READY:${id.toUpperCase()}]`, requiredFiles: [`${id}.md`] });
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'nightshift-append-'));
  t.after(() => { assert.ok(path.resolve(root).startsWith(path.resolve(os.tmpdir()) + path.sep)); fs.rmSync(root, { recursive: true }); });
  const directory = path.join(root, '.setup/runner'); fs.mkdirSync(directory, { recursive: true }); fs.mkdirSync(path.join(root, 'tools'));
  const manifest = { version: 1, stages: [stage('build', ['NightShift-A', 'NightShift-B', 'NightShift-C'])] };
  const state = { mode: 'resident', status: 'stopped', resumeStatus: 'awaiting-review', stage: 1, stageId: null, chatId: null, checkpoint: null, completed: false, completedStages: [{ id: 'build', files: { 'build.md': { hash: 'recorded' } } }], manifestHash: hash(JSON.stringify(manifest)) };
  const extension = { version: 1, maxWorkers: 2, stages: [stage('competition', ['NightShift-A', 'NightShift-B'])] };
  const manifestFile = path.join(root, 'tools/development-pipeline.json'), stateFile = path.join(directory, 'state.json'), extensionFile = path.join(root, 'extension.json');
  const save = () => { atomicJson(manifestFile, manifest); atomicJson(stateFile, state); atomicJson(extensionFile, extension); };
  save(); fs.writeFileSync(path.join(root, 'prompt.txt'), 'Concrete user-requested feature task.');
  return { root, directory, manifest, state, extension, manifestFile, stateFile, extensionFile, save, append: options => appendPipeline({ root, extensionFile, port: 0, ...options }) };
}
test('append preserves historical 3-worker stages and evidence, sets ready at the same index, and backs up exact originals', async t => {
  const f = fixture(t), manifestText = fs.readFileSync(f.manifestFile, 'utf8'), stateText = fs.readFileSync(f.stateFile, 'utf8');
  const result = await f.append();
  const manifest = JSON.parse(fs.readFileSync(f.manifestFile)), state = JSON.parse(fs.readFileSync(f.stateFile));
  assert.deepEqual(manifest.stages[0], f.manifest.stages[0]); assert.equal(manifest.maxWorkers, 2);
  assert.deepEqual(manifest.stages.map(s => s.id), ['build', 'competition']);
  assert.equal(state.stage, 1); assert.equal(state.stageId, 'competition'); assert.equal(state.status, 'ready'); assert.equal(state.resumeStatus, null);
  assert.deepEqual(state.completedStages, f.state.completedStages); assert.equal(state.checkpoint, null); assert.equal(state.manifestHash, hash(JSON.stringify(manifest)));
  assert.equal(fs.readFileSync(path.join(result.backupDirectory, 'manifest.json'), 'utf8'), manifestText);
  assert.equal(fs.readFileSync(path.join(result.backupDirectory, 'state.json'), 'utf8'), stateText);
  assert.equal(state.appendBackup, result.backupDirectory);
  assert.deepEqual(fs.readFileSync(path.join(f.directory, 'events.jsonl'), 'utf8').trim().split('\n').map(line => JSON.parse(line).kind), ['pipeline-append-prepared', 'pipeline-appended']);
  await assert.rejects(f.append(), /stopped/);
});
for (const [name, mutate, pattern] of [
  ['running status', f => { f.state.status = 'running'; }, /stopped/],
  ['wrong stop origin', f => { f.state.resumeStatus = 'running'; }, /awaiting-review/],
  ['incomplete index', f => { f.state.stage = 0; }, /every existing stage/],
  ['missing completion record', f => { f.state.completedStages = []; }, /every existing stage/],
  ['wrong completion record', f => { f.state.completedStages[0].id = 'other'; }, /every existing stage/],
  ['in-flight checkpoint', f => { f.state.checkpoint = { phase: 'sent' }; }, /no in-flight/],
  ['hash mismatch', f => { f.state.manifestHash = 'wrong'; }, /hash mismatch/],
  ['duplicate existing id', f => { f.extension.stages[0].id = 'build'; }, /Invalid stage/],
  ['new stage exceeds cap', f => { f.extension.stages[0].participants.push('NightShift-C'); }, /exceeds maxWorkers 2/],
  ['invalid cap', f => { f.extension.maxWorkers = 5; }, /Invalid maxWorkers/],
  ['five participants', f => { f.extension.maxWorkers = 4; f.extension.stages[0].participants = ['NightShift-A', 'NightShift-B', 'NightShift-C', 'NightShift-D', 'NightShift-E']; }, /Invalid participants/],
  ['prompt escapes workspace', f => { f.extension.stages[0].promptFile = '../outside.txt'; }, /escapes/],
  ['output escapes workspace', f => { f.extension.stages[0].requiredFiles = ['../outside.md']; }, /escapes/],
  ['empty extension', f => { f.extension.stages = []; }, /Invalid extension/],
  ['extension cannot overwrite old stages', f => { f.extension.overwrite = true; }, /Invalid extension/]
]) {
  test(`append rejects ${name} without changing either live file`, async t => {
    const f = fixture(t); mutate(f); f.save();
    const before = [f.manifestFile, f.stateFile].map(file => fs.readFileSync(file, 'utf8'));
    await assert.rejects(f.append(), pattern);
    assert.deepEqual([f.manifestFile, f.stateFile].map(file => fs.readFileSync(file, 'utf8')), before);
    assert.equal(fs.existsSync(path.join(f.directory, 'backups')), false);
  });
}
test('append rejects a live resident socket and leftover PID file', async t => {
  const f = fixture(t), resident = await acquireSingleton(0);
  try { await assert.rejects(f.append({ port: resident.address().port }), error => error.code === 'EADDRINUSE'); }
  finally { await new Promise(resolve => resident.close(resolve)); }
  fs.writeFileSync(path.join(f.directory, 'runner.pid'), '123');
  await assert.rejects(f.append(), /PID file remains/);
});
test('workspace path guard rejects existing junction ancestors outside the root', t => {
  const f = fixture(t), outside = fs.mkdtempSync(path.join(os.tmpdir(), 'nightshift-outside-'));
  t.after(() => { assert.ok(path.resolve(outside).startsWith(path.resolve(os.tmpdir()) + path.sep)); fs.rmSync(outside, { recursive: true }); });
  fs.symlinkSync(outside, path.join(f.root, 'escape'), process.platform === 'win32' ? 'junction' : 'dir');
  assert.throws(() => workspacePath(f.root, 'escape/future.md'), /escapes/);
});
test('a crash between manifest and state writes records backups and blocks all automatic dispatch', async t => {
  const f = fixture(t); let writes = 0;
  await assert.rejects(f.append({ writeJson(file, value) { if (++writes === 2) throw Error('simulated crash'); atomicJson(file, value); } }), /simulated crash; append backups:/);
  const manifest = JSON.parse(fs.readFileSync(f.manifestFile)), state = JSON.parse(fs.readFileSync(f.stateFile));
  assert.notEqual(state.manifestHash, hash(JSON.stringify(manifest)));
  const rows = fs.readFileSync(path.join(f.directory, 'events.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(rows.length, 1); assert.equal(rows[0].kind, 'pipeline-append-prepared');
  assert.ok(fs.existsSync(path.join(rows[0].backupDirectory, 'manifest.json')));
  await assert.rejects(f.append(), /hash mismatch/);
  const runner = new PipelineRunner({ manifest, store: createStore(f.directory), adapter: { list() { assert.fail('must never dispatch/query'); } }, files: {} });
  await runner.tick(); assert.equal(runner.state.status, 'attention'); assert.match(runner.state.reason, /Manifest changed/);
});
for (const limit of [undefined, 2]) {
  test(`omitting maxWorkers preserves existing ${limit ?? 'default three'} limit`, async t => {
    const f = fixture(t); delete f.extension.maxWorkers;
    if (limit !== undefined) f.manifest.maxWorkers = limit;
    f.state.manifestHash = hash(JSON.stringify(f.manifest)); f.save();
    const result = await f.append(); assert.equal(result.maxWorkers, limit ?? 3);
  });
}
test('approved four-worker extension is accepted', async t => {
  const f = fixture(t); f.extension.maxWorkers = 4;
  f.extension.stages[0].participants = ['NightShift-Profiles', 'NightShift-Economy', 'NightShift-Delivery', 'NightShift-World'];
  f.save(); const result = await f.append();
  assert.equal(result.maxWorkers, 4);
  assert.equal(JSON.parse(fs.readFileSync(f.manifestFile)).stages.at(-1).participants.length, 4);
});
