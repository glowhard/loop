// Voice mode: one session you talk to and that answers out loud.
//
// This side owns the speech process (voice-host.js) and turns what a session
// writes into something worth hearing. The window owns the microphone, the
// playing and the deciding when the user is talking, because the echo of the
// speakers is only cancelled for sound the window itself plays.
'use strict';

const path = require('path');
const fs = require('fs');
const { spawn, spawnSync } = require('child_process');

// How a session is told to answer while someone is listening rather than
// reading. Sent once, when voice mode starts on that session.
const VOICE_RULES = [
  'Voice mode is on: the user is speaking to you and your answer is read out loud by a voice.',
  'Answer in one or two short spoken sentences, the way you would say it to someone beside you. Put the answer first.',
  'Never read code, file paths, URLs, commands, lists or headings aloud. Say "it is on screen" and leave them in your reply for the screen to show.',
  'No markdown, no bullet points, no numbering, no emoji in what you say.',
  'Before a long piece of work, say in one line what you are about to do, then do it.',
  'When the work is done, say what changed in a sentence, not a report.',
  'If you did not catch something, ask for it in one short question.',
].join('\n');

// ---------- what is worth saying out loud ----------

const SPOKEN_MAX = 420; // past this it is a report, not a sentence

// Things that are to be read, not heard.
const stripForSpeech = (text) =>
  String(text || '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`]*`/g, ' ')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/https?:\/\/\S+/g, ' ')
    .replace(/\b[A-Za-z]:\\[^\s'"]+/g, ' ')
    .replace(/(^|\s)[~.]?\/[^\s'"]{2,}/g, ' ')
    .replace(/^\s{0,3}#{1,6}\s*/gm, '')
    .replace(/^\s{0,3}[-*+]\s+/gm, '')
    .replace(/^\s{0,3}\d{1,2}[.)]\s+/gm, '')
    .replace(/[*_]{1,2}([^*_]+)[*_]{1,2}/g, '$1')
    .replace(/[|─━┃│]+/g, ' ')
    .replace(/[ \t]+/g, ' ')
    .replace(/\s*\n\s*/g, '\n')
    .trim();

/** Split into sentences, so the first words can be spoken while the rest is made. */
function sentences(text) {
  const out = [];
  for (const line of String(text || '').split('\n')) {
    const t = line.trim();
    if (!t) continue;
    const parts = t.match(/[^.!?]+[.!?]+(\s|$)|[^.!?]+$/g) || [t];
    for (const p of parts) {
      const s = p.trim();
      if (s) out.push(s);
    }
  }
  return out;
}

/**
 * What the voice should say for one thing a session wrote: its own words with
 * everything that only makes sense on a screen taken out, cut to a couple of
 * sentences. Empty when there is nothing left worth hearing.
 */
function speakable(text) {
  const clean = stripForSpeech(text);
  if (!clean) return '';
  const said = sentences(clean);
  if (!said.length) return '';
  let out = '';
  for (const s of said) {
    // Keep whole sentences, and stop once it is long enough to be heard.
    if (out && (out + ' ' + s).length > SPOKEN_MAX) break;
    out = out ? out + ' ' + s : s;
    if (out.length >= SPOKEN_MAX) break;
  }
  if (out.length > SPOKEN_MAX) out = out.slice(0, SPOKEN_MAX).replace(/\s+\S*$/, '') + '.';
  // A reply that was all code or all paths: say so rather than nothing at all.
  if (!/[a-z]{3}/i.test(out)) return '';
  return out.length < clean.length - 40 ? out + ' The rest is on screen.' : out;
}

// ---------- names the ear has never heard ----------
// A general ear writes "Benny" for "Venli" and "loop" for "Loop", because the
// words it was trained on do not include this user's projects. Loop knows what
// they are called, so the names are put back afterwards by sound.

// Words common enough that a name must never replace them, however close.
const PLAIN = new Set([
  'the', 'this', 'that', 'then', 'them', 'they', 'there', 'these', 'those', 'what', 'when', 'where', 'which', 'while', 'with', 'would', 'could', 'should',
  'have', 'has', 'had', 'been', 'being', 'does', 'done', 'make', 'made', 'take', 'look', 'like', 'into', 'from', 'about', 'after', 'before', 'again',
  'said', 'says', 'tell', 'told', 'test', 'tests', 'code', 'file', 'files', 'line', 'lines', 'push', 'pull', 'open', 'close', 'stop', 'start', 'send',
  'check', 'change', 'changes', 'error', 'errors', 'branch', 'commit', 'server', 'session', 'please', 'thanks', 'something', 'anything', 'everything',
]);

// What a word sounds like, roughly: no vowels after the first letter, letters
// that are said the same folded together, doubles collapsed.
function sounds(word) {
  const w = String(word || '')
    .toLowerCase()
    .replace(/[^a-z]/g, '');
  if (!w) return '';
  const rest = w
    .slice(1)
    .replace(/[aeiouyh]/g, '')
    .replace(/[ckq]/g, 'k')
    .replace(/[sz]/g, 's')
    .replace(/[fv]/g, 'f')
    .replace(/[dt]/g, 't')
    .replace(/[gj]/g, 'j')
    .replace(/[mn]/g, 'n')
    .replace(/[bp]/g, 'p')
    .replace(/(.)\1+/g, '$1');
  return (w[0].replace(/[cq]/, 'k').replace(/z/, 's') + rest).slice(0, 6);
}

// How many single-letter changes apart two short words are.
function apart(a, b) {
  if (a === b) return 0;
  const prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    let left = prev[0];
    prev[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const was = prev[j];
      prev[j] = Math.min(prev[j] + 1, prev[j - 1] + 1, left + (a[i - 1] === b[j - 1] ? 0 : 1));
      left = was;
    }
  }
  return prev[b.length];
}

/**
 * Put the user's own names back into what was heard. `names` is what Loop
 * calls its projects and servers; anything that sounds like one of them, and
 * is not an ordinary English word, becomes it.
 */
function fixNames(text, names) {
  const known = (names || [])
    .map((n) => String(n || '').trim())
    .filter((n) => n.length >= 4 && /^[A-Za-z][A-Za-z0-9 -]*$/.test(n));
  if (!known.length || !text) return String(text || '');
  const keyed = known.map((n) => ({ name: n, key: sounds(n), low: n.toLowerCase() }));
  // A name the ear split in two: "Event Hive" for EventHive. Done first,
  // because afterwards there is no pair left to recognise.
  let out = String(text).replace(/([A-Za-z][A-Za-z']*)(\s+)([A-Za-z][A-Za-z']*)/g, (whole, a, gap, b) => {
    const joined = (a + b).toLowerCase();
    if (joined.length < 6) return whole;
    for (const k of keyed) {
      if (k.low.includes(' ')) continue;
      if (joined === k.low || (sounds(joined) === k.key && apart(joined, k.low) <= 2)) return k.name;
    }
    return whole;
  });
  return out.replace(/[A-Za-z][A-Za-z']*/g, (word) => {
    const low = word.toLowerCase();
    if (word.length < 4 || PLAIN.has(low)) return word;
    for (const k of keyed) {
      if (low === k.low) return k.name; // right word, maybe wrong capital
      const heard = sounds(word);
      if (!heard || !k.key) continue;
      // Close in sound, and close in spelling: both, or ordinary words start
      // turning into project names.
      if ((heard === k.key || apart(heard, k.key) <= 1) && apart(low, k.low) <= Math.max(2, Math.floor(k.low.length / 3))) return k.name;
    }
    return word;
  });
}

// ---------- the speech process ----------

// Node runs the speech libraries; Electron's own Node cannot load their
// native parts. The PC's node is used, and the user is told if there is none.
function nodeFor() {
  if (process.env.LOOP_VOICE_NODE) return process.env.LOOP_VOICE_NODE;
  for (const name of ['node', 'node.exe']) {
    const r = spawnSync(name, ['-v'], { encoding: 'utf8' });
    if (!r.error && String(r.stdout || '').startsWith('v')) return name;
  }
  return '';
}

const state = {
  host: null,
  waiting: new Map(), // id -> { res, rej }
  next: 1,
  rest: '',
  why: '', // why there is no voice, in words the user can act on
  ready: { say: false, hear: false },
  onEvent: () => {},
};

function stop() {
  if (state.host) {
    try {
      state.host.kill();
    } catch {
      /* already gone */
    }
  }
  state.host = null;
  for (const w of state.waiting.values()) w.rej(new Error('The voice stopped.'));
  state.waiting.clear();
  state.ready = { say: false, hear: false };
}

function host() {
  if (state.host) return state.host;
  const node = nodeFor();
  if (!node) {
    state.why = 'Voice needs Node on this PC (it runs the speech models). Install Node, or set LOOP_VOICE_NODE to its path.';
    throw new Error(state.why);
  }
  // Packed, Loop's files live inside app.asar, which only Electron can read:
  // a plain Node process needs the copy left outside it (see asarUnpack).
  const file = path.join(__dirname, 'voice-host.js').replace(`app.asar${path.sep}`, `app.asar.unpacked${path.sep}`);
  const proc = spawn(node, [file], {
    cwd: path.dirname(file),
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, LOOP_VOICE_CACHE: process.env.LOOP_VOICE_CACHE || '' },
  });
  state.host = proc;
  state.why = '';
  proc.stdout.setEncoding('utf8');
  proc.stdout.on('data', (chunk) => {
    state.rest += chunk;
    const lines = state.rest.split('\n');
    state.rest = lines.pop() || '';
    for (const line of lines) {
      if (!line.trim()) continue;
      let m = null;
      try {
        m = JSON.parse(line);
      } catch {
        continue;
      }
      if (m.t === 'ready') {
        state.ready[m.what === 'hear' ? 'hear' : 'say'] = true;
        state.onEvent({ t: 'ready', what: m.what, ms: m.ms });
      }
      const w = m.id && state.waiting.get(m.id);
      if (!w) continue;
      state.waiting.delete(m.id);
      if (m.t === 'failed') w.rej(new Error(m.why || 'The voice could not do that.'));
      else w.res(m);
    }
  });
  let err = '';
  proc.stderr.setEncoding('utf8');
  proc.stderr.on('data', (d) => {
    err = (err + d).slice(-2000);
  });
  proc.on('exit', (code) => {
    // A model that cannot be downloaded or loaded shows up here, so pass on
    // the last thing it printed rather than a bare number.
    const last = err.split('\n').filter((l) => l.trim()).pop() || '';
    state.why = code === 0 ? '' : `The voice stopped (${code}). ${last}`.trim();
    stop();
    state.onEvent({ t: 'gone', why: state.why });
  });
  proc.on('error', (e) => {
    state.why = 'The voice could not start: ' + e.message;
    stop();
    state.onEvent({ t: 'gone', why: state.why });
  });
  return proc;
}

function ask(msg, waitMs = 120000) {
  return new Promise((res, rej) => {
    let proc = null;
    try {
      proc = host();
    } catch (e) {
      return rej(e);
    }
    const id = msg.id || 'v' + state.next++;
    state.waiting.set(id, { res, rej });
    const timer = setTimeout(() => {
      if (state.waiting.delete(id)) rej(new Error('The voice took too long.'));
    }, waitMs);
    const done = (fn) => (v) => {
      clearTimeout(timer);
      fn(v);
    };
    const w = state.waiting.get(id);
    if (w) {
      w.res = done(res);
      w.rej = done(rej);
    }
    proc.stdin.write(JSON.stringify({ ...msg, id }) + '\n');
  });
}

// ---------- sound across the bridge ----------
// The window works in floats, the speech process in 16-bit bytes: a third of
// the size, which matters for ten seconds of sound on every turn.

const pcmBase64 = (floats) => {
  const a = floats instanceof Float32Array ? floats : new Float32Array(floats || []);
  const b = Buffer.allocUnsafe(a.length * 2);
  for (let i = 0; i < a.length; i++) {
    const v = Math.max(-1, Math.min(1, a[i]));
    b.writeInt16LE(Math.round(v * 32767), i * 2);
  }
  return b.toString('base64');
};

const pcmFloats = (b64) => {
  const b = Buffer.from(String(b64 || ''), 'base64');
  const out = new Float32Array(Math.floor(b.length / 2));
  for (let i = 0; i < out.length; i++) out[i] = b.readInt16LE(i * 2) / 32768;
  return out;
};

module.exports = {
  VOICE_RULES,
  speakable,
  sentences,
  fixNames,
  pcmBase64,
  pcmFloats,
  setListener: (fn) => (state.onEvent = typeof fn === 'function' ? fn : () => {}),
  /** Load the models, so the first thing said is not also the slowest. */
  warm: (what, voice) => ask({ t: 'warm', what, voice }, 600000),
  /** Text in, sound out: base64 16-bit PCM and the rate it plays at. */
  say: (text, voice) => ask({ t: 'say', text, voice }),
  /** Sound in, words out. */
  hear: (pcm, rate) => ask({ t: 'hear', pcm, rate }),
  voices: () => ask({ t: 'voices', id: 'voices' }, 600000),
  sample: (voice, file, text) => ask({ t: 'sample', voice, file, text }, 600000),
  state: () => ({ running: !!state.host, ready: { ...state.ready }, why: state.why, node: !!nodeFor() }),
  stop,
  _test: { stripForSpeech, nodeFor, sounds, apart },
};
