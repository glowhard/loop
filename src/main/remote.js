// Remote Control housekeeping. Claude Code leaves a marker in a session's
// transcript while it is connected to claude.ai, and reconnects on every
// resume for as long as the marker is there. Turning the switch off therefore
// means two things: the copy on claude.ai is deleted, and the marker is closed
// the same way Claude Code closes it when you disconnect by hand.
const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const { UUID_RE, CLAUDE_DIR } = require('./scanner');
const accounts = require('./accounts');

const ID_RE = /^cse_[A-Za-z0-9]{8,64}$/;
const API = 'https://api.anthropic.com/v1/code/sessions/';

function transcript(dir, sessionId) {
  if (!/^[A-Za-z0-9_-]+$/.test(dir || '') || !UUID_RE.test(sessionId || '')) return null;
  return path.join(CLAUDE_DIR, 'projects', dir, sessionId + '.jsonl');
}

// The remote copy this session points at right now: its id, or null.
async function pointer(dir, sessionId) {
  const file = transcript(dir, sessionId);
  if (!file) return null;
  try {
    const stat = await fsp.stat(file);
    const len = Math.min(stat.size, 2 * 1024 * 1024);
    const fh = await fsp.open(file, 'r');
    let tail;
    try {
      const buf = Buffer.alloc(len);
      await fh.read(buf, 0, len, stat.size - len);
      tail = buf.toString('utf8');
    } finally {
      await fh.close();
    }
    const at = tail.lastIndexOf('{"type":"bridge-session"');
    if (at < 0) return null;
    const end = tail.indexOf('\n', at);
    const rec = JSON.parse(tail.slice(at, end < 0 ? undefined : end));
    return ID_RE.test(rec.bridgeSessionId || '') ? rec.bridgeSessionId : null;
  } catch {
    return null;
  }
}

// Same record Claude Code writes when Remote Control is disconnected.
async function closePointer(dir, sessionId) {
  const file = transcript(dir, sessionId);
  if (!file) return;
  const fh = await fsp.open(file, 'a+');
  try {
    const { size } = await fh.stat();
    const last = Buffer.alloc(1);
    if (size) await fh.read(last, 0, 1, size - 1);
    const line = JSON.stringify({ type: 'bridge-session', sessionId, bridgeSessionId: '', lastSequenceNum: 0 });
    await fh.appendFile((size && last[0] !== 10 ? '\n' : '') + line + '\n');
  } finally {
    await fh.close();
  }
}

// The account's Claude Code login, used for this one call and never kept.
function login(accountId) {
  try {
    const home = accounts.homeOf(accountId);
    const c = JSON.parse(fs.readFileSync(path.join(home.dir, '.credentials.json'), 'utf8')).claudeAiOauth;
    const org = (JSON.parse(fs.readFileSync(home.json, 'utf8')).oauthAccount || {}).organizationUuid;
    if (!c || !c.accessToken || !org) return null;
    return { token: c.accessToken, org, expired: Boolean(c.expiresAt && c.expiresAt < Date.now()) };
  } catch {
    return null;
  }
}

// Delete a remote copy from claude.ai, archive included. The copy belongs to
// whichever account connected it, so the tab's account is tried first, then the rest.
const deleteCopy = (id, accountIds) => deleteWith(id, [...new Set(accountIds)].map(login));

// The same with logins given directly: a server session's copy belongs to the login on that server.
async function deleteWith(id, logins) {
  if (!ID_RE.test(id || '')) return { ok: false, reason: 'no remote copy' };
  let reason = 'not signed in';
  for (const who of logins) {
    if (!who || !who.token || !who.org) continue;
    try {
      const r = await fetch(API + id, {
        method: 'DELETE',
        headers: {
          Authorization: `Bearer ${who.token}`,
          'Content-Type': 'application/json',
          'anthropic-version': '2023-06-01',
          'anthropic-beta': 'ccr-byoc-2025-07-29',
          'x-organization-uuid': who.org,
        },
        body: '{}',
        signal: AbortSignal.timeout(15000),
      });
      if (r.ok || r.status === 404) return { ok: true, gone: r.status === 404 };
      reason =
        r.status === 401
          ? who.expired
            ? 'the login has expired; open any session with this account once and try again'
            : 'the login was refused'
          : `claude.ai answered ${r.status}`;
    } catch (e) {
      reason = e.name === 'TimeoutError' ? 'claude.ai did not answer' : 'no connection';
    }
  }
  return { ok: false, reason };
}

const link = (id) => (ID_RE.test(id || '') ? 'https://claude.ai/code/session_' + id.slice(4) : null);

// Before a session with the switch off is started: delete what it still points
// at and close the marker, so resuming cannot reconnect it.
async function forget(dir, sessionId, accountIds) {
  const id = await pointer(dir, sessionId);
  if (!id) return null;
  const result = await deleteCopy(id, accountIds);
  await closePointer(dir, sessionId).catch(() => {});
  return { id, ...result, link: link(id) };
}

module.exports = { pointer, closePointer, deleteCopy, deleteWith, forget, link };
