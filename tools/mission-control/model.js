(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.NightShiftModel=api;})(globalThis,function(){
 const stages={PLAN_DRAFT:'초안 작성',REVIEW_1:'독립 기획 검토',PLAN_REVISION:'검토 반영 · 수정',REVIEW_FINAL:'독립 최종 검토',DECISION:'결과 정리',IMPLEMENT_SERVER:'서버 구현',IMPLEMENT_UI:'화면 구현',IMPLEMENT_WORLD:'매장 제작',INTEGRATION:'Studio 통합',PLAYTEST:'플레이 테스트',FIX:'문제 수정'};
 const labels={'NightShift-Planner':'기획 워커','NightShift-DesignReview':'기획 검토 워커','NightShift-Review':'코드 검토 워커','NightShift-Story':'스토리 워커','NightShift-Server':'서버 워커','NightShift-UI':'화면 워커','NightShift-World':'매장 워커','NightShift-Main':'메인 일반 세션','NightShift-Worker':'검증 워커',moderator:'메인 오케스트레이터'};
 const participants=chat=>[...new Set((chat.participants||[]).map(p=>p.name).filter(Boolean))];
 const nodeKey=(chatId,name)=>JSON.stringify([chatId,name]);
 function targets(message,chat){
  if(message.participantName!=='moderator')return [];
  return participants(chat).filter(name=>{
   const escaped=name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
   return new RegExp('(^|[^\\p{L}\\p{N}_@-])@'+escaped+'(?=$|[^\\p{L}\\p{N}_-])','u').test(message.content||'');
  });
 }
 function view(chat){
   const messages=[...(chat.messages||[])].sort((a,b)=>new Date(a.timestamp)-new Date(b.timestamp));
   // A later delegation to another worker must not clear an outstanding request.
   const waiting=new Set();
   for(const message of messages){
    for(const name of targets(message,chat))waiting.add(name);
    if(message.participantName!=='moderator')waiting.delete(message.participantName);
   }
   const pending=chat.isActive?participants(chat).filter(name=>waiting.has(name)):[];
   let stage='';for(const m of messages){if(m.participantName!=='moderator')continue;const match=m.content.match(/^\s*\[([A-Z_0-9]+)\]/m);if(match&&stages[match[1]])stage=stages[match[1]];}
   return {pending,stage,messages};
 }
 function routes(message,chat){if(message.participantName==='moderator')return targets(message,chat).map(name=>['moderator',name]);return participants(chat).includes(message.participantName)?[[message.participantName,'moderator']]:[];}
 // Each group receives its own baseline, including groups discovered after startup.
 function createTracker(){const groups=new Map();return {ingest(chats){const fresh=[];for(const chat of chats){const initial=!groups.has(chat.id);if(initial)groups.set(chat.id,new Set());const seen=groups.get(chat.id);for(const message of view(chat).messages){if(message.id==null)continue;const id=String(message.id);if(seen.has(id))continue;seen.add(id);if(!initial)fresh.push({chatId:chat.id,message});}}return fresh;}};}
 function modelInfo(chat,name,agents=[]){
  const observed=name==='moderator'?chat?.modelInfo?.moderator:chat?.modelInfo?.participants?.[name];
  const agent=name==='moderator'?null:agents.find(a=>a.name===name);
  const hasObservation=!!observed?.model;
  const model=hasObservation?observed.model:agent?.configuredModel;
  const effort=hasObservation?observed.effort:agent?.configuredEffort;
  const source=hasObservation?'관측':model?'구성':'미확인';
  const activity=hasObservation&&observed.activity?.scope==='turn'?observed.activity:null;
  return {model:model||'미확인',effort:effort||'미확인',source,activity,observedAt:hasObservation?observed.observedAt:null,short:model?String(model).replace(/^openai\//,'').replace(/^gpt-/,''):'모델 미확인'};
 }
 function connectionPath(a,b,kind='line'){
  const mid=(a.x+b.x)/2,c={x:mid,y:a.y},d={x:mid,y:b.y};
  const points=kind==='branch'?[a,{x:a.x,y:b.y},b]:kind==='curve'?Array.from({length:81},(_,i)=>{const t=i/80,s=1-t;return {x:s*s*s*a.x+3*s*s*t*c.x+3*s*t*t*d.x+t*t*t*b.x,y:s*s*s*a.y+3*s*s*t*c.y+3*s*t*t*d.y+t*t*t*b.y};}):[a,b];
  const lengths=[0];for(let i=1;i<points.length;i++)lengths.push(lengths[i-1]+Math.hypot(points[i].x-points[i-1].x,points[i].y-points[i-1].y));
  return {d:kind==='curve'?`M${a.x},${a.y} C${c.x},${c.y} ${d.x},${d.y} ${b.x},${b.y}`:points.map((p,i)=>(i?'L':'M')+p.x+','+p.y).join(' '),pointAt(u){const distance=Math.max(0,Math.min(1,u))*lengths.at(-1);let i=1;while(i<lengths.length-1&&lengths[i]<distance)i++;const ratio=(distance-lengths[i-1])/(lengths[i]-lengths[i-1]||1);return {x:points[i-1].x+(points[i].x-points[i-1].x)*ratio,y:points[i-1].y+(points[i].y-points[i-1].y)*ratio};}};
 }
 function pathPoint(edge,u,reverse=false){
  const progress=reverse?1-u:u;
  try{const length=edge.element.getTotalLength();if(length>0)return edge.element.getPointAtLength(Math.max(0,Math.min(1,progress))*length);}catch{}
  return edge.geometry.pointAt(progress);
 }
 function activityText(info,busy=false){const a=info.activity;if(!a)return '도구 활동 미확인';const time=a.lastToolAt?new Date(a.lastToolAt).toLocaleTimeString('ko-KR',{hour12:false}):'없음';return `${busy?'현재':'최근 턴'} 도구 ${a.toolCalls}회 · ${time}`;}
 function developmentStatus(dev,connected=true){
  if(!connected)return {title:'연결 끊김 · 마지막 기록',reason:'새 상태를 확인하지 못했습니다.',working:false};
  if(!dev)return {title:'개발 상태 미확인',reason:'실행기 상태를 기다립니다.',working:false};
  if(dev.status==='attention')return {title:'개발 정지·확인 필요',reason:/settled idle.*completion marker/i.test(dev.reason||'')?'응답은 끝났지만 완료 표식을 확인하지 못했습니다.':dev.reason||'다음 단계로 진행하지 못했습니다.',working:false};
  if(dev.status==='awaiting-review')return {title:'등록 작업 완료·후속 검토',reason:'등록된 단계가 끝났습니다. 실제 검증 결과와 후속 작업을 확인합니다.',working:false};
  if(!dev.alive||dev.status==='stopped')return {title:'개발 실행기 중지',reason:dev.reason||'실행 중인 상주 개발 작업이 없습니다.',working:false};
  const titles={running:'개발 진행 중',ready:'개발 준비 중',dispatching:'다음 작업 전달 중','waiting-capacity':'워커 작업 완료 대기','waiting-resources':'파일·메모리 대기'};
  return {title:titles[dev.status]||'개발 상태 확인 필요',reason:dev.reason||'',working:Object.hasOwn(titles,dev.status)};
 }
 // Registry/pool state is metadata, never evidence of a message or a running turn.
 function workers(state){
  const byName=new Map();
  for(const a of state.agents||[])if(a.name)byName.set(a.name,{...a});
  for(const a of state.workerPool?.workers||[])if(a.name)byName.set(a.name,{...byName.get(a.name),...a});
  for(const c of state.chats||[])for(const name of participants(c))if(!byName.has(name))byName.set(name,{name});
  byName.delete('moderator');byName.delete('orchestrator');
  const list=[...byName.values()];
  for(const a of list){
   const parent=a.parentName;let cursor=parent;const seen=new Set([a.name]);let invalid=false;
   while(cursor&&cursor!=='moderator'&&cursor!=='orchestrator'){
    if(seen.has(cursor)||!byName.has(cursor)){invalid=true;break;}seen.add(cursor);cursor=byName.get(cursor).parentName;
   }
   a.parent=invalid||!parent||['moderator','orchestrator'].includes(parent)?'orchestrator':parent;
   a.parentIssue=invalid?'알 수 없는 부모 또는 순환 관계 · 루트에 표시':'';
  }
  return list;
 }
 function hierarchyLayout(list,availableWidth=320){
  const children=new Map();for(const a of list){if(!children.has(a.parent))children.set(a.parent,[]);children.get(a.parent).push(a);}
  const ordered=[];function visit(a){ordered.push(a);for(const child of children.get(a.name)||[])visit(child);}
  for(const a of children.get('orchestrator')||[])visit(a);
  // Every registered/queued worker stays visible; DFS keeps each family adjacent.
  const n=ordered.length,rx=340,ry=availableWidth>=700?245:300;
  const unit=ordered.map((a,i)=>{const angle=-Math.PI/2+i*2*Math.PI/Math.max(1,n);return {name:a.name,x:rx*Math.cos(angle),y:ry*Math.sin(angle)};});
  let scale=1;
  for(let i=0;i<n;i++)for(let j=i+1;j<n;j++)scale=Math.max(scale,Math.min(144/(Math.abs(unit[i].x-unit[j].x)||.0001),64/(Math.abs(unit[i].y-unit[j].y)||.0001)));
  const width=Math.ceil(rx*scale*2+184),height=Math.ceil(ry*scale*2+110),center={x:width/2,y:height/2},coords={orchestrator:center};
  for(const p of unit)coords[p.name]={x:center.x+p.x*scale,y:center.y+p.y*scale};
  return {coords,width,height};
 }
 function workerStatus(worker,pending,connected=true){
  if(!connected)return '마지막 기록 · '+workerStatus(worker,pending,true);
  if(pending)return '실제 명령 수신 · 응답 대기';
  if(worker.temporary&&['completed','complete','done','inactive'].includes(worker.status))return 'inactive(완료) · 재사용 가능';
  return worker.status?'풀 상태: '+worker.status:'등록됨 · 대기';
 }
 return {workers,hierarchyLayout,workerStatus,view,routes,targets,nodeKey,participants,createTracker,modelInfo,connectionPath,pathPoint,activityText,developmentStatus,label:name=>labels[name]||name.replace(/^NightShift-/, '')};
});
