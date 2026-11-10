// Sub-sessions: a session started off another one for one task, given what it
// needs to know, and handing back what the main session asked for. It runs in
// the same folder as its main session, so it shares that project's history and
// memory; for code it gets a git worktree and a branch of its own, kept in the
// project's .claude/worktrees folder (where Claude Code keeps its own) and out
// of git status.
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

function git(cwd, args, timeout = 60000) {
  return new Promise((resolve) => {
    execFile('git', ['-C', cwd, ...args], { windowsHide: true, timeout, maxBuffer: 4 * 1024 * 1024 }, (error, stdout, stderr) =>
      resolve({ ok: !error, out: String(stdout || '').trim(), err: String(stderr || error?.message || '').trim() }),
    );
  });
}

const isDir = (p) => {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
};

// The repositories a sub-session could work in: the one the folder is in, and
// any directly inside it (a workspace holding several apps).
async function repos(cwd) {
  const out = [];
  const top = await git(cwd, ['rev-parse', '--show-toplevel']);
  if (top.ok) out.push({ rel: '.', path: path.resolve(top.out) });
  let names = [];
  try {
    names = fs.readdirSync(cwd, { withFileTypes: true }).filter((d) => d.isDirectory() && !d.name.startsWith('.') && d.name !== 'node_modules');
  } catch {
    names = [];
  }
  for (const d of names) {
    const p = path.join(cwd, d.name);
    if (fs.existsSync(path.join(p, '.git')) && !out.some((r) => r.path === path.resolve(p))) out.push({ rel: d.name, path: path.resolve(p) });
  }
  return out;
}

// Make sure a folder never shows in a repository's status.
async function exclude(repoPath, pattern) {
  const file = await git(repoPath, ['rev-parse', '--git-path', 'info/exclude']);
  if (!file.ok) return;
  const f = path.resolve(repoPath, file.out);
  let text = '';
  try {
    text = fs.readFileSync(f, 'utf8');
  } catch {
    // made below
  }
  if (text.split(/\r?\n/).includes(pattern)) return;
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.appendFileSync(f, (text && !text.endsWith('\n') ? '\n' : '') + pattern + '\n');
}

const slugOf = (text) =>
  String(text || 'task')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 32) || 'task';

// A worktree on a new branch from what the repository has checked out now.
async function worktree({ cwd, repo, name }) {
  if (!isDir(cwd)) return { ok: false, error: 'The project folder is not there.' };
  const repoPath = path.resolve(cwd, repo || '.');
  const top = await git(repoPath, ['rev-parse', '--show-toplevel']);
  if (!top.ok) return { ok: false, error: `${repo || 'This folder'} is not a git repository.` };
  const root = path.resolve(top.out);
  const base = (await git(root, ['rev-parse', '--abbrev-ref', 'HEAD'])).out || 'HEAD';
  const slug = `${slugOf(name)}-${Math.random().toString(16).slice(2, 6)}`;
  const branch = `sub/${slug}`;
  const dest = path.join(cwd, '.claude', 'worktrees', slug);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  const made = await git(root, ['worktree', 'add', '-b', branch, dest, 'HEAD'], 180000);
  if (!made.ok) return { ok: false, error: made.err.split('\n').pop() || 'git could not make the worktree.' };
  // Neither the repository it came from nor the one the project folder is in
  // should list it as a new folder.
  await exclude(root, '.claude/worktrees/');
  const own = await git(cwd, ['rev-parse', '--show-toplevel']);
  if (own.ok && path.resolve(own.out) !== root) await exclude(path.resolve(own.out), '.claude/worktrees/');
  return { ok: true, path: dest, branch, base, repo: root };
}

// A finished sub-session's worktree goes; its branch stays for the main
// session to merge. Work not committed is never thrown away.
async function removeWorktree({ repo, path: where }) {
  if (!repo || !where || !isDir(where)) return { ok: true, gone: true };
  const dirty = await git(where, ['status', '--porcelain']);
  if (dirty.ok && dirty.out) return { ok: false, error: 'It has changes that are not committed, so it was left in place.' };
  const r = await git(repo, ['worktree', 'remove', where]);
  return r.ok ? { ok: true } : { ok: false, error: r.err.split('\n').pop() || 'git could not remove it.' };
}

module.exports = { repos, worktree, removeWorktree, slugOf, _test: { git, exclude } };
