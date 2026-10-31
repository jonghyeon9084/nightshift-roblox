const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
class Journal {
  constructor(directory) {
    fs.mkdirSync(directory, {recursive:true});
    this.file=path.join(directory,'activity.jsonl');
    this.rows=[]; this.ids=new Set(); this.latest=new Map();
    if(fs.existsSync(this.file)) {
      const contents=fs.readFileSync(this.file,'utf8');
      for(const line of contents.split('\n')) {
        try { const row=JSON.parse(line); this.rows.push(row); this.ids.add(row.id); if(row.stateKey)this.latest.set(row.stateKey,row.fingerprint); } catch {}
      }
      // Keep an interrupted last write from swallowing the next valid event.
      if(contents&&!contents.endsWith('\n'))fs.appendFileSync(this.file,'\n');
    }
  }
  add(row) {
    if(this.ids.has(row.id))return false;
    const entry={observedAt:new Date().toISOString(),...row};
    fs.appendFileSync(this.file,JSON.stringify(entry)+'\n');
    this.ids.add(entry.id);this.rows.push(entry);return true;
  }
  change(stateKey,value,detail) {
    const fingerprint=crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
    if(this.latest.get(stateKey)===fingerprint)return;
    const baseline=!this.latest.has(stateKey);
    this.latest.set(stateKey,fingerprint);
    this.add({id:crypto.randomUUID(),stateKey,fingerprint,baseline,...detail});
  }
  messages(chat) {
    for(const message of chat.messages)this.add({id:'message/'+chat.id+'/'+message.id,kind:'message',chatId:chat.id,topic:chat.topic,timestamp:message.timestamp,actor:message.participantName,content:message.content});
  }
  query({before,chatId,kind,q,limit=100}={}) {
    let end=before===undefined?this.rows.length:Math.max(0,Math.min(this.rows.length,Number(before)||0));
    const entries=[]; const needle=(q||'').toLowerCase();
    while(end>0 && entries.length<Math.min(200,Math.max(1,Number(limit)||100))) {
      const row=this.rows[--end];
      if(chatId&&row.chatId!==chatId)continue;
      if(kind&&row.kind!==kind)continue;
      if(needle&&!JSON.stringify(row).toLowerCase().includes(needle))continue;
      entries.push(row);
    }
    return {entries,nextCursor:end||null,total:this.rows.length};
  }
}
function readTranscript(file,chat) {
  if(!fs.existsSync(file))return [];
  return fs.readFileSync(file,'utf8').split(/\r?\n/).filter(Boolean).map((line,index)=>{
    const first=line.indexOf('|'),second=line.indexOf('|',first+1);
    if(first<0||second<0)return null;
    const content=line.slice(second+1).replace(/\\n/g,'\n');
    return {id:'source/'+chat.id+'/'+crypto.createHash('sha256').update(index+'|'+line).digest('hex'),kind:'message',chatId:chat.id,topic:chat.topic,timestamp:line.slice(0,first),actor:line.slice(first+1,second),content,source:'Maestro chat.log'};
  }).filter(Boolean);
}
module.exports={Journal,readTranscript};
