const test=require('node:test'),assert=require('node:assert/strict');
const {selectModel,validateSelection,assertInactive}=require('./model-routing.cjs');
const policy=require('./model-policy.json');
test('workload routes effort and model; dangerous data work escalates',()=>{
 assert.equal(selectModel(policy,'X',{workload:'test-run'}).effort,'low');
 assert.equal(selectModel(policy,'X',{workload:'interface'}).model,'gpt-6.1-sol');
 assert.equal(selectModel(policy,'X',{workload:'code',risks:['currency']}).tier,'critical');
 assert.equal(selectModel(policy,'X',{workload:'debug',unresolvedFailure:true}).effort,'xhigh');
 assert.equal(selectModel(policy,'X',{workload:'code'}).effort,'medium');
 assert.throws(()=>selectModel(policy,'X',{workload:'invented'}));
 assert.throws(()=>selectModel(policy,'X','invented'));
});
test('old stage tiers preserve their existing models',()=>{
 for(const tier of ['simple','standard','complex'])assert.equal(selectModel(policy,'X',tier).model,policy.tiers[tier].model);
});
test('catalog checks both model and effort, not just the model name',()=>{
 const c={models:[{slug:'example',supported_reasoning_levels:[{effort:'low'}]}]};
 assert.throws(()=>validateSelection({model:'absent',effort:'low'},c));
 assert.throws(()=>validateSelection({model:'example',effort:'ultra'},c));
 assert.equal(validateSelection({model:'example',effort:'low'},c).effort,'low');
});
test('configuration never changes a busy or unknown-state participant',()=>{
 for(const state of ['agent-working','moderator-thinking','error',undefined])assert.throws(()=>assertInactive('A',[{state,participants:[{name:'A'}]}]));
 assert.throws(()=>assertInactive('A',[{isActive:true,state:'idle',participants:[{name:'A'}]}]));
 assertInactive('A',[{state:'idle',participants:[{name:'A'}]}]);
 assertInactive('A',[{isActive:true,participants:[{name:'B'}]}]);
});
