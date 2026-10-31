'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { PipelineRunner, hash } = require('./pipeline.cjs');
const { acquireSingleton } = require('./resident.cjs');
const clone = value => structuredClone(value);
const makeStage = (id, extra = {}) => ({ id, name: id, chatName: `NightShift-${id}`, participants: ['NightShift-Test'], promptFile: `${id}.txt`, completionMarker: `[STAGE_READY:${id.toUpperCase()}]`, requiredFiles: [`${id}.md`], ...extra });
const message = (actor, content, timestamp) => ({ participantName: actor, role: actor === 'user' ? 'user' : 'assistant', content, timestamp });
function fixture(stages = [makeStage('one')], manifestOptions = {}) {
  let time = 100000, persisted = null;
  const events = [], chats = [], outputs = {}, prompts = new Map(), calls = [];
  const store = { read: () => clone(persisted), write: state => { persisted = clone(state); }, event: row => events.push(clone(row)) };
  const files = { readPrompt: p => `Project C:\\workspace; assigned file ${p}; finite work.`, writePrompt: (id, text) => { prompts.set(id, text); return id; }, snapshot: paths => Object.fromEntries(paths.map(p => [p, clone(outputs[p] || null)])) };
  const adapter = {
    async list() { return clone(chats); },
    async status(id) { return clone(chats.find(c => c.id === id)); },
    async setModel(role, tier) { calls.push(['model', role, tier]); },
    async dispatch(stage, existing, file) {
      calls.push(['dispatch', stage.id]);
      const chat = existing ? chats.find(c => c.id === existing.id) : { id: `chat-${stage.id}`, topic: stage.chatName, participants: stage.participants.map(name => ({ name })), messages: [] };
      if (!existing) chats.push(chat);
      chat.messages.push(message('user', prompts.get(file), time));
      chat.state = 'moderator-thinking'; chat.isActive = true;
    }
  };
  const make = () => new PipelineRunner({ manifest: { version: 1, ...manifestOptions, stages }, store, files, adapter, clock: () => time, uuid: () => `uuid-${calls.length}`, idleGraceMs: 12000 });
  function adopt(stage = stages[0], { active = true, marker = false } = {}) {
    const chat = { id: `chat-${stage.id}`, topic: stage.chatName, participants: stage.participants.map(name => ({ name })), messages: [message('user', `Do the task, finish with ${stage.completionMarker}`, time - 1000)], state: active ? 'agent-working' : 'idle', isActive: active };
    if (marker) chat.messages.push(message('moderator', `Verified\n${stage.completionMarker}`, time - 100));
    chats.push(chat); return chat;
  }
  function output(file, data = 'new content') { outputs[file] = { hash: hash(data), size: data.length, mtimeMs: time }; }
  return { make, adapter, files, chats, outputs, events, calls, adopt, output, advance: ms => { time += ms; }, get state() { return persisted; }, setState: state => { persisted = clone(state); } };
}

test('adopted valid completion dispatches and completes the next finite stage in the same tick', async () => {
  const a = makeStage('scale', { adoptExisting: true }), b = makeStage('build');
  const f = fixture([a, b]); f.adopt(a, { active: false, marker: true }); f.output('scale.md');
  const dispatch = f.adapter.dispatch;
  f.adapter.dispatch = async (...args) => { await dispatch(...args); const c = f.chats.at(-1); c.isActive = false; c.state = 'idle'; c.messages.push(message('moderator', b.completionMarker, 100001)); f.output('build.md'); };
  await f.make().tick();
  assert.equal(f.state.status, 'awaiting-review');
  assert.equal(f.state.completed, false);
  assert.deepEqual(f.state.completedStages.map(s => s.id), ['scale', 'build']);
  assert.deepEqual(f.calls, [['dispatch', 'build']]);
});

test('idle without marker is allowed to settle, then requires attention; no resend', async () => {
  const f = fixture(); const runner = f.make(); await runner.tick();
  const chat = f.chats[0]; chat.isActive = false; chat.state = 'idle';
  await runner.tick(); assert.equal(f.state.status, 'running');
  f.advance(11000); await runner.tick(); assert.equal(f.state.status, 'running');
  // A brief idle -> working transition resets the idle grace.
  chat.isActive = true; chat.state = 'agent-working'; await runner.tick();
  f.advance(2000); chat.isActive = false; chat.state = 'idle'; await runner.tick();
  f.advance(12001); await runner.tick(); assert.equal(f.state.status, 'attention');
  await runner.tick(); assert.equal(f.calls.filter(c => c[0] === 'dispatch').length, 1);
});

test('worker marker and old moderator marker cannot finish a fresh task', async () => {
  const f = fixture(); const runner = f.make(); await runner.tick();
  const chat = f.chats[0]; chat.isActive = false; chat.state = 'idle';
  chat.messages.unshift(message('moderator', '[STAGE_READY:ONE]', 90000));
  chat.messages.push(message('NightShift-Test', '[STAGE_READY:ONE]', 100001)); f.output('one.md');
  await runner.tick(); f.advance(12002); await runner.tick();
  assert.equal(f.state.status, 'attention'); assert.equal(f.state.completedStages.length, 0);
});

for (const content of ['[STAGE_READY:ONE]', '**[STAGE_READY:ONE]**', '__[STAGE_READY:ONE]__', '`[STAGE_READY:ONE]`', 'Verified\r\n  **[STAGE_READY:ONE]**  \r\nOutputs checked.']) {
  test(`standalone completion syntax is accepted: ${JSON.stringify(content)}`, async () => {
    const f = fixture(); const runner = f.make(); await runner.tick();
    const chat = f.chats[0]; chat.isActive = false; chat.state = 'idle';
    chat.messages.push(message('moderator', content, 100001)); f.output('one.md');
    await runner.tick();
    assert.equal(f.state.status, 'awaiting-review'); assert.equal(f.state.completedStages.length, 1);
  });
}

for (const content of [
  'Finish with **[STAGE_READY:ONE]** when ready.',
  '아직 **[STAGE_READY:ONE]** 아님',
  '**[STAGE_READY:ONE]**는 완료되지 않았습니다.',
  '> [STAGE_READY:ONE]',
  '> **[STAGE_READY:ONE]**',
  '> Example marker:\n**[STAGE_READY:ONE]**',
  '> `\n> [STAGE_READY:ONE]\n> `',
  '```\n[STAGE_READY:ONE]\n```',
  '```text\n**[STAGE_READY:ONE]**\n```',
  '~~~markdown\n`[STAGE_READY:ONE]`\n~~~',
  '````\n```\n[STAGE_READY:ONE]\n````',
  '```\n~~~\n[STAGE_READY:ONE]\n```',
  '```\n```still code\n[STAGE_READY:ONE]\n```',
  '```unclosed\n[STAGE_READY:ONE]',
  '    [STAGE_READY:ONE]',
  '\t**[STAGE_READY:ONE]**',
  '- **[STAGE_READY:ONE]**',
  '# [STAGE_READY:ONE]',
  '"[STAGE_READY:ONE]"',
  '**[STAGE_READY:ONE]__',
  '**`[STAGE_READY:ONE]`**',
  '***[STAGE_READY:ONE]***',
  '``[STAGE_READY:ONE]``',
  '**[STAGE_READY:OTHER]**'
]) {
  test(`non-assertion completion syntax is rejected: ${JSON.stringify(content)}`, async () => {
    const f = fixture(); const runner = f.make(); await runner.tick();
    const chat = f.chats[0]; chat.isActive = false; chat.state = 'idle';
    chat.messages.push(message('moderator', content, 100001)); f.output('one.md');
    await runner.tick(); f.advance(12002); await runner.tick();
    assert.equal(f.state.status, 'attention'); assert.equal(f.state.completedStages.length, 0);
    assert.equal(f.calls.filter(c => c[0] === 'dispatch').length, 1);
  });
}

test('a standalone assertion after a closed code fence can complete', async () => {
  const f = fixture(); const runner = f.make(); await runner.tick();
  const chat = f.chats[0]; chat.isActive = false; chat.state = 'idle'; f.output('one.md');
  chat.messages.push(message('moderator', '> Quoted example\n\n~~~text\n> inside code\n~~~~\n**[STAGE_READY:ONE]**', 100001));
  await runner.tick(); assert.equal(f.state.status, 'awaiting-review');
});

test('formatted marker still requires idle state and the latest fresh response to be moderator', async () => {
  const f = fixture(); const runner = f.make(); await runner.tick();
  const chat = f.chats[0]; f.output('one.md');
  chat.messages.push(message('moderator', '**[STAGE_READY:ONE]**', 100001));
  await runner.tick(); assert.equal(f.state.completedStages.length, 0);
  chat.isActive = false; chat.state = 'idle';
  chat.messages.push(message('NightShift-Test', '**[STAGE_READY:ONE]**', 100002));
  await runner.tick(); f.advance(12003); await runner.tick();
  assert.equal(f.state.status, 'attention'); assert.equal(f.state.completedStages.length, 0);
});

test('formatted moderator marker before this request cannot complete it', async () => {
  const f = fixture(); const runner = f.make(); await runner.tick();
  const chat = f.chats[0]; chat.isActive = false; chat.state = 'idle'; f.output('one.md');
  chat.messages.unshift(message('moderator', '**[STAGE_READY:ONE]**', 99999));
  await runner.tick(); f.advance(12002); await runner.tick();
  assert.equal(f.state.status, 'attention'); assert.equal(f.state.completedStages.length, 0);
});

test('superseding user request invalidates a formatted completion', async () => {
  const f = fixture(); const runner = f.make(); await runner.tick();
  const chat = f.chats[0]; chat.isActive = false; chat.state = 'idle'; f.output('one.md');
  chat.messages.push(message('moderator', '**[STAGE_READY:ONE]**', 100001), message('user', 'Different task', 100002));
  await runner.tick();
  assert.equal(f.state.status, 'attention'); assert.match(f.state.reason, /superseded/);
  assert.equal(f.state.completedStages.length, 0);
});

for (const output of ['missing', 'empty', 'unchanged']) {
  test(`formatted completion still rejects ${output} required output`, async () => {
    const f = fixture();
    if (output === 'unchanged') f.output('one.md', 'old');
    f.advance(10000); const runner = f.make(); await runner.tick();
    if (output === 'empty') f.output('one.md', '');
    const chat = f.chats[0]; chat.isActive = false; chat.state = 'idle';
    chat.messages.push(message('moderator', '**[STAGE_READY:ONE]**', 110001));
    await runner.tick(); assert.equal(f.state.status, 'attention');
    assert.match(f.state.reason, /missing, empty or unchanged/); assert.equal(f.state.completedStages.length, 0);
  });
}

test('recorded 2026-10-31 integration response resumes from attention without dispatch', async () => {
  // Exact moderator content from .setup/map-events.jsonl, 2026-10-31T10:46:28.724Z.
  // It is a static fixture, independent of local .setup files and Maestro availability.
  const content = `**[STAGE_READY:INTEGRATION]**

Integrator 보고에 따르면 로컬 Studio 통합과 실제 1인 플레이 완주를 확인했고, 치명 오류 2건을 수정했습니다.

- **플레이 검증:** 주문 5개 → 정전 1인 해결 → 결과 → 무료 로비 복귀 성공. 최종 응답 25건 정상, 콘솔 오류 없음.
- **구현:** 재실행 가능한 통합 로더, 클라이언트 LoadReporter, 회귀 검사 추가 및 중요 코드 검토 이슈 대응.
- **최종 상태:** Studio **Edit 모드**, 로컬 Place 저장 완료. 기존 Baseplate·SpawnLocation 유지, 공개 게시 없음.
- **미검증:** 2인·16인 플레이, 모바일 성능, 실제 스트리밍·지연 경합. 오프라인 검사 통과는 다인 플레이 검증을 의미하지 않습니다.

다음 작업은 **현재 최대 인원 30명 설정과 전역 시간 14.5의 야간 연출 적합성 검토**, 지원 환경에서의 다인 플레이 검증입니다. 재미·매출·16인 성능 검증 완료를 뜻하지 않습니다.

[통합 보고서](<C:/Users/HP/Documents/ChatGPT/로블록스 게임 개발/docs/implementation/integration-report.md>) · [검증 기록](<C:/Users/HP/Documents/ChatGPT/로블록스 게임 개발/.setup/studio-verification.json>) · [로컬 Place](<C:/Users/HP/Documents/ChatGPT/로블록스 게임 개발/.setup/NightShift-local.rbxl>)`;
  const stage = makeStage('integration', { requiredFiles: ['docs/implementation/integration-report.md', '.setup/studio-verification.json'] });
  // The old exact-line matcher missed this real assertion.
  assert.equal(content.split(/\r?\n/).some(line => line.trim() === stage.completionMarker), false);
  const f = fixture([stage]); f.advance(1793441812390 - 100000); await f.make().tick();
  const chat = f.chats[0]; chat.isActive = false; chat.state = 'idle';
  chat.messages.push(message('moderator', content, 1793443588724));
  f.advance(1793443603347 - 1793441812390);
  for (const file of stage.requiredFiles) f.output(file);
  const state = f.state; state.status = 'attention'; state.reason = 'Chat settled idle without a fresh moderator completion marker'; f.setState(state);
  const runner = f.make(); await runner.tick(); assert.equal(f.state.status, 'attention');
  runner.resume(); await runner.tick();
  assert.equal(f.state.status, 'awaiting-review'); assert.deepEqual(f.state.completedStages.map(s => s.id), ['integration']);
  assert.equal(f.calls.filter(c => c[0] === 'dispatch').length, 1);
});

test('unchanged preexisting output cannot pass merely because a marker is present', async () => {
  const f = fixture(); f.output('one.md', 'old'); f.advance(10000);
  const runner = f.make(); await runner.tick();
  const chat = f.chats[0]; chat.isActive = false; chat.state = 'idle'; chat.messages.push(message('moderator', '[STAGE_READY:ONE]', 110001));
  await runner.tick(); assert.equal(f.state.status, 'attention'); assert.match(f.state.reason, /unchanged/);
});

test('successful CLI timeout is reconciled from exact persisted user text without duplicate dispatch', async () => {
  const f = fixture(); const dispatch = f.adapter.dispatch;
  f.adapter.dispatch = async (...args) => { await dispatch(...args); throw Error('timeout after acceptance'); };
  const runner = f.make(); await runner.tick();
  assert.equal(f.state.checkpoint.phase, 'sent'); assert.equal(f.state.status, 'running');
  await f.make().tick(); assert.equal(f.calls.filter(c => c[0] === 'dispatch').length, 1);
  assert.ok(f.events.some(e => e.kind === 'dispatch-reconciled'));
});

test('ambiguous failed dispatch stays at attention across restart and explicit resume cannot resend it', async () => {
  const f = fixture(); f.adapter.dispatch = async () => { f.calls.push(['dispatch', 'one']); throw Error('network lost'); };
  await f.make().tick(); assert.equal(f.state.status, 'attention'); assert.equal(f.state.checkpoint.phase, 'prepared');
  const next = f.make(); await next.tick(); assert.equal(f.calls.length, 1);
  next.resume(); await next.tick(); assert.equal(f.calls.length, 1); assert.equal(f.state.status, 'attention');
});

test('crash after checkpoint and accepted send reattaches from real user message on restart', async () => {
  const f = fixture(); await f.make().tick();
  const state = f.state; state.status = 'dispatching'; state.checkpoint.phase = 'prepared'; delete state.checkpoint.userIdentity; f.setState(state);
  await f.make().tick(); assert.equal(f.state.status, 'running'); assert.equal(f.state.checkpoint.phase, 'sent'); assert.equal(f.calls.length, 1);
});

test('unexpected active chat and changed adoption request are never dispatched/adopted', async () => {
  const f = fixture(); f.adopt(); await f.make().tick();
  assert.equal(f.state.status, 'attention'); assert.equal(f.calls.length, 0);
  const g = fixture([makeStage('scale', { adoptExisting: true })]); const chat = g.adopt(); chat.messages.push(message('user', 'Different task', 100000));
  await g.make().tick(); assert.equal(g.state.status, 'attention'); assert.equal(g.calls.length, 0);
});

test('graceful stop/restart preserves in-flight stage, and stop requested prevents new dispatch', async () => {
  const f = fixture(); let runner = f.make(); await runner.tick(); runner.requestStop(); runner.stop();
  assert.equal(f.state.status, 'stopped'); runner = f.make(); await runner.tick();
  assert.equal(f.state.status, 'running'); assert.equal(f.calls.length, 1);
  const g = fixture(); const paused = g.make(); paused.requestStop(); await paused.tick(); assert.equal(g.calls.length, 0);
});

test('model routing executes before a fresh idle dispatch, never on adopted work', async () => {
  const f = fixture([makeStage('one', { modelAssignments: { Test: 'simple' } })]); await f.make().tick();
  assert.deepEqual(f.calls, [['model', 'Test', 'simple'], ['dispatch', 'one']]);
  const g = fixture([makeStage('one', { adoptExisting: true, modelAssignments: { Test: 'complex' } })]); g.adopt(); await g.make().tick(); assert.equal(g.calls.length, 0);
});

test('aggregate other-chat capacity waits without dispatch or attention, then advances immediately when freed', async () => {
  const f = fixture([makeStage('build', { participants: ['NightShift-A', 'NightShift-B', 'NightShift-C'] })]);
  f.chats.push({ id: 'dashboard', topic: 'NightShift-Dashboard', isActive: true, state: 'agent-working', participants: [{ name: 'NightShift-Dashboard' }], messages: [] });
  const runner = f.make(); await runner.tick();
  assert.equal(f.state.status, 'waiting-capacity'); assert.equal(f.calls.length, 0);
  await runner.tick(); assert.equal(f.events.filter(e => e.kind === 'waiting-capacity').length, 1);
  f.chats[0].isActive = false; f.chats[0].state = 'idle'; await runner.tick();
  assert.equal(f.state.status, 'running'); assert.deepEqual(f.calls, [['dispatch', 'build']]);
});

test('bound localhost singleton excludes a second process and releases cleanly', async () => {
  const first = await acquireSingleton(0);
  const port = first.address().port;
  try { await assert.rejects(acquireSingleton(port), error => error.code === 'EADDRINUSE'); }
  finally { await new Promise(resolve => first.close(resolve)); }
  const next = await acquireSingleton(port); await new Promise(resolve => next.close(resolve));
});

test('maxWorkers=2 waits for aggregate capacity and uses the configured limit in events', async () => {
  const f = fixture([makeStage('one', { participants: ['NightShift-A', 'NightShift-B'] })], { maxWorkers: 2 });
  f.chats.push({ id: 'other', topic: 'other', isActive: true, state: 'agent-working', participants: [{ name: 'NightShift-C' }], messages: [] });
  const runner = f.make(); await runner.tick();
  assert.equal(f.state.status, 'waiting-capacity'); assert.equal(f.calls.length, 0);
  assert.equal(f.events.at(-1).maximum, 2);
  f.chats[0].isActive = false; f.chats[0].state = 'idle'; await runner.tick();
  assert.equal(f.state.status, 'running'); assert.equal(f.calls.length, 1);
});

test('an uncompleted stage above maxWorkers stops explicitly instead of waiting forever', async () => {
  const f = fixture([makeStage('one', { participants: ['NightShift-A', 'NightShift-B', 'NightShift-C'] })], { maxWorkers: 2 });
  await f.make().tick(); assert.equal(f.state.status, 'attention'); assert.match(f.state.reason, /above maxWorkers 2/);
  assert.equal(f.calls.length, 0);
});

test('maxWorkers=4 waits while another worker is active, then dispatches the four-worker batch', async () => {
  const participants = ['NightShift-Profiles', 'NightShift-Economy', 'NightShift-Delivery', 'NightShift-World'];
  const f = fixture([makeStage('features', { participants })], { maxWorkers: 4 });
  f.chats.push({ id: 'other', topic: 'other', isActive: true, state: 'agent-working', participants: [{ name: 'NightShift-Review' }], messages: [] });
  const runner = f.make(); await runner.tick();
  assert.equal(f.state.status, 'waiting-capacity'); assert.equal(f.calls.length, 0);
  assert.equal(f.events.at(-1).maximum, 4); assert.equal(f.events.at(-1).occupied, 1);
  f.chats[0].isActive = false; f.chats[0].state = 'idle'; await runner.tick();
  assert.equal(f.state.status, 'running'); assert.deepEqual(f.calls, [['dispatch', 'features']]);
});
