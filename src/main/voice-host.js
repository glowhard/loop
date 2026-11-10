// The voice itself, in a process of its own: speech out (Kokoro or Piper) and
// speech in (Whisper). Both run on this PC and nothing said is sent anywhere.
//
// It lives apart from Loop because a model load takes seconds and a sentence
// takes most of a second: in the window's process that would be a freeze, and
// in Electron's own Node the speech libraries' native parts do not load.
//
// It speaks newline JSON on stdin and stdout. Audio travels as base64 16-bit
// PCM, which is a third of the size of the floats it is made from. Every
// answer carries back the id it was asked with: without it the asking side
// waits for something it has already been sent.
//
//   in  { t:'warm', id, what:'say'|'hear' }  out { t:'ready', id, what, ms }
//   in  { t:'say', id, text, voice }         out { t:'said', id, pcm, rate }
//   in  { t:'hear', id, pcm, rate }          out { t:'heard', id, text }
//   in  { t:'voices', id }                   out { t:'voices', id, list }
//   any failure                              out { t:'failed', id, why }
'use strict';

const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');

const KOKORO = 'onnx-community/Kokoro-82M-v1.0-ONNX';
// Measured on this PC: fp32 speaks faster than real time, while the smaller
// quantised build takes four times as long. Small is not fast here.
const KOKORO_DTYPE = 'fp32';
const WHISPER = 'onnx-community/whisper-base.en';
const WHISPER_DTYPE = 'q8';
const HEAR_RATE = 16000; // what Whisper listens at

const say = (m) => process.stdout.write(JSON.stringify(m) + '\n');
const now = () => Date.now();

// ---------- audio as bytes ----------

const toPcm = (floats) => {
  const b = Buffer.allocUnsafe(floats.length * 2);
  for (let i = 0; i < floats.length; i++) {
    const v = Math.max(-1, Math.min(1, floats[i]));
    b.writeInt16LE(Math.round(v * 32767), i * 2);
  }
  return b.toString('base64');
};

const fromPcm = (b64) => {
  const b = Buffer.from(String(b64 || ''), 'base64');
  const out = new Float32Array(Math.floor(b.length / 2));
  for (let i = 0; i < out.length; i++) out[i] = b.readInt16LE(i * 2) / 32768;
  return out;
};

// Whisper wants 16 kHz. Straight-line resampling is enough for speech.
function resample(pcm, from, to) {
  if (!from || from === to) return pcm;
  const out = new Float32Array(Math.max(1, Math.floor((pcm.length * to) / from)));
  for (let i = 0; i < out.length; i++) {
    const at = (i * from) / to;
    const a = Math.floor(at);
    const b = Math.min(a + 1, pcm.length - 1);
    out[i] = pcm[a] + (pcm[b] - pcm[a]) * (at - a);
  }
  return out;
}

// A wav file, for the Piper voice to be read from and for samples.
function wavOf(floats, rate) {
  const data = Buffer.allocUnsafe(floats.length * 2);
  for (let i = 0; i < floats.length; i++) {
    const v = Math.max(-1, Math.min(1, floats[i]));
    data.writeInt16LE(Math.round(v * 32767), i * 2);
  }
  const head = Buffer.alloc(44);
  head.write('RIFF', 0);
  head.writeUInt32LE(36 + data.length, 4);
  head.write('WAVEfmt ', 8);
  head.writeUInt32LE(16, 16);
  head.writeUInt16LE(1, 20);
  head.writeUInt16LE(1, 22);
  head.writeUInt32LE(rate, 24);
  head.writeUInt32LE(rate * 2, 28);
  head.writeUInt16LE(2, 32);
  head.writeUInt16LE(16, 34);
  head.write('data', 36);
  head.writeUInt32LE(data.length, 40);
  return Buffer.concat([head, data]);
}

// Read a wav of either shape: 16-bit whole numbers, or 32-bit floats.
function readWav(buf) {
  let pos = 12;
  let fmt = null;
  let data = null;
  while (pos + 8 <= buf.length) {
    const id = buf.toString('ascii', pos, pos + 4);
    const size = buf.readUInt32LE(pos + 4);
    if (id === 'fmt ') fmt = { format: buf.readUInt16LE(pos + 8), channels: buf.readUInt16LE(pos + 10), rate: buf.readUInt32LE(pos + 12), bits: buf.readUInt16LE(pos + 22) };
    if (id === 'data') data = buf.subarray(pos + 8, pos + 8 + size);
    pos += 8 + size + (size % 2);
  }
  if (!fmt || !data) throw new Error('that is not a wav file');
  const bytes = Math.max(1, fmt.bits / 8);
  const n = Math.floor(data.length / bytes / Math.max(1, fmt.channels));
  const mono = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const at = i * bytes * fmt.channels;
    mono[i] = fmt.format === 3 && fmt.bits === 32 ? data.readFloatLE(at) : data.readInt16LE(at) / 32768;
  }
  return { pcm: mono, rate: fmt.rate };
}

// ---------- the voices ----------

let kokoro = null;
let whisper = null;

async function engines() {
  if (!engines.loaded) {
    const { pipeline, env } = await import('@huggingface/transformers');
    if (process.env.LOOP_VOICE_CACHE) env.cacheDir = process.env.LOOP_VOICE_CACHE;
    engines.loaded = { pipeline };
  }
  return engines.loaded;
}

async function loadKokoro() {
  if (kokoro) return kokoro;
  const { KokoroTTS } = await import('kokoro-js');
  if (process.env.LOOP_VOICE_CACHE) {
    const { env } = await import('@huggingface/transformers');
    env.cacheDir = process.env.LOOP_VOICE_CACHE;
  }
  kokoro = await KokoroTTS.from_pretrained(KOKORO, { dtype: KOKORO_DTYPE, device: 'cpu' });
  return kokoro;
}

async function loadWhisper() {
  if (whisper) return whisper;
  const { pipeline } = await engines();
  whisper = await pipeline('automatic-speech-recognition', WHISPER, { dtype: WHISPER_DTYPE });
  return whisper;
}

// Piper: one short-lived process per sentence, reading the model beside it.
function piperSay(text) {
  const dir = process.env.LOOP_VOICE_PIPER || '';
  const exe = path.join(dir, process.platform === 'win32' ? 'piper.exe' : 'piper');
  const model = fs.existsSync(dir) ? (fs.readdirSync(dir).find((f) => f.endsWith('.onnx')) || '') : '';
  if (!fs.existsSync(exe) || !model) throw new Error('Piper is not set up: point LOOP_VOICE_PIPER at a folder holding piper.exe and a .onnx voice.');
  return new Promise((res, rej) => {
    const p = spawn(exe, ['--model', path.join(dir, model), '--output_file', '-'], { stdio: ['pipe', 'pipe', 'pipe'] });
    const out = [];
    let err = '';
    p.stdout.on('data', (d) => out.push(d));
    p.stderr.on('data', (d) => (err += d));
    p.on('error', rej);
    p.on('close', (code) => {
      if (code !== 0 && !out.length) return rej(new Error('Piper stopped: ' + (err.split('\n')[0] || code)));
      try {
        res(readWav(Buffer.concat(out)));
      } catch (e) {
        rej(e);
      }
    });
    p.stdin.end(text);
  });
}

async function speak(text, voice) {
  if (String(voice || '').startsWith('piper')) return piperSay(text);
  const tts = await loadKokoro();
  const out = await tts.generate(text, { voice: String(voice || 'af_heart') });
  return { pcm: out.audio, rate: out.sampling_rate };
}

// ---------- taking orders ----------

async function handle(m) {
  if (m.t === 'warm') {
    const t = now();
    if (m.what === 'hear') await loadWhisper();
    else if (String(m.voice || '').startsWith('piper')) await piperSay('Ready.');
    else await loadKokoro();
    return say({ t: 'ready', id: m.id, what: m.what || 'say', ms: now() - t });
  }
  if (m.t === 'say') {
    const t = now();
    const { pcm, rate } = await speak(String(m.text || ''), m.voice);
    return say({ t: 'said', id: m.id, pcm: toPcm(pcm), rate, ms: now() - t, seconds: pcm.length / rate });
  }
  if (m.t === 'hear') {
    const t = now();
    const asr = await loadWhisper();
    const pcm = resample(fromPcm(m.pcm), Number(m.rate) || HEAR_RATE, HEAR_RATE);
    // Under a quarter of a second of sound is a cough or a door, not words.
    if (pcm.length < HEAR_RATE / 4) return say({ t: 'heard', id: m.id, text: '', ms: now() - t });
    const out = await asr(pcm);
    return say({ t: 'heard', id: m.id, text: String((out && out.text) || '').trim(), ms: now() - t, seconds: pcm.length / HEAR_RATE });
  }
  if (m.t === 'voices') {
    const tts = await loadKokoro();
    const list = Object.entries(tts.voices || {}).map(([id, v]) => ({ id, name: (v && v.name) || id, language: (v && v.language) || '', gender: (v && v.gender) || '' }));
    return say({ t: 'voices', id: m.id, list });
  }
  if (m.t === 'sample') {
    // A few words in one voice, written to a file the window can play.
    const { pcm, rate } = await speak(String(m.text || 'Hello, this is how I sound.'), m.voice);
    fs.writeFileSync(String(m.file), wavOf(pcm, rate));
    return say({ t: 'sampled', id: m.id, file: m.file, voice: m.voice });
  }
  return say({ t: 'failed', id: m.id, why: 'Unknown voice command: ' + m.t });
}

// Only when this file is the process. Required from a test it must stay a
// quiet module: a stdin reader here would hold the test runner open.
if (require.main === module) startReading();

function startReading() {
let rest = '';
process.stdin.on('data', (chunk) => {
  rest += chunk;
  const lines = rest.split('\n');
  rest = lines.pop() || '';
  for (const line of lines) {
    if (!line.trim()) continue;
    let m = null;
    try {
      m = JSON.parse(line);
    } catch {
      continue; // half a line, or something not for us
    }
    handle(m).catch((e) => say({ t: 'failed', id: m.id, why: String((e && e.message) || e) }));
  }
});
process.stdin.on('end', () => process.exit(0));
say({ t: 'up', pid: process.pid });
}

module.exports = { _test: { toPcm, fromPcm, resample, wavOf, readWav } };
