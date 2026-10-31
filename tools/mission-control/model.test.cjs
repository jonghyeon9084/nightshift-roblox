const assert=require('node:assert/strict');
const model=require('./model.js');
const chat={isActive:true,participants:[{name:'NightShift-Planner'},{name:'NightShift-DesignReview'},{name:'NightShift-PlannerExtra'}],messages:[
 {participantName:'user',timestamp:1,content:'[DECISION] This is a task instruction, not completion'},
 {participantName:'moderator',timestamp:2,content:'[PLAN_DRAFT] @NightShift-Planner 초안을 작성하세요.'}
]};
assert.deepEqual(model.view(chat).pending,['NightShift-Planner']);
assert.equal(model.view(chat).stage,'초안 작성');
assert.deepEqual(model.routes(chat.messages[1],chat),[['moderator','NightShift-Planner']]);
chat.messages.push({participantName:'NightShift-Planner',timestamp:3,content:'완료'});
assert.deepEqual(model.view(chat).pending,[]);
chat.messages.push({participantName:'moderator',timestamp:4,content:'[REVIEW_1] @NightShift-DesignReview 독립 검토하세요.'});
assert.deepEqual(model.view(chat).pending,['NightShift-DesignReview']);
assert.equal(model.view(chat).stage,'독립 기획 검토');
assert.deepEqual(model.routes(chat.messages[2],chat),[['NightShift-Planner','moderator']]);
chat.isActive=false;
assert.deepEqual(model.view(chat).pending,[]);
console.log('PASS: Only actual dispatch targets wait; replies close pending state; user instructions do not advance phases; similarly named workers are distinct.');

// Separate overlapping delegations retain each worker's own latest request.
const parallel={isActive:true,participants:[{name:'A'},{name:'B'},{name:'Unassigned'}],messages:[
 {participantName:'B',timestamp:0,content:'Earlier response'},
 {participantName:'moderator',timestamp:1,content:'@A implement A'},
 {participantName:'moderator',timestamp:2,content:'@B implement B'},
 {participantName:'user',timestamp:3,content:'@Unassigned this is not a Moderator delegation'}
]};
assert.deepEqual(model.view(parallel).pending,['A','B']);
parallel.messages.push({participantName:'A',timestamp:4,content:'A complete'});
assert.deepEqual(model.view(parallel).pending,['B']);
parallel.messages.push({participantName:'moderator',timestamp:5,content:'@A revise A'});
assert.deepEqual(model.view(parallel).pending,['A','B'],'an old reply cannot close a new request');
parallel.messages.push({participantName:'B',timestamp:6,content:'B complete'});
assert.deepEqual(model.view(parallel).pending,['A'],'one reply closes only its own request');
parallel.isActive=false;
assert.deepEqual(model.view(parallel).pending,[]);
assert.deepEqual(model.view({isActive:true,participants:parallel.participants,messages:[
 {participantName:'user',timestamp:1,content:'@A'},
 {participantName:'moderator',timestamp:2,content:'@Unknown'}
]}).pending,[]);
console.log('PASS: Overlapping per-worker requests, re-delegation, independent replies, inactive groups and no actual targets.');

// Routing requires exact Unicode boundaries and group membership.
const group={id:'a',isActive:true,participants:[{name:'Worker'},{name:'Worker-Extra'},{name:'작업자'},{name:'A+B'}],messages:[]};
const dispatch=content=>({id:'dispatch',participantName:'moderator',timestamp:10,content});
assert.deepEqual(model.targets(dispatch('@WorkerExtra @Worker_Extra @Worker-Extra2 @Worker한글 x@Worker @@Worker'),group),[]);
assert.deepEqual(model.targets(dispatch('(@Worker), @작업자! @A+B.'),group),['Worker','작업자','A+B']);
assert.deepEqual(model.routes(dispatch('@Worker @Worker-Extra'),group),[['moderator','Worker'],['moderator','Worker-Extra']]);
assert.deepEqual(model.routes({participantName:'Worker'},group),[['Worker','moderator']]);
assert.deepEqual(model.routes({participantName:'user',content:'@Worker'},group),[]);
const other={id:'b',participants:[{name:'Other'}],messages:[]};
assert.deepEqual(model.routes(dispatch('@Worker'),other),[]);
assert.deepEqual(model.routes({participantName:'Worker'},other),[]);
assert.notEqual(model.nodeKey('a','moderator'),model.nodeKey('b','moderator'));
assert.notEqual(model.nodeKey('a','Worker'),model.nodeKey('b','Worker'));
const tracker=model.createTracker();
group.messages=[{...dispatch('@Worker'),id:'old'}];
assert.deepEqual(tracker.ingest([group]),[]);
assert.deepEqual(tracker.ingest([group]),[]);
group.messages.push({...dispatch('@Worker'),id:'new'});
assert.equal(tracker.ingest([group]).length,1);
assert.deepEqual(tracker.ingest([group]),[]);
other.messages=[{...dispatch('@Other'),id:'new'}];
assert.deepEqual(tracker.ingest([group,other]),[]);
other.messages.push({...dispatch('@Other'),id:'next'});
assert.deepEqual(tracker.ingest([other]).map(e=>e.chatId),['b']);
assert.deepEqual(tracker.ingest([group,other]),[]);
const agents=[{name:'NightShift-Main',configuredModel:'wrong-main-model'},{name:'Worker',configuredModel:'gpt-6',configuredEffort:'high'}];
assert.equal(model.modelInfo(group,'moderator',agents).source,'미확인');
assert.equal(model.modelInfo(group,'Worker',agents).source,'구성');
group.modelInfo={moderator:{model:'gpt-6.1',effort:'high',observedAt:'2026-10-31'},participants:{Worker:{model:'gpt-6.1-sol',effort:'low',observedAt:'2026-10-31'}}};
assert.equal(model.modelInfo(group,'moderator',agents).source,'관측');
assert.equal(model.modelInfo(group,'Worker',agents).model,'gpt-6.1-sol');
assert.equal(model.modelInfo(other,'moderator',agents).source,'미확인');
console.log('PASS: Unicode boundaries, group isolation, bidirectional routes, baselines, ID deduplication and model provenance.');

// Packets use the exact drawn geometry, including bent mobile routes and replies.
const branch=model.connectionPath({x:100,y:0},{x:0,y:100},'branch');
assert.equal(branch.d,'M100,0 L100,100 L0,100');
assert.deepEqual(branch.pointAt(.25),{x:100,y:50});
assert.deepEqual(model.pathPoint({geometry:branch},.25,true),{x:50,y:100});
const curve=model.connectionPath({x:0,y:0},{x:200,y:100},'curve');
assert.match(curve.d,/ C/);
const curved=curve.pointAt(.25);assert(Math.abs(curved.y-curved.x/2)>3,'curve sample must not travel on the straight chord');
assert.deepEqual(model.pathPoint({geometry:curve},.25,true),curve.pointAt(.75));
let nativeDistance;
const native={geometry:branch,element:{getTotalLength:()=>300,getPointAtLength:d=>{nativeDistance=d;return {x:d,y:17};}}};
assert.deepEqual(model.pathPoint(native,.2,true),{x:240,y:17});assert.equal(nativeDistance,240);
assert.deepEqual(model.pathPoint({geometry:branch},1,true),{x:100,y:0});
const activityInfo={activity:{scope:'turn',toolCalls:7,lastToolAt:'2026-10-31T09:30:00Z'}};
assert.match(model.activityText(activityInfo,true),/^현재 도구 7회/);
assert.match(model.activityText(activityInfo,false),/^최근 턴 도구 7회/);
assert.equal(model.developmentStatus({alive:true,status:'attention',reason:'needs marker'}).title,'개발 정지·확인 필요');
assert.equal(model.developmentStatus({alive:true,status:'attention'}).working,false);
assert.equal(model.developmentStatus({alive:true,status:'awaiting-review'}).title,'등록 작업 완료·후속 검토');
assert.equal(model.developmentStatus({alive:true,status:'awaiting-review'}).working,false);
assert.equal(model.developmentStatus({alive:true,status:'running'}).working,true);
console.log('PASS: Drawn cubic/mobile branch geometry, reverse arc-length routes, native SVG sampling, current-turn labels and settled development status.');

// Integration regression with a deterministic mock DOM and clock; not a browser test.
async function checkAppDelivery(){
 const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
 class Element{
  constructor(tag=''){this.tagName=tag;this.children=[];this.attrs={};this.style={setProperty(){}};this.value='';this.textContent='';this.clientWidth=364;this.handlers={};const classes=new Set();this.classList={contains:k=>classes.has(k),add:k=>classes.add(k),remove:k=>classes.delete(k),toggle(k,on){if(on===undefined)on=!classes.has(k);if(on)classes.add(k);else classes.delete(k);}};}
  setAttribute(k,v){this.attrs[k]=v;}
  append(...values){for(const value of values){if(value&&typeof value==='object'){value.remove();value.parent=this;}this.children.push(value);}}
  prepend(value){value.remove();value.parent=this;this.children.unshift(value);}
  replaceChildren(...values){for(const e of [...this.children])if(e&&typeof e==='object')e.remove();this.children=[];this.append(...values);}
  remove(){if(this.parent)this.parent.children=this.parent.children.filter(e=>e!==this);this.parent=null;}
  get firstChild(){return this.children[0];}
  addEventListener(kind,fn){this.handlers[kind]=fn;}
  getBoundingClientRect(){return {width:this.clientWidth};}
  getComputedTextLength(){return this.textContent.length*8;}
  querySelectorAll(selector){const result=[];for(const e of this.children){if(!e||typeof e!=='object')continue;if((e.attrs.class||'').split(' ').includes(selector.slice(1)))result.push(e);result.push(...e.querySelectorAll(selector));}return result;}
  querySelector(selector){return this.querySelectorAll(selector)[0]||null;}
 }
 const ids={};for(const m of fs.readFileSync(path.join(__dirname,'index.html'),'utf8').matchAll(/id="([^"]+)"/g))ids[m[1]]=new Element();
 const c={id:'a',topic:'A',state:'idle',isActive:true,participants:[{name:'Worker'}],messages:[{id:'old',participantName:'moderator',timestamp:1,content:'@Worker'}]};
 let snapshot={ok:true,at:new Date().toISOString(),agents:[{name:'Worker',states:['idle']}],chats:[c]},now=0,frames=[];
 const heading=new Element(),headingLabel=new Element();heading.append(headingLabel);
 const context={console,URLSearchParams,innerHeight:844,performance:{now:()=>now},document:{head:new Element(),body:new Element(),getElementById:id=>{assert.ok(ids[id],id);return ids[id];},createElement:tag=>new Element(tag),createElementNS:(_ns,tag)=>new Element(tag),createTextNode:t=>t,querySelector:selector=>selector==='.map-heading'?heading:selector==='.map-heading > span'?headingLabel:null,querySelectorAll:selector=>ids.graph.querySelectorAll(selector)},Option:class extends Element{constructor(t,v){super();this.textContent=t;this.value=v;}},matchMedia:()=>({matches:false,addEventListener(){}}),ResizeObserver:class{observe(){}},requestAnimationFrame:fn=>frames.push(fn),setTimeout:()=>{},setInterval:()=>{},fetch:async url=>({ok:true,json:async()=>url.startsWith('/api/history')?{entries:[],total:0,nextCursor:null}:structuredClone(snapshot)})};
 vm.createContext(context);vm.runInContext(fs.readFileSync(path.join(__dirname,'model.js'),'utf8'),context);vm.runInContext(fs.readFileSync(path.join(__dirname,'app.js'),'utf8'),context);
 const settle=()=>new Promise(setImmediate),evaluate=code=>vm.runInContext(code,context),packets=()=>ids.graph.querySelectorAll('.packet');
 async function finishPackets(){now+=4000;const current=frames;frames=[];for(const fn of current)fn(now);await settle();}
 await settle();assert.equal(packets().length,0,'baseline must not animate');
 const replay=ids.replay.onclick();assert.equal(packets().length,1);const historical=packets()[0];
 assert.equal(historical.children.filter(e=>e.tagName==='circle').length,2);assert.equal(historical.children.filter(e=>e.tagName==='path').length,0,'packet uses circles, no arrow path');
 c.messages.push({id:'during',participantName:'Worker',timestamp:2,content:'new reply during replay'});
 await evaluate('refresh()');await evaluate('refresh()');
 assert.equal(evaluate('pendingLive.length'),1,'live arrival stays queued exactly once');assert.equal(packets()[0],historical,'history and live must not mix');
 const originalParent=historical.parent,originalEpoch=evaluate('epoch');
 c.state='moderator-thinking';c.modelInfo={moderator:{model:'gpt-6.1',effort:'high'}};
 await evaluate('refresh()');assert.equal(packets()[0],historical);assert.equal(historical.parent,originalParent,'poll must retain packet DOM identity and focus opportunity');assert.equal(evaluate('epoch'),originalEpoch);assert.equal(evaluate('replaying'),true);
 await finishPackets();await replay;await settle();
 assert.equal(evaluate('replaying'),false);assert.equal(packets().length,1,'queued live arrival delivered after replay');
 assert.match(packets()[0].attrs['aria-label'],/재생 중 수신한 실제 활동/);assert.match(packets()[0].attrs['aria-label'],/Worker → moderator/);
 const live=packets()[0];await evaluate('refresh()');assert.equal(packets()[0],live);assert.equal(evaluate('pendingLive.length'),0);
 c.modelInfo.moderator.effort='low';await evaluate('refresh()');assert.equal(packets()[0],live,'live packet survives model update too');
 await finishPackets();assert.equal(packets().length,0);await evaluate('refresh()');assert.equal(packets().length,0,'delayed live event cannot repeat');
 c.messages.push({id:'switch',participantName:'Worker',timestamp:3,content:'reply'});await evaluate('refresh()');assert.equal(packets().length,1);
 ids.chat.value='a';ids.chat.onchange();assert.equal(packets().length,0,'user map switch explicitly cancels');await finishPackets();
 c.messages.push({id:'disconnect',participantName:'Worker',timestamp:4,content:'reply'});await evaluate('refresh()');assert.equal(packets().length,1);
 snapshot.ok=false;await evaluate('refresh()');assert.equal(packets().length,0,'disconnect explicitly cancels');assert.equal(ids.replay.disabled,true);
 console.log('PASS: Mock DOM replay/live queue isolation, delayed delivery once, poll/model-update packet persistence, user-switch and disconnect cancellation.');
 snapshot.ok=true;snapshot.development={alive:true,status:'awaiting-review'};snapshot.agents=Array.from({length:13},(_,i)=>({name:i?'Worker'+i:'Worker'}));
 ids.chat.value='';ids.chat.onchange();await evaluate('refresh()');
 vm.runInContext(fs.readFileSync(path.join(__dirname,'fleet.js'),'utf8'),context);
 const nodes=ids.graph.querySelectorAll('.node');assert.equal(nodes.length,14,'one hub plus all 13 registered workers');
 assert(parseFloat(ids.graph.style.height)<context.innerHeight-115,'13 workers fit a 390-class mobile viewport at 844px height');
 assert.match(evaluate('routePaths[model.nodeKey("a","Worker")].geometry.d'),/ L/,'fleet mobile packet route shares its bent visible path');
 assert.match(evaluate('fleetStatus.textContent'),/^등록 작업 완료·후속 검토/);
 const hub=nodes.find(n=>n.attrs['data-worker']==='orchestrator');assert(!hub.attrs.class.includes('busy'),'alive settled runner must not imply development in progress');
 console.log('PASS: Mock fleet central hub, all 13 mobile nodes, connected branch path and alive awaiting-review status.');
}
checkAppDelivery().catch(error=>{console.error(error);process.exitCode=1;});
