'use strict';
// Read-only connection check against Roblox's installed, official MCP server.
// No model/API request, credentials, Studio edits, or play-mode changes.
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');
const root = path.resolve(__dirname, '..');
const child = spawn('cmd.exe', ['/d', '/c', 'cd /d %LOCALAPPDATA%\\Roblox && .\\mcp.bat'], { windowsHide: true, stdio: ['pipe','pipe','pipe'] });
const pending = new Map();
let nextId = 1;
function failAll(error) { for (const p of pending.values()) { clearTimeout(p.timer); p.reject(error); } pending.clear(); }
child.on('error', failAll);
child.on('exit', code => failAll(new Error(`Studio MCP exited (${code})`)));
child.stderr.on('data', () => {});
child.stdin.on('error', failAll);
const lines = readline.createInterface({ input: child.stdout });
lines.on('line', line => {
  let message;
  try { message = JSON.parse(line); } catch { return; }
  if (message.id != null && pending.has(message.id)) {
    const p = pending.get(message.id); pending.delete(message.id); clearTimeout(p.timer);
    message.error ? p.reject(new Error(JSON.stringify(message.error))) : p.resolve(message.result);
  } else if (message.id != null && message.method) {
    child.stdin.write(JSON.stringify({jsonrpc:'2.0', id:message.id, error:{code:-32601,message:'Client method not supported'}})+'\n');
  }
});
function rpc(method, params) {
  return new Promise((resolve,reject) => {
    const id = nextId++;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`${method} timed out`)); }, 20000);
    pending.set(id,{resolve,reject,timer});
    child.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n');
  });
}
(async () => {
  try {
    const init = await rpc('initialize',{protocolVersion:'2025-06-18',capabilities:{},clientInfo:{name:'nightshift-connection-check',version:'1.0.0'}});
    child.stdin.write(JSON.stringify({jsonrpc:'2.0',method:'notifications/initialized'})+'\n');
    const tools = [];
    let cursor;
    do { const page=await rpc('tools/list',cursor?{cursor}:{}); tools.push(...page.tools); cursor=page.nextCursor; } while(cursor);
    const list = tools.find(t=>t.name==='list_roblox_studios');
    if (!list) throw new Error('Official server did not expose list_roblox_studios');
    if (list.inputSchema?.required?.length) throw new Error('List tool requires arguments: '+JSON.stringify(list.inputSchema));
    let studios, listed;
    // Studio reconnects asynchronously when its stdio bridge starts.
    for (let attempt=0; attempt<10; attempt++) {
      studios = await rpc('tools/call',{name:list.name,arguments:{}});
      if (studios.isError) throw new Error('Studio list failed: '+JSON.stringify(studios.content));
      listed = JSON.parse(studios.content.find(c=>c.type==='text').text).studios;
      if (listed.length) break;
      await new Promise(resolve=>setTimeout(resolve,2000));
    }
    if (listed.length !== 1) throw new Error(`Expected one open Studio; found ${listed.length}. Select an instance before proceeding.`);
    const studioId = listed[0].id;
    const studioState = await rpc('tools/call',{name:'get_studio_state',arguments:{studio_id:studioId}});
    if (studioState.isError) throw new Error('Studio state query failed: '+JSON.stringify(studioState.content));
    let workspace = null;
    if (JSON.stringify(studioState).includes('Edit')) {
      workspace = await rpc('tools/call',{name:'search_game_tree',arguments:{studio_id:studioId,datamodel_type:'Edit',path:'Workspace',max_depth:2,head_limit:20}});
      if (workspace.isError) throw new Error('Workspace query failed: '+JSON.stringify(workspace.content));
    }
    const report = {checkedAt:new Date().toISOString(),transport:'registered Windows stdio launch command',server:init.serverInfo,protocolVersion:init.protocolVersion,toolCount:tools.length,studios,studioState,workspace,availableTools:tools.map(t=>({name:t.name,description:t.description,inputSchema:t.inputSchema}))};
    fs.mkdirSync(path.join(root,'.setup'),{recursive:true});
    fs.writeFileSync(path.join(root,'.setup/studio-connection.json'),JSON.stringify(report,null,2));
    const {availableTools,...summary}=report;
    console.log(JSON.stringify(summary,null,2));
  } catch (error) { console.error(error.message); process.exitCode=1; }
  finally {
    child.stdin.end();
    const timer=setTimeout(()=>{child.kill();lines.close();child.stdout.destroy();child.stderr.destroy();},2000);
    timer.unref();
  }
})();
