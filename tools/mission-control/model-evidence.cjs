const fs=require('node:fs'),path=require('node:path');
const cache=new Map();let indexedAt=0,files=[];
// Names only. Never expose tool arguments, results, messages or reasoning text.
const toolNames=new Set(['exec','wait','exec_command','write_stdin','apply_patch','view_image','js','js_reset','getState','getTab','getApp','createBrowserTab']);
function safeTime(value){if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}T/.test(value))return null;const time=Date.parse(value);return Number.isFinite(time)?new Date(time).toISOString():null;}
function parseSessionMetadata(source){
 let value=null,activity=null;
 for(const line of source.split('\n')){
  let r;try{r=JSON.parse(line);}catch{continue;}
  const at=safeTime(r.timestamp);
  if(r.type==='turn_context'){
   activity={scope:'turn',lastEventAt:at,lastToolAt:null,toolCalls:0,lastToolName:null};
   const p=r.payload;
   if(typeof p?.model==='string'&&/^gpt-[a-z0-9.-]+$/i.test(p.model))value={model:p.model,effort:['minimal','none','low','medium','high','xhigh','max','ultra'].includes(p.effort)?p.effort:null,observedAt:at,activity};
   else if(value)value={...value,activity};
  }else if(activity){
   if(at&&['event_msg','response_item'].includes(r.type))activity.lastEventAt=at;
   if(r.type==='response_item'&&['function_call','custom_tool_call'].includes(r.payload?.type)){
    activity.toolCalls++;activity.lastToolAt=at;
    activity.lastToolName=toolNames.has(r.payload.name)?r.payload.name:null;
   }
  }
 }
 return value;
}
function json(file){try{return JSON.parse(fs.readFileSync(file,'utf8'));}catch{return {};}}
function index(directory){if(!fs.existsSync(directory))return;for(const e of fs.readdirSync(directory,{withFileTypes:true})){const p=path.join(directory,e.name);if(e.isDirectory())index(p);else if(e.name.endsWith('.jsonl'))files.push(p);}}
function sessionModel(id){
 if(!id)return null;
 if(Date.now()-indexedAt>15000){files=[];index(path.join(process.env.USERPROFILE,'.codex/sessions'));indexedAt=Date.now();}
 const file=files.find(f=>f.endsWith(id+'.jsonl'));if(!file)return null;
 const {size,mtimeMs}=fs.statSync(file),old=cache.get(file);if(old?.size===size&&old.mtimeMs===mtimeMs)return old.value;
 const value=parseSessionMetadata(fs.readFileSync(file,'utf8'));
 cache.set(file,{size,mtimeMs,value});return value;
}
function configured(){const s=json(path.join(process.env.APPDATA,'maestro/maestro-sessions.json'));return new Map((s.sessions||[]).map(a=>[a.name,{configuredModel:a.customModel||null,configuredEffort:a.customAgentConfig?.reasoningEffort||a.customArgs?.match(/model_reasoning_effort=["']?(\w+)/)?.[1]||null}]));}
function chatModels(id){const m=json(path.join(process.env.APPDATA,'maestro/group-chats',id,'metadata.json'));return {moderator:sessionModel(m.moderatorAgentSessionId),participants:Object.fromEntries((m.participants||[]).map(p=>[p.name,sessionModel(p.agentSessionId)]))};}
module.exports={configured,chatModels,parseSessionMetadata};
