const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {Journal,readTranscript}=require('./journal.cjs');
const {createGateway}=require('./mobile-gateway.cjs');
(async()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'nightshift-journal-'));
 try {
  let journal=new Journal(directory);
  journal.add({id:'m1',kind:'message',actor:'worker',content:'실제 응답'});
  journal.change('chat/1','working',{kind:'status'});
  journal=new Journal(directory);
  assert.equal(journal.add({id:'m1',kind:'message'}),false);
  journal.change('chat/1','working',{kind:'status'});
  assert.equal(journal.rows.length,2);
  journal.change('chat/1','idle',{kind:'status'});
  assert.equal(journal.rows.length,3);
  assert.equal(journal.query({q:'실제'}).entries[0].id,'m1');
  const page=journal.query({limit:1});assert.equal(page.nextCursor,2);
  assert.equal(journal.query({before:page.nextCursor,limit:1}).entries[0].content,undefined);
  const source=path.join(directory,'chat.log');fs.writeFileSync(source,'2026-10-31T09:00:00Z|worker|hello\\nworld\n');
  assert.equal(readTranscript(source,{id:'c',topic:'Test'})[0].content,'hello\nworld');
  const token='a'.repeat(64),server=createGateway(token);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base='http://127.0.0.1:'+server.address().port;
  try {
   assert.equal((await fetch(base+'/api/state')).status,401);
   assert.equal((await fetch(base+'/access/'+'b'.repeat(64))).status,401);
   const login=await fetch(base+'/access/'+token,{redirect:'manual'});
   assert.equal(login.status,303);assert.match(login.headers.get('set-cookie'),/HttpOnly; Secure; SameSite=Strict/);
   const headers={Cookie:'nightshift_access='+token};
   assert.equal((await fetch(base+'/api/state',{headers,method:'POST'})).status,405);
   assert.equal((await fetch(base+'/.setup/mobile-access.json',{headers})).status,404);
   assert.equal((await fetch(base+'/api/execute',{headers})).status,404);
   assert.equal((await fetch(base+'/api/state',{headers})).status,200);
  } finally {await new Promise(resolve=>server.close(resolve));}
  const publicServer=createGateway(token,{publicAccess:true});await new Promise(resolve=>publicServer.listen(0,'127.0.0.1',resolve));
  try {
   const publicBase='http://127.0.0.1:'+publicServer.address().port;
   assert.equal((await fetch(publicBase+'/api/state')).status,200);
   assert.equal((await fetch(publicBase+'/api/execute')).status,404);
   assert.equal((await fetch(publicBase+'/api/state',{method:'POST'})).status,405);
   assert.equal((await fetch(publicBase+'/.setup/mobile-access.json')).status,404);
  } finally {await new Promise(resolve=>publicServer.close(resolve));}
  console.log('PASS: durable deduplication, status transitions, search/pagination, transcript parsing, access key, secure cookie, read-only route allowlist, authenticated state.');
 } finally {for(const name of fs.readdirSync(directory))fs.unlinkSync(path.join(directory,name));fs.rmdirSync(directory);}
})().catch(error=>{console.error(error);process.exitCode=1;});
