'use strict';
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {PipelineRunner,busy,hash}=require('./pipeline.cjs');
const {createStore,createFiles,atomicJson,within}=require('./io.cjs');
const {selectModel}=require('../model-routing.cjs');
const policy=require('../model-policy.json');
const knownScopes={
 'NightShift-Server':{writes:['src/server'],reads:['src/shared']},
 'NightShift-UI':{writes:['src/client'],reads:['src/shared']},
 'NightShift-World':{writes:['tools/world'],reads:['src/shared']},
 'NightShift-Profiles':{writes:['src/server/Modules/ProfileService.luau'],reads:['src/shared']},
 'NightShift-Economy':{writes:['src/server/Modules/CommerceService.luau','src/server/Modules/ProgressionService.luau'],reads:['src/shared']},
 'NightShift-Delivery':{writes:['src/server/Modules/DeliveryService.luau'],reads:['src/shared']},
 'NightShift-Review':{writes:['docs/implementation/commerce-review.md'],reads:['src','tools/world']},
 'NightShift-Worker':{writes:['docs/implementation/foundation-audit.md'],reads:['src/server/Modules/ProfileService.luau','src/server/Modules/CommerceService.luau','src/server/Modules/ProgressionService.luau','src/server/Modules/DeliveryService.luau','src/shared']},
 'NightShift-Integrator':{writes:['src','tools/world','tools/integration','docs/implementation/commerce-integration-report.md','.setup/commerce-verification.json','@studio'],reads:['docs/implementation/commerce-review.md','docs/implementation/foundation-audit.md','docs/implementation/commerce-contract.md','docs/implementation/contract.md','docs/implementation/advertising.md']},
 'NightShift-Planner':{writes:['docs/design'],reads:['src/shared']},
 'NightShift-DesignReview':{writes:[],reads:['docs/design']},
 'NightShift-Story':{writes:['docs/story'],reads:['docs/design']}
};
const normalize=p=>{const n=path.posix.normalize(p.replaceAll('\\','/')).replace(/\/+$/,'').toLowerCase();return n==='.'?'*':n;};
function overlaps(a,b){a=normalize(a);b=normalize(b);return a==='*'||b==='*'||a===b||a.startsWith(b+'/')||b.startsWith(a+'/');}
function conflicts(a,b){return (a.writes||[]).some(p=>[...(b.writes||[]),...(b.reads||[])].some(q=>overlaps(p,q)))||(a.reads||[]).some(p=>(b.writes||[]).some(q=>overlaps(p,q)));}
function validatePool(config,root){
 if(config.version!==1||!Array.isArray(config.tasks)||!Number.isInteger(config.maxWorkers)||config.maxWorkers<1||config.maxWorkers>4||!Number.isFinite(config.minFreeMemoryMB)||config.minFreeMemoryMB<256)throw Error('Invalid worker pool configuration');
 const ids=new Set(),chatNames=new Set(),parents=new Map();
 for(const t of config.tasks){
  if(!/^[a-z][a-z0-9_]{0,63}$/.test(t.id)||ids.has(t.id)||!/^NightShift-[A-Za-z][A-Za-z0-9-]{0,35}$/.test(t.worker)||!t.title||!t.chatName?.startsWith('NightShift-'))throw Error('Invalid pool task identity');
  ids.add(t.id);
  if(chatNames.has(t.chatName))throw Error('Each task needs a unique chatName; reuse the worker with a new chat');chatNames.add(t.chatName);
  for(const field of ['writes','reads','dependsOn','requiredFiles'])if(!Array.isArray(t[field])||!t[field].every(v=>typeof v==='string'))throw Error('Missing task scopes/dependencies/outputs');
  if(!t.writes.length||!t.requiredFiles.length||!/^\[STAGE_READY:[A-Z0-9_-]+\]$/.test(t.completionMarker))throw Error('Task must have concrete outputs and completion marker');
  for(const file of [...t.writes,...t.reads,...t.requiredFiles,t.promptFile]){
   if(typeof file!=='string'||!file||path.isAbsolute(file)||file.split(/[\\/]/).includes('..'))throw Error('Invalid task path');
   if(root)within(root,file);
  }
  if(t.parentName!==null&&(!/^NightShift-[A-Za-z][A-Za-z0-9-]{0,35}$/.test(t.parentName)||t.parentName===t.worker))throw Error('Invalid task parent');
  if(parents.has(t.worker)&&parents.get(t.worker)!==t.parentName)throw Error('Worker parent cannot change between tasks');
  parents.set(t.worker,t.parentName);selectModel(policy,t.worker.slice(11),t);
 }
 const byId=new Map(config.tasks.map(t=>[t.id,t]));
 for(const t of config.tasks){
  const seen=new Set([t.worker]);let p=t.parentName;
  while(p){if(seen.has(p))throw Error('Worker parent cycle');seen.add(p);p=parents.get(p);}
  const walk=(id,stack)=>{if(stack.has(id))throw Error('Task dependency cycle');const task=byId.get(id);if(!task)throw Error('Unknown task dependency');for(const d of task.dependsOn)walk(d,new Set([...stack,id]));};walk(t.id,new Set());
 }
 return config;
}
function taskStage(t){const selection=selectModel(policy,t.worker.slice('NightShift-'.length),t);return {id:t.id,name:t.title,chatName:t.chatName,participants:[t.worker],promptFile:t.promptFile,completionMarker:t.completionMarker,requiredFiles:t.requiredFiles,adoptExisting:t.adoptExisting===true,modelAssignments:{[t.worker.slice('NightShift-'.length)]:selection.tier}};}
class WorkerPool {
 constructor({root,adapter,freeMemory=()=>os.freemem()/1048576,clock=Date.now}){
  Object.assign(this,{root,adapter,freeMemory,clock});this.directory=path.join(root,'.setup/worker-pool');fs.mkdirSync(this.directory,{recursive:true});this.runners=new Map();this.reasons=new Map();this.stopping=false;this.config={version:1,maxWorkers:4,minFreeMemoryMB:512,tasks:[]};this.lastStates=new Map();
  try{for(const t of JSON.parse(fs.readFileSync(path.join(this.directory,'state.json'),'utf8')).tasks||[])this.lastStates.set(t.id,t.status+'|'+(t.reason||''));}catch{}
 }
 event(kind,data){fs.appendFileSync(path.join(this.directory,'events.jsonl'),JSON.stringify({at:new Date(this.clock()).toISOString(),kind,...data})+'\n');}
 refresh(){
  const config=validatePool(JSON.parse(fs.readFileSync(path.join(this.root,'tools/worker-pool.json'),'utf8')),this.root);
  const definitionFile=path.join(this.directory,'definitions.json');let definitions={};
  try{definitions=JSON.parse(fs.readFileSync(definitionFile,'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
  for(const [id,digest]of Object.entries(definitions)){const task=config.tasks.find(t=>t.id===id);if(!task||hash(JSON.stringify(task))!==digest)throw Error('Existing pool task changed/removed; append a new task instead: '+id);}
  const next=Object.fromEntries(config.tasks.map(t=>[t.id,hash(JSON.stringify(t))]));
  if(JSON.stringify(next)!==JSON.stringify(definitions))atomicJson(definitionFile,next);
  for(const [id,r]of this.runners)if(!config.tasks.some(t=>t.id===id)&&!r.state.completedStages.length)throw Error('Cannot remove unfinished pool task');
  this.config=config;
  for(const t of config.tasks)this.getRunner(t);
 }
 scopes(chat){
  const task=this.config.tasks.find(t=>t.chatName===chat.topic);
  if(task){const extra=(chat.participants||[]).filter(p=>p.name!==task.worker);if(!extra.length)return task;return {writes:[...task.writes,'*'],reads:task.reads};}
  return (chat.participants||[]).reduce((all,p)=>{const s=knownScopes[p.name]||{writes:['*'],reads:[]};return {writes:[...all.writes,...s.writes],reads:[...all.reads,...s.reads]};},{writes:[],reads:[]});
 }
 guard(scope,chats,ignoreId){
  if(this.stopping)return 'Worker pool is stopping';
  const low=this.freeMemory()<this.config.minFreeMemoryMB;
  if(low)return `메모리 여유 대기: 최소 ${this.config.minFreeMemoryMB} MiB`;
  if(scope.worker){const assigned=chats.find(c=>c.id!==ignoreId&&busy(c)&&c.participants?.some(p=>p.name===scope.worker));if(assigned)return `담당 워커 작업 완료 대기: ${assigned.topic}`;}
  for(const c of chats.filter(c=>c.id!==ignoreId&&busy(c)))if(conflicts(scope,this.scopes(c)))return `파일 소유권 대기: ${c.topic}`;
  return null;
 }
 pipelineGuard(stage,chats,chatId){
  if(this.error)return this.error;
  if(this.hasFatal())return 'Worker pool usage/authentication halt';
  return this.guard(this.scopes({topic:stage.chatName,participants:stage.participants.map(name=>({name}))}),chats,chatId);
 }
 getRunner(t){
  if(this.runners.has(t.id))return this.runners.get(t.id);
  const directory=path.join(this.directory,t.id),stage=taskStage(t),store=createStore(directory),pool=this;
  const adapter={...this.adapter,capacityLimit:()=>pool.config.maxWorkers,canDispatch:(_stage,chats,chatId)=>pool.guard(t,chats,chatId),prepareDispatch:()=>pool.adapter.ensureWorker?.(t)};
  const runner=new PipelineRunner({manifest:{version:1,maxWorkers:4,stages:[stage]},store,files:createFiles(this.root,directory),adapter,clock:this.clock});
  this.runners.set(t.id,runner);return runner;
 }
 hasFatal(){return [...this.runners.values()].some(r=>r.state.halt||((r.state.status==='attention'||r.state.resumeStatus==='attention')&&/limit|authentication|한도|인증/i.test(r.state.reason||'')));}
 async observe(){
  if(this.stopping)return;
  this.refresh();this.error=null;
  for(const t of this.config.tasks){const r=this.getRunner(t);if(!r.state.completedStages.length&&(r.state.checkpoint||t.adoptExisting))await r.tick({allowDispatch:false});}
  this.publish();
 }
 async dispatchReady(mainState){
  if(this.stopping)return;
  let chats=null;
  for(const t of this.config.tasks){
   const r=this.getRunner(t),s=r.state;
   if(s.completedStages.length)continue;
   const inFlight=!!s.checkpoint||t.adoptExisting;if(inFlight)continue;
   let reason=null;
   if(!inFlight){
    if(mainState?.status==='attention'||mainState?.halt)reason='주 파이프라인 확인 필요: '+mainState.reason;
    if(this.hasFatal())reason='사용 한도/인증 확인 필요';
    if(!reason&&t.dependsOn.some(id=>!this.runners.get(id)?.state.completedStages.length))reason='선행 작업 완료 대기';
    if(!reason){chats??=await this.adapter.list();reason=this.guard(t,chats);}
   }
   if(reason){this.reasons.set(t.id,reason);continue;}
   this.reasons.delete(t.id);await r.tick();chats=null;
  }
  this.publish();
 }
 async tick(mainState){await this.observe();await this.dispatchReady(mainState);}
 publish(){
  const tasks=this.config.tasks.map(t=>{
   const s=this.runners.get(t.id)?.state;
   const settling=!!s?.checkpoint&&['idle','stopped'].includes(s.observedState);
   const status=s?.completedStages.length?'completed':s?.status==='attention'?'attention':settling||this.reasons.has(t.id)||s?.status==='waiting-capacity'||s?.status==='waiting-resources'?'waiting':s?.checkpoint?'active':'queued';
   const row={id:t.id,title:t.title,status,chatId:s?.chatId||s?.completedStages.at(-1)?.chatId||null,reason:status==='completed'?null:this.reasons.get(t.id)||s?.reason||(settling?'응답 종료 · 완료 확인 대기':null),observedState:s?.observedState||null};
   const fingerprint=status+'|'+(row.reason||'');if(this.lastStates.get(t.id)!==fingerprint){this.event('task-'+status,{...row,worker:t.worker,parentName:t.parentName,temporary:t.temporary===true});this.lastStates.set(t.id,fingerprint);}return row;
  });
  const workers=[];
  for(const name of new Set(this.config.tasks.map(t=>t.worker))){
   const entries=this.config.tasks.filter(t=>t.worker===name),task=entries.find(t=>tasks.find(x=>x.id===t.id).status==='active')||entries.find(t=>tasks.find(x=>x.id===t.id).status!=='completed')||entries.at(-1),row=tasks.find(t=>t.id===task.id);
   workers.push({name,parentName:task.parentName,temporary:task.temporary===true,status:row.status==='completed'?'inactive':row.status,taskId:task.id,taskTitle:task.title,chatId:row.chatId,reason:row.status==='completed'?'작업 완료 · 다음 배정까지 비활성':row.reason,observedState:row.observedState,tier:selectModel(policy,name.slice(11),task).tier});
  }
  this.snapshot={at:new Date(this.clock()).toISOString(),workers,tasks};atomicJson(path.join(this.directory,'state.json'),this.snapshot);return this.snapshot;
 }
 resume(){this.refresh();for(const t of this.config.tasks)this.getRunner(t).resume();}
 requestStop(){this.stopping=true;for(const r of this.runners.values())r.requestStop();}
 stop(){for(const r of this.runners.values())if(!r.state.completedStages.length)r.stop();this.event('pool-stopped',{});}
}
module.exports={WorkerPool,validatePool,taskStage,conflicts,overlaps};
