'use strict';
// Explicit operator review only: preserve incomplete stage/checkpoint, never invent a pass.
const fs=require('node:fs'),path=require('node:path');
const {PipelineRunner}=require('./pipeline.cjs');
const {createStore,createFiles}=require('./io.cjs');
const {acquireSingleton}=require('./resident.cjs');
async function main(){
 const [evidenceFile,...reasonParts]=process.argv.slice(2),reason=reasonParts.join(' ');
 const root=path.resolve(__dirname,'../..'),directory=path.join(root,'.setup/runner');
 const lock=await acquireSingleton(43823);
 try{
  if(fs.existsSync(path.join(directory,'runner.pid')))throw Error('Stop resident runner first');
  const store=createStore(directory),state=store.read();
  if(state?.status!=='stopped')throw Error('Expected stopped operator-reviewed state');
  const backup=path.join(directory,`before-defer-${Date.now()}.json`);
  fs.writeFileSync(backup,JSON.stringify(state,null,2)+'\n',{flag:'wx'});
  const runner=new PipelineRunner({manifest:JSON.parse(fs.readFileSync(path.join(root,'tools/development-pipeline.json'),'utf8')),store,files:createFiles(root,directory),adapter:{}});
  runner.defer(reason,evidenceFile);
  console.log(JSON.stringify({status:runner.state.status,stageId:runner.state.stageId,completed:false,checkpointPreserved:true,backup}));
 }finally{await new Promise(resolve=>lock.close(resolve));}
}
if(require.main===module)main().catch(e=>{console.error(e.message);process.exitCode=1;});
