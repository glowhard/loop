// The relay: what it lets through, and what it does not.
//
// It is started here as a real process against a real bridge-shaped server, so
// the checks are about behaviour rather than about the shape of the code.
const test = require('node:test');
const assert = require('node:assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { WebSocketServer } = require('ws');
const WebSocket = require('ws');

const sha = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');
const TOKEN = crypto.randomBytes(32).toString('base64url');
const KEY = crypto.randomBytes(32).toString('base64url');
const WRONG = crypto.randomBytes(32).toString('base64url');

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

// A port nobody else is on, rather than a guess.
const freePort = () =>
  new Promise((res) => {
    const s = require('net').createServer();
    s.listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => res(port));
    });
  });

// A stand-in for Loop's bridge: it says hello and echoes what it is told.
function fakeBridge() {
  const wss = new WebSocketServer({ port: 0 });
  wss.on('connection', (ws) => {
    opened.push(ws);
    ws.send('hello from the PC');
    ws.on('message', (d) => ws.send(`echo:${d}`));
  });
  return wss;
}

// Everything opened here, so the test can put it all down afterwards.
const opened = [];

function connect(url, headers) {
  return new Promise((res) => {
    const ws = new WebSocket(url, { headers });
    opened.push(ws);
    const done = (r) => res(r);
    ws.on('open', () => done({ ok: true, ws }));
    ws.on('unexpected-response', (_q, r) => done({ ok: false, status: r.statusCode }));
    ws.on('error', (e) => done({ ok: false, error: e.message }));
    setTimeout(() => done({ ok: false, error: 'timed out' }), 8000);
  });
}

const next = (ws) => new Promise((res) => ws.once('message', (d) => res(d.toString())));

test('the relay joins a browser to its PC, and refuses everyone else', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-'));
  const conf = path.join(dir, 'relay.json');
  fs.writeFileSync(conf, JSON.stringify({ machines: [sha(TOKEN)] }));
  const port = await freePort();
  const relay = spawn(process.execPath, [path.join(__dirname, '..', 'relay', 'relay.js')], {
    env: { ...process.env, PORT: String(port), LOOP_RELAY_CONFIG: conf },
    stdio: 'ignore',
  });
  const bridge = fakeBridge();
  t.after(() => {
    for (const w of opened.splice(0)) w.terminate();
    relay.kill();
    bridge.close();
    fs.rmSync(dir, { recursive: true, force: true });
  });
  await wait(600);
  const at = `ws://127.0.0.1:${port}`;

  // ---- the PC, with the wrong token and then the right one
  const refused = await connect(`${at}/pc`, { authorization: `Bearer ${WRONG}` });
  assert.equal(refused.ok, false, 'an unknown machine is refused');
  assert.equal(refused.status, 401);

  const pc = await connect(`${at}/pc?name=Desk`, { authorization: `Bearer ${TOKEN}` });
  assert.ok(pc.ok, 'the known machine is let in');
  pc.ws.send(`key ${sha(KEY)}`); // what a browser must present
  await wait(200);

  // ---- a browser with no key, a wrong key, and the right one
  const none = await connect(`${at}/ws`);
  assert.equal(none.ok, false, 'no key, no pipe');
  const wrong = await connect(`${at}/ws?k=${WRONG}`);
  assert.equal(wrong.ok, false, 'a wrong key is refused');
  assert.equal(wrong.status, 401);

  // the PC passes each browser to its own bridge
  const pipes = new Map();
  pc.ws.on('message', (d) => {
    const text = d.toString();
    const nl = text.indexOf('\n');
    const id = Number(nl < 0 ? text : text.slice(0, nl));
    if (nl < 0) return pipes.get(id)?.close();
    if (!pipes.has(id)) {
      const local = new WebSocket(`ws://127.0.0.1:${bridge.address().port}`);
      opened.push(local);
      local.waiting = [];
      local.on('open', () => local.waiting.splice(0).forEach((m) => local.send(m)));
      local.on('message', (m) => pc.ws.send(`${id}\n${m}`));
      pipes.set(id, local);
    }
    const body = text.slice(nl + 1);
    if (!body) return;
    const local = pipes.get(id);
    if (local.readyState === WebSocket.OPEN) local.send(body);
    else local.waiting.push(body);
  });

  const good = await connect(`${at}/ws?k=${KEY}`);
  assert.ok(good.ok, 'the right key opens a pipe');
  assert.equal(await next(good.ws), 'hello from the PC', 'the PC speaks for itself');
  good.ws.send('are you there');
  assert.equal(await next(good.ws), 'echo:are you there', 'and hears what is said');

  // ---- two browsers at once are kept apart
  const second = await connect(`${at}/ws?k=${KEY}`);
  assert.ok(second.ok);
  assert.equal(await next(second.ws), 'hello from the PC');
  second.ws.send('mine');
  good.ws.send('yours');
  const [a, b] = await Promise.all([next(second.ws), next(good.ws)]);
  assert.equal(a, 'echo:mine');
  assert.equal(b, 'echo:yours', 'one browser never hears another');

  // ---- the PC going away takes the browsers with it
  pc.ws.close();
  await wait(400);
  assert.equal(good.ws.readyState, WebSocket.CLOSED, 'no PC, no pipe');

  // and with no PC there, a browser with the right key gets nowhere
  const orphan = await connect(`${at}/ws?k=${KEY}`);
  assert.equal(orphan.ok, false, 'the key alone is not a way in');
});

test('wrong keys from one address stop being answered', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-'));
  const conf = path.join(dir, 'relay.json');
  fs.writeFileSync(conf, JSON.stringify({ machines: [sha(TOKEN)] }));
  const port = await freePort();
  const relay = spawn(process.execPath, [path.join(__dirname, '..', 'relay', 'relay.js')], {
    env: { ...process.env, PORT: String(port), LOOP_RELAY_CONFIG: conf },
    stdio: 'ignore',
  });
  t.after(() => {
    for (const w of opened.splice(0)) w.terminate();
    relay.kill();
    fs.rmSync(dir, { recursive: true, force: true });
  });
  await wait(600);
  let last = 0;
  for (let i = 0; i < 12; i++) {
    const r = await connect(`ws://127.0.0.1:${port}/ws?k=${crypto.randomBytes(24).toString('base64url')}`);
    last = r.status || 0;
  }
  assert.equal(last, 429, 'guessing is shut out, not answered forever');
});
