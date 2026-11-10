const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const memory = require('../src/main/memory');

const DIR = 'T--test-project';
const ME = '11111111-2222-3333-4444-555555555555';
const MATE = '99999999-2222-3333-4444-555555555555';
let tmp;
let url;
let seq = 0;

async function rpc(method, params, to = url) {
  const res = await fetch(to, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: ++seq, method, params }),
  });
  return res.status === 200 ? (await res.json()).result : { status: res.status };
}
const call = async (name, args = {}, to = url) => (await rpc('tools/call', { name, arguments: args }, to)).content[0].text;

test.before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'deck-test-'));
  await memory.init(tmp);
  memory.setProfileLookup((id) => ({ role: id === ME ? 'Tester' : '' }));
  url = JSON.parse(fs.readFileSync(memory.configFor(DIR, ME), 'utf8')).mcpServers['team-memory'].url;
});
test.after(() => {
  memory.stop();
  fs.rmSync(tmp, { recursive: true, force: true });
});

test('initialize describes memory, the role and the tools', async () => {
  const init = await rpc('initialize', { protocolVersion: '2025-03-26' });
  assert.match(init.instructions, /Your role on this team: Tester/);
  assert.match(init.instructions, /Memory is empty so far/);
  const names = (await rpc('tools/list')).tools.map((t) => t.name);
  for (const n of ['memory_search', 'memory_save', 'team_list', 'task_add', 'task_update', 'task_list']) assert.ok(names.includes(n), n);
});

test('a wrong secret or a malformed session id is refused', async () => {
  assert.strictEqual((await rpc('tools/list', {}, url.replace(/mcp\/[a-f0-9]+/, 'mcp/deadbeef'))).status, 404);
  assert.strictEqual((await rpc('tools/list', {}, url.replace(ME, 'not-a-session'))).status, 404);
});

test('save, search within a budget, read and delete', async () => {
  const saved = await call('memory_save', {
    title: 'Staging deploy',
    content: 'Deploy to staging with git pull on the box.\n\n' + 'Filler paragraph. '.repeat(400),
    scope: 'project',
    tags: ['deploy'],
  });
  const id = /\[id: ([^\]]+)\]/.exec(saved)[1];
  const found = await call('memory_search', { query: 'how to deploy staging', max_tokens: 300 });
  assert.match(found, /Staging deploy/);
  assert.ok(found.length < 300 * 3.7 + 400, 'reply stays near the token budget');
  assert.match(await call('memory_read', { id }), /git pull on the box/);
  assert.match((await rpc('initialize', {})).instructions, /"Staging deploy"/);
  assert.match(await call('memory_delete', { id }), /Deleted/);
  assert.match(await call('memory_search', { query: 'staging deploy' }), /No notes match/);
});

test("a member cannot change a teammate's knowledge base", async () => {
  const mateUrl = JSON.parse(fs.readFileSync(memory.configFor(DIR, MATE), 'utf8')).mcpServers['team-memory'].url;
  const saved = await call('memory_save', { title: 'Mate secret sauce', content: 'Only the teammate edits this.', scope: 'mine' }, mateUrl);
  const id = /\[id: ([^\]]+)\]/.exec(saved)[1];
  assert.match(await call('memory_search', { query: 'secret sauce', scope: 'team' }), /Mate secret sauce/);
  assert.match(await call('memory_delete', { id }), /read-only for you/);
  assert.match(await call('memory_save', { id, title: 'x', content: 'y', scope: 'mine' }), /read-only for you/);
  assert.match(await call('memory_read', { id }), /Only the teammate edits this/);
});

test('task board: add, take, finish', async () => {
  assert.match(await call('task_add', { title: 'Write the importer', assignee: 'Ops AI' }), /Added T1/);
  await call('task_add', { title: 'Review the importer' });
  assert.match(await call('task_update', { id: 't1', status: 'doing', note: 'Half way' }), /\[doing\][\s\S]*Half way/);
  assert.match(await call('task_list', { assignee: 'Ops AI' }), /T1 \[doing\] Write the importer/);
  await call('task_update', { id: 'T1', status: 'done' });
  const open = await call('task_list');
  assert.ok(!open.includes('T1 ') && open.includes('T2 '));
  assert.match(await call('task_update', { id: 'T9', status: 'done' }), /No task has the id/);
  assert.strictEqual((await memory.taskList(DIR)).length, 2);
});

test('memory folder can be moved and keeps its notes', async () => {
  await memory.saveNote({ dir: DIR, scope: 'project', title: 'Portable note', body: 'Travels with the folder.', tags: [], author: 'you' });
  const dest = path.join(tmp, 'elsewhere', 'mem');
  const r = await memory.setRoot(dest);
  assert.ok(r.ok, r.message);
  assert.ok(fs.existsSync(path.join(dest, 'session-deck-memory.json')));
  assert.ok(!fs.existsSync(path.join(tmp, 'memory')));
  assert.ok((await memory.list(DIR, 'project')).notes.some((n) => n.title === 'Portable note'));
  assert.strictEqual((await memory.taskList(DIR)).length, 2);
});
