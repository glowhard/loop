const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const accounts = require('../src/main/accounts');

function setup() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sd-acct-'));
  const mainDir = path.join(root, 'claude');
  const mainJson = path.join(root, 'claude.json');
  fs.mkdirSync(path.join(mainDir, 'projects', 'D--work'), { recursive: true });
  fs.mkdirSync(path.join(mainDir, 'sessions'));
  fs.writeFileSync(path.join(mainDir, 'projects', 'D--work', 'a.jsonl'), 'history');
  fs.writeFileSync(path.join(mainDir, 'settings.json'), '{"theme":"dark"}');
  fs.writeFileSync(path.join(mainDir, '.credentials.json'), 'main login');
  fs.writeFileSync(
    mainJson,
    JSON.stringify({
      hasCompletedOnboarding: true,
      oauthAccount: { emailAddress: 'main@example.com' },
      mcpServers: { x: { command: 'x' } },
      projects: { 'D:/work': { trusted: true } },
    }),
  );
  accounts.init(path.join(root, 'userData'), { mainDir, mainJson });
  return { root, mainDir };
}

test('a new account shares history and settings but not the login', () => {
  const { root, mainDir } = setup();
  const dir = accounts.prepare('work1');
  assert.ok(fs.lstatSync(path.join(dir, 'projects')).isSymbolicLink());
  assert.strictEqual(fs.readFileSync(path.join(dir, 'projects', 'D--work', 'a.jsonl'), 'utf8'), 'history');
  assert.strictEqual(fs.readFileSync(path.join(dir, 'settings.json'), 'utf8'), '{"theme":"dark"}');
  assert.ok(!fs.existsSync(path.join(dir, '.credentials.json')));
  const own = JSON.parse(fs.readFileSync(path.join(dir, '.claude.json'), 'utf8'));
  assert.strictEqual(own.hasCompletedOnboarding, true);
  assert.deepStrictEqual(own.mcpServers, { x: { command: 'x' } });
  assert.ok(own.projects['D:/work']);
  assert.strictEqual(own.oauthAccount, undefined);

  // what the account writes into a shared folder lands in the main one
  fs.writeFileSync(path.join(dir, 'projects', 'D--work', 'b.jsonl'), 'more');
  assert.ok(fs.existsSync(path.join(mainDir, 'projects', 'D--work', 'b.jsonl')));
  assert.deepStrictEqual(accounts.envFor('work1'), { CLAUDE_CONFIG_DIR: dir });
  assert.deepStrictEqual(accounts.envFor('default'), {});
  fs.rmSync(root, { recursive: true, force: true });
});

test('preparing again keeps the account own login details and picks up changed settings', () => {
  const { root, mainDir } = setup();
  const dir = accounts.prepare('work1');
  const file = path.join(dir, '.claude.json');
  fs.writeFileSync(file, JSON.stringify({ ...JSON.parse(fs.readFileSync(file, 'utf8')), oauthAccount: { emailAddress: 'work@example.com' } }));
  fs.writeFileSync(path.join(dir, '.credentials.json'), 'work login');
  fs.writeFileSync(path.join(mainDir, 'settings.json'), '{"theme":"light"}');
  accounts.prepare('work1');
  assert.strictEqual(JSON.parse(fs.readFileSync(file, 'utf8')).oauthAccount.emailAddress, 'work@example.com');
  assert.strictEqual(fs.readFileSync(path.join(dir, '.credentials.json'), 'utf8'), 'work login');
  assert.strictEqual(fs.readFileSync(path.join(dir, 'settings.json'), 'utf8'), '{"theme":"light"}');
  fs.rmSync(root, { recursive: true, force: true });
});

test("one login's cloud rules stay its own: settings and servers", () => {
  const { root, mainDir } = setup();
  const mainJson = path.join(root, 'claude.json');
  // The main login is a work account kept off the cloud.
  fs.writeFileSync(
    path.join(mainDir, 'settings.json'),
    JSON.stringify({ theme: 'dark', remoteControlAtStartup: false, env: { MCP_TIMEOUT: '60000', ENABLE_CLAUDEAI_MCP_SERVERS: 'false' } }),
  );
  fs.writeFileSync(
    mainJson,
    JSON.stringify({ mcpServers: { tool: { type: 'stdio', command: 'x' }, host: { type: 'http', url: 'http://127.0.0.1:7801/host' } } }),
  );
  const dir = accounts.prepare('acc3');
  // The other account added a cloud server of its own and chose Remote Control.
  const ownJson = path.join(dir, '.claude.json');
  const own = JSON.parse(fs.readFileSync(ownJson, 'utf8'));
  own.mcpServers.cloud = { type: 'http', url: 'https://mcp.example.com/mcp' };
  fs.writeFileSync(ownJson, JSON.stringify(own));
  const ownSettings = JSON.parse(fs.readFileSync(path.join(dir, 'settings.json'), 'utf8'));
  ownSettings.remoteControlAtStartup = true;
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify(ownSettings));

  accounts.prepare('acc3');
  const s = JSON.parse(fs.readFileSync(path.join(dir, 'settings.json'), 'utf8'));
  assert.strictEqual(s.theme, 'dark', 'ordinary settings still follow the main account');
  assert.strictEqual(s.env.MCP_TIMEOUT, '60000');
  assert.strictEqual(s.env.ENABLE_CLAUDEAI_MCP_SERVERS, undefined, "the main login's connector rule is not this one's");
  assert.strictEqual(s.remoteControlAtStartup, true, 'its own Remote Control choice is kept');
  const servers = JSON.parse(fs.readFileSync(ownJson, 'utf8')).mcpServers;
  assert.deepStrictEqual(Object.keys(servers).sort(), ['cloud', 'host', 'tool'], 'local servers shared, its cloud server kept');
});

test('removing an account never touches the shared history', () => {
  const { root, mainDir } = setup();
  const dir = accounts.prepare('work1');
  fs.writeFileSync(path.join(dir, '.credentials.json'), 'work login');
  accounts.remove('work1');
  assert.ok(!fs.existsSync(dir));
  assert.strictEqual(fs.readFileSync(path.join(mainDir, 'projects', 'D--work', 'a.jsonl'), 'utf8'), 'history');
  assert.strictEqual(fs.readFileSync(path.join(mainDir, '.credentials.json'), 'utf8'), 'main login');
  assert.ok(fs.existsSync(path.join(mainDir, 'sessions')));
  fs.rmSync(root, { recursive: true, force: true });
});

test('account ids that could reach outside the accounts folder are refused', () => {
  setup();
  for (const bad of ['..', '../x', 'a/b', 'A1', '', 'default']) assert.throws(() => accounts.dirFor(bad));
});

test('connector sign-ins reach every account; the Claude login never moves', () => {
  const { root, mainDir } = setup();
  const dir = accounts.prepare('work1');
  const main = path.join(mainDir, '.credentials.json');
  const work = path.join(dir, '.credentials.json');
  fs.writeFileSync(
    main,
    JSON.stringify({
      claudeAiOauth: { accessToken: 'main-login' },
      mcpOAuth: { 'github|a1': { accessToken: 'gh-old', expiresAt: 100 }, 'figma|b2': { accessToken: 'figma' }, 'slack|c3': { accessToken: '' } },
    }),
  );
  fs.writeFileSync(
    work,
    JSON.stringify({
      claudeAiOauth: { accessToken: 'work-login' },
      mcpOAuth: { 'github|a1': { accessToken: 'gh-new', expiresAt: 200 }, 'slack|c3': { accessToken: 'slack' } },
    }),
  );
  accounts.syncConnectors();
  const m = JSON.parse(fs.readFileSync(main, 'utf8'));
  const w = JSON.parse(fs.readFileSync(work, 'utf8'));
  assert.strictEqual(m.claudeAiOauth.accessToken, 'main-login');
  assert.strictEqual(w.claudeAiOauth.accessToken, 'work-login');
  assert.deepStrictEqual(m.mcpOAuth, w.mcpOAuth);
  assert.strictEqual(m.mcpOAuth['github|a1'].accessToken, 'gh-new'); // refreshed under Work, now everywhere
  assert.strictEqual(w.mcpOAuth['figma|b2'].accessToken, 'figma'); // signed in under Main, now under Work
  assert.strictEqual(m.mcpOAuth['slack|c3'].accessToken, 'slack'); // a real sign-in beats an empty one
  assert.strictEqual(accounts.syncConnectors(), 0); // settled: nothing left to write
  accounts.stopWatching();
  fs.rmSync(root, { recursive: true, force: true });
});

test('an account that is not signed in is left without a credentials file', () => {
  const { root, mainDir } = setup();
  const dir = accounts.prepare('work1');
  fs.writeFileSync(
    path.join(mainDir, '.credentials.json'),
    JSON.stringify({ claudeAiOauth: { accessToken: 'main-login' }, mcpOAuth: { 'x|1': { accessToken: 't' } } }),
  );
  accounts.syncConnectors();
  assert.ok(!fs.existsSync(path.join(dir, '.credentials.json')));
  accounts.stopWatching();
  fs.rmSync(root, { recursive: true, force: true });
});

test('connectors that belong to a claude.ai account are not shared', () => {
  const { root, mainDir } = setup();
  const dir = accounts.prepare('work1');
  const main = path.join(mainDir, '.credentials.json');
  const work = path.join(dir, '.credentials.json');
  fs.writeFileSync(
    main,
    JSON.stringify({
      claudeAiOauth: { accessToken: 'main-login' },
      mcpOAuth: { 'claude.ai Notion|n1': { accessToken: 'main-notion' }, 'github|a1': { accessToken: 'gh' } },
    }),
  );
  fs.writeFileSync(work, JSON.stringify({ claudeAiOauth: { accessToken: 'work-login' }, mcpOAuth: { 'claude.ai Gmail|g1': { accessToken: 'work-gmail' } } }));
  accounts.syncConnectors();
  const m = JSON.parse(fs.readFileSync(main, 'utf8')).mcpOAuth;
  const w = JSON.parse(fs.readFileSync(work, 'utf8')).mcpOAuth;
  assert.deepStrictEqual(Object.keys(m).sort(), ['claude.ai Notion|n1', 'github|a1']);
  assert.deepStrictEqual(Object.keys(w).sort(), ['claude.ai Gmail|g1', 'github|a1']);
  assert.strictEqual(accounts.syncConnectors(), 0);
  accounts.stopWatching();
  fs.rmSync(root, { recursive: true, force: true });
});
