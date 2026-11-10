// Extra Claude accounts. Each one is its own Claude Code config folder (what
// CLAUDE_CONFIG_DIR points at), so it holds its own login and nothing else of
// note: session history, the live registry, plugins and skills are links back
// to the main folder, and settings are copied from it on every launch. A
// session can therefore be resumed under any account.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { exec } = require('child_process');
const { CLAUDE_DIR } = require('./scanner');

const ID_RE = /^[a-z0-9]{1,24}$/;
const SHARED_DIRS = [
  'projects',
  'sessions',
  'file-history',
  'tasks',
  'todos',
  'plans',
  'session-env',
  'shell-snapshots',
  'paste-cache',
  'plugins',
  'skills',
  'agents',
  'commands',
];
const SHARED_FILES = ['settings.json', 'settings.local.json', 'CLAUDE.md', 'keybindings.json'];
// Taken from the main account once, so a new account does not replay first-run screens.
const SEED_KEYS = ['hasCompletedOnboarding', 'lastOnboardingVersion', 'installMethod', 'autoUpdates', 'autoUpdatesProtectedForNative', 'theme'];

let base = null;
let mainDir = CLAUDE_DIR;
let mainJson = process.env.CLAUDE_CONFIG_DIR ? path.join(CLAUDE_DIR, '.claude.json') : path.join(os.homedir(), '.claude.json');

function init(userData, overrides = {}) {
  base = path.join(userData, 'accounts');
  if (overrides.mainDir) mainDir = overrides.mainDir;
  if (overrides.mainJson) mainJson = overrides.mainJson;
}

const isMain = (id) => !id || id === 'default';

function dirFor(id) {
  if (!ID_RE.test(String(id)) || isMain(id)) throw new Error('Unknown account');
  return path.join(base, id);
}

function lstat(p) {
  try {
    return fs.lstatSync(p);
  } catch {
    return null;
  }
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function linkShared(dir) {
  for (const name of SHARED_DIRS) {
    const target = path.join(mainDir, name);
    const link = path.join(dir, name);
    const t = lstat(target);
    if (!t || !t.isDirectory()) continue;
    const l = lstat(link);
    if (l && l.isSymbolicLink()) continue;
    if (l) {
      // Claude made its own folder here before the main one existed. Only an
      // empty one is replaced; anything with content is left alone.
      try {
        fs.rmdirSync(link);
      } catch {
        continue;
      }
    }
    fs.symlinkSync(target, link, 'junction');
  }
}

// Settings that belong to the login rather than to the machine: whether its
// sessions join claude.ai by Remote Control, and whether its claude.ai
// connectors load. One account's rule (a work login kept off the cloud) is not
// another's, so these are never copied from the main account; each keeps its own.
const OWN_SETTINGS = ['remoteControlAtStartup'];
const OWN_ENV = ['ENABLE_CLAUDEAI_MCP_SERVERS'];

function mergedSettings(mainText, ownText) {
  let main;
  try {
    main = JSON.parse(mainText);
  } catch {
    return mainText; // not ours to understand; copied as it is
  }
  let own = {};
  try {
    own = JSON.parse(ownText || '{}') || {};
  } catch {
    own = {};
  }
  const out = { ...main };
  for (const k of OWN_SETTINGS) {
    if (own[k] !== undefined) out[k] = own[k];
    else delete out[k];
  }
  const env = { ...(main.env || {}) };
  for (const k of OWN_ENV) {
    if (own.env && own.env[k] !== undefined) env[k] = own.env[k];
    else delete env[k];
  }
  if (Object.keys(env).length) out.env = env;
  else delete out.env;
  // Nothing of the login's own in either: the main file goes over as it is.
  if (JSON.stringify(out) === JSON.stringify(main)) return Buffer.from(mainText);
  return Buffer.from(JSON.stringify(out, null, 2));
}

function copyShared(dir) {
  for (const name of SHARED_FILES) {
    let wanted;
    try {
      wanted = fs.readFileSync(path.join(mainDir, name));
    } catch {
      continue;
    }
    const to = path.join(dir, name);
    let have = null;
    try {
      have = fs.readFileSync(to);
    } catch {
      // not copied yet
    }
    if (name === 'settings.json') wanted = mergedSettings(wanted.toString('utf8'), have && have.toString('utf8'));
    if (!have || !have.equals(wanted)) fs.writeFileSync(to, wanted);
  }
}

// An MCP server on this machine (a program, or the shared tools host on
// 127.0.0.1) serves every account alike. One on the internet is signed in to
// by a login, so it stays with the account that added it.
const isLocalServer = (s) => {
  if (!s || typeof s !== 'object') return false;
  if (!s.type || s.type === 'stdio') return true;
  return /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\])(:|\/|$)/i.test(String(s.url || ''));
};

// The local MCP servers and the folders already trusted follow the main
// account; the login details and the account's own cloud servers stay its own.
function syncJson(dir) {
  const from = readJson(mainJson);
  if (!from) return;
  const file = path.join(dir, '.claude.json');
  const own = readJson(file) || {};
  const before = JSON.stringify(own);
  for (const k of SEED_KEYS) if (own[k] === undefined && from[k] !== undefined) own[k] = from[k];
  if (from.mcpServers) {
    const mine = Object.fromEntries(Object.entries(own.mcpServers || {}).filter(([, s]) => !isLocalServer(s)));
    const shared = Object.fromEntries(Object.entries(from.mcpServers).filter(([, s]) => isLocalServer(s)));
    own.mcpServers = { ...mine, ...shared };
  }
  if (from.projects) {
    own.projects = own.projects || {};
    for (const [k, v] of Object.entries(from.projects)) if (!own.projects[k]) own.projects[k] = v;
  }
  if (JSON.stringify(own) === before) return;
  const tmp = file + '.deck-tmp';
  fs.writeFileSync(tmp, JSON.stringify(own, null, 2));
  fs.renameSync(tmp, file);
}

// ---- connector sign-ins ----
// MCP servers and plugins keep their own sign-ins (GitHub, Vercel, Figma ...) in
// each account's credentials file, next to the Claude login. They have nothing
// to do with which Claude account is in use, so every account gets the same
// set: whichever copy of a sign-in is freshest is given to all of them. The
// Claude login itself is never copied.

const credFile = (dir) => path.join(dir, '.credentials.json');

function accountDirs() {
  const dirs = [mainDir];
  try {
    for (const d of fs.readdirSync(base, { withFileTypes: true })) if (d.isDirectory() && ID_RE.test(d.name)) dirs.push(path.join(base, d.name));
  } catch {
    // no extra accounts yet
  }
  return dirs;
}

// Connectors set up on claude.ai belong to one Claude account and stay with it.
const isShared = (key) => !/^claude.ai[ :|]/i.test(key);

// Higher is better: a sign-in with a token beats one without, a later expiry beats an earlier one.
const freshness = (e) => (e && e.accessToken ? e.expiresAt || 1 : 0);

function syncConnectors() {
  const files = [];
  for (const dir of accountDirs()) {
    try {
      const raw = fs.readFileSync(credFile(dir), 'utf8');
      files.push({ file: credFile(dir), raw, data: JSON.parse(raw), mtime: fs.statSync(credFile(dir)).mtimeMs });
    } catch {
      // not signed in yet, or mid-write; it joins on a later pass
    }
  }
  if (files.length < 2) return 0;
  files.sort((a, b) => b.mtime - a.mtime); // on a tie, the file written last wins
  const best = {};
  for (const f of files) {
    for (const [key, entry] of Object.entries(f.data.mcpOAuth || {})) {
      if (!isShared(key)) continue;
      if (!(key in best) || freshness(entry) > freshness(best[key])) best[key] = entry;
    }
  }
  let written = 0;
  for (const f of files) {
    const have = f.data.mcpOAuth || {};
    const own = Object.fromEntries(Object.entries(have).filter(([k]) => !isShared(k))); // stays with this account
    const wanted = { ...own, ...best };
    const same =
      Object.keys(wanted).length === Object.keys(have).length && Object.keys(wanted).every((k) => JSON.stringify(have[k]) === JSON.stringify(wanted[k]));
    if (same) continue;
    const tmp = f.file + '.deck-tmp';
    try {
      fs.writeFileSync(tmp, JSON.stringify({ ...f.data, mcpOAuth: wanted }), { mode: 0o600 });
      // Claude Code may have refreshed its own login in this file a moment ago.
      // If anything changed since it was read, leave it; the next pass picks it up.
      if (fs.readFileSync(f.file, 'utf8') !== f.raw) {
        fs.unlinkSync(tmp);
        continue;
      }
      fs.renameSync(tmp, f.file);
      written++;
    } catch {
      try {
        fs.unlinkSync(tmp);
      } catch {
        // nothing left behind
      }
    }
  }
  return written;
}

// Keep them in step while the app is open: a sign-in refreshed under one account
// reaches the others within a few seconds.
let watching = [];
let syncSoon = null;

function watchConnectors() {
  for (const f of watching) fs.unwatchFile(f);
  watching = accountDirs().map(credFile);
  for (const f of watching) {
    fs.watchFile(f, { interval: 4000 }, () => {
      clearTimeout(syncSoon);
      syncSoon = setTimeout(() => {
        try {
          syncConnectors();
        } catch {
          // try again on the next change
        }
      }, 1500);
    });
  }
  try {
    syncConnectors();
  } catch {
    // unreadable right now
  }
}

// Make the account's folder ready to launch from. Safe to call every time.
function prepare(id) {
  const dir = dirFor(id);
  const isNew = !lstat(dir);
  fs.mkdirSync(dir, { recursive: true });
  linkShared(dir);
  copyShared(dir);
  syncJson(dir);
  if (isNew || !watching.includes(credFile(dir))) watchConnectors();
  else syncConnectors();
  return dir;
}

const envFor = (id) => (isMain(id) ? {} : { CLAUDE_CONFIG_DIR: prepare(id) });

function run(command, id, timeout) {
  return new Promise((resolve) => {
    let env;
    try {
      env = { ...process.env, ...envFor(id) };
    } catch (e) {
      return resolve({ error: e.message, stdout: '' });
    }
    exec(command, { env, timeout, windowsHide: true }, (error, stdout) =>
      resolve({ error: error && !stdout ? error.message : null, stdout: String(stdout || '') }),
    );
  });
}

// Who is signed in. `stamp` changes whenever the login itself changes, which
// is how a fresh sign-in is told apart from the one that was already there.
async function status(id, claudeCmd) {
  const dir = isMain(id) ? mainDir : dirFor(id);
  const creds = lstat(path.join(dir, '.credentials.json'));
  const out = { id: isMain(id) ? 'default' : id, loggedIn: false, email: '', org: '', plan: '', stamp: creds ? creds.mtimeMs : 0 };
  if (!isMain(id) && !creds) return out; // never signed in: skip starting the CLI
  const r = await run(`${claudeCmd || 'claude'} auth status --json`, id, 25000);
  try {
    const j = JSON.parse(r.stdout.slice(r.stdout.indexOf('{')));
    out.loggedIn = Boolean(j.loggedIn);
    out.email = j.email || '';
    out.org = j.orgName || '';
    out.plan = j.subscriptionType || (j.authMethod && j.authMethod !== 'none' ? j.authMethod : '');
  } catch {
    out.error = r.error || 'Claude Code did not answer';
  }
  return out;
}

const logout = (id, claudeCmd) => run(`${claudeCmd || 'claude'} auth logout`, id, 25000);

// Delete an account's folder. The links to shared folders are unhooked first
// and checked, so the session history they point at can never be removed.
function remove(id) {
  const dir = dirFor(id);
  if (!lstat(dir)) return;
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = lstat(p);
    if (!st || !st.isSymbolicLink()) continue;
    try {
      fs.rmdirSync(p);
    } catch {
      fs.unlinkSync(p);
    }
    if (lstat(p)) throw new Error(`Could not unlink ${name}; the account folder was left in place.`);
  }
  fs.rmSync(dir, { recursive: true, force: true });
}

// The config folder and config file of an account, the main one included.
const homeOf = (id) => (isMain(id) ? { dir: mainDir, json: mainJson } : { dir: dirFor(id), json: path.join(dirFor(id), '.claude.json') });

module.exports = {
  homeOf,
  syncConnectors,
  watchConnectors,
  stopWatching: () => watching.forEach((f) => fs.unwatchFile(f)),
  init,
  prepare,
  envFor,
  status,
  logout,
  remove,
  dirFor,
  isMain,
  SHARED_DIRS,
};
