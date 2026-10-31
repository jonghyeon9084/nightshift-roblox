const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const crypto = require('node:crypto');
const {Journal,readTranscript}=require('./journal.cjs');
const modelEvidence=require('./model-evidence.cjs');
const run = promisify(execFile);
const root = path.resolve(__dirname, '../..');
const cli = path.join(process.env.LOCALAPPDATA, 'Programs/Maestro/resources/maestro-cli.js');
const port = 43821;
const groupId = 'group-328267a7-c84e-4fc2-bb1d-63fbb94bd916';
const evidence = path.join(root, '.setup/map-events.jsonl');
fs.mkdirSync(path.dirname(evidence), { recursive: true });
let snapshot = { ok: false, error: 'Maestro에 연결 중', agents: [], chats: [], at: null };
let lastClientAt = Date.now();
const seen = new Set();
const journal=new Journal(path.join(root,'.setup/history'));
const transcriptRoot=path.join(process.env.APPDATA,'maestro/group-chats');
const previousState=path.join(root,'.setup/history/last-state.json');
try { snapshot={...JSON.parse(fs.readFileSync(previousState,'utf8')),ok:false,error:'저장된 상태 · 현재 연결 확인 중'}; } catch {}
function trackFiles(directory) {
  if(!fs.existsSync(directory))return;
  for(const item of fs.readdirSync(directory,{withFileTypes:true})) {
    const file=path.join(directory,item.name);
    if(item.isDirectory()) { if(!['node_modules','.git','.setup'].includes(item.name))trackFiles(file); continue; }
    if(!item.isFile()||! /\.(md|json|luau|lua|js|cjs|html|css|ps1|txt)$/.test(item.name))continue;
    const relative=path.relative(root,file).replaceAll('\\','/');
    const hash=crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
    journal.change('file/'+relative,hash,{kind:'file',actor:'파일 관찰',content:relative,timestamp:fs.statSync(file).mtime.toISOString(),hash});
  }
}
async function command(args) {
  const { stdout } = await run(process.execPath, [cli, ...args, '--json'], { windowsHide: true, timeout: 12000, maxBuffer: 4 * 1024 * 1024 });
  return JSON.parse(stdout);
}
async function poll() {
  try {
    const [agents, list, sessions] = await Promise.all([command(['list','agents']), command(['group-chat','list']), command(['session','list'])]);
    if (!list.success || !sessions.success) throw new Error('Maestro 상태 조회 실패');
    const scoped = agents.filter(a => a.groupId === groupId);
    const names = new Set(scoped.map(a => a.name));
    const chats = [];
    const eligible = list.chats.filter(c => c.topic.startsWith('NightShift') && c.participants.some(p => names.has(p.name)));
    eligible.sort((a,b)=>Number(b.isActive)-Number(a.isActive));
    for (const chat of eligible.slice(0, 20)) {
      const result = await command(['group-chat','status',chat.id,'--tail','80']);
      if (!result.success) throw new Error('그룹 대화 조회 실패');
      chats.push(result.chat);
      result.chat.modelInfo=modelEvidence.chatModels(chat.id);
      const sourceDir=path.join(transcriptRoot,chat.id);
      const sourceLog=path.join(sourceDir,'chat.log');
      if(fs.existsSync(sourceLog)) {
        const archive=path.join(root,'.setup/history/maestro',chat.id);
        fs.mkdirSync(archive,{recursive:true});
        for(const name of ['chat.log','history.jsonl','metadata.json']) {
          const source=path.join(sourceDir,name);
          if(fs.existsSync(source))fs.copyFileSync(source,path.join(archive,name));
        }
        for(const entry of readTranscript(sourceLog,result.chat))journal.add(entry);
      } else journal.messages(result.chat);
      journal.change('chat/'+chat.id,{state:result.chat.state,isActive:result.chat.isActive,participants:result.chat.participants.map(p=>p.name)},{kind:'status',chatId:chat.id,topic:result.chat.topic,actor:'Maestro',content:result.chat.state+(result.chat.isActive?' · 활성':' · 비활성'),timestamp:new Date().toISOString()});
      for (const m of result.chat.messages) {
        const key = chat.id + '/' + m.id;
        if (!seen.has(key)) {
          seen.add(key);
          fs.appendFileSync(evidence, JSON.stringify({ observedAt: new Date().toISOString(), chatId: chat.id, message: m }) + '\n');
        }
      }
    }
    let preferredChatId;
    try { preferredChatId=JSON.parse(fs.readFileSync(path.join(root,'docs/automation-state.json'),'utf8')).chatId; } catch {}
    let development=null;
    try{
      let alive=false;development=JSON.parse(fs.readFileSync(path.join(root,'.setup/runner/state.json'),'utf8'));
      try{const health=await (await fetch('http://127.0.0.1:43823/health',{signal:AbortSignal.timeout(1200)})).json();if(health.service==='nightshift-resident-runner'&&health.root===root){alive=true;development=health.state;}}catch{}
      const manifest=JSON.parse(fs.readFileSync(path.join(root,'tools/development-pipeline.json'),'utf8'));
      development={alive,mode:development.mode,status:alive?development.status:'stopped',stage:development.stage,stageId:development.stageId,stageName:manifest.stages[development.stage]?.name,reason:development.reason,at:development.at,chatId:development.chatId,completedStages:development.completedStages?.map(s=>({id:s.id,at:s.at}))};
    }catch{}
    const configured=modelEvidence.configured();
    snapshot = { ok: true, at: new Date().toISOString(), preferredChatId, development, agents: scoped.map(a => ({id:a.id,name:a.name,type:a.toolType,...configured.get(a.name),states:sessions.sessions.filter(s=>s.agentId===a.id).map(s=>s.state)})), chats };
    for(const log of ['runner/events.jsonl','model-routing.jsonl']) {
      const file=path.join(root,'.setup',log);if(!fs.existsSync(file))continue;
      for(const line of fs.readFileSync(file,'utf8').split('\n')) {try{const event=JSON.parse(line);journal.add({id:log+'/'+crypto.createHash('sha256').update(line).digest('hex'),kind:'status',actor:log.startsWith('runner')?'상주 실행기':'모델 배정',timestamp:event.at||event.timestamp,content:JSON.stringify(event)});}catch{}}
    }
    for(const directory of ['src','docs','tools'])trackFiles(path.join(root,directory));
    fs.writeFileSync(previousState,JSON.stringify(snapshot));
  } catch (error) {
    snapshot = { ...snapshot, ok: false, error: error.message };
  } finally { setTimeout(poll, Date.now()-lastClientAt>60000?15000:5000); }
}
const server = http.createServer((req, res) => {
  if (req.headers.host !== `127.0.0.1:${port}` && req.headers.host !== `localhost:${port}`) { res.writeHead(403); return res.end(); }
  if (req.method !== 'GET') { res.writeHead(405); return res.end(); }
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy','no-referrer');
  res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'");
  const requestUrl=new URL(req.url,'http://localhost');
  if(requestUrl.pathname==='/api/history') { res.setHeader('Content-Type','application/json; charset=utf-8'); return res.end(JSON.stringify(journal.query(Object.fromEntries(requestUrl.searchParams)))); }
  if(requestUrl.pathname==='/api/history/export') { res.setHeader('Content-Type','application/x-ndjson'); res.setHeader('Content-Disposition','attachment; filename="nightshift-history.jsonl"'); return res.end(journal.rows.map(row=>JSON.stringify(row)).join('\n')+'\n'); }
  if (req.url === '/api/state') { lastClientAt = Date.now(); res.setHeader('Content-Type','application/json; charset=utf-8'); const stale = snapshot.at && Date.now() - Date.parse(snapshot.at) > 30000; return res.end(JSON.stringify(stale ? {...snapshot,ok:false,error:'마지막 상태가 오래되었습니다. 다시 조회 중'} : snapshot)); }
  const files = {'/':'index.html','/app.js':'app.js','/model.js':'model.js','/fleet.js':'fleet.js','/style.css':'style.css'};
  const file = files[req.url];
  if (!file) { res.writeHead(404); return res.end(); }
  res.setHeader('Content-Type', file.endsWith('.js') ? 'text/javascript; charset=utf-8' : file.endsWith('.css') ? 'text/css; charset=utf-8' : 'text/html; charset=utf-8');
  res.end(fs.readFileSync(path.join(__dirname,file)));
});
server.listen(port, '127.0.0.1', () => { fs.writeFileSync(path.join(root,'.setup/map-server.pid'),String(process.pid)); console.log(`NightShift map: http://127.0.0.1:${port}`); poll(); });
server.on('error', e => { console.error(e.message); process.exit(1); });
