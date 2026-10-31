const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const model=require('./model.js');
const fixture={agents:[{name:'NightShift-Dashboard',configuredModel:'configured-model',configuredEffort:'low'},{name:'RegistryOnly'},{name:'NightShift-Main'}],workerPool:{at:'2026-10-31',workers:[
 {name:'MainChild',parentName:'NightShift-Main',status:'waiting'},
 {name:'NightShift-Dashboard',status:'active',taskTitle:'계층 UI',reason:'실제 배정',chatId:'chat'},
 {name:'NightShift-PerfAudit',parentName:'NightShift-Dashboard',temporary:true,status:'inactive',taskId:'perf',reason:'완료',chatId:'chat'},
 {name:'Candidate',status:'queued'},
 {name:'Unknown',parentName:'missing'},
 {name:'CycleA',parentName:'CycleB'},{name:'CycleB',parentName:'CycleA'},
 {name:'Self',parentName:'Self'},
 ],tasks:[{id:'perf',title:'성능 검토'}]},chats:[{id:'chat',topic:'실제 그룹',isActive:true,state:'awaiting-responses',participants:[{name:'NightShift-Dashboard'},{name:'NightShift-PerfAudit'},{name:'ChatOnly'}],modelInfo:{participants:{'NightShift-PerfAudit':{model:'observed-model',effort:'high',observedAt:'2026-10-31',activity:{scope:'turn',toolCalls:2}}}},messages:[]}]};
const list=model.workers(fixture),worker=name=>list.find(a=>a.name===name);
assert.equal(worker('NightShift-Dashboard').configuredModel,'configured-model');
assert.equal(worker('NightShift-PerfAudit').parent,'NightShift-Dashboard');
assert.equal(list.filter(a=>a.name==='NightShift-Dashboard').length,1);
assert(worker('RegistryOnly'));assert(worker('ChatOnly'));assert(worker('Candidate'));
for(const n of ['Unknown','CycleA','CycleB','Self'])assert.equal(worker(n).parent,'orchestrator');
assert.match(model.workerStatus(worker('NightShift-PerfAudit'),false),/inactive\(완료\).*재사용/);
assert.match(model.workerStatus(worker('Candidate'),false),/풀 상태: queued/);
assert.match(model.workerStatus(worker('NightShift-PerfAudit'),true),/실제 명령/);
assert.match(model.workerStatus(worker('NightShift-PerfAudit'),true,false),/마지막 기록/);
assert.equal(model.workers({agents:[{name:'Legacy'}],chats:[]})[0].parent,'orchestrator');
assert.equal(worker('NightShift-Main').parent,'orchestrator','registered Main is an independent root child');
assert.equal(worker('MainChild').parent,'NightShift-Main','Main must remain the explicit parent');
const missingMain=model.workers({workerPool:{workers:[{name:'MainChild',parentName:'NightShift-Main'}]}});
assert.equal(missingMain.length,1,'missing Main is not synthesized');
assert.equal(missingMain[0].parent,'orchestrator');assert.match(missingMain[0].parentIssue,/알 수 없는 부모/);
const mainCycle=model.workers({agents:[{name:'NightShift-Main',parentName:'MainChild'},{name:'MainChild',parentName:'NightShift-Main'}]});
for(const a of mainCycle){assert.equal(a.parent,'orchestrator');assert.match(a.parentIssue,/순환/);}
const layout=model.hierarchyLayout(list);
assert.equal(layout.coords.orchestrator.x,layout.width/2);assert.equal(layout.coords.orchestrator.y,layout.height/2);
for(const [name,p] of Object.entries(layout.coords)){const half=name==='orchestrator'?108:76;assert(Number.isFinite(p.x)&&Number.isFinite(p.y));assert(p.x>=half&&p.x+half<=layout.width);assert(p.y>=38&&p.y+38<=layout.height);}
for(const width of [320,390,1280]){const many=model.workers({agents:Array.from({length:30},(_,i)=>({name:'W'+i}))}),circle=model.hierarchyLayout(many,width),nodes=many.map(a=>circle.coords[a.name]);for(let i=0;i<nodes.length;i++)for(let j=i+1;j<nodes.length;j++)assert(Math.abs(nodes[i].x-nodes[j].x)>=143.9||Math.abs(nodes[i].y-nodes[j].y)>=63.9,'radial nodes must not overlap');}
assert.deepEqual(model.routes({participantName:'user',content:'@NightShift-PerfAudit'},fixture.chats[0]),[]);
assert.deepEqual(model.routes({participantName:'moderator',content:'@NightShift-PerfAudit'},fixture.chats[0]),[['moderator','NightShift-PerfAudit']]);
assert.deepEqual(model.routes({participantName:'NightShift-PerfAudit',content:'완료'},fixture.chats[0]),[['NightShift-PerfAudit','moderator']]);
console.log('PASS hierarchy: merge, legacy, invalid parents/cycles, inactive reuse, pending vs pool, real routes and tree bounds');

// Deterministic DOM integration; this does not claim real browser rendering.
class Element{
 constructor(tag=''){this.tagName=tag;this.children=[];this.attrs={};this.style={setProperty(){}};this.value='';this.textContent='';this.clientWidth=320;this.handlers={};const set=new Set();this.classList={contains:k=>set.has(k),add:k=>set.add(k),remove:k=>set.delete(k),toggle(k,on){if(on===undefined)on=!set.has(k);if(on)set.add(k);else set.delete(k);}};}
 setAttribute(k,v){this.attrs[k]=v;}
 append(...values){for(const value of values){if(value&&typeof value==='object'){value.remove();value.parent=this;}this.children.push(value);}}
 prepend(value){value.remove();value.parent=this;this.children.unshift(value);}
 replaceChildren(...values){for(const e of [...this.children])if(e&&typeof e==='object')e.remove();this.children=[];this.append(...values);}
 remove(){if(this.parent)this.parent.children=this.parent.children.filter(e=>e!==this);this.parent=null;}
 get firstChild(){return this.children[0];}
 addEventListener(kind,fn){this.handlers[kind]=fn;}
 getBoundingClientRect(){return {width:this.clientWidth,height:200};}
 getComputedTextLength(){return this.textContent.length*8;}
 querySelectorAll(selector){return this.children.filter(e=>e&&typeof e==='object').flatMap(e=>[...((e.attrs.class||'').split(' ').includes(selector.slice(1))?[e]:[]),...e.querySelectorAll(selector)]);}
 querySelector(s){return this.querySelectorAll(s)[0]||null;}
}
async function run(){
 const ids={};for(const m of fs.readFileSync(path.join(__dirname,'index.html'),'utf8').matchAll(/id="([^"]+)"/g))ids[m[1]]=new Element();
 const heading=new Element(),label=new Element();heading.append(label);
 let snapshot={...structuredClone(fixture),ok:true,at:'2026-10-31',development:{alive:true,status:'awaiting-review'}};
 const context={console,URLSearchParams,innerHeight:640,performance:{now:()=>0},document:{head:new Element(),body:new Element(),getElementById:id=>{assert(ids[id],id);return ids[id];},createElement:t=>new Element(t),createElementNS:(_,t)=>new Element(t),createTextNode:t=>t,querySelector:s=>s==='.map-heading'?heading:s==='.map-heading > span'?label:null,querySelectorAll:s=>ids.graph.querySelectorAll(s)},Option:class extends Element{constructor(t,v){super();this.textContent=t;this.value=v;}},matchMedia:()=>({matches:false,addEventListener(){}}),ResizeObserver:class{observe(){}},requestAnimationFrame(){},setTimeout(){},setInterval(){},fetch:async url=>({ok:true,json:async()=>url.startsWith('/api/history')?{entries:[],total:0,nextCursor:null}:structuredClone(snapshot)})};
 vm.createContext(context);const evaluate=s=>vm.runInContext(s,context);
 for(const file of ['model.js','app.js','fleet.js'])evaluate(fs.readFileSync(path.join(__dirname,file),'utf8'));
 await new Promise(setImmediate);
 const nodes=()=>ids.graph.querySelectorAll('.node'),child=()=>nodes().find(n=>n.attrs['data-worker']==='NightShift-PerfAudit');
 assert.equal(nodes().length,list.length+1);assert.equal(child().attrs['data-parent'],'NightShift-Dashboard');
 assert(nodes().some(n=>n.attrs['data-worker']==='NightShift-Main'&&n.attrs['data-parent']==='orchestrator'));
 const mainChild=nodes().find(n=>n.attrs['data-worker']==='MainChild');assert.equal(mainChild.attrs['data-parent'],'NightShift-Main');
 const mainOwnership=ids.graph.querySelectorAll('.ownership-edge').find(e=>e.attrs['data-worker']==='MainChild');assert.equal(mainOwnership.attrs['data-parent'],'NightShift-Main');
 mainChild.handlers.click();assert.match(ids.detail.textContent,/부모: NightShift-Main/);
 const ownership=ids.graph.querySelectorAll('.ownership-edge').find(e=>e.attrs['data-worker']==='NightShift-PerfAudit');assert.equal(ownership.attrs['data-parent'],'NightShift-Dashboard');
 const edge=evaluate('routePaths[model.nodeKey("chat","NightShift-PerfAudit")]');
 assert.notEqual(edge.element,ownership);assert.deepEqual({...edge.geometry.pointAt(0)},{...layout.coords.orchestrator});assert.deepEqual({...edge.geometry.pointAt(1)},{...layout.coords['NightShift-PerfAudit']});
 assert.equal(ids.graph.querySelectorAll('.packet').length,0,'pool status and tool observations never animate');
 assert(!child().attrs.class.includes('busy'));assert.match(child().attrs['aria-label'],/inactive\(완료\)/);
 assert(parseFloat(ids.graph.style.width)<=320);assert(parseFloat(ids.graph.style.height)<=340);
 child().handlers.click();assert.match(ids.detail.textContent,/부모: NightShift-Dashboard/);assert.match(ids.detail.textContent,/작업: 성능 검토/);assert.match(ids.detail.textContent,/실행그룹: chat/);assert.match(ids.detail.textContent,/관측 모델: observed-model · effort: high/);assert.match(ids.detail.textContent,/구성 모델: 미확인/);
 ids['worker-picker'].value='NightShift-Dashboard';ids['worker-picker'].onchange();assert.match(ids.detail.textContent,/구성 모델: configured-model · effort: low/);assert(context.document.body.classList.contains('detail-open'));
 ids['fleet-controls'].children.find(e=>e.textContent==='100% 확대').onclick();assert.equal(parseFloat(ids.graph.style.width),layout.width);
 ids['fleet-controls'].children.find(e=>e.textContent==='전체보기').onclick();assert(parseFloat(ids.graph.style.width)<=320);
 snapshot.workerPool.workers.push({name:'NewChild',parentName:'NightShift-PerfAudit',status:'waiting'});await evaluate('refresh()');assert(nodes().some(n=>n.attrs['data-worker']==='NewChild'&&n.attrs['data-parent']==='NightShift-PerfAudit'),'pool-only changes trigger redraw');
 snapshot.agents=snapshot.agents.filter(a=>a.name!=='NightShift-Main');await evaluate('refresh()');
 assert(!nodes().some(n=>n.attrs['data-worker']==='NightShift-Main'));
 const orphan=nodes().find(n=>n.attrs['data-worker']==='MainChild');assert.equal(orphan.attrs['data-parent'],'orchestrator');
 orphan.handlers.click();assert.match(ids.detail.textContent,/알 수 없는 부모/);assert.match(ids.detail.textContent,/부모: orchestrator \(NightShift-Main\)/);
 snapshot.ok=false;await evaluate('refresh()');assert.match(child().attrs['aria-label'],/마지막 기록/);
 console.log('PASS hierarchy DOM: registered Main node/child edge, missing Main fallback/reason, direct Moderator route, no synthetic packets, mobile 320px fit, zoom, details, pool redraw and disconnect');
}
run().catch(error=>{console.error(error);process.exitCode=1;});
