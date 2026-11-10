// Sessions on other machines. A server is reached with the SSH client already
// on this PC; nothing is installed there. Each server gets one long-lived
// connection that reports, every few seconds, what is running and how loaded
// the machine is, and now and then which sessions exist. Tabs are separate
// SSH connections that run Claude Code inside tmux, so a session keeps going
// when the tab, this app or this PC goes away.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn, execFile } = require('child_process');
const { UUID_RE } = require('./scanner');
const { shellArg } = require('./shell');

const SYSTEM_SSH = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'OpenSSH', 'ssh.exe');
const SSH = fs.existsSync(SYSTEM_SSH) ? SYSTEM_SSH : 'ssh';
const ID_RE = /^[a-z0-9]{1,24}$/;
const USER_RE = /^[a-z_][a-z0-9_-]{0,31}$/;
// Where Claude Code and user tools usually live; a command run over SSH does not read the login profile.
const REMOTE_PATH = 'export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH"';

const state = new Map(); // server id -> { server, proc, status, cpu, timer }
let onChange = () => {};

const valid = (s) =>
  s &&
  ID_RE.test(s.id || '') &&
  /^[A-Za-z0-9._-]{1,253}$/.test(s.host || '') &&
  /^[A-Za-z0-9._-]{0,64}$/.test(s.user || '') &&
  (!s.port || (Number(s.port) > 0 && Number(s.port) < 65536)) &&
  !/["%\r\n]/.test(s.key || '') &&
  (!s.runAs || USER_RE.test(s.runAs));

const target = (s) => (s.user ? `${s.user}@${s.host}` : s.host);

const quote = (v) => `'${String(v).replace(/'/g, `'\\''`)}'`; // for the server's shell

// A server can run its sessions as another user than the one SSH logs in as:
// log in as root, work as a normal user. Everything Loop does there then
// happens as that user, so it sees that user's sessions, folders and sign-in.
// The text this returns has no double quotes, so it can sit inside them.
function asUser(s, script) {
  const u = s.runAs;
  if (!u) return script;
  const q = quote(script);
  return `if [ $(id -un) = ${u} ]; then ${script}; elif command -v sudo >/dev/null 2>&1; then exec sudo -n -H -u ${u} sh -c ${q}; else exec su -s /bin/sh ${u} -c ${q}; fi`;
}

// The same for a script fed on standard input. It first says who logged in.
function shellAs(s) {
  const u = s.runAs;
  const who = 'echo @@LOGIN $(id -un); ';
  if (!u) return who + 'exec sh -s';
  return `${who}if [ $(id -un) = ${u} ]; then exec sh -s; elif command -v sudo >/dev/null 2>&1; then exec sudo -n -H -u ${u} sh -s; else exec su -s /bin/sh ${u} -c 'sh -s'; fi`;
}

// Options shared by every connection to a server.
function sshArgs(s, interactive) {
  // On a phone's hotspot about one new connection in four never gets an
  // answer; trying again at once almost always does.
  const args = ['-o', 'ServerAliveInterval=20', '-o', 'ServerAliveCountMax=3', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectionAttempts=3'];
  // Conversations are text and the link is a phone's hotspot often enough:
  // compressing costs nothing here and saves most of the bytes.
  if (!interactive) args.push('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=7', '-o', 'Compression=yes');
  if (s.port) args.push('-p', String(Number(s.port)));
  if (s.key) args.push('-i', s.key, '-o', 'IdentitiesOnly=yes');
  return args;
}

// What the long-lived connection runs. Plain sh, fed on stdin, so nothing needs quoting.
const WATCH = `
${REMOTE_PATH}
cd 2>/dev/null
n=0
while :; do
  echo "@@BEGIN"
  read -r _ a b c d e f g _ < /proc/stat
  echo "@@SYS $(nproc 2>/dev/null || echo 1) $(awk '/MemTotal/{t=$2}/MemAvailable/{m=$2}/MemFree/{f=$2}END{print t, (m ? m : f)}' /proc/meminfo) $d $((a+b+c+d+e+f+g))"
  for f in "$HOME"/.claude/sessions/*.json; do
    [ -f "$f" ] || continue
    pid=\${f##*/}; pid=\${pid%.json}
    kill -0 "$pid" 2>/dev/null && { printf '@@LIVE '; tr -d '\\n' < "$f"; echo; }
  done
  echo "@@TMUX $(tmux list-sessions -F '#S' 2>/dev/null | tr '\\n' ',')"
  echo "@@END"
  if [ $((n % 10)) -eq 0 ]; then
    echo "@@BEGIN"
    echo "@@TOOLS $(command -v claude >/dev/null 2>&1 && claude --version 2>/dev/null | head -n1 || echo none)|$(command -v tmux >/dev/null 2>&1 && echo yes || echo no)|$(whoami)|$(hostname)"
    echo "@@USERS $(awk -F: '($3==0||($3>=1000&&$3<60000))&&$7!~/(nologin|false)$/{printf "%s,",$1}' /etc/passwd 2>/dev/null)"
    if [ $((n % 20)) -eq 0 ]; then echo "@@AUTH $(claude auth status --json 2>/dev/null | tr -d '\\n')"; fi
    for d in "$HOME"/.claude/projects/*/; do
      [ -d "$d" ] || continue
      for f in $(ls -t "$d"*.jsonl 2>/dev/null | head -n 15); do
        echo "@@S $(basename "$d") $(basename "$f" .jsonl) $(stat -c '%Y %s' "$f")"
        tail -c 200000 "$f" | grep -a -E '^\\{"type":"(custom-title|agent-name|ai-title|last-prompt)"' | tail -n 6 | cut -c1-700 | sed 's/^/@@M /'
        head -c 60000 "$f" | grep -a -m1 -o '"cwd":"[^"]*"' | sed 's/^/@@C /'
      done
    done
    echo "@@SCANNED"
    echo "@@END"
  fi
  n=$((n+1))
  sleep 3
done
`;

const field = (line, key) => {
  const m = new RegExp(`"${key}":"((?:[^"\\\\]|\\\\.)*)"`).exec(line);
  if (!m) return null;
  try {
    return JSON.parse(`"${m[1]}"`);
  } catch {
    return null;
  }
};
const clean = (s) => (s || '').replace(/\s+/g, ' ').trim().slice(0, 240);

// Turn one report from the server into status, running sessions and, when it carries one, the session list.
function digest(entry, lines) {
  const st = entry.status;
  const live = [];
  let projects = null;
  let cur = null;
  let quick = false; // the frequent report; the occasional one carries the session list instead
  for (const line of lines) {
    const sp = line.indexOf(' ');
    const tag = sp < 0 ? line : line.slice(0, sp);
    const rest = sp < 0 ? '' : line.slice(sp + 1);
    if (tag === '@@SYS') {
      quick = true;
      const [cores, total, avail, idle, all] = rest.split(' ').map(Number);
      const prev = entry.cpu;
      entry.cpu = { idle, all };
      st.load = {
        cores,
        memTotal: total * 1024,
        memUsed: (total - avail) * 1024,
        cpu: prev && all > prev.all ? Math.max(0, Math.min(100, Math.round(100 * (1 - (idle - prev.idle) / (all - prev.all))))) : st.load ? st.load.cpu : 0,
      };
    } else if (tag === '@@LIVE') {
      try {
        const o = JSON.parse(rest);
        if (o.sessionId)
          live.push({
            sessionId: o.sessionId,
            pid: o.pid,
            name: o.name || '',
            status: o.status || 'idle',
            cwd: o.cwd || '',
            entrypoint: o.entrypoint || '',
            startedAt: o.startedAt || 0,
            server: entry.server.id,
          });
      } catch {
        // being rewritten; the next report has it
      }
    } else if (tag === '@@TMUX') st.tmuxSessions = rest.split(',').filter(Boolean);
    else if (tag === '@@TOOLS') {
      const [claude, tmux, user, host] = rest.split('|');
      st.claude = claude && claude !== 'none' ? claude : '';
      st.tmux = tmux === 'yes';
      st.user = user || '';
      st.hostname = host || '';
    } else if (tag === '@@USERS') st.users = rest.split(',').filter((u) => USER_RE.test(u));
    else if (tag === '@@AUTH') {
      try {
        const j = JSON.parse(rest);
        st.auth = { loggedIn: Boolean(j.loggedIn), email: j.email || '', plan: j.subscriptionType || '' };
      } catch {
        st.auth = { loggedIn: false, email: '', plan: '' };
      }
    } else if (tag === '@@S') {
      projects = projects || new Map();
      const [dir, id, mtime, size] = rest.split(' ');
      if (!UUID_RE.test(id || '')) {
        cur = null;
        continue;
      }
      if (!projects.has(dir)) projects.set(dir, { enc: dir, sessions: [], cwd: null });
      cur = { id, mtime: Number(mtime) * 1000, size: Number(size), meta: {} };
      projects.get(dir).sessions.push(cur);
      cur.project = projects.get(dir);
    } else if (tag === '@@M' && cur) {
      // newest last: later lines overwrite earlier ones of the same kind
      if (rest.startsWith('{"type":"custom-title"')) cur.meta.customTitle = field(rest, 'customTitle');
      else if (rest.startsWith('{"type":"agent-name"')) cur.meta.agentName = field(rest, 'agentName');
      else if (rest.startsWith('{"type":"ai-title"')) cur.meta.aiTitle = field(rest, 'aiTitle');
      else if (rest.startsWith('{"type":"last-prompt"')) {
        const lp = field(rest, 'lastPrompt');
        if (lp && !/^[#<]/.test(lp.trim())) cur.meta.lastPrompt = lp;
      }
    } else if (tag === '@@C' && cur) {
      const cwd = field('{' + rest + '}', 'cwd');
      if (cwd && !cur.project.cwd) cur.project.cwd = cwd;
    } else if (tag === '@@SCANNED') projects = projects || new Map();
  }
  st.connected = true;
  st.error = '';
  st.at = Date.now();
  if (quick) entry.live = live;
  if (projects) {
    entry.projects = [...projects.values()]
      .map((p) => {
        const where = p.cwd || '/' + p.enc.replace(/^-/, '').replace(/-/g, '/'); // the folder name is a lossy copy of the path
        const sessions = p.sessions
          .map((s) => {
            const title = clean(s.meta.customTitle || s.meta.agentName || s.meta.aiTitle || s.meta.lastPrompt);
            const started = new Date(s.mtime).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
            return {
              id: s.id,
              title: title || `Session from ${started}`,
              named: Boolean(s.meta.customTitle || s.meta.agentName),
              lastPrompt: clean(s.meta.lastPrompt),
              mtime: s.mtime,
              size: s.size,
              empty: !title && s.size < 40000,
            };
          })
          .sort((a, b) => b.mtime - a.mtime);
        return {
          dir: `srv-${entry.server.id}-${p.enc}`.replace(/[^A-Za-z0-9_-]/g, '-'),
          path: where,
          exists: true,
          name: where.split('/').filter(Boolean).pop() || where,
          sessions,
          mtime: sessions.length ? sessions[0].mtime : 0,
          server: entry.server.id,
        };
      })
      .filter((p) => p.sessions.length)
      .sort((a, b) => b.mtime - a.mtime);
  }
}

function connect(entry) {
  const s = entry.server;
  let proc;
  try {
    proc = spawn(SSH, [...sshArgs(s, false), target(s), shellAs(s)], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  } catch (e) {
    entry.status.connected = false;
    entry.status.error = e.message;
    onChange();
    return;
  }
  entry.proc = proc;
  proc.stdin.on('error', () => {});
  proc.stdin.end(WATCH);
  let buf = '';
  let block = null;
  let err = '';
  proc.stdout.on('data', (d) => {
    buf += d;
    let nl;
    while ((nl = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, nl).replace(/\r$/, '');
      buf = buf.slice(nl + 1);
      if (line.startsWith('@@LOGIN ')) {
        entry.status.login = line.slice(8).trim();
        keepWarm(entry);
      }
      else if (line === '@@BEGIN') block = [];
      else if (line === '@@END' && block) {
        try {
          digest(entry, block);
        } catch {
          // a garbled report; the next one replaces it
        }
        block = null;
        onChange();
      } else if (block && block.length < 20000) block.push(line);
    }
    if (buf.length > 2e6) buf = '';
  });
  proc.stderr.on('data', (d) => (err = (err + d).slice(-600)));
  proc.on('error', (e) => (err = e.message));
  proc.on('close', () => {
    if (entry.proc !== proc) return; // replaced on purpose
    entry.proc = null;
    entry.live = [];
    entry.status.connected = false;
    const last =
      err
        .trim()
        .split(/\r?\n/)
        .filter((l) => !/^Warning: Permanently added/.test(l))
        .pop() || '';
    entry.status.error = /Permission denied/.test(last)
      ? 'The server refused the login. Open a terminal on it to check the key or password.'
      : /timed out|Could not resolve|No route|refused/i.test(last)
        ? 'The server cannot be reached.'
        : last || 'The connection closed.';
    onChange();
    entry.timer = setTimeout(() => state.has(s.id) && state.get(s.id) === entry && connect(entry), 15000);
  });
}

function drop(id) {
  const entry = state.get(id);
  if (!entry) return;
  state.delete(id);
  clearTimeout(entry.timer);
  clearInterval(entry.warm);
  const p = entry.proc;
  entry.proc = null;
  if (p) p.kill();
  if (entry.shell && !entry.shell.dead) entry.shell.proc.kill();
}

// Keep one connection per configured server; called whenever the list changes.
function sync(list) {
  const wanted = new Map((list || []).filter(valid).map((s) => [s.id, s]));
  for (const id of [...state.keys()]) {
    const next = wanted.get(id);
    const cur = state.get(id).server;
    if (!next || next.host !== cur.host || next.user !== cur.user || String(next.port || '') !== String(cur.port || '') || (next.key || '') !== (cur.key || '') || (next.runAs || '') !== (cur.runAs || ''))
      drop(id);
    else state.get(id).server = next;
  }
  for (const [id, s] of wanted) {
    if (state.has(id)) continue;
    const entry = { server: s, proc: null, timer: null, cpu: null, live: [], projects: [], status: { connected: false, error: 'Connecting', at: 0 } };
    state.set(id, entry);
    connect(entry);
  }
  onChange();
}

// Connect again now, for example after signing in to Claude there.
function refresh(id) {
  const entry = state.get(id);
  if (!entry) return;
  const s = entry.server;
  drop(id);
  sync([...[...state.values()].map((e) => e.server), s]);
}

// The session list is read only now and then, but what is running is known every
// few seconds. So a session that has just started is added from there: it and
// its folder show up at once instead of half a minute later.
function withLive(entry) {
  const known = new Set(entry.projects.flatMap((p) => p.sessions.map((x) => x.id)));
  const fresh = entry.live.filter((l) => l.cwd && !known.has(l.sessionId));
  if (!fresh.length) return entry.projects;
  const projects = entry.projects.map((p) => ({ ...p, sessions: [...p.sessions] }));
  for (const l of fresh) {
    // Remember when it was first seen, so the list does not change on every report.
    entry.seen = entry.seen || new Map();
    if (!entry.seen.has(l.sessionId)) entry.seen.set(l.sessionId, Date.now());
    const at = l.startedAt || entry.seen.get(l.sessionId);
    let p = projects.find((x) => x.path === l.cwd);
    if (!p) {
      p = {
        dir: `srv-${entry.server.id}-${l.cwd.replace(/[^A-Za-z0-9]/g, '-')}`.replace(/[^A-Za-z0-9_-]/g, '-'),
        path: l.cwd,
        exists: true,
        name: l.cwd.split('/').filter(Boolean).pop() || l.cwd,
        sessions: [],
        mtime: at,
        server: entry.server.id,
      };
      projects.push(p);
    }
    p.sessions.unshift({ id: l.sessionId, title: clean(l.name) || 'New session', named: Boolean(l.name), lastPrompt: '', mtime: at, size: 0, empty: false });
    p.mtime = Math.max(p.mtime, at);
  }
  return projects.sort((a, b) => b.mtime - a.mtime);
}

const snapshot = () => [...state.values()].map((e) => ({ id: e.server.id, ...e.status, projects: withLive(e), running: e.live.length }));
const live = () => [...state.values()].flatMap((e) => e.live);
const get = (id) => (state.get(id) || {}).server || null;

// Who the sessions run as: the chosen user, else whoever SSH logs in as.
const isRoot = (s) => (s.runAs ? s.runAs === 'root' : ((state.get(s.id) || {}).status || {}).user === 'root' || s.user === 'root');

const tmuxName = (sessionId) => 'loop-' + sessionId.slice(0, 13);

// The command a tab runs on this PC to work on the server. The part for the
// server is one argument: inside double quotes for cmd, so it uses single quotes
// only, and inside single quotes for a POSIX shell, so $ is left to the server.
function tabCommand(s, o, settings, platform = process.platform) {
  const arg = (script) => shellArg(script, platform);
  const exe = SSH === 'ssh' ? 'ssh' : `"${SSH}"`;
  const path$ = 'export PATH=$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH';
  const ssh = `${exe} -t ${sshArgs(s, true)
    .map((a) => (/[\s"]/.test(a) ? `"${a.replace(/"/g, '')}"` : a))
    .join(' ')} ${target(s)}`;
  const where = o.cwd && /^[^'"\r\n%!]+$/.test(o.cwd) ? o.cwd : '';
  if (o.kind === 'login') return `${ssh} ${arg(asUser(s, `${path$}; claude auth login`))}`;
  // Anthropic's own installer; it puts Claude Code in the user's home folder and leaves a shell open to read the result.
  if (o.kind === 'install')
    return `${ssh} ${arg(asUser(s, `${path$}; cd; curl -fsSL https://claude.ai/install.sh | bash; echo; echo Finished. Close this tab, then sign in.; exec $SHELL -l`))}`;
  if (o.kind === 'shell') {
    if (where) return `${ssh} ${arg(asUser(s, `cd ${quote(where)} 2>/dev/null; exec $SHELL -l`))}`;
    return s.runAs ? `${ssh} ${arg(asUser(s, 'cd; exec $SHELL -l'))}` : ssh;
  }
  if (!UUID_RE.test(o.sessionId || '')) throw new Error('Invalid session id');
  let flags = String(settings.flags || '').replace(/['"%!\r\n;&|<>`$\\]/g, '');
  // Claude Code refuses to skip permission prompts for root, on purpose. Loop leaves
  // that rule alone: as root, sessions simply ask before acting.
  if (isRoot(s))
    flags = flags
      .replace(/--dangerously-skip-permissions/g, '')
      .replace(/ +/g, ' ')
      .trim();
  const name = String(o.name || '')
    .replace(/[^A-Za-z0-9 ._-]/g, '')
    .trim();
  // With the Remote Control switch on, the session starts connected to claude.ai.
  const label = String(o.title || o.name || '')
    .replace(/[^A-Za-z0-9 ._-]/g, '')
    .trim();
  if (o.remote) flags = `${flags} --remote-control ${quote(label || 'Loop')}`.trim();
  const start = flags ? `claude ${flags}` : 'claude';
  const claude = o.kind === 'resume' ? `${start} --resume ${o.sessionId}` : `${start} --session-id ${o.sessionId}${name ? ` -n ${quote(name)}` : ''}`;
  // If Claude Code stops with an error, keep the screen up long enough to read it.
  const held = `${claude} || { echo; echo Claude Code stopped with an error, shown above.; sleep 20; }`;
  const t = tmuxName(o.sessionId);
  const cd = where ? `cd ${quote(where)} || { echo; echo That folder does not exist on the server.; sleep 4; exit 1; }; ` : '';
  // With tmux the session outlives this connection; opening the tab again reattaches to it.
  // The clipboard options let a copy made in the session reach this PC's clipboard.
  const inTmux = `tmux has-session -t ${t} 2>/dev/null || tmux -u new-session -d -s ${t} -x 200 -y 50 ${quote(held)}; tmux set-option -t ${t} status off >/dev/null 2>&1; tmux set-option -t ${t} mouse on >/dev/null 2>&1; tmux set-option -s set-clipboard on >/dev/null 2>&1; tmux set-option -t ${t} allow-passthrough on >/dev/null 2>&1; exec tmux -u attach -t ${t}`;
  return `${ssh} ${arg(asUser(s, `${path$}; ${cd}if command -v tmux >/dev/null 2>&1; then ${inTmux}; else exec ${claude}; fi`))}`;
}

// `asLogin` runs it as whoever SSH logs in as, not as the user chosen for sessions.
function run(s, command, timeout = 20000, asLogin = false) {
  return new Promise((resolve) => {
    execFile(SSH, [...sshArgs(s, false), target(s), asLogin ? command : asUser(s, command)], { windowsHide: true, timeout }, (error, stdout, stderr) =>
      resolve({ ok: !error, out: String(stdout || ''), err: String(stderr || '') }),
    );
  });
}

// Ask the server right now whether Claude Code is there and signed in. The
// regular reports only look every half minute or so, which is too slow right
// after an install or a sign-in.
async function probe(id) {
  const entry = state.get(id);
  if (!entry) return null;
  const r = await run(
    entry.server,
    `${REMOTE_PATH}; echo "@@TOOLS $(command -v claude >/dev/null 2>&1 && claude --version 2>/dev/null | head -n1 || echo none)|$(command -v tmux >/dev/null 2>&1 && echo yes || echo no)|$(whoami)|$(hostname)"; echo "@@USERS $(awk -F: '($3==0||($3>=1000&&$3<60000))&&$7!~/(nologin|false)$/{printf "%s,",$1}' /etc/passwd 2>/dev/null)"; echo "@@AUTH $(claude auth status --json 2>/dev/null | tr -d '\n')"`,
    25000,
  );
  const lines = r.out
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('@@'));
  if (lines.length) {
    digest(entry, lines);
    onChange();
  }
  return { id, ...entry.status };
}

// What SSH will really use for a server once your SSH config is applied: the
// address behind a short name, the user, the port and the key file.
function resolve(s) {
  return new Promise((done) => {
    if (!valid({ ...s, id: s.id || 'x' })) return done(null);
    const args = ['-G', ...(s.port ? ['-p', String(Number(s.port))] : []), ...(s.key ? ['-i', s.key] : []), target(s)];
    execFile(SSH, args, { windowsHide: true, timeout: 8000 }, (_e, out) => {
      const text = String(out || '');
      const one = (k) => (new RegExp('^' + k + ' (.+)$', 'mi').exec(text) || [])[1] || '';
      // Without a key of its own SSH lists every default name; keep the first that exists.
      const keys = [...text.matchAll(/^identityfile (.+)$/gim)].map((m) => path.normalize(m[1].trim().replace(/^~(?=[\\/])/, os.homedir())));
      done({ host: one('hostname').trim(), user: one('user').trim(), port: one('port').trim(), key: keys.find((k) => fs.existsSync(k)) || '' });
    });
  });
}

const okPath = (p) => typeof p === 'string' && p.length < 1000 && /^[^'"\r\n%!]*$/.test(p);

// Browsing folders means many small questions, and a fresh SSH login for each
// takes seconds. So the first question opens one extra connection that stays up
// for a couple of minutes and answers the rest at once.
function ask(entry, command, limit = 20000) {
  return new Promise((resolve) => {
    let sh = entry.shell;
    if (!sh || sh.dead) {
      let proc;
      try {
        proc = spawn(SSH, [...sshArgs(entry.server, false), target(entry.server), shellAs(entry.server)], { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
      } catch {
        return resolve(null);
      }
      sh = entry.shell = { proc, buf: '', waiting: [], n: 0, dead: false, idle: null };
      const me = sh;
      const end = () => {
        me.dead = true;
        clearTimeout(me.idle);
        me.waiting.splice(0).forEach((w) => w.done(null));
      };
      proc.on('error', end);
      proc.on('close', end);
      proc.stdin.on('error', () => {});
      proc.stdout.on('data', (d) => {
        me.buf += d;
        while (me.waiting.length) {
          const w = me.waiting[0];
          const i = me.buf.indexOf(w.mark);
          if (i < 0) return;
          const out = me.buf.slice(0, i);
          me.buf = me.buf.slice(i + w.mark.length + 1);
          me.waiting.shift();
          w.done(out);
        }
        me.buf = '';
      });
      proc.stdin.write(REMOTE_PATH + '\n');
    }
    const mark = `@@DONE${++sh.n}@@`;
    const proc = sh.proc;
    const late = setTimeout(() => proc.kill(), limit);
    sh.waiting.push({
      mark,
      done: (out) => {
        clearTimeout(late);
        resolve(out);
      },
    });
    // In a subshell, so one question's cd does not move the next one.
    proc.stdin.write(`( ${command} ) 2>/dev/null </dev/null\necho '${mark}'\n`);
    clearTimeout(sh.idle);
    sh.idle = setTimeout(() => proc.kill(), Math.max(120000, limit + 10000));
  });
}

// A new SSH connection to this server takes seconds, so one is kept open and
// ready: reading a conversation then costs milliseconds instead of a login.
function keepWarm(entry) {
  clearInterval(entry.warm);
  const poke = () => {
    if (!state.has(entry.server.id)) return clearInterval(entry.warm);
    ask(entry, ':', 15000);
  };
  poke();
  entry.warm = setInterval(poke, 60000);
}

// The folders inside one folder on the server, for choosing where a session works.
// A folder that cannot be opened falls back to the home folder, and says so.
async function listDir(id, dir) {
  const entry = state.get(id);
  if (!entry || !okPath(dir)) return null;
  const text = await ask(
    entry,
    `${dir ? `cd -- ${quote(dir)} 2>/dev/null || { echo @@NO; cd; }` : 'cd'}; echo "@@PWD $(pwd)"; echo "@@HOME $HOME"; [ -e .git ] && echo @@GIT; ls -1p 2>/dev/null | grep '/$' | head -n 400`,
  );
  if (!text || !text.includes('@@PWD ')) return null;
  const out = { path: '', home: '', git: false, missing: false, dirs: [] };
  for (const raw of text.split('\n')) {
    const line = raw.replace(/\r$/, '');
    if (line === '@@NO') out.missing = true;
    else if (line === '@@GIT') out.git = true;
    else if (line.startsWith('@@PWD ')) out.path = line.slice(6);
    else if (line.startsWith('@@HOME ')) out.home = line.slice(7);
    else if (line.endsWith('/')) out.dirs.push(line.slice(0, -1));
  }
  return out;
}

// Make a folder on the server (and any missing ones above it); gives back its full path.
async function makeDir(id, dir) {
  const entry = state.get(id);
  if (!entry || !dir || !okPath(dir)) return null;
  const text = await ask(entry, `mkdir -p -- ${quote(dir)} && cd -- ${quote(dir)} && pwd`);
  return (text || '').trim().split('\n').pop() || null;
}

// Get a project onto the server the proper way: the server clones it from git
// itself, with its own access. Nothing is copied up from this PC.
async function clone(id, dir, url) {
  const entry = state.get(id);
  url = String(url || '').trim();
  if (!/^(https:\/\/|ssh:\/\/|git@)[A-Za-z0-9@:/._~+-]+$/.test(url)) return { ok: false, error: 'That does not look like a git address.' };
  const name = url.replace(/\/+$/, '').replace(/\.git$/, '').split(/[/:]/).pop();
  if (!/^[A-Za-z0-9._-]+$/.test(name) || name.startsWith('.')) return { ok: false, error: 'That does not look like a git address.' };
  if (!entry || !dir || !okPath(dir)) return { ok: false, error: 'That server or folder cannot be used.' };
  const ssh = `GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new'`;
  const text = await ask(
    entry,
    `cd -- ${quote(dir)} && { [ -e ${quote(name)} ] && echo @@THERE || { command -v git >/dev/null || echo @@NOGIT; GIT_TERMINAL_PROMPT=0 ${ssh} git clone --quiet -- ${quote(url)} ${quote(name)} 2>&1 && echo @@OK; }; }`,
    180000,
  );
  const path$ = `${dir.replace(/\/$/, '')}/${name}`;
  if (text === null) return { ok: false, error: 'The server did not finish in time.' };
  if (text.includes('@@THERE')) return { ok: true, path: path$, existed: true };
  if (text.includes('@@OK')) return { ok: true, path: path$ };
  if (text.includes('@@NOGIT')) return { ok: false, error: 'git is not installed on the server.' };
  const last = text.trim().split('\n').filter((l) => !l.startsWith('@@')).pop() || '';
  return {
    ok: false,
    error: /Permission denied|Authentication failed|could not read Username|terminal prompts disabled|Repository not found/i.test(text)
      ? 'The server is not allowed to read that repository. Give the server read access (a read-only deploy key is the usual way), then try again.'
      : last.slice(0, 200) || 'The clone failed.',
  };
}

// ---- Remote Control for a session on a server ----
// The same housekeeping remote.js does for local sessions, done over there:
// find the copy on claude.ai a session points at, the login that owns it, and
// close the marker so a resume does not reconnect it.
const bridgeFiles = (sessionId) => `for f in "$HOME"/.claude/projects/*/${sessionId}.jsonl; do [ -f "$f" ] || continue`;

async function remotePointer(id, sessionId) {
  const entry = state.get(id);
  if (!entry || !UUID_RE.test(sessionId || '')) return null;
  const text = await ask(entry, `${bridgeFiles(sessionId)}; tail -c 2000000 "$f" | grep -a '^{"type":"bridge-session"' | tail -n 1; done`);
  const line = (text || '').split('\n').filter((l) => l.startsWith('{"type":"bridge-session"')).pop();
  try {
    const cse = JSON.parse(line).bridgeSessionId || '';
    return /^cse_[A-Za-z0-9]{8,64}$/.test(cse) ? cse : null;
  } catch {
    return null;
  }
}

// The server's Claude login, read for one call from this PC and never kept.
async function remoteLogin(id) {
  const entry = state.get(id);
  if (!entry) return null;
  const text = await ask(entry, `cat "$HOME"/.claude/.credentials.json; echo; echo @@ORG; grep -o '"organizationUuid": *"[^"]*"' "$HOME"/.claude.json | head -n 1`);
  try {
    const [creds, org] = (text || '').split('@@ORG');
    const c = JSON.parse(creds.slice(creds.indexOf('{'))).claudeAiOauth;
    const uuid = (/"organizationUuid": *"([^"]+)"/.exec(org) || [])[1];
    return c && c.accessToken && uuid ? { token: c.accessToken, org: uuid, expired: Boolean(c.expiresAt && c.expiresAt < Date.now()) } : null;
  } catch {
    return null;
  }
}

async function remoteClose(id, sessionId) {
  const entry = state.get(id);
  if (!entry || !UUID_RE.test(sessionId || '')) return;
  const line = JSON.stringify({ type: 'bridge-session', sessionId, bridgeSessionId: '', lastSequenceNum: 0 });
  await ask(entry, `${bridgeFiles(sessionId)}; [ -n "$(tail -c 1 "$f")" ] && echo >> "$f"; printf '%s\\n' '${line}' >> "$f"; done`);
}

// Make a normal user on the server for sessions to run as. It gets a home
// folder and a shell and nothing more: no password, no admin rights.
async function addUser(id, name) {
  const entry = state.get(id);
  name = String(name || '').trim();
  if (!entry) return { ok: false, error: 'That server was removed.' };
  if (!USER_RE.test(name) || name === 'root') return { ok: false, error: 'Use lowercase letters, digits, dashes and underscores, starting with a letter.' };
  const make = `useradd -m -s /bin/bash ${name}`;
  const r = await run(entry.server, `if id ${name} >/dev/null 2>&1; then echo @@THERE; elif [ $(id -u) = 0 ]; then ${make} 2>&1 && echo @@OK; else sudo -n ${make} 2>&1 && echo @@OK; fi`, 30000, true);
  if (r.out.includes('@@THERE') || r.out.includes('@@OK')) return { ok: true, existed: r.out.includes('@@THERE') };
  const last = (r.out + r.err).trim().split('\n').pop() || '';
  return { ok: false, error: /password is required|not allowed|Permission denied/i.test(r.out + r.err) ? 'The login user is not allowed to add users on that server.' : last.slice(0, 200) || 'The server did not answer.' };
}

// Stop a session that is running on the server, tab or no tab.
// What counts is that it is gone afterwards, whether or not it was still there to stop.
// A session the phone woke runs with no tmux at all, so it is also found by its
// own record there and ended.
const stopSession = (s, sessionId) => {
  if (!UUID_RE.test(sessionId || '')) return Promise.resolve({ ok: false });
  const t = tmuxName(sessionId);
  const mine = `for f in "$HOME"/.claude/sessions/*.json; do [ -f "$f" ] || continue; grep -q '"sessionId":"${sessionId}"' "$f" || continue; p=\${f##*/}; echo \${p%.json}; done`;
  return run(
    s,
    `tmux kill-session -t ${t} 2>/dev/null; for p in $(${mine}); do kill $p 2>/dev/null; done; sleep 1; for p in $(${mine}); do kill -0 $p 2>/dev/null && kill -9 $p 2>/dev/null; done; ! tmux has-session -t ${t} 2>/dev/null`,
  );
};

// The tail of what one background task printed on the server. Only Claude
// Code's own task output files are read, and the path comes from the session's
// own conversation, never from the phone.
async function readTaskOut(id, file) {
  const entry = state.get(id);
  const f = String(file || '');
  if (!entry || !/^[-\w./]+\/tasks\/[A-Za-z0-9_-]+\.output$/.test(f)) return { text: '', cut: false };
  const text = await ask(entry, `tail -c 60000 "${f}" 2>/dev/null`, 20000);
  return { text: String(text || ''), cut: false };
}

// The new part of a session's conversation file on the server, for the phone's
// chat. `from` is how much was read before; below zero means "the last part".
async function readTranscript(id, dir, sessionId, from) {
  const entry = state.get(id);
  if (!entry || !/^[A-Za-z0-9_-]+$/.test(String(dir)) || !UUID_RE.test(String(sessionId))) return null;
  // Loop names a server's project "srv-<server>-<folder>" to keep it apart
  // from the PC's own; on the server the folder is just <folder>.
  const mine = `srv-${entry.server.id}-`.replace(/[^A-Za-z0-9_-]/g, '-');
  const there = String(dir).startsWith(mine) ? String(dir).slice(mine.length) : String(dir);
  const f = `"$HOME/.claude/projects/${there}/${sessionId}.jsonl"`;
  // The phone shows the last hundred or so messages. Asking for the last
  // lines, rather than the last megabytes, gets those messages whole however
  // long one of them is, and pulls far less across the link.
  const first = !(from >= 0);
  const tail = first ? `tail -n 220 ${f} | tail -c 2000000` : `tail -c +${Number(from) + 1} ${f} | head -c 3000000`;
  const text = await ask(
    entry,
    `s=$(stat -c %s ${f} 2>/dev/null || echo 0); echo "@@SIZE $s"; if [ "$s" -gt ${first ? 0 : Number(from)} ]; then ${tail}; fi`,
    30000,
  );
  if (text == null) return null;
  const nl = text.indexOf('\n');
  const size = Number((/@@SIZE (\d+)/.exec(text.slice(0, nl)) || [])[1] || 0);
  const body = text.slice(nl + 1);
  // Less than the whole file: the app offers "Earlier" for the rest.
  return { size, text: body, cut: first && Buffer.byteLength(body) < size };
}

// Put one picture from the phone on the server, where its session can read it.
// A phone photo is megabytes, and this PC's link out may be a phone's hotspot:
// it is made about as large as Claude will look at (1600px, JPEG) and then
// sent as it is over its own SSH connection, which takes seconds. (Typed into
// the shell as text it took most of a minute, and often timed out.)
let nativeImage = null;
try {
  nativeImage = require('electron').nativeImage || null;
} catch {
  nativeImage = null;
}
function smaller(buf, name) {
  if (!nativeImage || buf.length < 300 * 1024) return { buf, name };
  try {
    let img = nativeImage.createFromBuffer(buf);
    if (img.isEmpty()) return { buf, name };
    const { width, height } = img.getSize();
    if (Math.max(width, height) > 1600) img = img.resize(width >= height ? { width: 1600, quality: 'good' } : { height: 1600, quality: 'good' });
    const out = img.toJPEG(85);
    return out.length < buf.length ? { buf: out, name: name.replace(/\.[a-z]+$/i, '.jpg') } : { buf, name };
  } catch {
    return { buf, name };
  }
}

async function putUpload(id, file, onProgress = () => {}) {
  // A connection that drops part way is tried once more from the start.
  return (await putOnce(id, file, onProgress)) || putOnce(id, file, onProgress);
}

async function putOnce(id, file, onProgress) {
  const entry = state.get(id);
  const base = path.basename(String(file || ''));
  if (!entry || !/^phone-[\w-]+\.(png|jpe?g|gif|webp|bmp)$/i.test(base)) return null;
  let raw;
  try {
    raw = fs.readFileSync(file);
  } catch {
    return null;
  }
  const { buf, name } = smaller(raw, base);
  const dest = `"$HOME/.loop-uploads/${name}"`;
  // Pictures there are cleared after a day, as on the PC.
  const script = `mkdir -p "$HOME/.loop-uploads" && cat > ${dest} && echo "@@PUT $HOME/.loop-uploads/${name}"; find "$HOME/.loop-uploads" -type f -mtime +1 -delete 2>/dev/null`;
  return new Promise((resolve) => {
    let out = '';
    let proc;
    try {
      proc = spawn(SSH, [...sshArgs(entry.server, false), target(entry.server), asUser(entry.server, script)], { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
    } catch {
      return resolve(null);
    }
    const late = setTimeout(() => proc.kill(), 120000);
    proc.stdout.on('data', (d) => (out += d));
    proc.stdin.on('error', () => {});
    proc.on('error', () => {});
    proc.on('close', () => {
      clearTimeout(late);
      const there = (/@@PUT (\S+)/.exec(out) || [])[1] || null;
      if (there) onProgress(1);
      resolve(there);
    });
    // In pieces, so how far it has got can be told; each waits for the last to drain.
    const PIECE = 16 * 1024;
    let at = 0;
    const more = () => {
      while (at < buf.length) {
        const piece = buf.subarray(at, at + PIECE);
        at += piece.length;
        onProgress(Math.min(0.97, at / buf.length));
        if (!proc.stdin.write(piece)) return proc.stdin.once('drain', more);
      }
      proc.stdin.end();
    };
    more();
  });
}

// What to start for a session that runs on the server in the background, the
// way one on this PC does: Claude Code taking messages as JSON, reached over
// SSH. Its standard input and output are the SSH connection's, so closing the
// connection ends it.
function directSpawn(id, o, settings) {
  const entry = state.get(id);
  if (!entry || !UUID_RE.test(String(o.sessionId || '')) || !okPath(o.cwd || '')) return null;
  const s = entry.server;
  let flags = String(settings.flags || '').replace(/['"%!\r\n;&|<>`$\\]/g, '');
  // As root, Claude Code will not skip permission prompts. Auto mode is the
  // nearest it allows: safe steps go ahead, and what it judges risky still
  // comes to the phone as a question.
  if (isRoot(s) && /--dangerously-skip-permissions/.test(flags)) {
    flags = flags.replace(/--dangerously-skip-permissions/g, '--permission-mode auto').replace(/ +/g, ' ').trim();
  }
  const claude = [
    'claude -p',
    '--input-format stream-json --output-format stream-json --verbose --include-partial-messages',
    '--permission-prompt-tool stdio',
    flags,
    `${o.fresh ? '--session-id' : '--resume'} ${o.sessionId}`,
  ]
    .filter(Boolean)
    .join(' ');
  // Not waiting for every tool server before reading the message, as on the PC.
  const script = `${REMOTE_PATH}; export CLAUDE_CODE_MCP_STARTUP_WAIT_MS=0; cd ${quote(o.cwd)} || exit 3; exec ${claude}`;
  return { cmd: SSH, args: [...sshArgs(s, false), target(s), asUser(s, script)] };
}

// Whether a session is running on the server right now, by its own record there.
async function runningThere(id, sessionId) {
  const entry = state.get(id);
  if (!entry || !UUID_RE.test(String(sessionId || ''))) return false;
  const out = await ask(entry, `for f in "$HOME"/.claude/sessions/*.json; do [ -f "$f" ] || continue; grep -q '"sessionId":"${sessionId}"' "$f" || continue; p=\${f##*/}; p=\${p%.json}; kill -0 "$p" 2>/dev/null && echo @@YES; done`, 15000);
  return /@@YES/.test(out || '');
}

module.exports = {
  readTaskOut,
  putUpload,
  directSpawn,
  runningThere,
  readTranscript,
  isRoot,
  probe,
  resolve,
  WATCH,
  sync,
  refresh,
  snapshot,
  live,
  get,
  tabCommand,
  stopSession,
  listDir,
  makeDir,
  addUser,
  remotePointer,
  remoteLogin,
  remoteClose,
  asUser,
  clone,
  withLive,
  drop,
  valid,
  tmuxName,
  digest,
  setListener: (fn) => (onChange = fn),
  stopAll: () => [...state.keys()].forEach(drop),
};
