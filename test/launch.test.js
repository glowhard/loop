const test = require('node:test');
const assert = require('node:assert');
const { buildCommand } = require('../src/main/ptys');

const id = '11111111-2222-3333-4444-555555555555';
const settings = { claudeCmd: 'claude', flags: '--dangerously-skip-permissions' };

test('a session with the switch off starts with no Remote Control option', () => {
  const cmd = buildCommand({ kind: 'resume', sessionId: id, remote: false }, settings, null);
  assert.strictEqual(cmd, `claude --dangerously-skip-permissions --resume ${id}`);
});

test('a session with the switch on starts connected, named after its tab', () => {
  const cmd = buildCommand({ kind: 'resume', sessionId: id, remote: true, title: 'Backend "dev" & co' }, settings, null);
  assert.strictEqual(cmd, `claude --dangerously-skip-permissions --remote-control "Backend dev  co" --resume ${id}`);
});

test('plain terminals and sign-in tabs take no session options', () => {
  assert.strictEqual(buildCommand({ kind: 'shell' }, settings, null), null);
  assert.strictEqual(buildCommand({ kind: 'login', remote: true }, settings, null), 'claude auth login');
  assert.throws(() => buildCommand({ kind: 'resume', sessionId: 'nope' }, settings));
});

test('on macOS and Linux nothing a shell would expand inside double quotes gets through', () => {
  const o = { kind: 'new', sessionId: id, remote: true, name: 'api $(rm -rf ~) `x` \\', title: 'a $HOME b', teamBrief: 'You are $(whoami)' };
  const cmd = buildCommand(o, settings, null, 'darwin');
  assert.ok(!/[$`\\]/.test(cmd), cmd);
  assert.ok(cmd.includes('--remote-control "a HOME b"'));
  // on Windows they mean nothing to cmd and stay as written
  assert.ok(buildCommand(o, settings, null, 'win32').includes('--remote-control "a $HOME b"'));
});
