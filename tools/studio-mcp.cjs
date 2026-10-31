'use strict';
// Local client for Roblox's installed official MCP. The main orchestrator owns Studio writes.
const {spawn}=require('node:child_process');
const fs=require('node:fs');
const path=require('node:path');
const readline=require('node:readline');
const root=path.resolve(__dirname,'..');
function contentText(result){return (result.content||[]).filter(c=>c.type==='text').map(c=>c.text).join('\n');}
async function withStudio(callback){
 const child=spawn('cmd.exe',['/d','/c','cd /d %LOCALAPPDATA%\\Roblox && .\\mcp.bat'],{windowsHide:true,stdio:['pipe','pipe','pipe']});
 const pending=new Map();let id=0;
 function fail(error){for(const p of pending.values()){clearTimeout(p.timer);p.reject(error);}pending.clear();}
 child.on('error',fail);child.stdin.on('error',fail);child.stderr.on('data',()=>{});child.on('exit',code=>fail(new Error('MCP exited: '+code)));
 const lines=readline.createInterface({input:child.stdout});
 const send=message=>child.stdin.write(JSON.stringify(message)+'\n');
 lines.on('line',line=>{let m;try{m=JSON.parse(line);}catch{return;}const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(new Error(JSON.stringify(m.error))):p.resolve(m.result);}else if(m.id!=null&&m.method){send({jsonrpc:'2.0',id:m.id,error:{code:-32601,message:'Unsupported client method'}});}});
 const rpc=(method,params,timeout=45000)=>new Promise((resolve,reject)=>{const key=++id;const timer=setTimeout(()=>{pending.delete(key);reject(new Error(method+' timed out'));},timeout);pending.set(key,{resolve,reject,timer});send({jsonrpc:'2.0',id:key,method,params});});
 try{
  await rpc('initialize',{protocolVersion:'2025-06-18',capabilities:{},clientInfo:{name:'nightshift-main',version:'1.0.0'}});
  send({jsonrpc:'2.0',method:'notifications/initialized'});
  let studios=[];
  for(let i=0;i<10;i++){const r=await rpc('tools/call',{name:'list_roblox_studios',arguments:{}});if(r.isError)throw Error(contentText(r));studios=JSON.parse(contentText(r)).studios;if(studios.length)break;await new Promise(r=>setTimeout(r,2000));}
  if(studios.length!==1)throw Error('Studio selection required: '+JSON.stringify(studios));
  const studio=studios[0];
  const call=async(name,args={})=>{const r=await rpc('tools/call',{name,arguments:{...args,studio_id:studio.id}});if(r.isError)throw Error(name+': '+contentText(r));return r;};
  return await callback({studio,call,rpc});
 }finally{child.stdin.end();const timer=setTimeout(()=>{child.kill();lines.close();child.stdout.destroy();child.stderr.destroy();},2000);timer.unref();}
}
module.exports={withStudio,contentText};
if(require.main===module){
 (async()=>{
  const input=process.argv[2];if(!input)throw Error('Usage: node tools/studio-mcp.cjs <request.json>');
  const requests=JSON.parse(fs.readFileSync(path.resolve(input),'utf8').replace(/^\uFEFF/,''));
  if(!Array.isArray(requests))throw Error('Request must be an array');
  await withStudio(async({studio,call})=>{
   console.log(JSON.stringify({studio}));
   for(const [index,request]of requests.entries()){
    const args={...request.arguments};if(request.codeFile){const file=path.resolve(root,request.codeFile);if(!file.startsWith(root+path.sep))throw Error('Code file must be inside project');args.code=fs.readFileSync(file,'utf8');}
    const result=await call(request.tool,args);
    const safeContent=[];for(const c of result.content||[]){if(c.type==='image'){const extension=c.mimeType==='image/jpeg'?'jpg':'png';const output=path.join(root,'.setup',`studio-capture-${index}.${extension}`);fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,Buffer.from(c.data,'base64'));safeContent.push({type:'saved-image',path:output});}else safeContent.push(c);}
    console.log(JSON.stringify({tool:request.tool,content:safeContent}));
   }
  });
 })().catch(e=>{console.error(e.message);process.exitCode=1;});
}
