// Unified role view: one orchestration hub, one node for every registered worker.
// Real group/session identity remains attached to every packet and detail entry.
const groupGraph=graph;
graph=function(){
 if(selected)return groupGraph();
 const root=$('graph'),w=Math.max(280,Math.floor(root.getBoundingClientRect().width)),mobile=w<620;
 const names=[...new Set([...(state.agents||[]).filter(a=>a.name!=='NightShift-Main').map(a=>a.name),...(state.chats||[]).flatMap(c=>model.participants(c))])];
 const rows=Math.ceil(names.length/2),firstY=138,available=Math.max(430,innerHeight-132),step=Math.max(72,Math.min(98,(available-firstY-42)/Math.max(1,rows-1))),h=mobile?firstY+42+Math.max(0,rows-1)*step:Math.max(560,rows*104+100),center={x:w/2,y:mobile?52:h/2};
 root.querySelector('.map-scene')?.remove();const g=svg('g',{class:'map-scene'});root.prepend(g);
 if(!packetLayer){packetLayer=svg('g',{class:'packet-layer'});root.append(packetLayer);}points={};routePaths={};
 const nodeWidth=mobile?Math.min(138,(w-32)/2):Math.min(188,w*.25),coords={};
 names.forEach((name,i)=>coords[name]={x:mobile?(i%2?w-nodeWidth/2-8:nodeWidth/2+8):(i%2?w-115:115),y:mobile?firstY+Math.floor(i/2)*step:74+Math.floor(i/2)*(h-148)/Math.max(1,rows-1)});
 for(const chat of state.chats){points[model.nodeKey(chat.id,'moderator')]=center;for(const name of model.participants(chat))points[model.nodeKey(chat.id,name)]=coords[name];}
 function box(name,p,label,line1,line2,main,busy,onClick,activity=''){
  const width=main?(mobile?190:206):nodeWidth;
  const node=svg('g',{class:`node ${main?'main':''} ${busy&&connected?'busy':''}`,transform:`translate(${p.x},${p.y})`,role:'button',tabindex:0,'aria-label':label+' · '+line1+' · '+line2,'data-worker':name});
  const height=main?76:68;
  node.append(svg('rect',{x:-width/2,y:-height/2,width,height,rx:13}),svg('text',{x:0,y:main?-16:-20,'text-anchor':'middle'},label),svg('text',{x:0,y:main?4:-4,'text-anchor':'middle',class:'sub'},line1),svg('text',{x:0,y:main?23:12,'text-anchor':'middle',class:'sub'},line2));
  if(activity)node.append(svg('text',{x:0,y:27,'text-anchor':'middle',class:'activity'},activity));
  activate(node,onClick);g.append(node);
 }
 for(const name of names){const p=coords[name],keys=state.chats.filter(c=>model.participants(c).includes(name)).map(c=>model.nodeKey(c.id,name));addEdge(g,keys,mobile?{x:center.x,y:center.y+38}:center,p,mobile?'branch':'curve');}
 const observed=state.chats.map(c=>c.modelInfo?.moderator?.model).filter(Boolean),unique=[...new Set(observed)];
 const hubModel=unique.length===1?unique[0].replace('gpt-',''):unique.length?'혼합 모델':'모델 확인 중';
 const devStatus=model.developmentStatus(state.development,connected);
 box('orchestrator',center,'메인 오케스트레이터',hubModel+' · 전체 워커 '+names.length+'개',devStatus.title,true,devStatus.working,()=>{
  $('detail').textContent='메인 오케스트레이터 · 전체 역할 지도\n'+devStatus.title+'\n'+devStatus.reason+'\n그룹별 실제 조정 세션을 이 중심 노드에 통합해 표시합니다.\n명령·응답을 선택하면 실제 그룹, 발신자, 수신자, 시각과 원문을 확인할 수 있습니다.\n\n'+state.chats.map(c=>c.topic+' · '+(phases[c.state]||c.state)+' · '+(c.modelInfo?.moderator?.model||'모델 미확인')+' · '+model.activityText(model.modelInfo(c,'moderator',state.agents),connected&&c.isActive&&c.state==='moderator-thinking')).join('\n');
  openFleetDetail();
 });
 const aliases={'NightShift-Dashboard':'상황실 UI','NightShift-Integrator':'통합·테스트','NightShift-Worker':'보조 검증'};
 for(const name of names){
  const chats=state.chats.filter(c=>model.participants(c).includes(name));
  const busy=chats.some(c=>c.isActive&&model.view(c).pending.includes(name));
  const latest=[...chats].sort((a,b)=>Number(b.isActive&&model.view(b).pending.includes(name))-Number(a.isActive&&model.view(a).pending.includes(name))||new Date(b.modelInfo?.participants?.[name]?.activity?.lastEventAt||b.modelInfo?.participants?.[name]?.observedAt||0)-new Date(a.modelInfo?.participants?.[name]?.activity?.lastEventAt||a.modelInfo?.participants?.[name]?.observedAt||0))[0];
  const info=model.modelInfo(latest,name,state.agents);
  const answered=chats.some(c=>(c.messages||[]).some(m=>m.participantName===name));
  box(name,coords[name],aliases[name]||model.label(name).replace(' 워커',''),info.short+' · '+info.source,connected?(busy?'명령 수신 · 응답 대기':answered?'응답 완료 · 대기':'등록됨 · 대기'):'마지막 기록',false,busy,()=>showNode(latest||null,name),model.activityText(info,busy&&connected));
 }
 const focusHeight=innerHeight-document.querySelector('.map-heading').getBoundingClientRect().height-20;
 root.style.height=(document.body.classList.contains('map-focus')?Math.min(h,Math.max(260,focusHeight)):h)+'px';root.setAttribute('viewBox',`0 0 ${w} ${h}`);
};
const fleetFocus=document.createElement('button');fleetFocus.type='button';fleetFocus.id='fleet-focus';
function setFleetFocus(on){document.body.classList.toggle('map-focus',on);document.body.classList.remove('detail-open');fleetFocus.textContent=on?'통신·기록 보기':'전체 지도 크게';signature='';if(state)render();}
fleetFocus.onclick=()=>setFleetFocus(!document.body.classList.contains('map-focus'));
document.querySelector('.map-heading').append(fleetFocus);
document.querySelector('.map-heading').append($('motion-toggle'));$('motion-toggle').style.fontSize='11px';
const fleetStyle=document.createElement('style');fleetStyle.textContent='.map-focus header,.map-focus .toolbar,.map-focus aside,.map-focus .roster,.map-focus .history,.map-focus footer,.map-focus #detail{display:none}.map-focus main{max-width:none;padding:8px}.map-focus .workspace{display:block}.map-focus .map-heading{padding:8px 12px;align-items:center;gap:4px;flex-wrap:wrap}.map-focus #mode{display:none}#fleet-focus{font-size:12px;min-height:36px}.map-focus .map{max-width:1300px;margin:auto}#fleet-status{width:100%;font-size:11px;color:var(--green)}#fleet-close{display:none}.map-focus.detail-open #detail{display:block;position:fixed;z-index:20;bottom:12px;left:12px;right:12px;max-height:52vh;background:#222637;border:1px solid var(--accent);border-radius:14px;padding:56px 18px 18px;box-shadow:0 0 0 100vmax #0006}.map-focus.detail-open #fleet-close{display:block;position:fixed;z-index:21;right:24px;bottom:calc(min(52vh, var(--detail-height, 52vh)) - 32px)}';document.head.append(fleetStyle);
const fleetStatus=document.createElement('small');fleetStatus.id='fleet-status';document.querySelector('.map-heading').append(fleetStatus);
const fleetClose=document.createElement('button');fleetClose.id='fleet-close';fleetClose.textContent='상세 닫기';fleetClose.onclick=()=>document.body.classList.remove('detail-open');document.body.append(fleetClose);
function openFleetDetail(){if(!document.body.classList.contains('map-focus'))return;document.body.classList.add('detail-open');document.body.style.setProperty('--detail-height',$('detail').getBoundingClientRect().height+'px');}
const detailMessage=showMessage,detailNode=showNode;
showMessage=function(...args){detailMessage(...args);if(!replaying)openFleetDetail();};
showNode=function(...args){detailNode(...args);openFleetDetail();};
const fleetRender=render;
render=function(){fleetRender();const dev=state?.development,status=model.developmentStatus(dev,connected);fleetStatus.textContent=status.title+(dev?.stageName||dev?.stageId?' · '+(dev.stageName||dev.stageId):'')+(status.reason?' · '+status.reason:'');fleetStatus.className=status.working?'working':'settled';};
setFleetFocus(true);
document.querySelector('.map-heading > span').textContent='전체 워커 연결 지도';
$('graph').setAttribute('aria-label','메인 오케스트레이터에서 전체 워커로 뻗는 연결 지도');
