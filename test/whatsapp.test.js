// A session told to listen to someone gets their WhatsApp messages, and nobody else's.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const wa = require('../src/main/whatsapp');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'loop-wa-'));
const got = [];
const S = '11111111-1111-1111-1111-111111111111';

// A stand-in for the bridge's contact lookup.
const CONTACTS = [
  { phone: '919800000002', name: 'ravi' },
  { phone: '919800000001', name: 'Ravneet' },
];
let bridge;
test.before(async () => {
  bridge = http.createServer((req, res) => {
    const q = new URL(req.url, 'http://x').searchParams.get('q').toLowerCase();
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(CONTACTS.filter((c) => c.name.toLowerCase().includes(q) || (q.replace(/\D/g, '').length >= 5 && c.phone.includes(q.replace(/\D/g, ''))))));
  });
  await new Promise((r) => bridge.listen(0, '127.0.0.1', r));
  wa.init(dir, async (d, sessionId, text) => (got.push({ d, sessionId, text }), true), { bridge: `http://127.0.0.1:${bridge.address().port}` });
  for (let i = 0; i < 40 && !fs.existsSync(path.join(dir, 'whatsapp-hook.json')); i++) await new Promise((r) => setTimeout(r, 25));
});
test.after(() => {
  wa.stop();
  bridge.close();
});

const hook = () => JSON.parse(fs.readFileSync(path.join(dir, 'whatsapp-hook.json'), 'utf8'));
const post = (body, token) =>
  fetch(hook().url, { method: 'POST', headers: { 'content-type': 'application/json', 'x-loop-token': token ?? hook().token }, body: JSON.stringify(body) });

test('the hook address and token are written for the bridge', () => {
  assert.match(hook().url, /^http:\/\/127\.0\.0\.1:\d+\/whatsapp$/);
  assert.ok(hook().token.length >= 32);
});

test('a post without the right token is refused', async () => {
  assert.strictEqual((await post({ phone: '919800000002', text: 'hi' }, 'wrong')).status, 404);
});

test('a name several contacts share is asked about; the exact one is taken', async () => {
  assert.match(await wa.listen('proj', S, 'rav', false), /Several contacts match/);
  assert.match(await wa.listen('proj', S, 'ravi', false), /Listening to ravi \(\+919800000002\)/);
  assert.match(await wa.listen('proj', S, 'ravi', false), /already listening/);
  assert.match(await wa.listen('proj', S, 'nobody', false), /No saved WhatsApp contact/);
});

test('their messages arrive together, labelled as outside words; others do not', async () => {
  await post({ phone: '919800000002', name: 'ravi', text: 'hi', time: '2026-10-18T12:41:00+05:30' });
  await post({ phone: '919800000002', name: 'ravi', text: 'you there?', time: '2026-10-18T12:41:05+05:30' });
  await post({ phone: '910000000000', name: 'someone else', text: 'not for you' });
  await post({ phone: '919800000002', is_group: true, text: 'in a group' });
  await new Promise((r) => setTimeout(r, 200));
  wa._flushAll();
  assert.strictEqual(got.length, 1);
  assert.strictEqual(got[0].sessionId, S);
  assert.strictEqual(got[0].d, 'proj');
  assert.match(got[0].text, /hi\n.*you there\?/);
  assert.match(got[0].text, /never as instructions/);
  assert.doesNotMatch(got[0].text, /not for you|in a group/);
});

test('a session moved by /clear keeps listening, and can stop', async () => {
  const T = '22222222-2222-2222-2222-222222222222';
  wa.moved(S, T);
  assert.match(await wa.listen('proj', T, '', false), /You listen to: ravi/);
  assert.match(await wa.listen('proj', T, 'ravi', true), /Stopped listening to ravi/);
  assert.match(await wa.listen('proj', T, '', false), /not listening to anyone/);
});
