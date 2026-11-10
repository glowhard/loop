// Voice mode as it actually runs: sound comes in from the audio thread, the
// words go to the session, the session's reply is spoken, and talking over it
// stops it. The whole renderer file is loaded here with stand-ins for the
// window, so a turn can be played out without a microphone or a model.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'renderer', 'voice.js'), 'utf8');

// A fake world: what the window and Loop would give the voice bar.
function load() {
  const sent = []; // what was sent to the session
  const spoken = []; // what was asked to be said out loud
  const heard = []; // what the ear will claim to have heard, in order
  const sizes = []; // how much sound was handed to the ear each time
  let onChat = null;
  let onAsk = null;

  const deck = {
    voiceState: async () => ({ node: true }),
    voiceWarm: async () => true,
    voiceRules: async () => 'VOICE RULES',
    voiceHear: async (pcm, rate) => {
      sizes.push({ samples: pcm.length, rate });
      return { text: heard.length ? heard.shift() : '' };
    },
    voicePlan: async (text) => ({ spoken: text, parts: [text] }),
    voiceSay: async (text) => {
      spoken.push(text);
      return { pcm: new Float32Array(240), rate: 24000 };
    },
    voiceFollow: () => {},
    voiceUnfollow: () => {},
    onVoiceChat: (cb) => (onChat = cb),
    onVoiceEvent: () => {},
    onDirectAsk: (cb) => (onAsk = cb),
  };
  const world = {
    deck,
    S: { tabs: new Map(), active: null, config: { settings: {} } },
    toast: () => {},
    sessionTitle: (s) => s.id,
    sessionById: () => ({ p: null, s: null }),
    renderTools: () => {},
    tabFor: () => null,
    sayTo: async (p, s, text) => {
      sent.push(text);
      return { ok: true };
    },
  };
  const names = Object.keys(world);
  const made = new Function(...names, SRC + '; return { V, onFrame, heardSomething, takeIt, interrupt, speaking, look };')(...names.map((n) => world[n]));
  return { ...made, sent, spoken, heard, sizes, chat: (msg) => onChat(msg), ask: (id, a) => onAsk(id, a) };
}

// Open voice mode far enough to run a turn, without touching audio hardware.
function started(v) {
  v.V.on = true;
  v.V.p = { dir: 'D--x', path: 'D:/x', server: '' };
  v.V.s = { id: '11111111-1111-4111-8111-111111111111' };
  v.V.told = true; // the rules have already gone, to keep assertions simple
  v.V.look = 'listening';
  // Past the half second the ear spends learning the room.
  for (let i = 0; i < 30; i++) v.onFrame({ rms: 0.002, pcm: new Float32Array(320) });
  return v;
}

// Somebody talks for a while and then stops.
const talk = (v, frames = 30) => {
  for (let i = 0; i < frames; i++) v.onFrame({ rms: 0.09, pcm: new Float32Array(320).fill(0.09) });
  for (let i = 0; i < 40; i++) v.onFrame({ rms: 0.002, pcm: new Float32Array(320) });
};

const settled = () => new Promise((r) => setTimeout(r, 30));

test('the mic being on is the whole of the switch: what you say goes to the session', async () => {
  const v = started(load());
  v.heard.push('run the tests for me');
  talk(v);
  await settled();
  assert.deepStrictEqual(v.sent, ['run the tests for me'], 'no name to call, no word to end on');
  assert.strictEqual(v.V.look, 'thinking');
  assert.strictEqual(v.V.lastHeard, 'run the tests for me', 'the bar shows what it heard');
});

test('the session is told how to speak once, and not again after that', async () => {
  const v = started(load());
  v.V.told = false;
  v.heard.push('first thing', 'second thing');
  talk(v);
  await settled();
  talk(v);
  await settled();
  assert.match(v.sent[0], /^VOICE RULES\n\nfirst thing$/);
  assert.strictEqual(v.sent[1], 'second thing', 'the rules are not repeated every turn');
});

test("what the session writes is spoken, and only its own words", async () => {
  const v = started(load());
  v.chat({ reset: true, items: [{ k: 'text', id: 'old', text: 'said before voice mode started' }] });
  await settled();
  assert.deepStrictEqual(v.spoken, [], 'the conversation so far is read, not read out');

  v.chat({
    items: [
      { k: 'tool', id: 't1', name: 'Bash' },
      { k: 'result', id: 't1', ok: true, text: '122 passed' },
      { k: 'text', id: 'a1', text: 'All the tests pass.' },
      { k: 'user', id: 'u1', text: 'this was typed, not said' },
    ],
  });
  await settled();
  assert.deepStrictEqual(v.spoken, ['All the tests pass.'], 'tools and results stay on the screen');

  // The same thing arriving twice is not said twice.
  v.chat({ items: [{ k: 'text', id: 'a1', text: 'All the tests pass.' }] });
  await settled();
  assert.strictEqual(v.spoken.length, 1);
});

test('talking over it stops it on the sound, before a word has been read', async () => {
  const v = started(load());
  v.chat({ items: [{ k: 'text', id: 'a1', text: 'This is a long answer that is still being read out.' }] });
  await settled();
  assert.ok(v.speaking(), 'it is talking');
  const before = v.V.turn;
  // Only a hundred milliseconds of speech, and no transcript yet.
  for (let i = 0; i < 6; i++) v.onFrame({ rms: 0.09, pcm: new Float32Array(320).fill(0.09) });
  assert.ok(v.V.turn > before, 'it was cut off');
  assert.strictEqual(v.speaking(), false);
  assert.strictEqual(v.V.look, 'listening');
});

test('it does not answer its own voice coming back through the speakers', async () => {
  const v = started(load());
  v.chat({ items: [{ k: 'text', id: 'a1', text: 'I changed the login page and pushed it.' }] });
  await settled();
  // The speakers, heard by the microphone: the same words it just said.
  v.heard.push('I changed the login page and pushed it');
  await v.heardSomething([new Float32Array(16000).fill(0.05)]);
  assert.deepStrictEqual(v.sent, [], 'its own words are not sent back to it');

  // Something a person actually said, while it is still talking, does go.
  v.heard.push('no, do the signup page instead');
  await v.heardSomething([new Float32Array(16000).fill(0.05)]);
  assert.deepStrictEqual(v.sent, ['no, do the signup page instead']);
});

test('a cough, a door or a note about noise is not sent anywhere', async () => {
  const v = started(load());
  for (const noise of ['', '(engine revving)', '[BLANK_AUDIO]', 'hm']) {
    v.heard.push(noise);
    await v.heardSomething([new Float32Array(16000).fill(0.05)]);
  }
  assert.deepStrictEqual(v.sent, []);
  assert.strictEqual(v.V.look, 'listening', 'and it goes straight back to listening');
});

test('a question the session is waiting on is read out, and answered on screen', async () => {
  const v = started(load());
  v.ask(v.V.s.id, { key: 'k1', question: 'Allow Bash?' });
  await settled();
  assert.deepStrictEqual(v.spoken, ['Allow Bash? Answer it on screen.']);
  // A question for a different session is not this one's business.
  v.ask('99999999-9999-4999-8999-999999999999', { key: 'k2', question: 'Allow Write?' });
  await settled();
  assert.strictEqual(v.spoken.length, 1);
});

test('it stops listening for good when voice mode is left', async () => {
  const v = started(load());
  v.V.on = false;
  v.heard.push('this should go nowhere');
  talk(v);
  await settled();
  assert.deepStrictEqual(v.sent, []);
});

test('the sound handed to the ear starts before the first word, not after it', async () => {
  const v = started(load());
  // Twelve frames of room, then speech. The ear only knows someone is talking
  // seven frames in, so without the ones kept back the first word is clipped:
  // "Stop what you are doing" was arriving as "what you are doing".
  for (let i = 0; i < 12; i++) v.onFrame({ rms: 0.002, pcm: new Float32Array(320) });
  v.heard.push('stop what you are doing');
  talk(v, 25);
  await settled();
  assert.strictEqual(v.sizes.length, 1);
  // 25 frames of speech plus the quiet ones the ear waited through; the kept
  // back frames put it well past what was heard from the moment it noticed.
  const spoke = 25 * 320;
  assert.ok(v.sizes[0].samples > spoke, `only ${v.sizes[0].samples} samples for ${spoke} of speech: the start was lost`);
});

test('the ear is told the rate the sound really came in at', async () => {
  const v = started(load());
  // A microphone at 44.1 kHz gives frames at 14700, not 16000. Called 16000,
  // every word comes out slightly wrong.
  v.onFrame({ rms: 0.002, pcm: new Float32Array(294), rate: 14700 });
  v.heard.push('check the logs');
  for (let i = 0; i < 25; i++) v.onFrame({ rms: 0.09, pcm: new Float32Array(294).fill(0.09), rate: 14700 });
  for (let i = 0; i < 40; i++) v.onFrame({ rms: 0.002, pcm: new Float32Array(294), rate: 14700 });
  await settled();
  assert.strictEqual(v.sizes[0].rate, 14700);
});
