// What differs between Windows and macOS or Linux: which shell a terminal runs,
// how a process is stopped along with everything it started, and how process
// names are listed. Each takes the platform so both sides can be tested anywhere.
const os = require('os');
const { execFile, execFileSync } = require('child_process');

const isWin = (platform = process.platform) => platform === 'win32';

// The user's own shell, else the one the system starts by default.
function userShell(env = process.env, platform = process.platform) {
  if (isWin(platform)) return env.ComSpec || 'cmd.exe';

  return env.SHELL || (platform === 'darwin' ? '/bin/zsh' : '/bin/bash');
}

// The program and arguments for a terminal. The command travels in
// SESSION_DECK_RUN, which the shell expands itself.
// once: the terminal ends with the command; otherwise it drops back to a prompt.
function terminal(command, once, env = process.env, platform = process.platform) {
  const file = userShell(env, platform);

  // /s makes cmd strip exactly the outer quotes, so quoted paths inside survive.
  if (isWin(platform)) return { file, args: command ? `/s ${once ? '/c' : '/k'} "%SESSION_DECK_RUN%"` : [] };

  // A login, interactive shell reads the same profile a terminal app does, so
  // claude and the user's tools are on the PATH. Afterwards a fresh prompt takes over.
  if (!command) return { file, args: ['-l'] };

  const run = 'eval "$SESSION_DECK_RUN"';

  return { file, args: ['-l', '-i', '-c', once ? run : `${run}; exec "$SHELL" -l`] };
}

// A script handed to the terminal's shell as one argument: inside double quotes
// for cmd, single quotes elsewhere so $ and backticks reach the far side untouched.
function shellArg(script, platform = process.platform) {
  if (isWin(platform)) return `"${script}"`;

  return `'${String(script).replace(/'/g, `'\\''`)}'`;
}

// Every process under pid, deepest first, from `ps` output of "pid ppid" lines.
function descendants(pid, psOut) {
  const kids = new Map();
  for (const line of String(psOut).split('\n')) {
    const m = /^\s*(\d+)\s+(\d+)/.exec(line);
    if (!m) continue;
    const parent = Number(m[2]);
    if (!kids.has(parent)) kids.set(parent, []);
    kids.get(parent).push(Number(m[1]));
  }

  const out = [];
  const seen = new Set();
  const walk = (p) => {
    for (const k of kids.get(p) || []) {
      // ps reads one process at a time, so a pid reused meanwhile could loop back
      if (seen.has(k)) continue;
      seen.add(k);
      walk(k);
      out.push(k);
    }
  };
  walk(Number(pid));

  return out;
}

// Stop a process and everything it started, the way taskkill /T does.
function killTree(pid, platform = process.platform) {
  if (!pid) return;

  if (isWin(platform)) {
    execFile('taskkill', ['/F', '/T', '/PID', String(pid)], () => {});
    return;
  }

  execFile('ps', ['-A', '-o', 'pid=,ppid='], (err, out) => {
    const all = err ? [] : descendants(pid, out);
    for (const p of [...all, Number(pid)]) {
      try {
        process.kill(p, 'SIGKILL');
      } catch {
        // already gone
      }
    }
  });
}

// The name a process was started as: "claude", or "node cli.js" for a script.
// Claude Code's own binary file is named after its version (2.1.3), so the file
// name the system reports is no use; how it was started says "claude".
function startedAs(args) {
  const [prog = '', script = ''] = String(args).trim().split(/\s+/);
  const name = prog.split('/').pop();

  return /^(node|bun)$/.test(name) && script ? `${name} ${script.split('/').pop()}` : name;
}

// pid -> lower-case program name, for every process on this machine.
function parseProcessList(stdout, platform = process.platform) {
  const names = new Map();
  for (const line of String(stdout).split(/\r?\n/)) {
    const m = isWin(platform) ? /^"([^"]+)","(\d+)"/.exec(line) : /^\s*(\d+)\s+(.+?)\s*$/.exec(line);
    if (!m) continue;
    if (isWin(platform)) names.set(Number(m[2]), m[1].toLowerCase());
    else names.set(Number(m[1]), startedAs(m[2]).toLowerCase());
  }

  return names;
}

const processListCommand = (platform = process.platform) => (isWin(platform) ? ['tasklist', ['/FO', 'CSV', '/NH']] : ['ps', ['-A', '-o', 'pid=,args=']]);

// An app opened from the Dock or a desktop menu gets a bare PATH, without the
// folders the user's profile adds (where claude usually is). Ask the login shell once.
function loginPath(platform = process.platform, env = process.env) {
  if (isWin(platform)) return null;

  try {
    const out = execFileSync(userShell(env, platform), ['-l', '-i', '-c', 'printf "@@PATH=%s@@" "$PATH"'], {
      encoding: 'utf8',
      timeout: 5000,
      stdio: ['ignore', 'pipe', 'ignore'],
      cwd: os.homedir(),
    });
    // Marked at both ends: a profile can print before it, and a logout file after.
    const m = /@@PATH=(.*?)@@/s.exec(out);

    return m && m[1].trim() ? m[1].trim() : null;
  } catch {
    return null;
  }
}

module.exports = { isWin, userShell, terminal, shellArg, descendants, killTree, parseProcessList, processListCommand, loginPath };
