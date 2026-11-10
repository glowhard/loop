// The relay: how a browser anywhere reaches a PC that is not on the internet.
//
// The PC dials out and stays connected. A browser connects here instead of to
// the PC, and this passes bytes between the two without reading them. It holds
// nothing: no sessions, no files, no conversation.
//
// Two separate secrets have to line up before anything is joined up:
//
//   the machine token  the PC proves it is the PC. Its fingerprint is listed
//                      in the config file on this server, so no one else can
//                      register a machine here at all.
//   the space key      a browser proves it was given the way in. Only its
//                      fingerprint is kept here, handed over by the PC when it
//                      registers, so this server never stores a usable secret.
//
// Past both of those sits the PC's own pairing code, which this never sees and
// cannot answer for. Someone who steals the space key still has to get past it.
const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT) || 8790;
const CONFIG = process.env.LOOP_RELAY_CONFIG || '/etc/loop-relay.json';
const MAX_FRAME = 16 * 1024 * 1024; // one picture, not a film
const MAX_BROWSERS = 8; // at once, across every machine
const BAD_TRIES = 10; // wrong keys from one address before it is shut out
const SHUT_OUT = 60 * 60 * 1000; // for an hour
const FORGET_TRIES = 10 * 60 * 1000;

const sha = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');

// Comparing secrets must take the same time whether or not they match.
function same(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

function allowed() {
  try {
    const c = JSON.parse(fs.readFileSync(CONFIG, 'utf8'));
    return (Array.isArray(c.machines) ? c.machines : []).map(String);
  } catch {
    return [];
  }
}

const machines = new Map(); // fingerprint -> { ws, keyHash, name, at, pipes }
const tries = new Map(); // address -> { n, at }
// Machines that were here and went away, by their key's fingerprint. A browser
// still holding that key is told the PC is away, not counted as guessing:
// otherwise a phone retrying a PC that is switched off gets shut out of every
// machine within minutes.
const away = new Set();

function knock(ip, ok) {
  const t = tries.get(ip) || { n: 0, at: 0 };
  if (ok) return tries.delete(ip);
  if (Date.now() - t.at > FORGET_TRIES) t.n = 0;
  t.n += 1;
  t.at = Date.now();
  tries.set(ip, t);
  if (tries.size > 5000) tries.clear();
}

const shutOut = (ip) => {
  const t = tries.get(ip);
  return Boolean(t && t.n >= BAD_TRIES && Date.now() - t.at < SHUT_OUT);
};

const where = (req) => String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ ok: true, machines: machines.size }));
  }
  res.writeHead(404).end();
});

const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_FRAME, perMessageDeflate: false });

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, 'http://x');
  const ip = where(req);
  const refuse = (code, why) => {
    socket.write(`HTTP/1.1 ${code} ${why}\r\nConnection: close\r\n\r\n`);
    socket.destroy();
  };
  if (shutOut(ip)) return refuse(429, 'Too Many Requests');

  // ---- the PC, dialling out ----
  if (url.pathname === '/pc') {
    const token = (req.headers.authorization || '').replace(/^Bearer /, '');
    const fingerprint = sha(token);
    if (!token || !allowed().some((m) => same(m, fingerprint))) {
      knock(ip, false);
      return refuse(401, 'Unauthorized');
    }
    knock(ip, true);
    return wss.handleUpgrade(req, socket, head, (ws) => machineHere(ws, fingerprint, url.searchParams.get('name') || 'PC'));
  }

  // ---- a browser, from anywhere ----
  if (url.pathname === '/ws') {
    const key = url.searchParams.get('k') || '';
    const machine = [...machines.values()].find((m) => m.keyHash && same(m.keyHash, sha(key)));
    if (key && !machine && [...away].some((h) => same(h, sha(key)))) return refuse(503, 'Service Unavailable');
    if (!key || !machine) {
      knock(ip, false);
      return refuse(401, 'Unauthorized');
    }
    if ([...machines.values()].reduce((n, m) => n + m.pipes.size, 0) >= MAX_BROWSERS) return refuse(503, 'Busy');
    knock(ip, true);
    return wss.handleUpgrade(req, socket, head, (ws) => browserHere(ws, machine));
  }
  refuse(404, 'Not Found');
});

// A PC has arrived. One machine, one connection: a new one replaces the old.
function machineHere(ws, fingerprint, name) {
  const old = machines.get(fingerprint);
  if (old) {
    for (const p of old.pipes.values()) p.close(1012, 'the PC reconnected');
    try {
      old.ws.close();
    } catch {
      // already gone
    }
  }
  const m = { ws, keyHash: '', name: String(name).slice(0, 40), at: Date.now(), pipes: new Map(), seq: 0 };
  machines.set(fingerprint, m);
  log('machine here', m.name);

  ws.on('message', (data, binary) => {
    if (binary) return;
    const text = data.toString();
    const nl = text.indexOf('\n');
    const head = nl < 0 ? text : text.slice(0, nl);
    // The PC says which space key opens this machine before anything else.
    if (head.startsWith('key ')) {
      m.keyHash = head.slice(4).trim();
      away.delete(m.keyHash);
      return;
    }
    const id = Number(head);
    const pipe = m.pipes.get(id);
    if (!pipe) return;
    if (nl < 0) return pipe.close(1000, 'done');
    pipe.send(text.slice(nl + 1));
  });
  const beat = setInterval(() => ws.ping(), 20000);
  ws.on('close', () => {
    clearInterval(beat);
    if (machines.get(fingerprint) === m) machines.delete(fingerprint);
    if (m.keyHash && ![...machines.values()].some((x) => x.keyHash === m.keyHash)) away.add(m.keyHash);
    for (const p of m.pipes.values()) p.close(1012, 'the PC went away');
    log('machine gone', m.name);
  });
  ws.on('error', () => ws.close());
}

// A browser has arrived, and is joined to its machine.
function browserHere(ws, m) {
  const id = ++m.seq;
  m.pipes.set(id, ws);
  const toPc = (line) => {
    if (m.ws.readyState === m.ws.OPEN) m.ws.send(line);
  };
  toPc(`${id}\n`); // an empty body opens the pipe
  ws.on('message', (data, binary) => {
    if (binary) return;
    toPc(`${id}\n${data.toString()}`);
  });
  const beat = setInterval(() => ws.ping(), 20000);
  ws.on('close', () => {
    clearInterval(beat);
    m.pipes.delete(id);
    toPc(`${id}`); // no newline: the pipe is closed
  });
  ws.on('error', () => ws.close());
}

const log = (...a) => console.log(new Date().toISOString(), ...a);

server.listen(PORT, '127.0.0.1', () => log(`relay listening on 127.0.0.1:${PORT}, ${allowed().length} machine(s) allowed`));
