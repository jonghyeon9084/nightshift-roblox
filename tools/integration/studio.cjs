'use strict';
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'../..');
function transport(){
 if(fs.existsSync(path.join(process.env.LOCALAPPDATA,'Roblox/mcp.bat'))) return require('../studio-mcp.cjs');
 // The running Studio was installed in Codex's MSIX virtualized LocalAppData.
 // Reuse the original official-client implementation unchanged on disk. Only its
 // subprocess launch expression is adapted in memory; no alternative protocol.
 const exe=process.env.NIGHTSHIFT_STUDIO_MCP;
 if(!exe || !path.isAbsolute(exe) || path.basename(exe)!=='StudioMCP.exe' || !fs.existsSync(exe)) throw Error('Official StudioMCP.exe path required in NIGHTSHIFT_STUDIO_MCP');
 const file=path.join(root,'tools/studio-mcp.cjs');
 const source=fs.readFileSync(file,'utf8');
 const launch=/const child=spawn\('cmd\.exe',\[[^\n]+?\],\{windowsHide:true,stdio:\['pipe','pipe','pipe'\]\}\);/g;
 if((source.match(launch)||[]).length!==1) throw Error('Original client changed; launch adaptation requires review');
 const Module=require('node:module');
 const adapted=new Module(file,module);adapted.filename=file;adapted.paths=module.paths;
 adapted._compile(source.replace(launch,`const child=spawn(${JSON.stringify(exe)},[],{windowsHide:true,stdio:['pipe','pipe','pipe']});`),file);
 return adapted.exports;
}
async function run(){
 const input=JSON.parse(fs.readFileSync(process.argv[2],'utf8').replace(/^\uFEFF/,''));
 const requests=Array.isArray(input)?input:[input];
 await transport().withStudio(async({studio,call,rpc})=>{
  const listed=await rpc('tools/list',{});
  fs.mkdirSync(path.join(root,'.setup/integration'),{recursive:true});
  fs.writeFileSync(path.join(root,'.setup/integration/tools.json'),JSON.stringify(listed,null,2));
  console.log(JSON.stringify({studio,tools:listed.tools.map(t=>t.name)}));
  for(const req of requests){
   const args={...req.arguments};
   if(req.codeFile)args.code=fs.readFileSync(path.resolve(root,req.codeFile),'utf8');
   const result=await call(req.tool,args);
   const safe=[];
   for(const c of result.content||[]){
    if(c.type==='image'){
     const p=path.join(root,'.setup/integration',`${Date.now()}.${c.mimeType==='image/jpeg'?'jpg':'png'}`);
     fs.writeFileSync(p,Buffer.from(c.data,'base64'));safe.push({type:'image',path:p});
    } else safe.push(c);
   }
   const record={at:new Date().toISOString(),studio,tool:req.tool,label:req.label,content:safe};
   fs.appendFileSync(path.join(root,'.setup/integration/events.jsonl'),JSON.stringify(record)+'\n');
   console.log(JSON.stringify(record));
  }
 });
}
module.exports={transport,root};
if(require.main===module)run().catch(e=>{console.error(e.stack);process.exitCode=1;});
