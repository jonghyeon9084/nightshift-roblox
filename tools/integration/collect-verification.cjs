'use strict';
// Summarize already recorded evidence. This script does not run Studio or tests.
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^\uFEFF/,'');
const lines=p=>read(p).trim().split(/\r?\n/).map(JSON.parse);
const last=(arr,label)=>arr.filter(x=>x.label===label).at(-1);
const textOf=r=>r.content.filter(x=>x.type==='text').map(x=>x.text).join('\n');
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,p))).digest('hex');
const events=lines('.setup/integration/events.jsonl');
const play=lines('.setup/integration/play-flow.jsonl');
const post=lines('.setup/integration/postplay.jsonl');
const mode=last(events,'final Edit state');
const install=last(events,'final source equality and idempotency');
const censusEvent=last(events,'final retained content and engine census');
const installed=JSON.parse(textOf(install));
const census=JSON.parse(textOf(censusEvent));
const result=last(play,'result');
const retry=last(play,'free retry');
const consoleEvent=last(post,'final play console');
const manifest=JSON.parse(read('.setup/integration/manifest.json'));
assert.match(textOf(mode),/Current Studio Mode: Edit/);
assert.equal(installed.Changed,0);
assert.equal(installed.Installed,11);
assert.equal(result.data.SuccessCount,5);
assert.equal(result.data.Code,'AdjustedClose');
assert.equal(retry.data.Store.Phase,'Lobby');
assert.equal(retry.data.Self.Loaded,true);
assert.equal(retry.data.Acks.length,25);
assert(retry.data.Acks.every(x=>x.Ok));
assert.equal(consoleEvent.data,'NightShift server ready: four independent stores; target capacity 16; no play-test claim');
for(const m of manifest){
 assert.equal(hash(m.file),m.sha256,'Evidence is stale: '+m.file);
 assert(census.Sources.some(s=>s.Path===m.target && s.Class===m.className && s.Hash===m.sha256));
}
// Tee-Object on Windows PowerShell writes UTF-16LE. Read without changing logs.
const offline=p=>{const b=fs.readFileSync(path.join(root,p));return b[0]===255&&b[1]===254?b.toString('utf16le'):b.toString('utf8');};
assert.match(offline('.setup/integration/server-offline.txt'),/5192 assertions; 72 full/);
assert.match(offline('.setup/integration/client-offline.txt'),/18 pure load-report race\/retry assertions/);
assert.match(offline('.setup/integration/world-offline.txt'),/"compile": "PASS"/);
const place='.setup/NightShift-local.rbxl';
const stat=fs.statSync(path.join(root,place));
const report={
 schemaVersion:1,trackingId:'1983ffc0-ec8e-4f43-ae24-52a456d7152d',
 actor:'NightShift-Integrator',assembledAt:new Date().toISOString(),
 status:'STAGE_READY:INTEGRATION',scope:'Local integration, actual one-client play and fatal-error repair only',
 workerGate:{checked:'Maestro group statuses and build/review histories before Studio writes',result:'Other game-worker groups idle; build and independent review completed'},
 studio:{id:mode.studio.id,name:'Place1',placeId:0,finalMode:'Edit',verifiedAt:mode.at,closed:false,published:false},
 localPlace:{path:path.join(root,place),bytes:stat.size,modifiedAt:stat.mtime.toISOString(),sha256:hash(place),savedThrough:'Studio File > Save to File As',reopened:false},
 installation:{...installed,baselinePreserved:{Baseplate:census.Baseplate,SpawnLocation:census.OriginalSpawn},sources:manifest},
 settings:{streamingEnabled:census.Streaming,maxPlayers:census.MaxPlayers,targetPlayers:16,lightingClockTime:census.ClockTime},
 actualPlay:{clients:1,serverStateInjection:false,movement:'Client Humanoid:MoveTo with distance assertions; actual keyboard/mouse tool inputs',
  resultAt:result.at,result:result.data,acknowledgements:25,rejectedAcknowledgements:0,
  retry:{at:retry.at,phase:'Lobby',loaded:true,ready:false,carry:false,role:false},
  hubInteraction:last(play,'hub marker result'),heldButton:last(play,'CR-001 engine check'),
  otherStoreJoins:post.filter(x=>/^join Store0[234]$/.test(x.label)),
  hubAfterRejoin:last(post,'Hub prompt after rejoin'),console:consoleEvent},
 syntheticEngineTest:{...last(post,'synthetic rebind'),limitation:'Client marker temporarily removed/restored; not real streaming eviction, delayed RemoteEvent or result-to-lobby race'},
 offline:{serverAssertions:5192,scheduleLayoutTeamLoops:72,clientAssertions:{StateStore:16,TrayView:19,LoadReporter:18},world:'AST/AABB 30 boxes, eight reachable markers, four-stud route; not engine geometry',evidence:['.setup/integration/server-offline.txt','.setup/integration/client-offline.txt','.setup/integration/world-offline.txt']},
 fixes:[
  {id:'CR-001',status:'fixed',evidence:'Stable GUI identities and latest callback; actual 1.6-second mouse hold across state updates produced one successful acknowledgement',remaining:'Real touch and multi-client concurrent updates'},
  {id:'CR-002',status:'fixed-partially-engine-verified',evidence:'Context-aware bounded LoadReporter, 18 pure assertions, synthetic marker rebind without F5',remaining:'Natural result-to-lobby delayed RemoteEvent race'},
  {id:'CR-003',status:'fixed',evidence:'Actual Hub E opened stores; one prompt remained after store changes',remaining:'Real mobile touch and streaming eviction'},
  {id:'INT-001',status:'fixed',failure:'Startup: Hub Spawn is obstructed or has no floor',cause:'Original coplanar SpawnLocation intercepted floor ray',fix:'Ray includes owned world; overlap still rejects external collidable obstacles'},
  {id:'INT-002',status:'fixed',failure:'First outage: attempt to index boolean with storeId',cause:'Vacant role owner false passed nil-only guard',fix:'Reject false before indexing user; 1–4-person vacant-role regression coverage'},
  {id:'INT-003',status:'fixed',failure:'Immediate role renewal could return COOLDOWN',fix:'Renewal clock reset after successful new role assignment; final 25 acknowledgements all OK'},
  {id:'INT-004',status:'fixed',failure:'Default UI list name sorting displaced rows',fix:'Explicit LayoutOrder sorting'}
 ],
 initialFailures:['Official MCP batch missing at nonvirtual LocalAppData; resolved by launching installed official StudioMCP.exe using original transport implementation in memory','INT-001 and INT-002 failed actual play before repairs','Early character_navigation reported success without arriving; replaced test movement with bounded physical MoveTo waypoints','One stop request timed out during an active automation; next state query confirmed Edit','Offline log capture initially used a relative Tee path while test changed directory; world CLI initially omitted required bin argument. Corrected invocations passed; these were harness invocation failures'],
 unverified:['Two-client play: official start_stop_play schema exposes only is_start; no client-count/server test interface','Three/four-person role collaboration and cross-store concurrency','Sixteen-player performance and isolation under real load','Mobile/touch, real device frame time, memory and bandwidth','Actual streaming eviction and delayed/out-of-order network result-boundary race','Full S1/S2 live concurrency matrix','Night lighting and blackout visual readability; current global ClockTime remains 14.5','Playtest fun, retention and revenue','Saved Place reopen test'],
 remaining:['Actual MaxPlayers is 30; Config target 16 is not a place setting','Small viewport HUD scroll/readability still needs device validation','Full physical order loop covered Store01; rotated stores 02–04 covered entry/load and Store04 synthetic rebind only'],
 evidence:['.setup/integration/events.jsonl','.setup/integration/play-flow.jsonl','.setup/integration/postplay.jsonl','.setup/integration/tools.json','.setup/integration/manifest.json','.setup/integration/1793443138366.jpg'],
 forbiddenActionsPerformed:[],blocked:false
};
fs.writeFileSync(path.join(root,'.setup/studio-verification.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({status:report.status,finalMode:report.studio.finalMode,sources:manifest.length,placeBytes:stat.size,report:'.setup/studio-verification.json'}));
