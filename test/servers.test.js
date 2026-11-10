const test = require('node:test');
const assert = require('node:assert');
const servers = require('../src/main/servers');

const id = '11111111-2222-3333-4444-555555555555';
const server = { id: 'vps1', name: 'Build box', host: '203.0.113.10', user: 'deploy', port: 2222, key: 'C:\keys\id_ed25519' };
const settings = { flags: '--dangerously-skip-permissions' };

test('a server tab runs Claude inside tmux so it outlives the connection', () => {
  const cmd = servers.tabCommand(server, { kind: 'resume', cwd: '/home/deploy/app', sessionId: id }, settings);
  assert.match(cmd, /ssh(\.exe")? -t /);
  assert.match(cmd, / -p 2222 -i C:\keys\id_ed25519 -o IdentitiesOnly=yes deploy@203\.0\.113\.10 "/);
  assert.ok(cmd.includes("cd '/home/deploy/app' || { echo; echo That folder does not exist on the server.; sleep 4; exit 1; }; "));
  assert.match(cmd, /tmux has-session -t loop-11111111-2222 2>\/dev\/null \|\| tmux -u new-session -d -s loop-11111111-2222/);
  // an error from Claude Code stays on screen instead of vanishing with the session
  assert.ok(
    cmd.includes(`'claude --dangerously-skip-permissions --resume ${id} || { echo; echo Claude Code stopped with an error, shown above.; sleep 20; }'`),
  );
  assert.match(cmd, /else exec claude --dangerously-skip-permissions --resume /);
  assert.strictEqual((cmd.match(/"/g) || []).length % 2, 0); // balanced for cmd.exe
});

test('as root, the flag Claude Code refuses for root is left out, not worked around', () => {
  const cmd = servers.tabCommand({ ...server, id: 'r1', user: 'root' }, { kind: 'resume', cwd: '/root/app', sessionId: id }, settings);
  assert.ok(!cmd.includes('--dangerously-skip-permissions'));
  assert.ok(!cmd.includes('IS_SANDBOX'));
  assert.ok(cmd.includes(`'claude --resume ${id} || {`));
});

test('names and folders cannot smuggle commands onto the server', () => {
  const cmd = servers.tabCommand(server, { kind: 'new', cwd: '/srv/app', sessionId: id, name: 'api"; rm -rf ~ #`$(x)' }, settings);
  assert.ok(cmd.includes('api rm -rf  x'));
  assert.ok(!cmd.includes('api"'));
  assert.ok(!/[`$]\(|"; rm/.test(cmd));
  // a folder with a quote in it is not used at all
  const odd = servers.tabCommand(server, { kind: 'shell', cwd: "/srv/it's" }, settings);
  assert.ok(!odd.includes("it's"));
  assert.throws(() => servers.tabCommand(server, { kind: 'resume', sessionId: 'nope' }, settings));
});

test('plain terminal and sign-in tabs', () => {
  assert.ok(servers.tabCommand(server, { kind: 'shell' }, settings).endsWith('deploy@203.0.113.10'));
  assert.match(servers.tabCommand(server, { kind: 'shell', cwd: '/srv/app' }, settings), /"cd '\/srv\/app' 2>\/dev\/null; exec \$SHELL -l"$/);
  assert.match(servers.tabCommand(server, { kind: 'login' }, settings), /; claude auth login"$/);
  assert.match(servers.tabCommand(server, { kind: 'install' }, settings), /curl -fsSL https:\/\/claude\.ai\/install\.sh \| bash; /);
});

test('only well-formed servers are connected to', () => {
  assert.ok(servers.valid(server));
  assert.ok(servers.valid({ id: 'a1', host: 'buildbox' })); // a name from the SSH config
  for (const bad of [
    { id: 'a1', host: 'x; rm -rf /' },
    { id: 'a1', host: 'h', user: 'a b' },
    { id: 'A!', host: 'h' },
    { id: 'a1', host: 'h', port: 99999 },
    { id: 'a1', host: 'h', key: 'k" -o ProxyCommand=x' },
  ]) {
    assert.ok(!servers.valid(bad), JSON.stringify(bad));
  }
});

test('a report from the server becomes status, running sessions and projects', () => {
  const entry = { server, status: {}, cpu: { idle: 1000, all: 2000 }, live: [], projects: [] };
  servers.digest(entry, [
    '@@SYS 4 8000000 6000000 1600 3000',
    `@@LIVE {"pid":4242,"sessionId":"${id}","cwd":"/home/deploy/app","status":"busy","name":"api"}`,
    '@@TMUX loop-11111111-2222,other,',
    '@@TOOLS 2.1.296 (Claude Code)|yes|deploy|buildbox',
    '@@AUTH {"loggedIn":true,"email":"me@example.com","subscriptionType":"max"}',
    `@@S -home-deploy-app ${id} 1791580000 250000`,
    '@@M {"type":"ai-title","aiTitle":"Old title","sessionId":"x"}',
    '@@M {"type":"custom-title","customTitle":"API work","sessionId":"x"}',
    '@@M {"type":"last-prompt","lastPrompt":"fix the login bug","sessionId":"x"}',
    '@@C "cwd":"/home/deploy/app"',
    '@@S -home-deploy-app not-a-session 1 1',
    '@@SCANNED',
  ]);
  assert.strictEqual(entry.status.connected, true);
  assert.deepStrictEqual(entry.status.load, { cores: 4, memTotal: 8000000 * 1024, memUsed: 2000000 * 1024, cpu: 40 });
  assert.deepStrictEqual(entry.status.auth, { loggedIn: true, email: 'me@example.com', plan: 'max' });
  assert.strictEqual(entry.status.tmux, true);
  assert.strictEqual(entry.live.length, 1);
  assert.strictEqual(entry.live[0].server, 'vps1');
  assert.strictEqual(entry.projects.length, 1);
  const p = entry.projects[0];
  assert.strictEqual(p.path, '/home/deploy/app');
  assert.strictEqual(p.name, 'app');
  assert.strictEqual(p.server, 'vps1');
  assert.match(p.dir, /^[A-Za-z0-9_-]+$/);
  assert.strictEqual(p.sessions.length, 1);
  assert.strictEqual(p.sessions[0].title, 'API work');
  assert.strictEqual(p.sessions[0].lastPrompt, 'fix the login bug');
});

test('a session that has just started shows up before the next full scan', () => {
  const entry = {
    server,
    status: {},
    projects: [{ dir: 'srv-vps1--home-deploy-app', path: '/home/deploy/app', name: 'app', server: 'vps1', mtime: 5, sessions: [{ id, title: 'API work' }] }],
    live: [
      { sessionId: id, cwd: '/home/deploy/app', name: 'api' }, // already listed
      { sessionId: '22222222-2222-3333-4444-555555555555', cwd: '/home/deploy/app', name: 'second', startedAt: 9 },
      { sessionId: '33333333-2222-3333-4444-555555555555', cwd: '/srv/new site', name: '', startedAt: 7 },
    ],
  };
  const list = servers.withLive(entry);
  assert.deepStrictEqual(
    list.map((p) => [p.dir, p.sessions.map((x) => x.title)]),
    [
      ['srv-vps1--home-deploy-app', ['second', 'API work']],
      ['srv-vps1--srv-new-site', ['New session']],
    ],
  );
  assert.strictEqual(entry.projects[0].sessions.length, 1); // the scanned list itself is left alone
});

test('only git addresses are cloned, and nothing else reaches the server shell', async () => {
  for (const url of ['', 'rm -rf /', 'https://x/y.git; reboot', "https://x/'y", 'file:///etc', 'https://github.com/a/..']) {
    const r = await servers.clone('nope', '/srv', url);
    assert.strictEqual(r.error, 'That does not look like a git address.', url);
  }
  for (const url of ['https://github.com/me/app.git', 'git@github.com:me/app.git', 'ssh://git@host/me/app'])
    assert.strictEqual((await servers.clone('nope', '/srv', url)).error, 'That server or folder cannot be used.', url);
});

test('sessions can run as another user than the one that logs in', () => {
  const as = { ...server, id: 'r2', user: 'root', runAs: 'worker' };
  const cmd = servers.tabCommand(as, { kind: 'new', cwd: '/home/worker/app', sessionId: id, name: "it's" }, settings);
  // the same script three ways: already that user, through sudo, through su
  assert.match(cmd, /"if \[ \$\(id -un\) = worker \]; then export PATH=/);
  assert.match(cmd, /; elif command -v sudo >\/dev\/null 2>&1; then exec sudo -n -H -u worker sh -c 'export PATH=/);
  assert.match(cmd, /; else exec su -s \/bin\/sh worker -c 'export PATH=.*; fi"$/);
  // a normal user keeps the flag that root is refused
  assert.ok(cmd.includes('--dangerously-skip-permissions'));
  assert.ok(!servers.isRoot(as));
  assert.ok(servers.isRoot({ ...as, runAs: 'root' }));
  assert.strictEqual((cmd.match(/"/g) || []).length % 2, 0);
  assert.ok(!/[%!]/.test(cmd));
  assert.match(servers.tabCommand(as, { kind: 'shell' }, settings), /sudo -n -H -u worker sh -c 'cd; exec \$SHELL -l'/);
  assert.match(servers.tabCommand(as, { kind: 'login' }, settings), /sudo -n -H -u worker sh -c 'export PATH=[^']*; claude auth login'/);
  assert.strictEqual(servers.asUser(server, 'echo hi'), 'echo hi');
  // the user name is never free text
  for (const runAs of ['a b', 'x;reboot', "o'k", '-u', 'Root']) assert.ok(!servers.valid({ ...server, runAs }), runAs);
});

test('adding a user takes a plain name only', async () => {
  for (const name of ['root', 'a b', 'x; rm -rf /', '', '-m']) assert.strictEqual((await servers.addUser('nope', name)).ok, false, name);
});
