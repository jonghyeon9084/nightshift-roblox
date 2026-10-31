const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),vm=require('node:vm');
const {performance}=require('node:perf_hooks');
const {PollCache,createLimiter,FileHashCache,readWorkerPool,ingestPoolEvents,MessageIngestor}=require('./poll-cache.cjs');
const {Journal}=require('./journal.cjs');
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function fixture(t){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'nightshift-poll-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));return dir;}
function source(dir,id){const d=path.join(dir,id);fs.mkdirSync(d,{recursive:true});for(const name of ['metadata.json','history.jsonl','chat.log'])fs.writeFileSync(path.join(d,name),'initial');return d;}

test('late CLI aliases survive disk restart, overlapping tails and later log catch-up without synthetic messages',t=>{
 const dir=fixture(t),log=path.join(dir,'chat.log'),journalDir=path.join(dir,'journal');
 const timestamp='2026-10-31T09:00:00.000Z',participantName='NightShift-PerfAudit',content='같은 내용';
 const line=`${timestamp}|${participantName}|${content}\n`,message=id=>({id,timestamp,participantName,content});
 const chat=ids=>({id:'c',topic:'NightShift-MapPerformance',messages:ids.map(message)});
 fs.writeFileSync(log,line.repeat(2));
 let journal=new Journal(journalDir),ingestor=new MessageIngestor(journal);
 ingestor.ingest(chat([]),log);assert.equal(journal.rows.length,2);
 ingestor.ingest(chat(['b','c']),null);assert.equal(journal.rows.length,2,'late aliases are not chat messages');
 const index=path.join(journalDir,'message-links.jsonl');
 const links=fs.readFileSync(index,'utf8').trim().split('\n').map(JSON.parse);
 assert.deepEqual(links.map(r=>[r.id,r.occurrence]),[['b',1],['c',2]]);assert.ok(links.every(r=>Object.keys(r).sort().join(',')==='id,key,occurrence'));
 journal=new Journal(journalDir);ingestor=new MessageIngestor(journal);
 ingestor.ingest(chat(['c','d']),null);assert.equal(journal.rows.length,3,'new d must not consume restored occurrence 2');
 fs.appendFileSync(log,line);ingestor.ingest(chat(['c','d']),log);assert.equal(journal.rows.length,3,'log catch-up does not duplicate d');
 journal=new Journal(journalDir);ingestor=new MessageIngestor(journal);ingestor.ingest(chat(['c','d']),log);assert.equal(journal.rows.length,3,'second restart retains all links');
 fs.renameSync(index,index+'.saved');fs.mkdirSync(index);
 assert.throws(()=>ingestor.ingest(chat(['d','e']),null));assert.equal(journal.rows.length,3,'failed alias persistence cannot be success');
 fs.rmdirSync(index);fs.renameSync(index+'.saved',index);ingestor.ingest(chat(['d','e']),null);assert.equal(journal.rows.length,4,'failed alias can be retried');
 fs.appendFileSync(log,line);ingestor.ingest(chat(['d','e']),log);assert.equal(journal.rows.length,4);assert.ok(journal.rows.every(r=>r.kind==='message'&&r.content===content));
 assert.equal(new Journal(journalDir).rows.length,4,'only real messages enter activity journal');
});

test('alias index restores a valid interrupted append and rejects corrupted complete rows',t=>{
 const dir=fixture(t),journal=new Journal(dir),index=path.join(dir,'message-links.jsonl');
 const row={key:'a'.repeat(64),id:'c',occurrence:2};
 fs.writeFileSync(index,JSON.stringify(row)+'\n{"key":');let ingestor=new MessageIngestor(journal);assert.equal(ingestor.cliIds.get(row.key).get('c'),2);assert.equal(fs.readFileSync(index,'utf8'),JSON.stringify(row)+'\n');
 fs.writeFileSync(index,JSON.stringify(row));ingestor=new MessageIngestor(journal);assert.equal(ingestor.cliIds.get(row.key).get('c'),2);assert.ok(fs.readFileSync(index,'utf8').endsWith('\n'));
 fs.writeFileSync(index,JSON.stringify(row)+'\nBROKEN\n');assert.throws(()=>new MessageIngestor(journal));
});

test('real log/CLI formats merge once: unchanged active polls, CLI ahead, log catch-up, restart, repeated messages and deletion',async t=>{
 const dir=fixture(t),src=path.join(dir,'source'),d=source(src,'c'),log=path.join(d,'chat.log'),journalDir=path.join(dir,'journal');
 const base=Date.parse('2026-10-31T09:00:00.000Z');
 const message=(id,offset,content)=>({id,timestamp:base+offset,participantName:'NightShift-PerfAudit',content});
 const old=message('old',-1000,'CLI tail 밖 메시지'),a=message('a',0,'첫 줄\n둘째 줄 | 구분자'),b=message('b',1,'반복'),c=message('c',1,'반복'),ahead=message('ahead',2,'로그보다 먼저 도착'),later=message('later',3,'로그 삭제 중 도착');
 const line=m=>`${new Date(m.timestamp).toISOString()}|${m.participantName}|${m.content.replace(/\n/g,'\\n')}\n`;
 fs.writeFileSync(log,[old,a,b,c].map(line).join(''));
 let journal=new Journal(journalDir),ingestor=new MessageIngestor(journal),messages=[a,b,c];
 const chat={id:'c',topic:'NightShift-MapPerformance',state:'busy',isActive:true};
 const makeCache=()=>new PollCache({sourceRoot:src,archiveRoot:path.join(dir,'archive'),command:async()=>({success:true,chat:{...chat,messages}}),ingest:(...args)=>ingestor.ingest(...args)});
 let cache=makeCache();await cache.get(chat);assert.equal(journal.rows.length,4);await cache.get(chat);assert.equal(journal.rows.length,4,'same messages through unchanged active fallback');
 messages=[a,b,c,ahead];await cache.get(chat);assert.equal(journal.rows.length,5,'CLI-only message is immediate');
 fs.appendFileSync(log,line(ahead));await cache.get(chat);assert.equal(journal.rows.length,5,'late log copy must not duplicate CLI');
 journal=new Journal(journalDir);ingestor=new MessageIngestor(journal);cache=makeCache();await cache.get(chat);assert.equal(journal.rows.length,5,'restart replays without duplicates');
 fs.unlinkSync(log);messages=[a,b,c,ahead,later];await cache.get(chat);assert.equal(journal.rows.length,6);
 fs.writeFileSync(log,[old,a,b,c,ahead,later].map(line).join(''));await cache.get(chat);assert.equal(journal.rows.length,6,'restored log reconciles');
 assert.equal(journal.rows.filter(r=>r.content==='반복').length,2,'distinct same-time messages retain multiplicity');
 assert.equal(journal.rows.filter(r=>r.content===a.content).length,1);assert.ok(journal.rows.every(r=>r.kind==='message'));
});

test('idle hit, busy fresh, transitions, list/message/file invalidation, failure recovery and deletion',async t=>{
 const dir=fixture(t),src=path.join(dir,'source'),archive=path.join(dir,'archive');const d=source(src,'c');
 let calls=0,ingests=0,fail=false,ingestFail=false;
 const cache=new PollCache({sourceRoot:src,archiveRoot:archive,command:async()=>{calls++;if(fail)throw Error('mock failure');return {success:true,chat:{id:'c',messages:[]}};},ingest(){ingests++;if(ingestFail)throw Error('copy/ingest failed');}});
 const idle={id:'c',state:'idle',isActive:false,messageCount:0};
 await cache.get(idle);await cache.get(idle);assert.equal(calls,1);assert.equal(ingests,1);
 const archiveLog=path.join(archive,'c/chat.log');fs.utimesSync(archiveLog,new Date(0),new Date(0));await cache.get(idle);assert.equal(fs.statSync(archiveLog).mtimeMs,0,'idle must not recopy archive');
 const active={...idle,state:'busy',isActive:true};await cache.get(active);await cache.get(active);assert.equal(calls,3);
 await cache.get(idle);assert.equal(calls,4,'active to idle refresh');
 await cache.get({...idle,messageCount:1});assert.equal(calls,5,'list signature changes invalidate');
 for(const name of ['history.jsonl','metadata.json','chat.log']){fs.appendFileSync(path.join(d,name),'new message');await cache.get({...idle,messageCount:1});}
 assert.equal(calls,8);assert.equal(fs.readFileSync(archiveLog,'utf8'),'initialnew message');
 fail=true;await assert.rejects(cache.get(active),/mock failure/);await assert.rejects(cache.get(idle));fail=false;await cache.get(idle);assert.equal(calls,11);
 fs.unlinkSync(path.join(d,'history.jsonl'));await cache.get(idle);assert.equal(calls,12);assert.ok(fs.existsSync(path.join(archive,'c/history.jsonl')),'archive survives source deletion');
 ingestFail=true;fs.appendFileSync(path.join(d,'chat.log'),'changed');await assert.rejects(cache.get(idle),/ingest failed/);ingestFail=false;await cache.get(idle);assert.equal(calls,14);
 cache.prune([]);assert.equal(cache.entries.size,0);await cache.get(idle);assert.equal(calls,15);
 fs.rmSync(d,{recursive:true});await cache.get(idle);assert.equal(calls,16);assert.ok(fs.existsSync(archiveLog));
});

test('hash cache, strict pool whitelist, missing/malformed state, durable status-only event history',t=>{
 const dir=fixture(t),file=path.join(dir,'state.json'),hashes=new FileHashCache();
 assert.deepEqual(readWorkerPool(file),{workers:[],tasks:[]});fs.writeFileSync(file,'{}');const hash=hashes.hash(file);assert.equal(hashes.hash(file),hash);fs.writeFileSync(file,'{"changed":true}');assert.notEqual(hashes.hash(file),hash);
 const worker={name:'NightShift-PerfAudit',parentName:'NightShift-Dashboard',temporary:true,status:'active',taskId:'t',taskTitle:'audit',chatId:'c',reason:'assigned',tier:'standard',cwd:'private-path',command:'private-command'};
 fs.writeFileSync(file,JSON.stringify({at:'now',workers:[worker,{...worker,parentName:'bad',status:'bad'}],tasks:[{id:'t',title:'audit',status:'completed',command:'private-command'}],secret:'secret'}));
 const pool=readWorkerPool(file);assert.equal(pool.workers[1].status,'attention');assert.equal(pool.workers[1].parentName,null);assert.equal(JSON.stringify(pool).includes('private'),false);assert.deepEqual(Object.keys(pool).sort(),['at','tasks','workers']);
 const events=path.join(dir,'events.jsonl'),journal=new Journal(path.join(dir,'journal'));
 const rows=['task-active','task-completed','worker-inactive','task-queued'].map(kind=>JSON.stringify({at:'2026-10-31T00:00:00Z',kind,worker:worker.name,id:'t',title:'audit',status:'active',command:'private-command',path:'private-path'}));
 fs.writeFileSync(events,rows.join('\n')+'\n'+ '{"incomplete":');ingestPoolEvents(events,journal);ingestPoolEvents(events,journal);assert.equal(journal.rows.length,4);assert.ok(journal.rows.every(r=>r.kind==='status'));assert.equal(JSON.stringify(journal.rows).includes('private'),false);
 assert.equal(new Journal(path.join(dir,'journal')).rows.length,4);fs.writeFileSync(file,'invalid');assert.throws(()=>readWorkerPool(file));fs.unlinkSync(file);assert.equal(hashes.hash(file),null);
});

test('negative CLI responses and real archive IO failures are retried; limiter frees failed slots',async t=>{
 const dir=fixture(t),src=path.join(dir,'source');source(src,'c');const archive=path.join(dir,'blocked');fs.writeFileSync(archive,'blocked');
 let success=false,calls=0;
 const cache=new PollCache({sourceRoot:src,archiveRoot:archive,command:async()=>{calls++;return {success,chat:{id:'c',messages:[]}};},ingest(){}});
 const idle={id:'c',isActive:false,state:'inactive'};
 await assert.rejects(cache.get(idle),/조회 실패/);success=true;await assert.rejects(cache.get(idle));assert.equal(cache.entries.size,0);
 fs.unlinkSync(archive);await cache.get(idle);await cache.get(idle);assert.equal(calls,3);
 const limit=createLimiter(1);let finished=false;
 const results=await Promise.allSettled([limit(()=>{throw Error('failed');}),limit(()=>{finished=true;})]);assert.equal(results[0].status,'rejected');assert.equal(finished,true);
});

test('mock poll measurement with 26 groups and a global three-command cap',async t=>{
 const dir=fixture(t),limit=createLimiter(3);let calls=0,running=0,peak=0;
 const command=args=>limit(async()=>{calls++;running++;peak=Math.max(peak,running);await delay(10);running--;return {success:true,chat:{id:args[2],messages:[]}};});
 const chats=Array.from({length:26},(_,i)=>({id:'c'+i,state:i<24?'idle':'busy',isActive:i>=24}));for(const c of chats)source(dir,c.id);
 const cache=new PollCache({sourceRoot:dir,archiveRoot:path.join(dir,'archive'),command,ingest(){}});
 async function poll(){await Promise.all([command(['list','agents']),command(['group-chat','list']),command(['session','list'])]);await Promise.all(chats.map(c=>cache.get(c)));}
 let start=performance.now();await poll();const coldMs=performance.now()-start;assert.equal(calls,29);
 calls=0;start=performance.now();await poll();const warmMs=performance.now()-start;assert.equal(calls,5);assert.equal(peak,3);
 // Same injected latency and legacy 20-group sequential limit (no processes launched).
 start=performance.now();await Promise.all([delay(10),delay(10),delay(10)]);for(let i=0;i<20;i++)await delay(10);const legacyMs=performance.now()-start;
 console.log(JSON.stringify({measurement:'mock only',groups:26,idle:24,busy:2,latencyMs:10,coldMs:+coldMs.toFixed(1),warmMs:+warmMs.toFixed(1),legacyCapped20Ms:+legacyMs.toFixed(1),coldCalls:29,warmCalls:5,legacyCalls:23,peak}));
});

test('server integration: all 26 groups, public state, CLI failure/recovery, stale threshold and removed group',async t=>{
 const dir=fixture(t),setup=path.join(dir,'.setup');fs.mkdirSync(path.join(setup,'worker-pool'),{recursive:true});
 fs.writeFileSync(path.join(setup,'worker-pool/state.json'),JSON.stringify({workers:[{name:'NightShift-PerfAudit',status:'active',command:'PRIVATE'}],tasks:[]}));
 let handler,nextPoll,fail=true,groups=Array.from({length:26},(_,i)=>({id:'c'+i,topic:'NightShift-'+i,state:'idle',isActive:false,participants:[{name:'NightShift-Dashboard'}]}));
 const counts=new Map();const proc={execPath:process.execPath,env:{LOCALAPPDATA:dir,APPDATA:dir},pid:123};
 const fakeExec=(exe,args,options,cb)=>{const cmd=args.slice(1,-1);const key=cmd.join(' ');counts.set(key,(counts.get(key)||0)+1);let value;
  if(cmd[0]==='list')value=[{id:'a',name:'NightShift-Dashboard',groupId:'group-328267a7-c84e-4fc2-bb1d-63fbb94bd916'}];
  else if(cmd[0]==='session')value={success:true,sessions:[]};
  else if(cmd[1]==='list')value={success:true,chats:groups};
  else {if(fail)return cb(Error('PRIVATE COMMAND'));value={success:true,chat:{...groups.find(c=>c.id===cmd[2]),messages:[]}};}
  cb(null,{stdout:JSON.stringify(value)});
 };
 const load=require;const completion=[];
 const context={require(name){if(name==='node:http')return {createServer(fn){handler=fn;return {listen(p,h,cb){cb();},on(){}};}};if(name==='node:child_process')return {execFile:fakeExec};if(name==='node:util')return {promisify:fn=>(...args)=>new Promise((resolve,reject)=>fn(...args,(err,result)=>err?reject(err):resolve(result)))};if(name==='./model-evidence.cjs')return {configured:()=>new Map(),chatModels:()=>({})};return load(name);},__dirname:path.join(dir,'tools/mission-control'),process:proc,console:{log(){}},setTimeout(fn){nextPoll=fn;completion.shift()?.();},fetch:async()=>{throw Error('offline');},AbortSignal,URL};
 async function runPoll(fn){await new Promise(resolve=>{completion.push(resolve);fn();});}
 await runPoll(()=>vm.runInNewContext(fs.readFileSync(path.join(__dirname,'server.cjs'),'utf8'),context));
 function state(){let body;handler({headers:{host:'127.0.0.1:43821'},method:'GET',url:'/api/state'},{setHeader(){},end(v){body=v;}});return JSON.parse(body);}
 assert.equal(state().chats.length,26);assert.equal(state().workerPool.workers[0].command,undefined);assert.equal(state().ok,false);
 assert.ok(state().chats.every(c=>c.stale&&c.lookupFailed&&c.error&&c.participants[0].name==='NightShift-Dashboard'&&c.messages.length===0),'first failure retains every listed node with explicit error');
 const count=()=>[...counts].filter(([k])=>k.startsWith('group-chat status')).reduce((n,[,v])=>n+v,0);
 assert.equal(count(),26);fail=false;await runPoll(nextPoll);assert.equal(state().ok,true);assert.equal(state().chats.length,26);assert.ok(state().chats.every(c=>!c.stale&&!c.lookupFailed));assert.equal(count(),52);await runPoll(nextPoll);assert.equal(count(),52);
 groups[25]={...groups[25],state:'busy',isActive:true};fail=true;await runPoll(nextPoll);assert.equal(state().ok,false);assert.equal(state().chats.length,26);assert.equal(state().chats.find(c=>c.id==='c25').stale,true);assert.equal(JSON.stringify(state()).includes('PRIVATE'),false);
 fail=false;await runPoll(nextPoll);assert.equal(state().ok,true);
 groups=groups.slice(0,25);await runPoll(nextPoll);assert.equal(state().chats.length,25);
 const RealDate=Date;context.Date=class extends RealDate{static now(){return RealDate.now()+31000;}};assert.equal(state().ok,false);assert.match(state().error,/오래/);
});
