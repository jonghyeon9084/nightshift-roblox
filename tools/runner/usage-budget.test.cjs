const test=require('node:test'),assert=require('node:assert/strict');
const {normalize,parseEvents,evaluate}=require('./usage-budget.cjs');
const now=1793463000000;
const policy={enabled:true,reservePercent:10,stopNewAtRemainingPercent:20,stopActiveAtRemainingPercent:15,maxSnapshotAgeSeconds:900};
const sample=(used=71,at=now,reset=now/1000+86400)=>normalize({limit_id:'codex',primary:{used_percent:used,window_minutes:10080,resets_at:reset}},at,'test');
test('29 percent remaining allows work; 20 stops dispatch and 15 stops active work',()=>{
 assert.equal(evaluate(policy,[sample()],now).remainingPercent,29);
 assert.equal(evaluate(policy,[sample()],now).blocked,false);
 assert.equal(evaluate(policy,[sample(80)],now).blocked,true);
 assert.equal(evaluate(policy,[sample(80)],now).stopActive,false);
 assert.equal(evaluate(policy,[sample(85)],now).stopActive,true);
});
test('missing, stale, future and expired quotas block new work instead of implying free usage',()=>{
 for(const samples of [[],[sample(0,now-901000)],[sample(0,now+6000)],[sample(0,now,now/1000)]])assert.equal(evaluate(policy,samples,now).blocked,true);
 assert.equal(normalize({limitId:'codex',primary:null},now,'test'),null);
 assert.equal(normalize({limitId:'codex',primary:{usedPercent:null,windowDurationMins:5,resetsAt:now/1000+10}},now,'test'),null);
});
test('lagging reports in same window cannot lower usage; genuine new reset window can',()=>{
 assert.equal(evaluate(policy,[sample(84,now-10),sample(71)],now).remainingPercent,16);
 assert.equal(evaluate(policy,[sample(84,now-10,now/1000+10),sample(2,now,now/1000+90000)],now).remainingPercent,98);
});
test('uses most constrained window and rejects malformed percentages',()=>{
 const a=sample();a.windows.push({name:'secondary',usedPercent:90,windowMinutes:300,resetsAt:now/1000+300});
 assert.equal(evaluate(policy,[a],now).remainingPercent,10);
 assert.equal(sample(-1),null);assert.equal(sample(101),null);
 assert.equal(evaluate({...policy,reservePercent:9},[sample()],now).blocked,true);
});
test('only allowlisted quota metadata is retained from real token-count rows',()=>{
 const raw={type:'event_msg',timestamp:new Date(now).toISOString(),payload:{type:'token_count',info:{secret:'OMIT'},rate_limits:{limit_id:'codex',primary:{used_percent:71,window_minutes:10080,resets_at:now/1000+9000},credits:{secret:'OMIT'}}}};
 const result=parseEvents('broken\n'+JSON.stringify(raw)+'\n'+JSON.stringify({...raw,type:'response_item'}),'test');
 assert.equal(result.length,1);assert.equal(JSON.stringify(result).includes('OMIT'),false);
});
