'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const request = JSON.parse(fs.readFileSync(path.join(root, 'setup-test/request.json'), 'utf8'));
const report = JSON.parse(fs.readFileSync(path.join(root, request.workerOutput), 'utf8'));
const v = request.input;
const expected = v.completedOrders >= v.requiredOrders && v.blackoutResolved && v.shiftFinished;
assert.equal(report.testId, request.testId);
assert.equal(report.nonce, request.nonce);
assert.equal(report.success, expected);
assert.equal(report.testedStudio, false);
assert.equal(typeof report.explanation, 'string');
assert(report.explanation.trim().length > 0);
console.log(JSON.stringify({test: request.testId, artifactValidated: true, success: report.success, testedStudio: false}));
// This validates the returned artifact only. Maestro's real conversation log
// must separately establish that a worker received and performed the task.
