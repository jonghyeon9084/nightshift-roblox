// Unified role view: one orchestration hub, one node for every registered worker.
// Real group/session identity remains attached to every packet and detail entry.
let fleetZoom='fit';
const groupGraph=graph;
graph=function(){
 if(selected)return groupGraph();
 const root=$('graph'),list=model.workers(state),names=list.map(a=>a.name),layout=model.hierarchyLayout(list,$('graph-viewport').clientWidth),coords=layout.coords,center=coords.orchestrator;
 const viewport=$('graph-viewport'),w=layout.width,h=layout.height,mobile=viewport.clientWidth<620;
 const g=svg('g',{class:'map-scene'});root.querySelector('.map-scene')?.remove();root.prepend(g);
 if(!packetLayer){packetLayer=svg('g',{class:'packet-layer'});root.append(packetLayer);}points={};routePaths={};
 const nodeWidth=128;
 for(const chat of state.chats){points[model.nodeKey(chat.id,'moderator')]=center;for(const name of model.participants(chat))points[model.nodeKey(chat.id,name)]=coords[name];}
 function box(name,p,label,line1,line2,main,busy,onClick,activity=''){
  const width=main?216:nodeWidth;
  const node=svg('g',{class:`node ${main?'main':''} ${busy&&connected?'busy':''} ${list.find(a=>a.name===name)?.temporary&&['inactive','completed','complete','done'].includes(list.find(a=>a.name===name)?.status)&&!busy?'inactive':''}`,transform:`translate(${p.x},${p.y})`,role:'button',tabindex:0,'aria-label':label+' · '+line1+' · '+line2,'data-worker':name,'data-parent':list.find(a=>a.name===name)?.parent||''});
  const height=main?76:52;
  const clip=s=>String(s).length>(main?30:24)?String(s).slice(0,main?28:22)+'…':s;
  node.append(svg('rect',{x:-width/2,y:-height/2,width,height,rx:13}),svg('text',{x:0,y:main?-16:-4,'text-anchor':'middle',style:'font-size:'+(main?19:17)+'px'},clip(label)));
  if(main)node.append(svg('text',{x:0,y:4,'text-anchor':'middle',class:'sub'},clip(line1)),svg('text',{x:0,y:23,'text-anchor':'middle',class:'sub'},clip(line2)));
  else node.append(svg('text',{x:0,y:16,'text-anchor':'middle',class:'sub',style:'font-size:13px'},!connected?'연결 확인':busy?'실행 중':/inactive|완료/.test(line2)?'완료 · 비활성':/attention/.test(line2)?'확인 필요':'대기'));
  node.append(svg('title',{},name+' · '+line1+' · '+line2));activate(node,onClick);g.append(node);
 }
 // Dashed ownership edges carry no packets. Actual chat routes always use their real endpoints.
 for(const worker of list){const hasActualRoute=state.chats.some(c=>model.participants(c).includes(worker.name));if(worker.parent==='orchestrator'&&hasActualRoute)continue;const p=coords[worker.name],parent=coords[worker.parent];g.append(svg('path',{d:model.connectionPath(parent,p,'curve').d,class:'ownership-edge','data-worker':worker.name,'data-parent':worker.parent}));}
 for(const name of names){const keys=state.chats.filter(c=>model.participants(c).includes(name)).map(c=>model.nodeKey(c.id,name));if(keys.length)addEdge(g,keys,center,coords[name],'line');}
 const observed=state.chats.map(c=>c.modelInfo?.moderator?.model).filter(Boolean),unique=[...new Set(observed)];
 const hubModel=unique.length===1?unique[0].replace('gpt-',''):unique.length?'혼합 모델':'모델 확인 중';
 const devStatus=model.developmentStatus(state.development,connected);
 box('orchestrator',center,'메인 오케스트레이터',hubModel+' · 전체 워커 '+names.length+'개',devStatus.title,true,devStatus.working,()=>{
  $('detail').textContent='메인 오케스트레이터 · 전체 역할 지도\n'+devStatus.title+'\n'+devStatus.reason+'\n그룹별 실제 조정 세션을 이 중심 노드에 통합해 표시합니다.\n명령·응답을 선택하면 실제 그룹, 발신자, 수신자, 시각과 원문을 확인할 수 있습니다.\n\n'+state.chats.map(c=>c.topic+' · '+(phases[c.state]||c.state)+' · '+(c.modelInfo?.moderator?.model||'모델 미확인')+' · '+model.activityText(model.modelInfo(c,'moderator',state.agents),connected&&c.isActive&&c.state==='moderator-thinking')).join('\n');
  openFleetDetail();
 });
 const aliases={'NightShift-Dashboard':'상황실 UI','NightShift-Integrator':'통합·테스트','NightShift-Worker':'보조 검증','NightShift-Main':'일반 메인','NightShift-Profiles':'저장','NightShift-Economy':'경제','NightShift-Delivery':'배송','NightShift-PerfAudit':'성능 검토','NightShift-PoolReview':'배정 검토','NightShift-TruckWorld':'트럭·창고','NightShift-StoreStorage':'창고 서버','NightShift-WarehouseUI':'창고 화면','NightShift-StoreDesign':'매장 기획'};
 for(const name of names){
  const worker=list.find(a=>a.name===name);
  const chats=state.chats.filter(c=>model.participants(c).includes(name));
  const busy=chats.some(c=>c.isActive&&model.view(c).pending.includes(name));
  const latest=[...chats].sort((a,b)=>Number(b.isActive&&model.view(b).pending.includes(name))-Number(a.isActive&&model.view(a).pending.includes(name))||new Date(b.modelInfo?.participants?.[name]?.activity?.lastEventAt||b.modelInfo?.participants?.[name]?.observedAt||0)-new Date(a.modelInfo?.participants?.[name]?.activity?.lastEventAt||a.modelInfo?.participants?.[name]?.observedAt||0))[0];
  const info=model.modelInfo(latest,name,list);

  box(name,coords[name],aliases[name]||model.label(name).replace(' 워커',''),info.short+' · '+info.effort+' · '+info.source,model.workerStatus(worker,busy,connected),false,busy,()=>showNode(latest||null,name),model.activityText(info,busy&&connected));
 }
 root.setAttribute('viewBox',`0 0 ${w} ${h}`);
 const top=viewport.getBoundingClientRect().top,availableHeight=Number.isFinite(top)?innerHeight-top-18:innerHeight-(mobile?300:260);
 const scale=fleetZoom==='fit'?Math.min(viewport.clientWidth/w,Math.max(180,availableHeight)/h):fleetZoom;
 viewport.style.maxHeight=Math.max(180,availableHeight)+'px';
 root.style.width=Math.max(1,Math.floor(w*scale))+'px';root.style.height=Math.max(1,Math.floor(h*scale))+'px';
 $('fleet-scale').textContent=Math.round(scale*100)+'% · '+names.length+'개 워커';

};
const viewport=$('graph-viewport'),controls=$('fleet-controls'),picker=$('worker-picker');
for(const [label,value] of [['전체보기','fit'],['100% 확대',1],['150% 확대',1.5]]){const button=document.createElement('button');button.type='button';button.textContent=label;button.onclick=()=>{stopPackets();fleetZoom=value;signature='';render();};controls.append(button);}
picker.onchange=()=>{const name=picker.value;if(name)showNode(state.chats.find(c=>c.isActive&&model.view(c).pending.includes(name))||state.chats.find(c=>model.participants(c).includes(name))||null,name);};
new ResizeObserver(()=>{signature='';if(state)render();}).observe(viewport);
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
render=function(){fleetRender();const chosen=picker.value;picker.replaceChildren(new Option('워커 상세 선택',''),...model.workers(state||{}).map(a=>new Option(a.name,a.name)));picker.value=chosen;const dev=state?.development,status=model.developmentStatus(dev,connected);fleetStatus.textContent=status.title+(dev?.stageName||dev?.stageId?' · '+(dev.stageName||dev.stageId):'')+(status.reason?' · '+status.reason:'');fleetStatus.className=status.working?'working':'settled';};
setFleetFocus(true);
document.querySelector('.map-heading > span').textContent='전체 워커 연결 지도';
$('graph').setAttribute('aria-label','모든 워커의 작업 소속과 실제 그룹 통신 지도');
