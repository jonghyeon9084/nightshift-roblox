'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createStore, createFiles, transcriptMessages, mergeMessages, timestamp, within } = require('./io.cjs');

test('disk checkpoint survives reopening, events append, required outputs capture hashes and missing files', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'nightshift-runner-'));
  t.after(() => fs.rmSync(root, { recursive: true }));
  const dir = path.join(root, '.setup/runner'); const store = createStore(dir);
  store.write({ status: 'dispatching', checkpoint: { dispatchId: 'test', phase: 'prepared' } });
  store.event({ kind: 'dispatch-prepared' }); store.event({ kind: 'stopped' });
  assert.equal(createStore(dir).read().checkpoint.dispatchId, 'test');
  assert.equal(fs.readFileSync(path.join(dir, 'events.jsonl'), 'utf8').trim().split('\n').length, 2);
  const files = createFiles(root, dir); fs.writeFileSync(path.join(root, 'artifact.md'), '검증');
  const result = files.snapshot(['artifact.md', 'absent.md']);
  assert.ok(result['artifact.md'].size > 0); assert.equal(result['absent.md'], null);
  assert.throws(() => within(root, '../outside'), /escapes/);
});

test('transcript user/moderator normalization ignores incomplete final append only', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'nightshift-transcript-'));
  t.after(() => fs.rmSync(root, { recursive: true }));
  fs.mkdirSync(path.join(root, 'chat'));
  const file = path.join(root, 'chat/history.jsonl');
  const rows = [{ type: 'user', participantName: 'You', fullResponse: 'prompt', timestamp: 1000 }, { type: 'delegation', participantName: 'Moderator', fullResponse: 'result', timestamp: 2000 }];
  fs.writeFileSync(file, rows.map(JSON.stringify).join('\n') + '\n{"incomplete":');
  const parsed = transcriptMessages(root, 'chat');
  assert.deepEqual(parsed.map(m => m.participantName), ['user', 'moderator']);
  fs.writeFileSync(file, '{bad}\n{}\n'); assert.throws(() => transcriptMessages(root, 'chat'));
});

test('Maestro history/live timestamp skew is deduplicated without losing genuinely repeated prompts', () => {
  const live = [{ participantName: 'user', content: 'same prompt', timestamp: 1000 }];
  const archived = [{ participantName: 'user', content: 'same prompt', timestamp: 1050, eventType: 'user' }, { participantName: 'user', content: 'same prompt', timestamp: 10000, eventType: 'user' }];
  const merged = mergeMessages(live, archived);
  assert.equal(merged.length, 2); assert.equal(merged[0].timestamp, 1000); assert.equal(merged[0].eventType, 'user');
});

test('numeric and ISO source timestamps normalize for chronological comparisons', () => {
  assert.equal(timestamp(1000), 1000); assert.equal(timestamp('1000'), 1000);
  assert.equal(timestamp('1970-01-01T00:00:01.000Z'), 1000);
  assert.throws(() => timestamp('not a date'), /timestamp/);
});
