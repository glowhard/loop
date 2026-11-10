// What a session has running in the background, and what each one printed.
//
// Claude Code starts some commands in the background (run_in_background) and
// runs agents of its own; both keep going while the conversation moves on. Each
// leaves a trail in the session's .jsonl: the call that started it, a result
// naming its id and the file its output goes to, and later a <task-notification>
// saying how it ended. Reading that trail gives the phone the same list the PC
// shows, without Loop having to watch any processes itself.
'use strict';
const fs = require('fs');
const fsp = fs.promises;

const STARTED = /^Command (?:running in background with ID|was moved to the background \(ID): ?([A-Za-z0-9_-]+)/;
const OUT_FILE = /Output is being written to: ?(.+?)(?:\.\s|\s*$|\n)/;
const NOTE = /<task-notification>([\s\S]*?)<\/task-notification>/;
// An agent is started with one tool call and then runs on its own. Its result
// is only the receipt; the name it ends under is the agent id inside it.
const LAUNCHED = /Async agent launched successfully[^]*?agentId: ?([A-Za-z0-9_-]+)/;
const tagIn = (s, tag) => {
  const m = new RegExp(`<${tag}>([^]*?)</${tag}>`).exec(s);
  return m ? m[1].trim() : '';
};

const OVER = { completed: 'done', failed: 'failed', stopped: 'stopped', killed: 'stopped', cancelled: 'stopped' };

// One line of the conversation file, as the scan sees it.
function eat(state, r) {
  const at = Date.parse(r.timestamp) || 0;
  const text = typeof r === 'object' ? JSON.stringify(r.content || '') : '';
  // The notice Claude Code queues when a background command ends. It travels
  // as a queued command and again as the message that carries it, so the first
  // one to arrive wins and the rest change nothing.
  const inMessage = r.message && typeof r.message.content === 'string' ? r.message.content : '';
  const carrier = r.content || (r.attachment && r.attachment.prompt) || inMessage || '';
  const note = NOTE.exec(typeof carrier === 'string' ? carrier : '');
  if (note) {
    const id = tagIn(note[1], 'task-id');
    const t = state.byId.get(id);
    const status = OVER[tagIn(note[1], 'status').toLowerCase()] || 'done';
    if (t && t.status === 'running') {
      t.status = status;
      t.ended = at || t.ended;
      t.note = tagIn(note[1], 'summary');
      t.out = t.out || tagIn(note[1], 'output-file');
    }
    return;
  }
  if ((r.type !== 'user' && r.type !== 'assistant') || !r.message) return;
  const c = r.message.content;
  if (!Array.isArray(c)) return;
  for (const p of c) {
    if (p.type === 'tool_use') {
      const i = p.input || {};
      if (p.name === 'Bash' || p.name === 'PowerShell') {
        // Any command may end up in the background: one asked for it, and one
        // the harness moved there to get a message through. Both are named by
        // the call that started them.
        state.waiting.set(p.id, { kind: 'Bash', name: title(i), started: at, status: 'running', asked: i.run_in_background === true });
      } else if (p.name === 'Task' || p.name === 'Agent') {
        const t = { id: p.id, kind: 'Agent', name: i.description || 'Agent', started: at, status: 'running', out: '' };
        state.byId.set(p.id, t);
        state.order.push(t);
      }
      continue;
    }
    if (p.type !== 'tool_result') continue;
    const agent = state.byId.get(p.tool_use_id);
    if (agent && agent.kind === 'Agent' && agent.status === 'running') {
      const off = LAUNCHED.exec(String(flat(p.content)));
      if (off) {
        // It has only just started, and will be named by its agent id when it
        // ends, so it is listed under that from here.
        state.byId.delete(p.tool_use_id);
        agent.id = off[1];
        state.byId.set(agent.id, agent);
        continue;
      }
      agent.status = p.is_error ? 'failed' : 'done';
      agent.ended = at;
      continue;
    }
    // A command that went to the background: its result says so, and names it.
    const held = state.waiting.get(p.tool_use_id);
    const said = String(flat(p.content)).trim();
    const id = STARTED.exec(said);
    const file = OUT_FILE.exec(said);
    // Both notices name the file the output goes to. A command whose own
    // output opens with those words is not one of them.
    if (!id || !file) continue;
    const t = held || { kind: 'Bash', name: 'A command', started: at, status: 'running' };
    delete t.asked;
    state.waiting.delete(p.tool_use_id);
    t.id = id[1];
    t.out = file ? file[1].trim().replace(/\.$/, '') : '';
    if (!state.byId.has(t.id)) {
      state.byId.set(t.id, t);
      state.order.push(t);
    }
  }
}

const flat = (c) => (typeof c === 'string' ? c : Array.isArray(c) ? c.map((x) => (typeof x === 'string' ? x : x.text || '')).join('\n') : '');
const title = (i) =>
  String(i.description || String(i.command || '').split('\n')[0] || 'A command')
    .trim()
    .slice(0, 120);

// Every background task of one session, newest first, running ones first.
function readTasks(text) {
  const state = { byId: new Map(), order: [], waiting: new Map() };
  for (const line of String(text || '').split('\n')) {
    if (!line || line.length > 6e6) continue;
    let r;
    try {
      r = JSON.parse(line);
    } catch {
      continue;
    }
    eat(state, r);
  }
  const live = state.order.filter((t) => t.status === 'running');
  const over = state.order.filter((t) => t.status !== 'running');
  const out = (t) => ({ id: t.id || '', kind: t.kind, name: t.name, status: t.status, started: t.started || 0, ended: t.ended || 0, note: t.note || '', file: t.out || '' });
  return [...live.reverse().map(out), ...over.reverse().map(out)];
}

// The tail of what one task printed. Only the files Claude Code itself named in
// this session's conversation are read: the phone passes the task's id, never a
// path of its own.
async function tailOf(file, bytes = 60 * 1024) {
  try {
    const { size } = await fsp.stat(file);
    const start = Math.max(0, size - bytes);
    const fh = await fsp.open(file, 'r');
    try {
      const buf = Buffer.alloc(size - start);
      await fh.read(buf, 0, buf.length, start);
      return { text: buf.toString('utf8'), cut: start > 0, size };
    } finally {
      await fh.close();
    }
  } catch {
    return { text: '', cut: false, size: 0 };
  }
}

// The id of the background task a result announces, if that is what it is.
const startedIn = (said) => {
  const t = String(said || '').trim();
  const id = STARTED.exec(t);
  return id && OUT_FILE.test(t) ? id[1] : '';
};

// The id and how it ended, from one <task-notification> notice.
function noticeIn(text) {
  const note = NOTE.exec(String(text || ''));
  if (!note) return null;
  return { id: tagIn(note[1], 'task-id'), status: OVER[tagIn(note[1], 'status').toLowerCase()] || 'done' };
}

module.exports = { readTasks, tailOf, startedIn, noticeIn };
