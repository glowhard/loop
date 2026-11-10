/* global deck, S, toast, save, renderList, formDialog, confirmBox, sessionTitle, projectByDir, accountFor, sayTo, phoneLookSoon */
'use strict';

// ---------- sub-sessions ----------
// A session started off another one for one task. It runs in the same folder
// as its main session, so it shares that project's history and memory, and is
// shown under it. For code it works in a git worktree on a branch of its own.
// It is told what to hand back; when it calls subsession_done, Loop puts the
// result into the main session as a message, from the sub-session by name.

const subOf = (id) => (S.config.subSessions || {})[id] || null;
const subsOf = (parentId) =>
  Object.entries(S.config.subSessions || {})
    .filter(([, v]) => v.parent === parentId)
    .map(([id, v]) => ({ id, ...v }))
    .sort((a, b) => (a.at || 0) - (b.at || 0));

// What a main session gets back, when nobody said: code gives a branch, the rest a report.
const RETURNS_CODE = 'The branch name, the commits on it (hash and one line each), and a summary of 3 lines or fewer: what changed and how to check it. Do not merge or push unless the task says so.';
const RETURNS_REPORT = 'A short report: what was done, links or files, and anything that needs a decision. 8 lines or fewer.';

// The session object for an id, wherever Loop has it.
function sessionById(id) {
  for (const p of S.projects) {
    const s = p.sessions.find((x) => x.id === id);
    if (s) return { p, s };
  }
  return { p: null, s: null };
}

// What the main session has been saying, so the sub-session starts knowing it.
async function recentContext(p, parentId) {
  try {
    const turns = await deck.peek({ dir: p.dir, sessionId: parentId });
    const text = turns
      .slice(-6)
      .map((t) => `${t.role === 'user' ? 'User' : 'Main session'}: ${String(t.text).replace(/\s+/g, ' ').slice(0, 600)}`)
      .join('\n');
    return text.slice(-3000);
  } catch {
    return '';
  }
}

function briefFor(sub, parentName, ctx) {
  return [
    `You are a sub-session of "${parentName}", started for one task. You do not see its conversation; everything you need is below.`,
    `Task: ${sub.task}`,
    sub.branch
      ? `Work in the git worktree ${sub.worktree} on branch ${sub.branch} (made from ${sub.base || 'the current branch'}). Make every change there, and commit it there. Do not touch the main checkout.`
      : '',
    ctx ? `What the main session knows that you need:\n${ctx}` : '',
    'Its notes are in memory: memory_search or memory_list with scope "parent". Project notes are scope "project".',
    `When you are done, call subsession_done with exactly this, and nothing longer: ${sub.returns}`,
    'If you cannot finish, call subsession_done saying what is missing. Ask the user only for a decision that is theirs.',
  ]
    .filter(Boolean)
    .join('\n\n');
}

// Start one. `by` is who asked: 'user' (Loop or the phone) or 'session' (the
// main session's own tool). Returns { ok, text, id }.
async function startSub(p, parentId, o) {
  const task = String(o.task || '').trim();
  if (!task) return { ok: false, text: 'Say what the sub-session should do.' };
  if (!p || !p.exists) return { ok: false, text: 'That project folder is not there.' };
  if (p.server) return { ok: false, text: 'Sub-sessions start from the Loop that runs the session: open the server’s own Loop on the phone.' };
  const parent = sessionById(parentId).s || { id: parentId, title: 'the main session' };
  const parentName = sessionTitle(parent);
  // A short name, cut at a word rather than in the middle of one.
  const said = String(o.name || task).replace(/\s+/g, ' ').trim();
  const cut = said.length > 40 ? said.slice(0, 40).replace(/\s+\S*$/, '') : said;
  const name = (cut.length >= 12 ? cut : said.slice(0, 40)).replace(/[\s,.:;-]+$/, '');
  // Code gets a worktree unless asked not to, when the project has a repository.
  let tree = null;
  let note = '';
  if (o.worktree !== false) {
    const repos = await deck.subRepos(p.path);
    const want = o.repo ? repos.find((r) => r.rel === o.repo || r.path.toLowerCase().endsWith(String(o.repo).toLowerCase())) : repos[0];
    if (want) {
      const r = await deck.subWorktree({ cwd: p.path, repo: want.rel, name });
      if (r.ok) tree = r;
      else note = ` No worktree: ${r.error}`;
    } else if (o.worktree === true) note = ' No git repository there, so it works in the project folder.';
  }
  const id = crypto.randomUUID();
  const returns = String(o.returns || '').trim() || (S.config.sessionReturns || {})[parentId] || (tree ? RETURNS_CODE : RETURNS_REPORT);
  const sub = {
    parent: parentId,
    dir: p.dir,
    task: task.slice(0, 4000),
    returns: returns.slice(0, 1000),
    name,
    by: o.by || 'user',
    status: 'working',
    at: Date.now(),
    branch: tree ? tree.branch : '',
    base: tree ? tree.base : '',
    worktree: tree ? tree.path : '',
    repo: tree ? tree.repo : '',
  };
  S.config.subSessions = S.config.subSessions || {};
  S.config.subSessions[id] = sub;
  S.config.sessionAlias[id] = name;
  save();
  const ctx = [String(o.context || '').trim(), o.by === 'session' ? '' : await recentContext(p, parentId)].filter(Boolean).join('\n\n');
  const why = await deck.directSend({ dir: p.dir, cwd: p.path, sessionId: id, text: briefFor(sub, parentName, ctx), account: accountFor(p.dir, parentId), fresh: true });
  if (why) {
    sub.status = 'failed';
    sub.result = why;
    save();
    renderList();
    return { ok: false, text: `The sub-session could not start: ${why}` };
  }
  renderList();
  phoneLookSoon();
  return { ok: true, id, text: `Started sub-session "${name}"${tree ? ` on branch ${tree.branch}` : ''}.${note}` };
}

// A sub-session's result goes into its main session, from it by name.
async function finishSub(id, result) {
  const sub = subOf(id);
  if (!sub) return 'You are not a sub-session, so there is no main session to hand this to.';
  sub.status = 'done';
  sub.result = String(result || '').slice(0, 8000);
  sub.doneAt = Date.now();
  save();
  renderList();
  const { p, s } = sessionById(sub.parent);
  if (!p || !s) return 'Saved, but the main session is no longer in Loop, so it was not told.';
  const lines = [`Session message from "${sub.name}" (your sub-session) - done: ${sub.task.slice(0, 200)}`, sub.result];
  if (sub.branch) lines.push(`Branch: ${sub.branch}  (worktree ${sub.worktree})`);
  const r = await sayTo(p, s, lines.join('\n'));
  return r.ok ? `Handed to "${sessionTitle(s)}". You are done; stop here.` : `Saved, but "${sessionTitle(s)}" could not be reached: ${r.text || 'unknown'}. The user can read it in Loop.`;
}

function listSubs(parentId) {
  const list = subsOf(parentId);
  if (!list.length) return 'You have no sub-sessions.';
  return list
    .map((x) => `- "${x.name}": ${x.status}${x.branch ? `, branch ${x.branch}` : ''}. Task: ${x.task.slice(0, 160)}${x.result ? `\n  Result: ${x.result.slice(0, 600)}` : ''}`)
    .join('\n');
}

// Deleting one: it is stopped, its worktree goes when nothing is left
// uncommitted (the branch stays, to be merged), and it leaves the list.
async function closeSub(id) {
  const sub = subOf(id);
  if (!sub) return { ok: false, text: 'That is not a sub-session.' };
  await deck.directStop(id);
  if (sub.worktree) {
    const r = await deck.subRemove({ repo: sub.repo, path: sub.worktree });
    if (!r.ok) return { ok: false, text: `"${sub.name}" was stopped but kept: ${r.error}` };
  }
  sub.status = 'closed';
  if (!S.config.hiddenSessions.includes(id)) S.config.hiddenSessions.push(id);
  save();
  renderList();
  phoneLookSoon();
  return { ok: true, text: `Deleted "${sub.name}".${sub.branch ? ` Branch ${sub.branch} is kept.` : ''}` };
}

// The subsession_* tools, as a session calls them.
async function subCommand(q) {
  const sub = q.sub || {};
  if (q.action === 'subsession_done') return finishSub(q.me, sub.result);
  if (q.action === 'subsession_list') return listSubs(q.me);
  if (q.action === 'subsession_close') {
    const want = String(sub.session || '').trim().toLowerCase();
    const mine = subsOf(q.me).filter((x) => x.status !== 'closed');
    const pick = want === 'done' ? mine.filter((x) => x.status === 'done') : mine.filter((x) => x.name.toLowerCase() === want || x.id.startsWith(want)).slice(0, 1);
    if (!pick.length) return want === 'done' ? 'None of your sub-sessions has handed back yet.' : `You have no sub-session called "${sub.session}". Call subsession_list for the names.`;
    const out = [];
    for (const x of pick) out.push((await closeSub(x.id)).text);
    return out.join('\n');
  }
  if (q.action === 'subsession_returns') {
    S.config.sessionReturns = S.config.sessionReturns || {};
    S.config.sessionReturns[q.me] = String(sub.returns || '').slice(0, 1000);
    save();
    return 'Noted: sub-sessions started for you hand back that, unless told otherwise.';
  }
  if (q.action === 'subsession_start') {
    if (subOf(q.me)) return 'A sub-session does not start sub-sessions of its own: do the work, or say in subsession_done what else is needed.';
    const p = projectByDir(q.dir);
    const r = await startSub(p, q.me, { ...sub, by: 'session' });
    return r.ok ? `${r.text} It reports back to you as a message when it is done. Carry on with your own work.` : r.text;
  }
  return 'Unknown sub-session action.';
}

// Started by the user, from a session's menu in Loop.
async function subDialog(p, s) {
  const repos = p.server ? [] : await deck.subRepos(p.path);
  const fields = [
    { key: 'task', label: 'Task', type: 'textarea', value: '', placeholder: 'What should the sub-session do? It does not see the main conversation, but gets its last messages and notes.' },
    { key: 'returns', label: 'What to hand back (optional)', value: (S.config.sessionReturns || {})[s.id] || '', placeholder: 'Default: the branch and commits for code, a short report otherwise' },
  ];
  if (repos.length) {
    fields.push({
      key: 'repo',
      label: 'Work on a branch of',
      type: 'select',
      value: repos[0].rel,
      options: [...repos.map((r) => ({ value: r.rel, label: r.rel === '.' ? 'this project' : r.rel })), { value: '-', label: 'No branch (not code)' }],
    });
  }
  const v = await formDialog({ title: `Sub-session of ${sessionTitle(s)}`, body: 'It runs beside the main session and hands its result back to it when done.', fields, confirm: 'Start' });
  if (!v) return;
  const r = await startSub(p, s.id, { task: v.task, returns: v.returns, repo: v.repo && v.repo !== '-' ? v.repo : '', worktree: v.repo !== '-' && repos.length > 0, by: 'user' });
  toast(r.text, !r.ok);
}

// Sessions in the order they are shown: each sub-session right under its main
// one. Those whose main session is not in the list stay where they are.
function withSubs(list) {
  const ids = new Set(list.map((s) => s.id));
  const out = [];
  for (const s of list) {
    const sub = subOf(s.id);
    if (sub && ids.has(sub.parent)) continue;
    out.push(s);
    for (const c of subsOf(s.id)) {
      const child = list.find((x) => x.id === c.id);
      if (child) out.push(child);
    }
  }
  return out;
}
