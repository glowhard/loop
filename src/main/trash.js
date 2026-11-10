// Deleted sessions. A deleted session's saved conversation is moved here, can be
// put back for 30 days, and is then removed for good.
const fsp = require('fs/promises');
const path = require('path');
const { UUID_RE, CLAUDE_DIR } = require('./scanner');

const KEEP_MS = 30 * 24 * 3600 * 1000;
const DIR_RE = /^[A-Za-z0-9_-]+$/;
let ROOT = '';
let PROJECTS = path.join(CLAUDE_DIR, 'projects');

const valid = (dir, id) => DIR_RE.test(String(dir)) && UUID_RE.test(String(id));
const exists = (p) => fsp.access(p).then(() => true, () => false);

async function move(from, to) {
  await fsp.mkdir(path.dirname(to), { recursive: true });
  try {
    await fsp.rename(from, to);
  } catch (e) {
    if (e.code !== 'EXDEV') throw e;
    await fsp.cp(from, to, { recursive: true }); // another drive: copy, then remove
    await fsp.rm(from, { recursive: true, force: true });
  }
}

async function put(dir, id, title) {
  if (!valid(dir, id)) return false;
  const from = path.join(PROJECTS, dir, id);
  const to = path.join(ROOT, dir, id);
  try {
    await move(from + '.jsonl', to + '.jsonl');
  } catch {
    return false;
  }
  if (await exists(from)) await move(from, to).catch(() => {}); // its subagent transcripts
  await fsp.writeFile(to + '.json', JSON.stringify({ title: String(title || '').slice(0, 200), at: Date.now() }));
  return true;
}

async function list() {
  const out = [];
  for (const dir of await fsp.readdir(ROOT).catch(() => [])) {
    for (const name of await fsp.readdir(path.join(ROOT, dir)).catch(() => [])) {
      if (!name.endsWith('.json') || name.endsWith('.jsonl')) continue;
      const id = name.slice(0, -5);
      if (!valid(dir, id)) continue;
      try {
        const meta = JSON.parse(await fsp.readFile(path.join(ROOT, dir, name), 'utf8'));
        out.push({ dir, id, title: meta.title || id, at: Number(meta.at) || 0, until: (Number(meta.at) || 0) + KEEP_MS });
      } catch {}
    }
  }
  return out.sort((a, b) => b.at - a.at);
}

async function drop(dir, id) {
  const at = path.join(ROOT, dir, id);
  for (const p of [at + '.jsonl', at + '.json', at]) await fsp.rm(p, { recursive: true, force: true }).catch(() => {});
}

async function restore(dir, id) {
  if (!valid(dir, id)) return false;
  const from = path.join(ROOT, dir, id);
  const to = path.join(PROJECTS, dir, id);
  if (!(await exists(from + '.jsonl')) || (await exists(to + '.jsonl'))) return false;
  try {
    await move(from + '.jsonl', to + '.jsonl');
  } catch {
    return false;
  }
  if ((await exists(from)) && !(await exists(to))) await move(from, to).catch(() => {});
  await drop(dir, id);
  return true;
}

async function purge(now = Date.now()) {
  let n = 0;
  for (const t of await list()) {
    if (now < t.until) continue;
    await drop(t.dir, t.id);
    n++;
  }
  return n;
}

function init(userData) {
  ROOT = path.join(userData, 'trash');
  purge().catch(() => {});
  setInterval(() => purge().catch(() => {}), 6 * 3600 * 1000).unref();
}

module.exports = {
  init,
  put,
  list,
  restore,
  purge,
  KEEP_MS,
  _test: { setRoots: (root, projects) => ((ROOT = root), (PROJECTS = projects)) },
};
