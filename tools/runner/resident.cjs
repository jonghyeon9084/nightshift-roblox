'use strict';
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { PipelineRunner } = require('./pipeline.cjs');
const { createStore, createFiles, createAdapter, within } = require('./io.cjs');
const { WorkerPool } = require('./pool.cjs');
const DEFAULT_PORT = 43823;
function acquireSingleton(port, listener = (_req, res) => res.end()) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(listener);
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => resolve(server));
  });
}
async function main(options = {}) {
  const root = options.root || path.resolve(__dirname, '../..');
  const manifestFile = options.manifestFile || path.join(root, 'tools/development-pipeline.json');
  const port = options.port ?? DEFAULT_PORT;
  const directory = path.join(root, '.setup/runner');
  let runner, pool, timer, watcher, debounce, stopping = false, ticking = false;
  const server = await acquireSingleton(port, (req, res) => {
    if (![ `127.0.0.1:${port}`, `localhost:${port}` ].includes(req.headers.host) || req.headers.origin) { res.writeHead(403); return res.end(); }
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    if (req.method === 'GET' && req.url === '/health') return res.end(JSON.stringify({ service: 'nightshift-resident-runner', pid: process.pid, root, entry: __filename, state: runner?.state || null, workerPool:pool?.snapshot||null }));
    if (req.method === 'POST' && req.url === '/stop' && req.headers['x-runner-pid'] === String(process.pid)) { res.end(JSON.stringify({ stopping: true, pid: process.pid })); void stop(); return; }
    res.writeHead(404); res.end('{}');
  });
  async function stop() {
    if (stopping) return;
    stopping = true;
    runner?.requestStop();
    pool?.requestStop();
    clearTimeout(timer); clearTimeout(debounce); watcher?.close();
    // Finish an already issued CLI call; never stop its moderator/participants.
    while (ticking || runner?.locked) await new Promise(resolve => setTimeout(resolve, 100));
    try {
      runner?.stop();
      pool?.stop();
      try { fs.unlinkSync(path.join(directory, 'runner.pid')); } catch (e) { if (e.code !== 'ENOENT') console.error(e.message); }
    } catch (error) { console.error(`Stop checkpoint could not be saved: ${error.message}`); }
    finally { server.close(); }
  }
  try {
    fs.mkdirSync(directory, { recursive: true });
    const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8').replace(/^\uFEFF/, ''));
    for (const stage of manifest.stages || []) {
      within(root, stage.promptFile);
      for (const file of stage.requiredFiles || []) within(root, file);
    }
    // Context only: never rewrite the previous automation's status or invoke it.
    try { JSON.parse(fs.readFileSync(path.join(root, 'docs/automation-state.json'), 'utf8').replace(/^\uFEFF/, '')); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    const adapter=createAdapter(root);
    if(fs.existsSync(path.join(root,'tools/worker-pool.json'))){pool=new WorkerPool({root,adapter});pool.refresh();}
    runner = new PipelineRunner({ manifest, store: createStore(directory), files: createFiles(root, directory), adapter: {...adapter,capacityLimit:()=>pool?.config.maxWorkers??4,canDispatch:(stage,chats,chatId)=>pool?.pipelineGuard(stage,chats,chatId)} });
    if (options.resume) { runner.resume();pool?.resume(); }
    runner.save();
    fs.writeFileSync(path.join(directory, 'runner.pid'), String(process.pid));
    runner.event('resident-started', { port, manifestFile });
    let pending = false;
    async function tick() {
      if (stopping) return;
      if (ticking) { pending = true; return; }
      ticking = true;
      clearTimeout(timer);
      try { await pool?.observe();await runner.tick({allowDispatch:false});if(!runner.state.checkpoint&&!['attention','awaiting-review'].includes(runner.state.status)&&!pool?.hasFatal()&&!runner.state.halt)await runner.tick();await pool?.dispatchReady(runner.state); }
      catch (e) { console.error(e.message);if(pool){pool.error=e.message;pool.event('pool-error',{reason:e.message});} }
      finally {
        ticking = false;
        if (!stopping) {
          const urgent = pending; pending = false;
          timer = setTimeout(tick, urgent ? 0 : 2500);
        }
      }
    }
    const transcriptRoot = path.join(process.env.APPDATA, 'maestro/group-chats');
    if (fs.existsSync(transcriptRoot)) {
      try {
        watcher = fs.watch(transcriptRoot, { recursive: true }, (_event, filename) => {
          if (filename && !/(?:history\.jsonl|metadata\.json|chat\.log)$/.test(String(filename))) return;
          clearTimeout(debounce); debounce = setTimeout(tick, 120);
        });
        watcher.on('error', error => { runner.event('watcher-fallback', { reason: error.message }); watcher.close(); });
      } catch (error) { runner.event('watcher-fallback', { reason: error.message }); }
    }
    process.once('SIGINT', stop); process.once('SIGTERM', stop);
    console.log(`Resident runner listening on 127.0.0.1:${port}; PID ${process.pid}`);
    void tick();
    return { server, runner, stop };
  } catch (error) { await stop(); throw error; }
}
if (require.main === module) {
  const args = process.argv.slice(2);
  const allowed = new Set(['--resume']);
  if (args.some(arg => !allowed.has(arg))) { console.error('Usage: node tools/runner/resident.cjs [--resume]'); process.exitCode = 1; }
  else main({ resume: args.includes('--resume') }).catch(error => { console.error(error.code === 'EADDRINUSE' ? 'Resident runner already owns port 43823; no duplicate instance started' : error.message); process.exitCode = 1; });
}
module.exports = { main, acquireSingleton, DEFAULT_PORT };
