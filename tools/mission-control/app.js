const $=id=>document.getElementById(id);
const ns='http://www.w3.org/2000/svg', model=NightShiftModel, tracker=model.createTracker();
const motion=matchMedia('(prefers-reduced-motion: reduce)');
let motionOverride=null;try{const saved=localStorage.getItem('nightshift-motion');if(saved!==null)motionOverride=saved==='on';}catch{}
const motionReduced=()=>motionOverride===null?motion.matches:!motionOverride;
let state=null, selected='', signature='', points={}, connected=false, replaying=false, epoch=0;
let pendingLive=[], delivering=false, packetLayer=null, routePaths={};
const phases={idle:'대기','moderator-thinking':'Moderator 작업 중','agent-working':'워커 작업 중','awaiting-responses':'응답 대기',error:'오류'};
function svg(tag,attrs={},text){const e=document.createElementNS(ns,tag);for(const [k,v] of Object.entries(attrs))e.setAttribute(k,v);if(text!=null)e.textContent=text;return e;}
function activate(el,fn){el.addEventListener('click',fn);el.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();fn();}});}
function showMessage(m,chat,route){
 const rs=route?[route]:model.routes(m,chat);
 $('detail').textContent=`그룹: ${chat.topic} (${chat.id})\n시각: ${new Date(m.timestamp).toLocaleString('ko-KR')}\n메시지 ID: ${m.id??'없음'}\n발신: ${m.participantName}\n수신: ${rs.length?rs.map(r=>r[1]).join(', '):'확인된 라우팅 없음'}\n\n${m.content||''}`;
}
function showNode(chat,name){
 const info=model.modelInfo(chat,name,state.agents);
 const busy=!!chat?.isActive&&(name==='moderator'?chat.state==='moderator-thinking':model.view(chat).pending.includes(name));
 const configured=model.workers(state).find(a=>a.name===name)||state.agents.find(a=>a.name===name);
 const observed=name==='moderator'?chat?.modelInfo?.moderator:chat?.modelInfo?.participants?.[name];
 const task=state.workerPool?.tasks?.find(t=>(t.id||t.taskId)===configured?.taskId);
 const ownership=configured?`\n부모: ${configured.parent} (${configured.parentName||'루트'})\n${configured.parentIssue||'부모 관계는 작업 소속이며 통신 증거가 아닙니다.'}\n작업: ${configured.taskTitle||task?.title||configured.taskId||'미지정'}\n이유: ${configured.reason||'미기록'}\n실행그룹: ${configured.chatId||chat?.id||'미지정'}\n풀 상태: ${configured.status||'미등록'} · ${configured.temporary?'임시':'일반'} · ${configured.tier||'tier 미지정'}\n표시 상태: ${model.workerStatus(configured,busy,connected)}`:'';
 const m=chat&&[...(chat.messages||[])].reverse().find(m=>m.participantName===name);
 $('detail').textContent=`${chat?'그룹: '+chat.topic+' ('+chat.id+')':'등록된 일반 세션'}\n세션: ${name}\n관측 모델: ${observed?.model||'미확인'} · effort: ${observed?.effort||'미확인'}\n구성 모델: ${configured?.configuredModel||'미확인'} · effort: ${configured?.configuredEffort||'미확인'}${ownership}\n관측 시각: ${info.observedAt?new Date(info.observedAt).toLocaleString('ko-KR'):'미확인'}\n${model.activityText(info,busy&&connected)}\n집계 범위: 마지막 턴 시작 이후 · 최근 도구: ${info.activity?.lastToolName||'미확인'}\n최근 이벤트: ${info.activity?.lastEventAt?new Date(info.activity.lastEventAt).toLocaleString('ko-KR'):'미확인'}${configured?.configuredModel?'\n다음 요청 설정: '+configured.configuredModel+' · '+configured.configuredEffort:''}\n\n${m?.content||'해당 세션의 응답 기록 없음'}`;
}
function addEdge(parent,key,a,b,kind='line'){const geometry=model.connectionPath(a,b,kind),element=svg('path',{d:geometry.d,class:'edge'});parent.append(element);const edge={geometry,element};if(Array.isArray(key))for(const k of key)routePaths[k]=edge;else routePaths[key]=edge;return edge;}
function stopPackets(){epoch++;document.querySelectorAll('.packet').forEach(e=>e.remove());}
function selectMap(id){stopPackets();replaying=false;selected=id;signature='';render();void drainLive();}
function receiveLive(fresh){for(const entry of fresh){const chat=state.chats.find(c=>c.id===entry.chatId);pendingLive.push({...entry,chat,receivedAt:new Date().toISOString(),deferred:replaying});}void drainLive();}
async function drainLive(){
 if(delivering||replaying||!connected)return;
 delivering=true;const run=epoch;
 try{while(pendingLive.length&&connected&&!replaying&&run===epoch){const entry=pendingLive.shift();if(!selected||selected===entry.chatId)await animate(entry.message,entry.chat,false,entry);}}
 finally{delivering=false;if(pendingLive.length&&connected&&!replaying)void drainLive();}
}
function visibleChats(){return (state?.chats||[]).filter(c=>!selected||c.id===selected);}
function graph(){
 const root=$('graph');root.style.width='100%';const w=Math.max(280,Math.floor(root.getBoundingClientRect().width)),compact=w<560;
 // Rebuild only the scene: keep the packet layer attached, including keyboard focus.
 const old=root.querySelector('.map-scene');if(old)old.remove();
 const g=svg('g',{class:'map-scene'});root.prepend(g);
 if(!packetLayer){packetLayer=svg('g',{class:'packet-layer'});root.append(packetLayer);}
 points={};routePaths={};let y=26;
 function fitText(el){const original=el.textContent;while(el.textContent.length>1&&el.getComputedTextLength()>w-28)el.textContent=el.textContent.slice(0,-2)+'…';el.append(svg('title',{},original));}
 const addText=(x,y,text,cls)=>{const el=svg('text',{x,y,class:cls||''},text);g.append(el);fitText(el);};
 function node(chat,name,x,y,main,busy,registered=false){
  const key=model.nodeKey(registered?'registry':chat.id,name),info=model.modelInfo(chat,name,state.agents),nw=compact?130:176;
  points[key]={x,y};const group=svg('g',{class:`node ${main?'main':''} ${busy?'busy':''}`,transform:`translate(${x},${y})`,role:'button',tabindex:0,'aria-label':`${chat?.topic||'일반 세션'} ${name} · ${info.model} · ${info.source}`,'data-worker':name,'data-parent':model.workers(state).find(a=>a.name===name)?.parent||''});
  const title=svg('title',{},`${name} · ${info.model} · ${info.effort} · ${info.source}`);
  const label=main?'Moderator':model.label(name);
  const clip=(s,n)=>s.length>n?s.slice(0,n-1)+'…':s;
  group.append(title,svg('rect',{x:-nw/2,y:-44,width:nw,height:88,rx:12}),svg('text',{x:0,y:-24,'text-anchor':'middle'},clip(label,compact?18:24)),svg('text',{x:0,y:-6,'text-anchor':'middle',class:'sub'},clip(info.short,compact?20:27)),svg('text',{x:0,y:12,'text-anchor':'middle',class:'sub'},info.source+' · '+(busy?'응답 대기':main?(phases[chat.state]||chat.state||'미확인'):registered?'일반 세션':'참가 세션')),svg('text',{x:0,y:31,'text-anchor':'middle',class:'activity'},model.activityText(info,busy&&connected)));
  activate(group,()=>showNode(chat,name));g.append(group);
 }
 for(const chat of visibleChats()){
  const names=model.participants(chat),view=model.view(chat);
  const heading=svg('g',{role:'button',tabindex:0,class:'group-title','aria-label':chat.topic+' 그룹 상세'});
  heading.append(svg('text',{x:14,y},chat.topic||chat.id));activate(heading,()=>selectMap(chat.id));g.append(heading);fitText(heading.firstChild);
  addText(14,y+20,`${chat.isActive?'활성':'비활성'} · ${phases[chat.state]||chat.state||'상태 미확인'}${view.stage?' · '+view.stage:''}`,'group-sub');
  y+=82;const mx=compact?78:w*.24,wx=compact?w-78:w*.75;
  for(let i=0;i<names.length;i++){const py=y+i*108;addEdge(g,model.nodeKey(chat.id,names[i]),{x:mx,y},{x:wx,y:py});}
  node(chat,'moderator',mx,y,true,false);
  names.forEach((name,i)=>node(chat,name,wx,y+i*108,false,view.pending.includes(name)));
  y+=Math.max(1,names.length)*108;g.append(svg('path',{d:`M14,${y-28} H${w-14}`,class:'group-divider'}));
 }
 if(!selected&&(state.agents||[]).length){
  addText(14,y,'등록된 일반 세션 · 그룹 세션과 별개','group-title');y+=65;
  const cols=compact?2:Math.max(2,Math.floor(w/210));
  state.agents.forEach((a,i)=>node(null,a.name,w*(i%cols+.5)/cols,y+Math.floor(i/cols)*104,false,false,true));
  y+=Math.ceil(state.agents.length/cols)*104;
 }
 if(!visibleChats().length)addText(14,28,'확인된 그룹 대화가 없습니다.');
 const h=Math.max(220,y);root.style.height=h+'px';root.setAttribute('viewBox',`0 0 ${w} ${h}`);
}
function animate(m,chat,replay=false,receipt=null){
 if(!connected)return Promise.resolve();
 const rs=model.routes(m,chat),run=epoch;
 if(!rs.length)return Promise.resolve();
 $('mode').textContent=(replay?'과거 기록 재생 · ':receipt?.deferred?'재생 중 수신한 실제 활동 · ':'새 실제 메시지 · ')+chat.topic;
 return Promise.all(rs.map(route=>new Promise(resolve=>{
  const [from,to]=route,edge=routePaths[model.nodeKey(chat.id,from==='moderator'?to:from)];if(!edge)return resolve();
  const packet=svg('g',{class:'packet '+(from==='moderator'?'command':'reply'),role:'button',tabindex:0,'aria-label':`${replay?'과거 재생':receipt?.deferred?'재생 중 수신한 실제 활동':'새 메시지'} ${from} → ${to} · ${new Date(m.timestamp).toLocaleString('ko-KR')}`});
  packet.append(svg('circle',{r:14,class:'packet-halo'}),svg('circle',{r:5.5,class:'packet-orb'}),svg('title',{},`${from} → ${to} · 수신 확인: ${receipt?.receivedAt||'과거 재생'} · ${m.content}`));const origin=model.pathPoint(edge,motionReduced()?1:0,from!=='moderator');packet.setAttribute('transform',`translate(${origin.x},${origin.y})`);activate(packet,()=>showMessage(m,chat,route));packetLayer.append(packet);
  const start=performance.now();function tick(t){
   if(run!==epoch||!connected){packet.remove();return resolve();}
   const u=motionReduced()?1:Math.min(1,(t-start)/1800);
   const p=model.pathPoint(edge,u,from!=='moderator');packet.setAttribute('transform',`translate(${p.x},${p.y})`);
   if(u<1)requestAnimationFrame(tick);else if(t-start<3000)requestAnimationFrame(tick);else{packet.remove();resolve();}
  }requestAnimationFrame(tick);
 })));
}
function render(){
 if(!state)return;
 $('chat').replaceChildren(new Option('전체 맵 · 모든 그룹과 세션',''),...(state.chats||[]).map(c=>new Option(c.topic,c.id)));$('chat').value=selected;
 $('phase').textContent=selected?'그룹 상세':'전체 맵 · '+state.chats.length+'개 그룹';
 $('stage').textContent='';
 const dev=state.development,devStatus=model.developmentStatus(dev,connected);$('development').textContent=devStatus.title+' · '+devStatus.reason;
 const sig=JSON.stringify([selected,connected,dev,$('graph').clientWidth,(state.chats||[]).map(c=>[c.id,c.topic,c.state,c.isActive,c.participants,c.modelInfo,model.view(c).pending]),state.agents,state.workerPool]);
 if(sig!==signature){signature=sig;graph();}
 $('messages').replaceChildren();const q=$('message-query').value.toLocaleLowerCase();
 const rows=visibleChats().flatMap(chat=>(chat.messages||[]).map(m=>({chat,m}))).sort((a,b)=>new Date(b.m.timestamp)-new Date(a.m.timestamp));
 for(const {chat,m} of rows){
  if(q&&!`${chat.topic} ${m.participantName} ${m.content}`.toLocaleLowerCase().includes(q))continue;
  const li=document.createElement('li'),b=document.createElement('button'),strong=document.createElement('strong'),time=document.createElement('time'),txt=document.createElement('span');
  const rs=model.routes(m,chat);strong.textContent=`${chat.topic} · ${m.participantName} → ${rs.length?rs.map(r=>r[1]).join(', '):'수신 미확인'}`;
  time.textContent=new Date(m.timestamp).toLocaleString('ko-KR');txt.textContent=(m.content||'').slice(0,160);b.append(strong,time,txt);b.onclick=()=>showMessage(m,chat);li.append(b);$('messages').append(li);
 }
 $('replay').disabled=!connected||replaying||!rows.length;
 $('agents').replaceChildren();for(const a of model.workers(state)){const el=document.createElement('div'),small=document.createElement('small');el.className='agent';el.append(document.createTextNode(a.name));const info=model.modelInfo(null,a.name,state.agents);small.textContent=`${info.short} · ${info.source} · ${(a.states||[]).join(', ')||'미확인'}`;el.append(small);$('agents').append(el);}
}
function disconnected(reason){connected=false;replaying=false;stopPackets();$('connection').textContent='연결 끊김 · 마지막 기록 유지';$('connection').className='error';$('updated').textContent=reason;$('mode').textContent='연결 끊김 · 패킷 이동 중단';$('replay').disabled=true;render();}
async function refresh(){
 try{
  const response=await fetch('/api/state',{cache:'no-store'});if(!response.ok)throw new Error('HTTP '+response.status);const next=await response.json();
  if(!next.ok){if(!state){state={...next,chats:next.chats||[],agents:next.agents||[]};tracker.ingest(state.chats);render();}disconnected(next.error||'현재 상태 확인 실패');return;}
  connected=true;state={...next,chats:next.chats||[],agents:next.agents||[]};const fresh=tracker.ingest(state.chats);
  if(selected&&!state.chats.some(c=>c.id===selected)){stopPackets();replaying=false;selected='';}
  $('connection').textContent='전체조정 서비스 · Maestro 연결됨';$('connection').className='';$('updated').textContent='마지막 조회 '+new Date(state.at).toLocaleString('ko-KR');
  if(!replaying&&!delivering)$('mode').textContent=motionReduced()?'실제 기록 · 움직임 줄이기':'실제 기록 · 최초 이력 제외 / 새 ID만 이동';
  render();receiveLive(fresh);
 }catch(error){disconnected('새 상태를 확인하지 못했습니다. '+error.message);}finally{setTimeout(refresh,2000);}
}
$('chat').onchange=()=>selectMap($('chat').value);
$('message-query').oninput=()=>render();
$('replay').onclick=async()=>{
 if(!connected||replaying)return;stopPackets();replaying=true;const run=epoch;$('replay').disabled=true;
 const rows=visibleChats().flatMap(chat=>model.view(chat).messages.map(m=>({chat,m}))).sort((a,b)=>new Date(a.m.timestamp)-new Date(b.m.timestamp));
 for(const {chat,m} of rows){if(run!==epoch||!connected||!replaying)break;showMessage(m,chat);await animate(m,chat,true);}
 if(run===epoch){replaying=false;$('mode').textContent='과거 기록 재생 완료 · 실시간 대기';$('replay').disabled=!connected;void drainLive();}
};
motion.addEventListener('change',()=>{stopPackets();replaying=false;$('mode').textContent='동작 설정 변경 · 실시간 대기';render();void drainLive();});
function motionLabel(){$('motion-toggle').textContent=motionReduced()?'이동 켜기':'이동 끄기';}
$('motion-toggle').onclick=()=>{motionOverride=motionReduced();try{localStorage.setItem('nightshift-motion',motionOverride?'on':'off');}catch{}motionLabel();};motionLabel();
let lastWidth=0;new ResizeObserver(()=>{const w=$('graph').clientWidth;if(w!==lastWidth){lastWidth=w;stopPackets();signature='';replaying=false;render();void drainLive();}}).observe($('graph'));
refresh();
let historyCursor=null,historyBusy=false,historyExpanded=false,historyGeneration=0;
const historyKinds={message:'지시·응답',status:'작업 상태',file:'산출물'};
async function loadHistory(more=false) {
 if(historyBusy)return;historyBusy=true;
 const generation=historyGeneration;
 try {
  const params=new URLSearchParams({kind:$('history-kind').value,q:$('history-query').value,limit:'50'});
  if(more&&historyCursor!==null)params.set('before',historyCursor);
  const response=await fetch('/api/history?'+params,{cache:'no-store'});if(!response.ok)throw new Error('HTTP '+response.status);
  const result=await response.json();if(generation!==historyGeneration)return;
  if(!more)$('history-list').replaceChildren();
  for(const entry of result.entries) {
   const li=document.createElement('li'),details=document.createElement('details'),summary=document.createElement('summary'),pre=document.createElement('pre');
   summary.textContent=`${new Date(entry.timestamp||entry.observedAt).toLocaleString('ko-KR')} · ${historyKinds[entry.kind]||entry.kind} · ${entry.actor}${entry.baseline?' · 최초 확인':''}${entry.topic?' · '+entry.topic:''}`;
   const excerpt=document.createElement('span');excerpt.className='history-excerpt';excerpt.textContent=entry.content?.slice(0,180)||'';
   summary.append(excerpt);pre.textContent=(entry.content||'')+(entry.hash?'\nSHA256: '+entry.hash:'')+'\n\n관찰 시각: '+new Date(entry.observedAt).toLocaleString('ko-KR');
   details.append(summary,pre);li.append(details);$('history-list').append(li);
  }
  historyCursor=result.nextCursor;$('history-more').hidden=historyCursor===null;
  $('history-summary').textContent=`누적 ${result.total}개 · 현재 ${$('history-list').children.length}개 표시 · ${more?'이전 기록 탐색 중':'최신 기록 자동 갱신'}`;
 }catch(error){$('history-summary').textContent='이력을 새로 가져오지 못했습니다. 마지막 기록을 유지합니다.';}
 finally{historyBusy=false;if(generation!==historyGeneration)loadHistory();}
}
$('history-filter').onsubmit=e=>{e.preventDefault();historyGeneration++;historyExpanded=false;loadHistory();};
$('history-more').onclick=()=>{historyExpanded=true;loadHistory(true);};
loadHistory();setInterval(()=>{if(!historyExpanded&&!document.querySelector('#history-list details[open]'))loadHistory();},10000);
