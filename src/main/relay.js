// Reaching this PC from an ordinary web address.
//
// The bridge waits to be called, which only works where the phone can see this
// machine: on your own network, or over your tailnet. To work from anywhere,
// this dials out to a relay you run and stays connected. The relay passes
// bytes between a browser and here, and each browser it sends becomes an
// ordinary connection to the bridge on this PC: nothing about the bridge
// changes, and the relay never sees past it.
//
// Two secrets live here. The machine token says this PC is itself; the space
// key is what a browser must have, and the relay is told only its fingerprint.
// Both are made here and never leave except to the relay.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

const RETRY = [1000, 2000, 5000, 10000, 20000, 30000]; // a dropped relay is tried again
let conf = null; // { url, token, key, name }
let ws = null;
let pipes = new Map(); // id -> the connection into our own bridge
let tries = 0;
let timer = null;
let stopped = true;
let onChange = () => {};
let status = { on: false, why: '' };

const fingerprint = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');

const newSecret = () => crypto.randomBytes(32).toString('base64url');

/// What a browser is given: the page, the key in the part after the #, and
/// the PC's own address so the page can try the short way first.
let direct = '';
const setDirect = (where) => (direct = String(where || ''));

function link(c = conf) {
  if (!c || !c.url || !c.key) return '';
  const page = c.url.replace(/^wss?:/, 'https:').replace(/\/(pc|ws)$/, '');
  return `${page}/#k=${c.key}${direct ? `&d=${direct}` : ''}`;
}

function tell() {
  onChange({ ...status, link: link() });
}

function stop() {
  stopped = true;
  clearTimeout(timer);
  timer = null;
  for (const p of pipes.values()) p.close();
  pipes = new Map();
  if (ws) {
    try {
      ws.close();
    } catch {
      // already closing
    }
  }
  ws = null;
  status = { on: false, why: '' };
  tell();
}

// Its own settings file: these belong to this machine, not to the window's
// config, and the secrets in them are not for anything else to carry around.
let file = '';

function init(userData) {
  file = path.join(userData, 'relay.json');
}

function settings() {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function save(o) {
  try {
    fs.writeFileSync(file, JSON.stringify(o || null, null, 2), { mode: 0o600 });
  } catch {
    // nowhere to keep it; it lasts until Loop closes
  }
}

/// Turn it on or off, or change where it dials. Secrets missing are made here.
function set(o, bridgePort) {
  const was = settings() || {};
  const want =
    o && o.on
      ? {
          on: true,
          url: String(o.url || was.url || '').trim(),
          name: String(o.name || was.name || '').slice(0, 40),
          token: o.fresh || !was.token ? newSecret() : was.token,
          key: o.fresh || !was.key ? newSecret() : was.key,
        }
      : null;
  save(want);
  return sync(bridgePort);
}

/// Start, or start again, from what is on file.
function sync(bridgePort) {
  const want = settings();
  const live = want && want.on && want.url ? want : null;
  const same = JSON.stringify(live) === JSON.stringify(conf);
  conf = live;
  if (bridgePort) port = bridgePort;
  if (!live) {
    stop();
    return null;
  }
  if (!same || stopped) {
    stop();
    stopped = false;
    connect();
  }
  return live;
}

let port = 8787;

function connect() {
  if (stopped || !conf) return;
  clearTimeout(timer);
  const where = conf.url.replace(/^https?:/, (m) => (m === 'https:' ? 'wss:' : 'ws:')).replace(/\/$/, '');
  let socket;
  try {
    socket = new WebSocket(`${where}/pc?name=${encodeURIComponent(conf.name || 'PC')}`, {
      headers: { authorization: `Bearer ${conf.token}` },
      handshakeTimeout: 15000,
      perMessageDeflate: false,
    });
  } catch (e) {
    return later(e.message);
  }
  ws = socket;
  socket.on('open', () => {
    tries = 0;
    status = { on: true, why: '' };
    // The relay is told what a browser must present, never the key itself.
    socket.send(`key ${fingerprint(conf.key)}`);
    tell();
  });
  socket.on('message', (data, binary) => {
    if (binary || socket !== ws) return;
    const text = data.toString();
    const nl = text.indexOf('\n');
    const id = Number(nl < 0 ? text : text.slice(0, nl));
    if (!Number.isFinite(id)) return;
    if (nl < 0) return shut(id); // the browser went away
    const body = text.slice(nl + 1);
    if (!pipes.has(id)) open(id);
    const p = pipes.get(id);
    if (!p || !body) return;
    if (p.readyState === WebSocket.OPEN) p.send(body);
    else p.waiting.push(body);
  });
  socket.on('close', () => socket === ws && later('The relay closed the connection.'));
  socket.on('error', (e) => socket === ws && later(e.message));
}

// One browser, as an ordinary connection to the bridge on this PC.
function open(id) {
  const p = new WebSocket(`ws://127.0.0.1:${port}/ws`, { perMessageDeflate: false });
  p.waiting = [];
  pipes.set(id, p);
  p.on('open', () => {
    for (const m of p.waiting.splice(0)) p.send(m);
  });
  p.on('message', (data, binary) => {
    if (binary) return;
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(`${id}\n${data.toString()}`);
  });
  p.on('close', () => {
    pipes.delete(id);
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(`${id}`);
  });
  p.on('error', () => p.close());
}

function shut(id) {
  const p = pipes.get(id);
  pipes.delete(id);
  if (p) p.close();
}

function later(why) {
  if (stopped) return;
  for (const p of pipes.values()) p.close();
  pipes = new Map();
  ws = null;
  status = { on: false, why: String(why || '').slice(0, 200) };
  tell();
  const wait = RETRY[Math.min(tries++, RETRY.length - 1)];
  clearTimeout(timer);
  timer = setTimeout(connect, wait);
}

module.exports = {
  setDirect,
  init,
  set,
  settings,
  sync,
  stop,
  link,
  newSecret,
  state: () => ({ ...status, link: link() }),
  setListener: (fn) => (onChange = fn),
  _test: { fingerprint },
};
