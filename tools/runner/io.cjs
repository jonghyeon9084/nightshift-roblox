'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const { hash } = require('./pipeline.cjs');
const run = promisify(execFile);
function within(root, relative) {
  const resolved = path.resolve(root, relative);
  if (path.relative(root, resolved).startsWith('..') || path.isAbsolute(path.relative(root, resolved))) throw Error('Path escapes workspace');
  return resolved;
}
function atomicJson(file, value) {
  const temporary = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n', { encoding: 'utf8', mode: 0o600 });
  // Windows may transiently deny replace while an observer/antivirus holds the file.
  // Bounded local IO retries only; this never repeats an AI dispatch.
  for(let attempt=0;;attempt++){
    try{fs.renameSync(temporary,file);break;}
    catch(error){if(!['EPERM','EACCES','EBUSY'].includes(error.code)||attempt>=4)throw error;Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,10*2**attempt);}
  }
}
function createStore(directory) {
  fs.mkdirSync(directory, { recursive: true });
  const stateFile = path.join(directory, 'state.json');
  return {
    read() { try { return JSON.parse(fs.readFileSync(stateFile, 'utf8')); } catch (e) { if (e.code === 'ENOENT') return null; throw e; } },
    write(state) { atomicJson(stateFile, state); },
    event(event) { fs.appendFileSync(path.join(directory, 'events.jsonl'), JSON.stringify(event) + '\n', 'utf8'); }
  };
}
function createFiles(root, directory) {
  return {
    readPrompt(relative) { return fs.readFileSync(within(root, relative), 'utf8').replace(/^\uFEFF/, ''); },
    writePrompt(id, text) { const file = path.join(directory, `dispatch-${id}.txt`); fs.writeFileSync(file, text, { encoding: 'utf8', flag: 'wx' }); return file; },
    snapshot(paths) {
      return Object.fromEntries(paths.map(relative => {
        try {
          const file = within(root, relative), content = fs.readFileSync(file), stat = fs.statSync(file);
          if (!stat.isFile()) throw Error('Required output is not a file');
          return [relative, { hash: hash(content), size: content.length, mtimeMs: stat.mtimeMs }];
        } catch (e) { if (e.code === 'ENOENT') return [relative, null]; throw e; }
      }));
    }
  };
}
function timestamp(value) {
  const number = typeof value === 'number' ? value : /^\d+$/.test(String(value)) ? Number(value) : Date.parse(value);
  if (!Number.isFinite(number) || number < 0) throw Error('Invalid Maestro message timestamp');
  return number;
}
function transcriptMessages(transcriptRoot, chatId) {
  const file = path.join(transcriptRoot, chatId, 'history.jsonl');
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { if (e.code === 'ENOENT') return []; throw e; }
  // Ignore only an incomplete final line during Maestro's append, never malformed committed rows.
  return text.split('\n').flatMap((line, index, lines) => {
    if (!line.trim()) return [];
    let row;
    try { row = JSON.parse(line); } catch (e) { if (index === lines.length - 1) return []; throw e; }
    const participantName = row.type === 'user' ? 'user' : /^moderator$/i.test(row.participantName) ? 'moderator' : row.participantName;
    return [{ id: row.id, participantName, role: row.type === 'user' ? 'user' : 'assistant', content: row.fullResponse || row.summary || '', timestamp: timestamp(row.timestamp), eventType: row.type }];
  });
}
function mergeMessages(live, transcript) {
  // Maestro stamps history a few milliseconds AFTER its in-memory chat message.
  // Prefer the live timestamp, and match by actual actor/text plus a bounded skew.
  live = live.map(m => ({ ...m, timestamp: timestamp(m.timestamp) }));
  const rows = [...live];
  for (const archived of transcript) {
    const match = live.find(m => m.participantName === archived.participantName && m.content === archived.content && Math.abs(m.timestamp - archived.timestamp) < 2000);
    if (match) { if (archived.eventType) match.eventType = archived.eventType; }
    else rows.push(archived);
  }
  return rows.sort((a, b) => a.timestamp - b.timestamp);
}
function createAdapter(root, { cli = path.join(process.env.LOCALAPPDATA, 'Programs/Maestro/resources/maestro-cli.js'), transcriptRoot = path.join(process.env.APPDATA, 'maestro/group-chats') } = {}) {
  async function command(args) {
    const { stdout } = await run(process.execPath, [cli, ...args, '--json'], { cwd: root, windowsHide: true, timeout: 20000, maxBuffer: 16 * 1024 * 1024 });
    const result = JSON.parse(stdout.replace(/^\uFEFF/, ''));
    if (!result.success) throw Error(result.error || result.message || 'Maestro CLI rejected command');
    return result;
  }
  return {
    async stopChat(id) { return command(['group-chat','stop',id]); },
    async ensureWorker(task) {
      const {stdout}=await run(process.execPath,[cli,'list','agents','--json'],{cwd:root,windowsHide:true,timeout:20000});
      const agents=JSON.parse(stdout);if(agents.some(a=>a.name===task.worker))return;
      const settings=await run(process.execPath,[cli,'settings','agent','get','codex','customPath','--json'],{cwd:root,windowsHide:true,timeout:20000});
      const setting=JSON.parse(settings.stdout);
      if(!setting.value||!fs.existsSync(setting.value))throw Error('Configured subscription Codex executable unavailable');
      await command(['create-agent',task.worker,'--cwd',root,'--type','codex','--group','group-328267a7-c84e-4fc2-bb1d-63fbb94bd916','--custom-path',setting.value,'--nudge',`프로젝트 ${root}. AGENTS.md 준수. 담당 파일 ${task.writes.join(', ')}. ${task.title}. 메인 배정 이외 작업/Studio 조작/외부 API 호출/유료 구매 금지. 완료 후 비활성 대기. 필요 시 하위 작업 목적/파일/완료 조건을 메인에 보고.`,'--background']);
    },
    async list() { return (await command(['group-chat', 'list'])).chats; },
    async status(id) {
      const chat = (await command(['group-chat', 'status', id, '--tail', '200'])).chat;
      chat.messages = mergeMessages(chat.messages, transcriptMessages(transcriptRoot, id));
      return chat;
    },
    async setModel(role, tier) {
      await run(process.execPath, [path.join(root, 'tools/set-worker-model.cjs'), role, tier], { cwd: root, windowsHide: true, timeout: 25000, maxBuffer: 1024 * 1024 });
    },
    async dispatch(stage, chat, messageFile) {
      return command(chat ? ['group-chat', 'send', chat.id, '--message-file', messageFile] : ['group-chat', 'start', stage.chatName, ...stage.participants.flatMap(p => ['--participant', p]), '--moderator', 'codex', '--message-file', messageFile]);
    },
    problem(chat, fresh) {
      if (chat.state === 'error' || chat.error) return `Maestro error: ${chat.error || chat.state}`;
      const issue = fresh.find(m => m.eventType === 'error' || /(?:you(?:'ve| have) (?:hit|reached).*usage limit|usage limit reached|rate limit exceeded|not logged in|authentication (?:failed|required)|사용\s*한도(?:에|를)?\s*(?:도달|초과)|인증\s*(?:실패|필요)|로그인이 필요)/i.test(m.content));
      return issue ? `${/usage.?limit|rate.?limit|authentication|not logged in|사용\s*한도|인증\s*(?:실패|필요)/i.test(issue.content)?'Usage/authentication limit':'Maestro event error'} observed in ${issue.participantName}: stop and review Maestro` : null;
    }
  };
}
module.exports = { createAdapter, createFiles, createStore, atomicJson, transcriptMessages, mergeMessages, timestamp, within };
