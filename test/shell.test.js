const test = require('node:test');
const assert = require('node:assert');
const shell = require('../src/main/shell');

test('on Windows a terminal is cmd, with the command in a variable it expands itself', () => {
  assert.deepStrictEqual(shell.terminal(null, false, { ComSpec: 'C:\\Windows\\system32\\cmd.exe' }, 'win32'), {
    file: 'C:\\Windows\\system32\\cmd.exe',
    args: [],
  });
  assert.deepStrictEqual(shell.terminal('claude', false, {}, 'win32'), { file: 'cmd.exe', args: '/s /k "%SESSION_DECK_RUN%"' });
  assert.deepStrictEqual(shell.terminal('ssh box', true, {}, 'win32'), { file: 'cmd.exe', args: '/s /c "%SESSION_DECK_RUN%"' });
});

test('on macOS and Linux a terminal is the user’s own shell, read as a login shell', () => {
  assert.deepStrictEqual(shell.terminal(null, false, { SHELL: '/usr/bin/fish' }, 'linux'), { file: '/usr/bin/fish', args: ['-l'] });
  assert.strictEqual(shell.terminal(null, false, {}, 'darwin').file, '/bin/zsh');
  assert.strictEqual(shell.terminal(null, false, {}, 'linux').file, '/bin/bash');
  // the command runs, then a prompt in the same folder takes over
  assert.deepStrictEqual(shell.terminal('claude', false, { SHELL: '/bin/zsh' }, 'darwin').args, [
    '-l',
    '-i',
    '-c',
    'eval "$SESSION_DECK_RUN"; exec "$SHELL" -l',
  ]);
  // a server tab ends with its connection
  assert.deepStrictEqual(shell.terminal('ssh box', true, { SHELL: '/bin/zsh' }, 'darwin').args, ['-l', '-i', '-c', 'eval "$SESSION_DECK_RUN"']);
});

test('a script handed to the shell is one argument that the shell leaves alone', () => {
  assert.strictEqual(shell.shellArg('exec $SHELL -l', 'win32'), '"exec $SHELL -l"');
  assert.strictEqual(shell.shellArg("cd 'a b'; exec $SHELL -l", 'linux'), `'cd '\\''a b'\\''; exec $SHELL -l'`);
});

test('stopping a process takes everything it started, children first', () => {
  const ps = ['  1     0', ' 10     1', ' 20    10', ' 21    10', ' 30    20', ' 99     1', ''].join('\n');
  assert.deepStrictEqual(shell.descendants(10, ps), [30, 20, 21]);
  assert.deepStrictEqual(shell.descendants(99, ps), []);
});

test('process lists are read on every system', () => {
  const win = shell.parseProcessList('"claude.exe","4242","Console","1","120,000 K"\r\n"node.exe","77","Console","1","9 K"\r\n', 'win32');
  assert.strictEqual(win.get(4242), 'claude.exe');
  assert.strictEqual(win.get(77), 'node.exe');
  // Claude Code's binary is named after its version; how it was started still says claude
  const nix = shell.parseProcessList(
    [
      '  501 claude --resume 11111111-2222-3333-4444-555555555555',
      '  502 /usr/bin/node /usr/lib/node_modules/@anthropic-ai/claude-code/cli.js',
      '  503 /bin/zsh -l',
      '  504 /Applications/Claude.app/Contents/Helpers/chrome-native-host x',
      '',
    ].join('\n'),
    'darwin',
  );
  assert.strictEqual(nix.get(501), 'claude');
  assert.strictEqual(nix.get(502), 'node cli.js');
  assert.strictEqual(nix.get(503), 'zsh');
  assert.ok(!/claude/.test(nix.get(504)));
  assert.deepStrictEqual(shell.processListCommand('win32'), ['tasklist', ['/FO', 'CSV', '/NH']]);
  assert.deepStrictEqual(shell.processListCommand('linux'), ['ps', ['-A', '-o', 'pid=,args=']]);
});

test('Windows never asks a login shell for its PATH', () => {
  assert.strictEqual(shell.loginPath('win32'), null);
});
