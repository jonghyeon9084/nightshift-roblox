const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {WorkerPool,validatePool,conflicts}=require('./pool.cjs');
function task(id,extra={}){return {id,title:id,worker:'NightShift-'+id,parentName:null,temporary:true,workload:'code',dependsOn:[],writes:[id+'.md'],reads:[],chatName:'NightShift-'+id,promptFile:id+'.txt',completionMarker:'[STAGE_READY:'+id.toUpperCase()+']',requiredFiles:[id+'.md'],...extra};}
function fixture(t,tasks=[task('first')]){
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'nightshift-pool-'));
 t.after(()=>{const resolved=fs.realpathSync(root);assert.ok(resolved.startsWith(fs.realpathSync(os.tmpdir())+path.sep));fs.rmSync(resolved,{recursive:true,force:true});});
 fs.mkdirSync(path.join(root,'tools'));const config={version:1,maxWorkers:4,minFreeMemoryMB:512,tasks};
 fs.writeFileSync(path.join(root,'tools/worker-pool.json'),JSON.stringify(config));for(const task of tasks)fs.writeFileSync(path.join(root,task.promptFile),'Work once. '+task.completionMarker);
 const chats=[],calls=[];let now=100000,free=1000;
 const adapter={async list(){return structuredClone(chats);},async status(id){return structuredClone(chats.find(c=>c.id===id));},async setModel(role,tier){calls.push(['model',role,tier]);},async ensureWorker(task){calls.push(['register',task.worker]);},async dispatch(stage,existing,file){const chat={id:stage.id,topic:stage.chatName,participants:stage.participants.map(name=>({name})),isActive:true,state:'agent-working',messages:[{participantName:'user',role:'user',timestamp:now,content:fs.readFileSync(file,'utf8')}]};chats.push(chat);calls.push(['dispatch',stage.id]);}};
 adapter.problem=require('./io.cjs').createAdapter(root).problem;
 const make=()=>new WorkerPool({root,adapter,clock:()=>now,freeMemory:()=>free});
 const complete=id=>{now+=10;const chat=chats.find(c=>c.id===id);chat.isActive=false;chat.state='idle';chat.messages.push({participantName:'moderator',timestamp:now,content:tasks.find(t=>t.id===id).completionMarker});fs.writeFileSync(path.join(root,id+'.md'),'verified output');};
 return {root,config,chats,calls,adapter,make,complete,setFree:v=>free=v,write:()=>fs.writeFileSync(path.join(root,'tools/worker-pool.json'),JSON.stringify(config))};
}
test('validates parents, cycles, dependencies and bounded concrete work',()=>{
 const c={version:1,maxWorkers:4,minFreeMemoryMB:512,tasks:[task('a'),task('b',{parentName:'NightShift-a',dependsOn:['a']})]};validatePool(c);
 assert.throws(()=>validatePool({...c,tasks:[task('a',{parentName:'NightShift-b'}),task('b',{parentName:'NightShift-a'})]}),/cycle/);
 assert.throws(()=>validatePool({...c,tasks:[task('a',{dependsOn:['missing']})]}),/Unknown/);
 assert.throws(()=>validatePool({...c,tasks:[task('a',{dependsOn:['a']})]}),/cycle/);
 assert.throws(()=>validatePool({...c,tasks:[task('a',{writes:['../escape']})]}),/path/);
 assert.throws(()=>validatePool({...c,maxWorkers:5}));
});
test('quota gate blocks models and dispatch while preserving observation; hard reserve stops own active chat once',async t=>{
 const f=fixture(t,[task('first'),task('second',{dependsOn:['first']})]),p=f.make();
 let quota={enabled:true,blocked:true,stopActive:false,reason:'quota reserve'};
 p.budget={check:()=>quota};await p.tick({status:'running'});assert.equal(f.calls.length,0);
 quota={enabled:true,blocked:false,stopActive:false};await p.tick({status:'running'});assert.equal(f.chats.length,1);
 f.adapter.stopChat=async id=>{f.calls.push(['stop',id]);const c=f.chats.find(c=>c.id===id);c.isActive=false;c.state='stopped';};
 quota={enabled:true,blocked:true,stopActive:true,reason:'quota reserve',remainingPercent:15,reservePercent:10};
 await p.tick({status:'running'});await p.tick({status:'running'});
 assert.equal(f.calls.filter(c=>c[0]==='stop').length,1);assert.equal(f.chats.length,1);
 assert.equal(p.snapshot.usageBudget.remainingPercent,15);
 assert.equal(p.runners.get('first').state.completedStages.length,0);
});
test('file locks include read/write and Windows case; read/read stays parallel',()=>{
 assert.equal(conflicts({writes:['SRC/server']},{reads:['src/server/x.luau']}),true);
 assert.equal(conflicts({reads:['src']},{writes:['src/client']}),true);
 assert.equal(conflicts({reads:['src']},{reads:['src/client']}),false);
 assert.equal(conflicts({writes:['src/server']},{writes:['src/server2']}),false);
});
test('explicit task hold prevents dispatch without rewriting definitions or completing work',async t=>{
 const f=fixture(t),p=f.make();f.config.heldTasks={first:'superseded by source-only handoff'};f.write();await p.tick({status:'running'});
 assert.equal(f.calls.length,0);assert.equal(p.snapshot.tasks[0].status,'waiting');assert.match(p.snapshot.tasks[0].reason,/보류/);
 assert.equal(p.runners.get('first').state.completedStages.length,0);
 delete f.config.heldTasks;f.write();await p.tick({status:'running'});assert.equal(f.chats.length,1);
});
test('activates independent tasks, completes then deactivates without another dispatch',async t=>{
 const f=fixture(t,[task('first'),task('second')]),p=f.make();await p.tick({status:'running'});
 assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,2);assert.equal(p.snapshot.workers[0].status,'active');
 f.complete('first');await p.tick({status:'running'});assert.equal(p.snapshot.workers[0].status,'inactive');
 await f.make().tick({status:'running'});assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,2);
});
test('dependency and memory wait are rechecked, and completion unlocks the next task',async t=>{
 const f=fixture(t,[task('first'),task('second',{dependsOn:['first'],parentName:'NightShift-first'})]),p=f.make();
 f.setFree(400);await p.tick({status:'running'});assert.equal(f.calls.length,0);
 f.setFree(900);await p.tick({status:'running'});assert.equal(f.chats.length,1);assert.equal(p.snapshot.tasks[1].status,'waiting');
 f.complete('first');await p.tick({status:'running'});assert.equal(f.chats.length,2);assert.equal(p.snapshot.workers[1].parentName,'NightShift-first');
});
test('active global work reserves capacity; file lock blocks even with a spare slot',async t=>{
 const f=fixture(t),p=f.make();f.chats.push({id:'external',topic:'Other',state:'agent-working',isActive:true,participants:[{name:'unknown'}]});
 await p.tick({status:'running'});assert.equal(f.calls.length,0);assert.match(p.snapshot.tasks[0].reason,/소유권/);
 f.chats[0].participants=Array.from({length:4},()=>({name:'NightShift-UI'}));await p.tick({status:'running'});assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,0);assert.equal(p.snapshot.tasks[0].status,'waiting');
 f.chats[0].isActive=false;f.chats[0].state='idle';await p.tick({status:'running'});assert.equal(f.chats.length,2);
});
test('main attention blocks new model requests; in-flight work remains observable',async t=>{
 const f=fixture(t),p=f.make();await p.tick({status:'attention',reason:'usage limit'});assert.equal(f.calls.length,0);
 await p.tick({status:'running'});assert.equal(f.chats.length,1);f.complete('first');await p.tick({status:'attention',reason:'usage limit'});assert.equal(p.snapshot.tasks[0].status,'completed');
});
test('reuse of one worker waits for its current task without an attention stop',async t=>{
 const f=fixture(t,[task('first'),task('second',{worker:'NightShift-first'})]),p=f.make();
 await p.tick({status:'running'});
 assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,1);
 assert.equal(p.snapshot.tasks[1].status,'waiting');assert.match(p.snapshot.tasks[1].reason,/담당 워커/);
 f.complete('first');await p.tick({status:'running'});
 assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,2);assert.equal(p.snapshot.tasks[1].status,'active');
});
test('an interrupted ambiguous dispatch never resends on restart',async t=>{
 const f=fixture(t),p=f.make();await p.tick({status:'running'});const r=p.runners.get('first');r.state.checkpoint.phase='prepared';r.store.write(r.state);f.chats.length=0;
 const restarted=f.make();await restarted.tick({status:'running'});assert.equal(restarted.snapshot.tasks[0].status,'attention');assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,1);
});
test('R1/R2: equivalent scope spellings conflict; role reuse requires a unique group',()=>{
 assert.equal(conflicts({writes:['./SRC//server/']},{reads:['src/server/x.luau']}),true);
 assert.equal(conflicts({writes:['.']},{reads:['src/client']}),true);
 assert.throws(()=>validatePool({version:1,maxWorkers:4,minFreeMemoryMB:512,tasks:[task('a',{chatName:'NightShift-Same'}),task('b',{chatName:'NightShift-Same'})]}),/unique chatName/);
});
test('R3: dispatch limit stays durable and blocks other tasks including after restart',async t=>{
 const f=fixture(t,[task('first'),task('second')]);f.adapter.dispatch=async stage=>{f.calls.push(['dispatch',stage.id]);throw Error('usage limit reached');};
 const p=f.make();await p.tick({status:'running'});assert.deepEqual(f.calls.filter(c=>c[0]==='dispatch'),[['dispatch','first']]);assert.equal(p.runners.get('first').state.halt.kind,'limit-auth');
 const next=f.make();await next.tick({status:'running'});assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,1);assert.throws(()=>next.resume(),/halt/);
});
test('R4: existing group with extra participants is never dispatched',async t=>{
 const f=fixture(t);f.chats.push({id:'extra',topic:'NightShift-first',state:'idle',isActive:false,participants:[{name:'NightShift-first'},{name:'NightShift-extra'}],messages:[]});
 const p=f.make();await p.tick({status:'running'});assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,0);assert.equal(p.snapshot.tasks[0].status,'attention');
});
test('R5: observed idle during marker grace is waiting, not active',async t=>{
 const f=fixture(t),p=f.make();await p.tick({status:'running'});f.chats[0].state='idle';f.chats[0].isActive=false;await p.tick({status:'running'});
 assert.equal(p.snapshot.workers[0].status,'waiting');assert.equal(p.snapshot.workers[0].observedState,'idle');
});
test('R6: new file conflict or memory drop during model setup blocks dispatch',async t=>{
 const f=fixture(t,[task('first',{writes:['src/client']})]);f.adapter.setModel=async()=>f.chats.push({id:'race',topic:'ExternalUI',state:'agent-working',isActive:true,participants:[{name:'NightShift-UI'}],messages:[]});
 const p=f.make();await p.tick({status:'running'});assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,0);assert.equal(p.snapshot.tasks[0].status,'waiting');
 const g=fixture(t);g.adapter.setModel=async()=>g.setFree(200);await g.make().tick({status:'running'});assert.equal(g.calls.filter(c=>c[0]==='dispatch').length,0);
});
test('R7: current reduced capacity applies without rewriting an immutable checkpoint',async t=>{
 const f=fixture(t,[task('first'),task('second')]),p=f.make();p.refresh();f.config.maxWorkers=1;f.write();await p.tick({status:'running'});
 assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,1);assert.equal(p.snapshot.tasks[1].status,'waiting');
 const r=f.make();await r.tick({status:'running'});assert.notEqual(r.snapshot.tasks[0].status,'attention');assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,1);
});
test('R8: later in-flight limit is observed before an earlier queued task is dispatched',async t=>{
 const bad=task('bad',{adoptExisting:true}),f=fixture(t,[task('first'),bad]);f.chats.push({id:'bad',topic:bad.chatName,participants:[{name:bad.worker}],isActive:false,state:'idle',messages:[{role:'user',participantName:'user',timestamp:99900,content:bad.completionMarker},{participantName:'moderator',timestamp:99910,content:'usage limit reached'}]});
 const p=f.make();await p.tick({status:'running'});assert.equal(f.calls.filter(c=>c[0]==='dispatch').length,0);assert.equal(p.hasFatal(),true);
});
test('pool definitions append safely but cannot silently change or disappear',t=>{
 const f=fixture(t),p=f.make();p.refresh();f.config.tasks.push(task('second'));f.write();p.refresh();assert.equal(p.runners.size,2);
 f.config.tasks[0].title='changed';f.write();assert.throws(()=>p.refresh(),/changed\/removed/);
 f.config.tasks.shift();f.write();assert.throws(()=>p.refresh(),/changed\/removed/);
});
