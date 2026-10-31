const test=require('node:test');
const assert=require('node:assert/strict');
const {publicFrameHeaders}=require('./mobile-gateway.cjs');
const original={'content-security-policy':"default-src 'self'; script-src 'self'; frame-ancestors 'none'",'x-content-type-options':'nosniff'};
test('public map allows only the owner Pages origin while preserving other protections',()=>{
 const result=publicFrameHeaders(original,true);
 assert.equal(result['content-security-policy'],"default-src 'self'; script-src 'self'; frame-ancestors https://jonghyeon9084.github.io");
 assert.equal(result['x-content-type-options'],'nosniff');
 assert.match(original['content-security-policy'],/frame-ancestors 'none'/);
});
test('private gateway and local server policy remain unchanged',()=>assert.deepEqual(publicFrameHeaders(original,false),original));
