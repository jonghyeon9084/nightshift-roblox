const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {readTranscript}=require('./journal.cjs');

// chat.log has no message IDs. Match the two representations one-to-one by
// timestamp, actor, content and occurrence, retaining repeated equal messages.
function messageKey(row){
  const time=typeof row.timestamp==='number'?row.timestamp:Date.parse(row.timestamp);
  return crypto.createHash('sha256').update(JSON.stringify([row.chatId,Number.isFinite(time)?new Date(time).toISOString():row.timestamp,row.actor,String(row.content||'').replace(/\r\n/g,'\n')])).digest('hex');
}
class MessageIngestor {
  constructor(journal){
    this.journal=journal;this.transcripts=new Map();this.cliIds=new Map();this.coverage=new Map();
    // Private index, outside activity.jsonl: aliases are metadata, not chat events.
    this.linkFile=path.join(path.dirname(journal.file),'message-links.jsonl');
    this.loadLinks();
    const legacy=new Map();
    for(const row of journal.rows){
      if(row.kind!=='message')continue;
      const key=messageKey(row);
      if(row.messageOccurrence){this.coverage.set(key,Math.max(this.coverage.get(key)||0,row.messageOccurrence));}
      else {const counts=legacy.get(key)||{source:0,message:0};counts[row.id?.startsWith('source/')?'source':'message']++;legacy.set(key,counts);}
      if(row.messageId!=null)this.remember(key,row.messageId,row.messageOccurrence);
      else if(row.id?.startsWith('message/'+row.chatId+'/'))this.remember(key,row.id.slice(('message/'+row.chatId+'/').length));
    }
    for(const [key,counts]of legacy)this.coverage.set(key,Math.max(this.coverage.get(key)||0,counts.source,counts.message));
  }
  loadLinks(){
    let source;try{source=fs.readFileSync(this.linkFile,'utf8');}catch(e){if(e.code==='ENOENT')return;throw e;}
    const lines=source.split('\n');
    for(let i=0;i<lines.length;i++){
      if(!lines[i])continue;
      let row;try{row=JSON.parse(lines[i]);}catch(e){
        if(i!==lines.length-1)throw e;
        // A process may stop during its final append. Keep the valid prefix.
        fs.truncateSync(this.linkFile,Buffer.byteLength(source.slice(0,source.lastIndexOf('\n')+1)));return;
      }
      if(!/^[a-f0-9]{64}$/.test(row.key)||typeof row.id!=='string'||!Number.isSafeInteger(row.occurrence)||row.occurrence<1)throw Error('Invalid message alias index');
      let ids=this.cliIds.get(row.key);if(!ids){ids=new Map();this.cliIds.set(row.key,ids);}
      if(ids.has(row.id)&&ids.get(row.id)!==row.occurrence)throw Error('Conflicting message alias index');
      ids.set(row.id,row.occurrence);
    }
    if(source&&!source.endsWith('\n'))fs.appendFileSync(this.linkFile,'\n');
  }
  remember(key,id,occurrence){
    let ids=this.cliIds.get(key);if(!ids){ids=new Map();this.cliIds.set(key,ids);}
    const value=String(id);
    if(!ids.has(value)){
      const n=Number.isSafeInteger(occurrence)&&occurrence>0?occurrence:[...ids.values()].reduce((max,n)=>Math.max(max,n),0)+1;
      // Commit even a late alias for an already-recorded occurrence before use.
      // IO failures propagate to PollCache, leaving this ID retryable.
      fs.appendFileSync(this.linkFile,JSON.stringify({key,id:value,occurrence:n})+'\n');
      ids.set(value,n);
    }
    return ids.get(value);
  }
  ingest(chat,sourceLog){
    if(sourceLog)this.transcripts.set(chat.id,readTranscript(sourceLog,chat));
    const candidates=new Map();
    const put=(key,occurrence,row)=>{let rows=candidates.get(key);if(!rows){rows=new Map();candidates.set(key,rows);}rows.set(occurrence,row);};
    const counts=new Map();
    for(const row of this.transcripts.get(chat.id)||[]){const key=messageKey(row),n=(counts.get(key)||0)+1;counts.set(key,n);put(key,n,row);}
    for(const m of chat.messages||[]){
      const row={kind:'message',chatId:chat.id,topic:chat.topic,timestamp:m.timestamp,actor:m.participantName,content:m.content,messageId:m.id};
      const key=messageKey(row),n=this.remember(key,m.id);put(key,n,row);
    }
    for(const [key,rows]of candidates)for(const [occurrence,row]of rows){
      if(occurrence<=(this.coverage.get(key)||0))continue;
      this.journal.add({...row,id:'observed-message/'+chat.id+'/'+key+'/'+occurrence,messageOccurrence:occurrence});
      this.coverage.set(key,occurrence);
    }
  }
}

function fileStamp(file) {
  try {const s=fs.statSync(file);return `${s.mtimeMs}:${s.size}`;}
  catch(e){if(e.code==='ENOENT')return null;throw e;}
}
function createLimiter(max=3) {
  if(!Number.isInteger(max)||max<1)throw Error('Invalid concurrency');
  let running=0;const queue=[];
  function next(){while(running<max&&queue.length){const {fn,resolve,reject}=queue.shift();running++;Promise.resolve().then(fn).then(resolve,reject).finally(()=>{running--;next();});}}
  return fn=>new Promise((resolve,reject)=>{queue.push({fn,resolve,reject});next();});
}
class PollCache {
  constructor({sourceRoot,archiveRoot,command,ingest}){Object.assign(this,{sourceRoot,archiveRoot,command,ingest});this.entries=new Map();}
  prune(chats){const ids=new Set(chats.map(c=>c.id));for(const id of this.entries.keys())if(!ids.has(id))this.entries.delete(id);}
  async get(chat){
    const source=path.join(this.sourceRoot,chat.id);
    const stamps=Object.fromEntries(['metadata.json','history.jsonl','chat.log'].map(name=>[name,fileStamp(path.join(source,name))]));
    const signature=JSON.stringify([chat,stamps]);
    const old=this.entries.get(chat.id);
    // Unknown/live states are never treated as a settled cache hit.
    const settled=chat.isActive===false&&['idle','inactive','completed','stopped','archived'].includes(chat.state);
    if(settled&&old?.signature===signature)return old.value;
    // Evict before attempting work: a failed refresh must be retried, never a hit.
    this.entries.delete(chat.id);
    const result=await this.command(['group-chat','status',chat.id,'--tail','80']);
    if(!result.success||!result.chat)throw Error('그룹 대화 조회 실패');
    if(JSON.stringify(stamps)!==JSON.stringify(old?.stamps)){
      const archive=path.join(this.archiveRoot,chat.id);fs.mkdirSync(archive,{recursive:true});
      for(const [name,stamp] of Object.entries(stamps))if(stamp!==null)fs.copyFileSync(path.join(source,name),path.join(archive,name));
      // Deleted source files do not erase the durable archive.
      await this.ingest(result.chat,stamps['chat.log']!==null?path.join(source,'chat.log'):null);
    }else await this.ingest(result.chat,null);
    this.entries.set(chat.id,{signature,stamps,value:result.chat});
    return result.chat;
  }
}
class FileHashCache {
  constructor(){this.entries=new Map();}
  hash(file){const stamp=fileStamp(file);if(stamp===null){this.entries.delete(file);return null;}const old=this.entries.get(file);if(old?.stamp===stamp)return old.hash;const hash=crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');this.entries.set(file,{stamp,hash});return hash;}
}
const statuses=new Set(['queued','active','completed','inactive','attention','waiting']);
const text=v=>typeof v==='string'?v:null;
const parentName=v=>typeof v==='string'&&/^NightShift-[A-Za-z][A-Za-z0-9-]{0,35}$/.test(v)?v:null;
function publicPool(value){
  return {...(text(value?.at)?{at:value.at}:{}),workers:(Array.isArray(value?.workers)?value.workers:[]).map(w=>({name:text(w.name),parentName:parentName(w.parentName),temporary:w.temporary===true,status:statuses.has(w.status)?w.status:'attention',taskId:text(w.taskId),taskTitle:text(w.taskTitle),chatId:text(w.chatId),reason:text(w.reason),tier:text(w.tier)})),tasks:(Array.isArray(value?.tasks)?value.tasks:[]).map(t=>({id:text(t.id),title:text(t.title),status:statuses.has(t.status)?t.status:'attention',chatId:text(t.chatId),reason:text(t.reason)}))};
}
function readWorkerPool(file){try{return publicPool(JSON.parse(fs.readFileSync(file,'utf8')));}catch(e){if(e.code==='ENOENT')return {workers:[],tasks:[]};throw e;}}
function ingestPoolEvents(file,journal){
  if(fileStamp(file)===null)return;
  const source=fs.readFileSync(file,'utf8');
  // Ignore an incomplete append until the next poll.
  for(const line of source.slice(0,source.lastIndexOf('\n')+1).split('\n')){
    if(!line)continue;const event=JSON.parse(line);
    const safe={kind:text(event.kind),worker:text(event.worker),parentName:parentName(event.parentName),temporary:event.temporary===true,...publicPool({tasks:[event]}).tasks[0]};
    journal.add({id:'worker-pool/'+crypto.createHash('sha256').update(line).digest('hex'),kind:'status',actor:'워커 실행기',timestamp:text(event.at),chatId:safe.chatId,content:JSON.stringify(safe)});
  }
}
module.exports={fileStamp,createLimiter,PollCache,FileHashCache,publicPool,readWorkerPool,ingestPoolEvents,MessageIngestor};
