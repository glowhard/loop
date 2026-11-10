// Runs in its own process and owns every terminal. Starting a process, a burst
// of output or a slow resize can each hold a thread for a while; here that
// costs the window nothing, because the window lives in another process.
const pty = require('@lydell/node-pty');
const shell = require('./shell');

// If the app itself was started from inside a Claude Code session, these
// would make the sessions we launch think they are its children.
const INHERITED = [
  'CLAUDECODE',
  'CLAUDE_PID',
  'CLAUDE_CODE_ENTRYPOINT',
  'CLAUDE_CODE_CHILD_SESSION',
  'CLAUDE_CODE_MESSAGING_SOCKET',
  'CLAUDE_CODE_MESSAGING_TOKEN',
  'CLAUDE_CODE_SESSION_ID',
  'CLAUDE_CODE_SESSION_ATTENDED',
];

const ptys = new Map(); // tab id -> { proc, queue, timer }
const post = (m) => process.parentPort.postMessage(m);

function open(o) {
  if (ptys.has(o.id)) return;
  const env = { ...process.env, ...o.env };
  for (const k of INHERITED) delete env[k];
  // Started with npm start, npm's own settings would follow into every terminal,
  // where nvm, for one, refuses to load.
  for (const k of Object.keys(env)) if (/^npm_/i.test(k)) delete env[k];
  // A NO_COLOR left in the environment the app was started from would turn every
  // session black and white. These terminals always do full colour.
  delete env.NO_COLOR;
  delete env.FORCE_COLOR;
  env.COLORTERM = 'truecolor';
  // The command travels in a variable that the shell expands itself. With the full
  // command on cmd's own command line, Windows held the launch for up to five
  // seconds per session while it checked a command line it had never seen; a
  // fixed command line is let through at once.
  if (o.command) env.SESSION_DECK_RUN = o.command;
  const { file, args } = shell.terminal(o.command, o.once, env);
  if (!shell.isWin()) env.SHELL = env.SHELL || file;
  const proc = pty.spawn(file, args, {
    name: 'xterm-256color',
    cols: Math.max(20, o.cols || 120),
    rows: Math.max(5, o.rows || 30),
    cwd: o.cwd,
    env,
  });
  const entry = { proc, queue: '', timer: null };
  ptys.set(o.id, entry);

  // Coalesce bursts so a busy session does not flood the window with messages.
  const flush = () => {
    entry.timer = null;
    if (entry.queue) post({ t: 'data', id: o.id, d: entry.queue });
    entry.queue = '';
  };
  proc.onData((d) => {
    entry.queue += d;
    if (!entry.timer) entry.timer = setTimeout(flush, 8);
  });
  proc.onExit(() => {
    if (entry.timer) clearTimeout(entry.timer);
    flush();
    // A closed tab can be reopened under the same id; only report our own exit.
    if (ptys.get(o.id) === entry) ptys.delete(o.id);
    post({ t: 'exit', id: o.id });
  });
}

// Stopping a terminal: asking it to go, or insisting. Asking lets Claude Code
// write down where it got to; insisting is for one that will not listen.
function kill(id, force) {
  const e = ptys.get(id);
  if (!e) return;
  ptys.delete(id);
  try {
    if (force && e.proc.pid) shell.killTree(e.proc.pid);
    else e.proc.kill();
  } catch {
    // already gone
  }
}

process.parentPort.on('message', ({ data: m }) => {
  const e = ptys.get(m.id);
  try {
    if (m.t === 'open') open(m);
    else if (m.t === 'write') e && e.proc.write(m.d);
    else if (m.t === 'resize') e && m.cols > 1 && m.rows > 1 && e.proc.resize(Math.floor(m.cols), Math.floor(m.rows));
    // The window is behind on drawing this terminal: stop reading from the
    // process until it catches up, so output cannot pile up without limit.
    else if (m.t === 'flow') e && (m.hold ? e.proc.pause() : e.proc.resume());
    else if (m.t === 'kill') kill(m.id, m.force);
    else if (m.t === 'killAll') for (const id of [...ptys.keys()]) kill(id);
  } catch (err) {
    if (m.t === 'open') {
      post({ t: 'data', id: m.id, d: `\x1b[31mCould not start this terminal.\x1b[0m\r\n${err.message}\r\n` });
      post({ t: 'exit', id: m.id });
    }
    // anything else: the process exited between the check and the call
  }
});
