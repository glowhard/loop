const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sd-remote-'));
process.env.CLAUDE_CONFIG_DIR = root; // read when the modules load
const remote = require('../src/main/remote');

const id = '11111111-2222-3333-4444-555555555555';
const file = path.join(root, 'projects', 'D--work', id + '.jsonl');
const marker = (bridge) => JSON.stringify({ type: 'bridge-session', sessionId: id, bridgeSessionId: bridge, lastSequenceNum: 0 });

test('finds the remote copy a session points at, and closes the marker like Claude Code does', async () => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, '{"type":"user"}\n' + marker('cse_01AAAAAAAAAAAAAAAA') + '\n{"type":"assistant"}'); // no final newline
  assert.strictEqual(await remote.pointer('D--work', id), 'cse_01AAAAAAAAAAAAAAAA');
  await remote.closePointer('D--work', id);
  assert.strictEqual(await remote.pointer('D--work', id), null);
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  assert.strictEqual(lines[2], '{"type":"assistant"}'); // earlier history untouched
  assert.strictEqual(lines[3], marker(''));
  assert.strictEqual(lines[4], '');
});

test('a session that never had Remote Control has nothing to clean', async () => {
  fs.writeFileSync(file, '{"type":"user"}\n');
  assert.strictEqual(await remote.pointer('D--work', id), null);
  assert.strictEqual(await remote.forget('D--work', id, ['default']), null);
  assert.strictEqual(fs.readFileSync(file, 'utf8'), '{"type":"user"}\n');
});

test('bad names never reach the disk or the network', async () => {
  assert.strictEqual(await remote.pointer('../x', id), null);
  assert.strictEqual(await remote.pointer('D--work', 'nope'), null);
  assert.deepStrictEqual(await remote.deleteCopy('https://evil.example/x', ['default']), { ok: false, reason: 'no remote copy' });
  assert.strictEqual(remote.link('cse_01AAAAAAAAAAAAAAAA'), 'https://claude.ai/code/session_01AAAAAAAAAAAAAAAA');
});
