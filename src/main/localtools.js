// Tool servers on this PC, waited for before a session starts.
//
// Claude Code connects to each tool once, as a session starts, and never tries
// a failed one again. A tool served on this PC (an http address on 127.0.0.1)
// that is still starting when Loop opens a session, as happens right after
// login, stays red in that session for good. So before a session starts, Loop
// waits for those addresses to answer. A tool that never comes up is waited for
// once; after that it is skipped until it is seen up again.
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');

const WAIT = 30000; // the longest a session waits for its tools
const EVERY = 500;
const LOCAL = new Set(['127.0.0.1', 'localhost', '[::1]', '::1']);

const gaveUp = new Set(); // "host:port" that did not come up in a whole wait

// The local http tools a session would connect to: its account's own, and its folder's.
function localPorts(config, cwd) {
  const servers = [config.mcpServers || {}];
  const proj = (config.projects || {})[String(cwd || '').replace(/\\/g, '/')];
  if (proj) servers.push(proj.mcpServers || {});
  const out = new Set();
  for (const list of servers) {
    for (const s of Object.values(list)) {
      if (!s || !/^(http|sse)$/.test(s.type || '') || !s.url) continue;
      let u;
      try {
        u = new URL(s.url);
      } catch {
        continue;
      }
      if (!LOCAL.has(u.hostname)) continue;
      out.add(`${u.hostname.replace(/^\[|\]$/g, '')}:${u.port || (u.protocol === 'https:' ? 443 : 80)}`);
    }
  }
  return [...out];
}

function readConfig(env) {
  const dir = (env && env.CLAUDE_CONFIG_DIR) || process.env.CLAUDE_CONFIG_DIR;
  const file = dir ? path.join(dir, '.claude.json') : path.join(os.homedir(), '.claude.json');
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return {};
  }
}

const answers = (hostPort) =>
  new Promise((resolve) => {
    const i = hostPort.lastIndexOf(':');
    const sock = net.connect({ host: hostPort.slice(0, i), port: Number(hostPort.slice(i + 1)) });
    const done = (ok) => {
      sock.destroy();
      resolve(ok);
    };
    sock.setTimeout(1000, () => done(false));
    sock.once('connect', () => done(true));
    sock.once('error', () => done(false));
  });

// Resolves once every local tool answers, or the wait is over. Never rejects:
// a session starts either way.
async function ready(env, cwd, o = {}) {
  const wait = o.wait ?? WAIT;
  let left = localPorts(o.config || readConfig(env), cwd);
  const end = Date.now() + wait;
  for (;;) {
    const up = await Promise.all(left.map(answers));
    left.forEach((p, i) => up[i] && gaveUp.delete(p));
    left = left.filter((p, i) => !up[i] && !gaveUp.has(p));
    if (!left.length) return true;
    if (Date.now() >= end) {
      left.forEach((p) => gaveUp.add(p));
      return false;
    }
    await new Promise((r) => setTimeout(r, o.every ?? EVERY));
  }
}

module.exports = { ready, localPorts };
