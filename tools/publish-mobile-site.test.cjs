'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {validateUrl}=require('./publish-mobile-site.cjs');
test('public root tunnel URL is accepted',()=>assert.equal(validateUrl('https://example-test.trycloudflare.com/'),'https://example-test.trycloudflare.com/'));
for(const value of ['http://example.trycloudflare.com/','https://example.trycloudflare.com.evil.test/','https://example.trycloudflare.com/access/private-key','https://example.trycloudflare.com/?token=private','https://user:secret@example.trycloudflare.com/','https://example.trycloudflare.com:8443/','https://example.trycloudflare.com/#secret','https://localhost/']) {
 test('reject unsafe or private endpoint '+value.replace(/secret|private/g,'redacted'),()=>assert.throws(()=>validateUrl(value)));
}
