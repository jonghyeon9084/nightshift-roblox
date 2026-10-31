'use strict';
const fs=require('node:fs'),path=require('node:path');
function normalize(raw,at,source){
 const limitId=raw?.limitId??raw?.limit_id;
 if(limitId!=='codex'||!Number.isFinite(at))return null;
 const windows=[];
 for(const name of ['primary','secondary']){
  const w=raw[name];if(w==null)continue;
  const used=w.usedPercent??w.used_percent,minutes=w.windowDurationMins??w.window_minutes,reset=w.resetsAt??w.resets_at;
  if(!Number.isFinite(used)||used<0||used>100||!Number.isFinite(minutes)||minutes<=0||!Number.isFinite(reset)||reset<=0)return null;
  windows.push({name,usedPercent:used,windowMinutes:minutes,resetsAt:reset});
 }
 return windows.length?{at,source,limitId,windows}:null;
}
function parseEvents(text,source){
 const result=[];
 for(const line of text.split('\n')){
  if(!/"type"\s*:\s*"token_count"/.test(line))continue;
  try{const row=JSON.parse(line);if(row.type!=='event_msg'||row.payload?.type!=='token_count')continue;
   const item=normalize(row.payload.rate_limits,Date.parse(row.timestamp),source);if(item)result.push(item);
  }catch{}
 }
 return result;
}
function evaluate(policy,samples,now){
 if(!policy?.enabled)return {enabled:false,blocked:false,stopActive:false,reason:null};
 if(!Number.isFinite(policy.reservePercent)||policy.reservePercent<10||!(policy.stopActiveAtRemainingPercent>policy.reservePercent)||!(policy.stopNewAtRemainingPercent>=policy.stopActiveAtRemainingPercent)||policy.stopNewAtRemainingPercent>100||!Number.isFinite(policy.maxSnapshotAgeSeconds)||policy.maxSnapshotAgeSeconds<1)return {enabled:true,blocked:true,stopActive:false,reason:'사용량 보호 설정 오류 · 새 배정 중단'};
 const fresh=samples.filter(s=>s&&s.at<=now+5000&&now-s.at<=policy.maxSnapshotAgeSeconds*1000&&s.windows.every(w=>w.resetsAt*1000>now)).sort((a,b)=>b.at-a.at);
 if(!fresh.length)return {enabled:true,blocked:true,stopActive:false,reason:'사용량 잔량 확인 대기 · 오래되거나 없는 잔량으로 새 배정하지 않음'};
 const latest=fresh[0];
 // Within the same quota window never regress to a smaller delayed usage report.
 const windows=latest.windows.map(w=>({...w,usedPercent:Math.max(w.usedPercent,...fresh.flatMap(s=>s.windows.filter(x=>x.name===w.name&&x.resetsAt===w.resetsAt&&x.windowMinutes===w.windowMinutes).map(x=>x.usedPercent)))}));
 const remainingPercent=Math.min(...windows.map(w=>100-w.usedPercent));
 const blocked=remainingPercent<=policy.stopNewAtRemainingPercent,stopActive=remainingPercent<=policy.stopActiveAtRemainingPercent;
 return {enabled:true,blocked,stopActive,remainingPercent,reservePercent:policy.reservePercent,at:new Date(latest.at).toISOString(),source:latest.source,windows,reason:blocked?`사용량 ${remainingPercent}% 남음 · 최소 ${policy.reservePercent}% 보존을 위해 새 배정 중단`:null};
}
class UsageBudget {
 constructor(root,{sessions=path.join(process.env.USERPROFILE||'','.codex/sessions'),clock=Date.now}={}){Object.assign(this,{root,sessions,clock});this.cachedAt=-Infinity;this.samples=[];}
 check(){
  const file=path.join(this.root,'tools/usage-budget-policy.json');let policy;
  try{policy=JSON.parse(fs.readFileSync(file,'utf8'));}catch(e){if(e.code==='ENOENT')return {enabled:false,blocked:false,stopActive:false,reason:null};return {enabled:true,blocked:true,stopActive:false,reason:'사용량 보호 설정을 읽을 수 없음'};}
  const now=this.clock();
  if(now-this.cachedAt>=15000){
   this.samples=[];this.cachedAt=now;
   try{const snapshot=JSON.parse(fs.readFileSync(path.join(this.root,'.setup/usage-budget/official-snapshot.json'),'utf8'));const item=normalize(snapshot.rateLimits,Date.parse(snapshot.at),'official-usage-tool');if(item)this.samples.push(item);}catch{}
   const candidates=[];
   for(const offset of [-1,0,1]){
    const day=new Date(now+offset*86400000).toISOString().slice(0,10).split('-');const directory=path.join(this.sessions,...day);
    try{for(const entry of fs.readdirSync(directory,{withFileTypes:true})){if(!entry.isFile()||!entry.name.endsWith('.jsonl'))continue;const name=path.join(directory,entry.name),stat=fs.statSync(name);if(now-stat.mtimeMs<2*86400000)candidates.push({name,stat});}}catch{}
   }
   for(const c of candidates.sort((a,b)=>b.stat.mtimeMs-a.stat.mtimeMs).slice(0,16)){
    let fd;try{fd=fs.openSync(c.name,'r');const length=Math.min(c.stat.size,1024*1024),buffer=Buffer.alloc(length);fs.readSync(fd,buffer,0,length,c.stat.size-length);this.samples.push(...parseEvents(buffer.toString('utf8'),'official-codex-session'));}catch{}finally{if(fd!==undefined)fs.closeSync(fd);}
   }
  }
  return evaluate(policy,this.samples,now);
 }
}
module.exports={normalize,parseEvents,evaluate,UsageBudget};
