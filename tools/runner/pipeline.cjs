'use strict';
const crypto = require('node:crypto');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const busy = chat => chat && (chat.isActive || !['idle', 'stopped'].includes(chat.state));
const user = m => m.role === 'user' || m.participantName === 'user';
const ordered = chat => [...(chat.messages || [])].sort((a, b) => a.timestamp - b.timestamp);
const latestUser = chat => ordered(chat).filter(user).at(-1);
const identity = m => m && `${m.timestamp}:${hash(m.content || '')}`;
function hasCompletionMarker(content, marker) {
  // A marker is an assertion on its own line, optionally bold or inline code.
  // Do not strip arbitrary Markdown: quoted examples and fenced code are not assertions.
  const assertions = new Set([marker, `**${marker}**`, `__${marker}__`, `\`${marker}\``]);
  let fence = null, quote = false;
  for (const line of (content || '').split(/\r?\n/)) {
    const delimiter = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line);
    if (fence) {
      if (delimiter && delimiter[1][0] === fence.character && delimiter[1].length >= fence.length && !delimiter[2].trim()) fence = null;
      continue;
    }
    // Markdown permits unprefixed paragraph continuations inside a blockquote.
    if (/^ {0,3}>/.test(line)) { quote = true; continue; }
    if (quote) { if (!line.trim()) quote = false; else continue; }
    if (delimiter) { fence = { character: delimiter[1][0], length: delimiter[1].length }; continue; }
    // Four-space/tab indentation is a Markdown code block, not a standalone assertion.
    if (/^(?: {4}| *\t)/.test(line)) continue;
    if (assertions.has(line.trim())) return true;
  }
  return false;
}
function validateManifest(manifest) {
  if (manifest.version !== 1 || !Array.isArray(manifest.stages) || !manifest.stages.length) throw Error('Invalid pipeline manifest');
  if (manifest.maxWorkers !== undefined && (!Number.isInteger(manifest.maxWorkers) || manifest.maxWorkers < 1 || manifest.maxWorkers > 4)) throw Error('Invalid maxWorkers: expected 1, 2, 3 or 4');
  const ids = new Set();
  for (const [i, s] of manifest.stages.entries()) {
    if (!s.id || ids.has(s.id) || !s.name || !s.chatName || !s.promptFile || !/^\[STAGE_READY:[A-Z0-9_-]+\]$/.test(s.completionMarker)) throw Error(`Invalid stage ${i}`);
    ids.add(s.id);
    if (!Array.isArray(s.participants) || !s.participants.length || s.participants.length > 4 || new Set(s.participants).size !== s.participants.length || !s.participants.every(p => typeof p === 'string' && p)) throw Error(`Invalid participants: ${s.id}`);
    if (!Array.isArray(s.requiredFiles) || !s.requiredFiles.every(p => typeof p === 'string' && p)) throw Error(`Invalid requiredFiles: ${s.id}`);
    if (s.adoptExisting && i !== 0) throw Error('Only the initial stage may adopt existing work');
    for (const [role, tier] of Object.entries(s.modelAssignments || {})) {
      if (!s.participants.includes(`NightShift-${role}`) || !['simple', 'standard', 'complex'].includes(tier)) throw Error(`Invalid model assignment: ${s.id}`);
    }
  }
}

// All durable effects and CLI operations are injected so tests never contact Maestro.
class PipelineRunner {
  constructor({ manifest, store, adapter, files, clock = Date.now, uuid = crypto.randomUUID, idleGraceMs = 12000 }) {
    validateManifest(manifest);
    Object.assign(this, { manifest, store, adapter, files, clock, uuid, idleGraceMs });
    this.manifestHash = hash(JSON.stringify(manifest));
    this.state = store.read() || { mode: 'resident', status: 'ready', stage: 0, stageId: manifest.stages[0].id, chatId: null, completedStages: [], completed: false, manifestHash: this.manifestHash };
    this.locked = false;
  }
  save(patch = {}) {
    Object.assign(this.state, patch, { mode: 'resident', completed: false, pid: process.pid, at: new Date(this.clock()).toISOString() });
    this.store.write(this.state);
  }
  event(kind, extra = {}) { this.store.event({ at: new Date(this.clock()).toISOString(), kind, stageId: this.state.stageId, chatId: this.state.chatId, ...extra }); }
  attention(reason) { this.save({ status: 'attention', reason }); this.event('attention', { reason }); }
  capacityAvailable(chats, stage, chatId) {
    const maximum = this.manifest.maxWorkers ?? 3;
    if (stage.participants.length > maximum) { this.attention(`Stage ${stage.id} requests ${stage.participants.length} workers above maxWorkers ${maximum}`); return false; }
    const occupied = chats.filter(c => c.id !== chatId && busy(c)).reduce((sum, c) => sum + (c.participants?.length || 3), 0);
    if (occupied + stage.participants.length <= maximum) return true;
    const reason = `Waiting for worker capacity: ${occupied} active elsewhere + ${stage.participants.length} requested exceeds ${maximum}`;
    const changed = this.state.status !== 'waiting-capacity' || this.state.reason !== reason;
    this.save({ status: 'waiting-capacity', reason });
    if (changed) this.event('waiting-capacity', { occupied, requested: stage.participants.length, maximum });
    return false;
  }
  resume() {
    if (this.state.manifestHash !== this.manifestHash) throw Error('Manifest changed; retain checkpoint and review before resetting');
    if (this.state.status === 'attention') { this.save({ status: this.state.checkpoint ? 'running' : 'ready', reason: null, idleSince: null }); this.event('operator-resume'); }
  }
  async tick() {
    if (this.stopRequested || this.locked || ['attention', 'awaiting-review'].includes(this.state.status)) return;
    this.locked = true;
    try {
      if (this.state.manifestHash !== this.manifestHash) return this.attention('Manifest changed after checkpoint; manual review required');
      if (this.state.status === 'stopped') this.save({ status: this.state.resumeStatus || (this.state.checkpoint ? 'running' : 'ready'), resumeStatus: null });
      // Each completed stage advances here in the same tick, with no timer delay.
      for (let remaining = this.manifest.stages.length * 3 + 1; remaining > 0; remaining--) {
        if (this.stopRequested) return;
        const stage = this.manifest.stages[this.state.stage];
        if (!stage) { this.save({ status: 'awaiting-review', stageId: null, chatId: null, reason: 'Finite pipeline finished; independent integration/Studio verification still requires review' }); this.event('pipeline-awaiting-review'); return; }
        const chats = await this.adapter.list();
        const matches = chats.filter(c => c.topic === stage.chatName);
        if (matches.length > 1) return this.attention(`Duplicate chat name: ${stage.chatName}`);
        let chat = matches[0] ? await this.adapter.status(matches[0].id) : null;
        if (this.state.chatId && (!chat || chat.id !== this.state.chatId)) return this.attention('Checkpoint chat disappeared or changed');
        if (chat && !stage.participants.every(p => chat.participants.some(member => member.name === p))) return this.attention('Required participants missing from existing chat');
        if (this.state.checkpoint) {
          if (!chat) return this.attention('Dispatch result cannot be reconciled: chat missing');
          if (this.state.checkpoint.phase === 'prepared') {
            const sent = ordered(chat).filter(user).filter(m => hash(m.content || '') === this.state.checkpoint.wireHash && m.timestamp >= this.state.checkpoint.preparedAt - 2000);
            if (sent.length !== 1) return this.attention('Ambiguous interrupted dispatch; exact user-message evidence absent or duplicated. No automatic resend');
            this.save({ chatId: chat.id, status: 'running', checkpoint: { ...this.state.checkpoint, phase: 'sent', userIdentity: identity(sent[0]), userHash: hash(sent[0].content || ''), startAt: sent[0].timestamp } });
            this.event('dispatch-reconciled', { dispatchId: this.state.checkpoint.dispatchId, promptHash: this.state.checkpoint.promptHash });
          }
        } else if (stage.adoptExisting) {
          const opening = chat && latestUser(chat);
          if (!opening || !(opening.content || '').includes(stage.completionMarker)) return this.attention('Initial adoption does not match the latest requested completion marker');
          this.save({ status: 'running', chatId: chat.id, checkpoint: { phase: 'adopted', startAt: opening.timestamp, userIdentity: identity(opening), userHash: hash(opening.content || ''), baseline: {}, adoptedAt: this.clock() }, idleSince: null });
          this.event('adopted', { startAt: opening.timestamp, userMessageHash: hash(opening.content || '') });
        } else {
          if (busy(chat)) return this.attention('Existing chat is busy with unexpected work; dispatch refused');
          if (!this.capacityAvailable(chats, stage, chat?.id)) return;
          const conflict = chats.find(c => c.id !== chat?.id && busy(c) && c.participants.some(p => stage.participants.includes(p.name)));
          if (conflict) return this.attention(`Participant busy in another chat: ${conflict.topic}`);
          const prompt = this.files.readPrompt(stage.promptFile);
          if (!prompt.trim()) return this.attention('Empty stage prompt');
          for (const [role, tier] of Object.entries(stage.modelAssignments || {})) await this.adapter.setModel(role, tier);
          // Recheck after model assignment; CLI itself also refuses busy sends.
          if (chat) { chat = await this.adapter.status(chat.id); if (busy(chat)) return this.attention('Chat became active before dispatch'); }
          if (!this.capacityAvailable(await this.adapter.list(), stage, chat?.id)) return;
          if (this.stopRequested) return;
          const preparedAt = this.clock(), dispatchId = this.uuid();
          const wirePrompt = `${prompt.trimEnd()}\n\n[RUNNER_DISPATCH:${stage.id}:${dispatchId}]\n`;
          const baseline = this.files.snapshot(stage.requiredFiles);
          const messageFile = this.files.writePrompt(dispatchId, wirePrompt);
          this.save({ status: 'dispatching', reason: null, chatId: chat?.id || null, idleSince: null, checkpoint: { phase: 'prepared', preparedAt, dispatchId, promptHash: hash(prompt), wireHash: hash(wirePrompt), messageFile, baseline } });
          this.event('dispatch-prepared', { dispatchId, promptHash: hash(prompt) });
          try { await this.adapter.dispatch(stage, chat, messageFile); }
          catch (error) { this.event('dispatch-error', { reason: error.message }); /* Reconcile below; a timeout is not proof no message was sent. */ }
          // Always verify actual persisted user text, even after an apparently successful CLI response.
          continue;
        }
        const cp = this.state.checkpoint;
        const currentUser = latestUser(chat);
        if (!currentUser || hash(currentUser.content || '') !== cp.userHash || Math.abs(currentUser.timestamp - cp.startAt) > 2000) return this.attention('A different user message superseded this stage');
        const fresh = ordered(chat).filter(m => !user(m) && m.timestamp >= cp.startAt);
        const error = this.adapter.problem ? this.adapter.problem(chat, fresh) : null;
        if (error) return this.attention(error);
        const last = fresh.at(-1);
        const marker = last?.participantName === 'moderator' && hasCompletionMarker(last.content, stage.completionMarker);
        if (!busy(chat) && marker) {
          const outputs = this.files.snapshot(stage.requiredFiles);
          const invalid = stage.requiredFiles.filter(p => {
            const output = outputs[p], before = cp.baseline[p];
            if (!output || !output.size) return true;
            return cp.phase !== 'adopted' && !(output.hash !== before?.hash || (output.mtimeMs > (before?.mtimeMs || 0) && output.mtimeMs >= cp.preparedAt));
          });
          if (invalid.length) return this.attention(`Completion marker has missing, empty or unchanged required files: ${invalid.join(', ')}`);
          const completedStages = [...this.state.completedStages, { id: stage.id, chatId: chat.id, at: new Date(this.clock()).toISOString(), marker: stage.completionMarker, messageIdentity: identity(last), files: outputs, adopted: cp.phase === 'adopted' }];
          this.event('stage-completed', { marker: stage.completionMarker, messageIdentity: identity(last), files: outputs });
          const next = this.state.stage + 1;
          this.save({ status: 'ready', stage: next, stageId: this.manifest.stages[next]?.id || null, chatId: null, checkpoint: null, completedStages, idleSince: null });
          continue;
        }
        if (!busy(chat)) {
          const now = this.clock(), recent = fresh.at(-1)?.timestamp || cp.startAt;
          const idleSince = this.state.idleSince ?? now;
          if (now - idleSince >= this.idleGraceMs && now - recent >= this.idleGraceMs) return this.attention('Chat settled idle without a fresh moderator completion marker');
          this.save({ status: 'running', idleSince, observedState: chat.state });
        } else this.save({ status: 'running', idleSince: null, observedState: chat.state });
        return;
      }
      this.attention('Transition guard reached; no further automatic dispatch');
    } catch (error) { this.attention(`Runner/CLI failure: ${error.message}`); }
    finally { this.locked = false; }
  }
  requestStop() { this.stopRequested = true; }
  stop() { this.save({ resumeStatus: this.state.status, status: 'stopped' }); this.event('stopped', { inFlightPreserved: true }); }
}
module.exports = { PipelineRunner, validateManifest, hash, busy };
