// The Remote Control switch, by session.
//
// Loop can only work it on a session it runs itself. The bug this covers: the
// switch said "Remote Control is on" for a session running in the Claude
// desktop app, where Loop cannot reach it, and nothing ever connected.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'renderer', 'app.js'), 'utf8');
const cut = (name) => {
  let from = src.indexOf(`function ${name}(`);
  if (src.slice(from - 6, from) === 'async ') from -= 6;
  return src.slice(from, src.indexOf('\n}\n', from) + 2);
};

const dir = 'C--remote-test';
const id = '11111111-1111-4111-8111-111111111111';

// `live` is what the registry says about the session; `tab` whether one is open
// here; `pointer` whether claude.ai has a live copy of it.
function runner({ live = null, tab = null, pointer = false, toggled = 'Remote Control is on.' } = {}) {
  const calls = { stopped: 0, started: 0, toggled: 0, saved: 0 };
  const config = { sessionRemote: {} };
  const S = { config, live: new Map(live ? [[id, live]] : []) };
  const deck = {
    directStop: async () => (calls.stopped++, S.live.delete(id), true),
    directSend: async (o) => (calls.started++, (calls.lastSend = o), null),
    remotePointer: async () => pointer,
  };
  const scope = {
    S,
    deck,
    tabFor: () => tab,
    sessionTitle: () => 'Dev one',
    whereItRuns: () => 'the Claude desktop app',
    remoteOn: (x) => Boolean(config.sessionRemote[x]),
    toggleRemote: async () => (calls.toggled++, toggled),
    accountFor: () => 'default',
    save: () => calls.saved++,
    renderList: () => {},
    renderTabs: () => {},
    sleep: () => Promise.resolve(),
    waitFor: async (check) => Boolean(await check()),
  };
  const keys = Object.keys(scope);
  const setRemote = new Function(...keys, [cut('setRemote'), 'return setRemote;'].join('\n'))(...keys.map((k) => scope[k]));
  return { setRemote, calls, config, S };
}

const project = { dir, path: 'C:/remote-test' };
const session = { id, title: 'Dev one' };

test('a session running in the Claude desktop app is not switched, and says so', async () => {
  const r = runner({ live: { status: 'idle', entrypoint: 'claude-desktop' } });
  const out = await r.setRemote(project, session, true);
  assert.strictEqual(out.ok, false);
  assert.match(out.text, /running in the Claude desktop app, which owns its Remote Control switch/);
  assert.match(out.text, /open the session here first/);
  // Nothing was stored: the switch never claims to be on when it is not.
  assert.deepStrictEqual(r.config.sessionRemote, {});
  assert.strictEqual(r.calls.started, 0);
});

test('one Loop runs in the background is started again, connected', async () => {
  const r = runner({ live: { status: 'idle', bg: true }, pointer: 'cse_abcdefgh' });
  const out = await r.setRemote(project, session, true);
  assert.strictEqual(out.ok, true);
  assert.match(out.text, /Remote Control is on for Dev one/);
  assert.strictEqual(r.config.sessionRemote[id], true);
  // It let go of the old runner and started a fresh one, which carries the switch.
  assert.strictEqual(r.calls.stopped, 1);
  assert.strictEqual(r.calls.started, 1);
  assert.strictEqual(r.calls.lastSend.warm, true);
});

test('a background session that will not connect leaves the switch off', async () => {
  const r = runner({ live: { status: 'idle', bg: true }, pointer: false });
  const out = await r.setRemote(project, session, true);
  assert.strictEqual(out.ok, false);
  assert.match(out.text, /did not connect/);
  assert.strictEqual(r.config.sessionRemote[id], undefined);
});

test('a busy session is left alone until it is idle', async () => {
  const r = runner({ live: { status: 'busy', bg: true } });
  const out = await r.setRemote(project, session, true);
  assert.strictEqual(out.ok, false);
  assert.match(out.text, /is working\. Use the switch when it is idle/);
  assert.strictEqual(r.calls.stopped, 0);
});

test('a session that is not running keeps the switch for its next start', async () => {
  const r = runner();
  const on = await r.setRemote(project, session, true);
  assert.strictEqual(on.ok, true);
  assert.match(on.text, /connects to Remote Control as soon as Loop starts it/);
  assert.strictEqual(r.config.sessionRemote[id], true);

  const off = await r.setRemote(project, session, false);
  assert.strictEqual(off.ok, true);
  assert.match(off.text, /Remote Control is off/);
  assert.strictEqual(r.config.sessionRemote[id], undefined);
});

test('with a terminal open here, the terminal switch does the work', async () => {
  const r = runner({ tab: { id: 't1', exited: false, sessionId: id } });
  const out = await r.setRemote(project, session, true);
  assert.strictEqual(out.ok, true);
  assert.strictEqual(r.calls.toggled, 1);
  assert.strictEqual(out.text, 'Remote Control is on.');
});
