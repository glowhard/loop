// Sub-sessions on the git side: a worktree on a branch of its own, inside the
// project's .claude/worktrees, kept out of git status, and never removed with
// work in it that is not committed.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const subs = require('../src/main/subs');

const git = (cwd, ...args) => execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8' }).trim();

function repo() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'loop-subs-'));
  git(root, 'init', '-q', '-b', 'main');
  git(root, 'config', 'user.email', 'test@example.com');
  git(root, 'config', 'user.name', 'Test');
  fs.writeFileSync(path.join(root, 'a.txt'), 'one\n');
  git(root, 'add', '.');
  git(root, 'commit', '-q', '-m', 'first');
  return root;
}

test('a sub-session gets a worktree on its own branch, out of git status', async () => {
  const root = repo();
  const r = await subs.worktree({ cwd: root, repo: '.', name: 'Fix the login page' });
  assert.ok(r.ok, r.error);
  assert.match(r.branch, /^sub\/fix-the-login-page-[0-9a-f]{4}$/);
  assert.strictEqual(r.base, 'main');
  assert.ok(r.path.startsWith(path.join(root, '.claude', 'worktrees')));
  assert.strictEqual(git(r.path, 'branch', '--show-current'), r.branch);
  assert.strictEqual(git(root, 'status', '--porcelain'), '', 'the worktree folder does not show as new');
  fs.rmSync(root, { recursive: true, force: true });
});

test('a worktree with work not committed is left in place; a clean one goes and its branch stays', async () => {
  const root = repo();
  const r = await subs.worktree({ cwd: root, repo: '.', name: 'task' });
  fs.writeFileSync(path.join(r.path, 'b.txt'), 'new\n');
  const kept = await subs.removeWorktree({ repo: r.repo, path: r.path });
  assert.strictEqual(kept.ok, false);
  assert.ok(fs.existsSync(r.path));
  git(r.path, 'add', '.');
  git(r.path, 'commit', '-q', '-m', 'work');
  const gone = await subs.removeWorktree({ repo: r.repo, path: r.path });
  assert.ok(gone.ok, gone.error);
  assert.ok(!fs.existsSync(r.path));
  assert.ok(git(root, 'branch', '--list', r.branch).includes(r.branch), 'the branch is kept for merging');
  fs.rmSync(root, { recursive: true, force: true });
});

test('a workspace lists its own repository and the ones inside it', async () => {
  const root = repo();
  const inner = path.join(root, 'backend');
  fs.mkdirSync(inner);
  git(inner, 'init', '-q', '-b', 'develop');
  const list = await subs.repos(root);
  assert.deepStrictEqual(
    list.map((x) => x.rel),
    ['.', 'backend'],
  );
  fs.rmSync(root, { recursive: true, force: true });
});

test('a folder that is not a repository says so', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'loop-subs-plain-'));
  const r = await subs.worktree({ cwd: dir, repo: '.', name: 'x' });
  assert.strictEqual(r.ok, false);
  assert.match(r.error, /not a git repository/);
  fs.rmSync(dir, { recursive: true, force: true });
});
