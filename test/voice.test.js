// Voice mode: what is worth saying out loud, when someone is talking, and
// when the voice is only hearing itself through the speakers.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const voice = require('../src/main/voice');
const host = require('../src/main/voice-host');

// The hearing lives in the renderer, which has no module system: take it out.
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'renderer', 'voice.js'), 'utf8');
const from = src.indexOf('const FRAME_MS =');
const body = src.slice(from, src.indexOf('// ---------- the state of it ----------'));
const ear = new Function(body + '; return { newEar, earStep, isEcho, tooLittle, SPEECH_OFF, SPEECH_ON, BARGE_ON };')();

// Half a second of a quiet room, which is what the ear listens to before it
// decides anything: in real use there is always some silence before a word.
const settled = () => {
  const st = ear.newEar();
  for (let i = 0; i < 30; i++) ear.earStep(st, 0.002, false);
  return st;
};

// Frames of sound, as the audio thread delivers them: loudness per 20 ms.
const feed = (st, rms, frames, speaking = false) => {
  const seen = [];
  for (let i = 0; i < frames; i++) {
    const e = ear.earStep(st, rms, speaking);
    if (e) seen.push(e);
  }
  return seen;
};

test('a quiet room says nothing, and talking then stopping is one thing said', () => {
  const st = settled();
  assert.deepStrictEqual(feed(st, 0.002, 100), [], 'the room on its own is not speech');
  assert.deepStrictEqual(feed(st, 0.09, 40), ['start'], 'talking starts it once, not every frame');
  assert.deepStrictEqual(feed(st, 0.002, ear.SPEECH_OFF + 1), ['end'], 'a pause ends what was said');
});

test('a cough is dropped, and the microphone cannot run forever', () => {
  const st = settled();
  // Loud enough to start, over too quickly to be words.
  feed(st, 0.09, ear.SPEECH_ON + 2);
  assert.deepStrictEqual(feed(st, 0.002, ear.SPEECH_OFF + 1), ['drop']);

  // Someone who never stops talking: it is closed off by itself and the next
  // stretch is heard as the next thing said, rather than being lost.
  const long = settled();
  feed(long, 0.09, 10);
  assert.deepStrictEqual(feed(long, 0.09, 2000), ['end', 'start']);
});

test('talking over the voice cuts in sooner than talking into silence', () => {
  const quiet = settled();
  const over = settled();
  let toStart = 0;
  while (!feed(quiet, 0.09, 1).length) toStart++;
  let toBarge = 0;
  let what = [];
  while (!(what = feed(over, 0.09, 1, true)).length) toBarge++;
  assert.deepStrictEqual(what, ['barge'], 'while speaking, speech means cut in');
  assert.ok(toBarge < toStart, `cutting in should take fewer frames (${toBarge} vs ${toStart})`);
});

test('a fan becomes the room, not something said', () => {
  // A fan already running when voice mode opens.
  const st = ear.newEar();
  // Steady noise well above the first floor: it becomes the floor, and the
  // room is not heard as one endless thing said.
  assert.deepStrictEqual(feed(st, 0.02, 600), []);
  assert.deepStrictEqual(feed(st, 0.02, 200), [], 'steady noise stops counting as speech');
  assert.deepStrictEqual(feed(st, 0.4, 40), ['start'], 'a voice over that noise is still heard');
});

test("the voice's own words coming back through the speakers are not an answer", () => {
  const now = Date.now();
  const spoken = [{ text: 'I changed the login page and the tests pass.', at: now }];
  assert.strictEqual(ear.isEcho('I changed the login page and the tests pass', spoken, true, 0, now), true);
  assert.strictEqual(ear.isEcho('no wait, do the signup page instead', spoken, true, 0, now), false);
  // Long after it stopped speaking, the same words are the user's own.
  assert.strictEqual(ear.isEcho('I changed the login page and the tests pass', spoken, false, now - 9000, now), false);
});

test('sounds that are not words are not sent on', () => {
  assert.strictEqual(ear.tooLittle(''), true);
  assert.strictEqual(ear.tooLittle(' (engine revving) '), true, 'the ear writes notes like this for noise');
  assert.strictEqual(ear.tooLittle('[BLANK_AUDIO]'), true);
  assert.strictEqual(ear.tooLittle('hm'), true);
  assert.strictEqual(ear.tooLittle('stop'), false);
  assert.strictEqual(ear.tooLittle('what did you change'), false);
});

test('what is read aloud leaves out what only makes sense on a screen', () => {
  const said = voice.speakable(
    'Done. I fixed it in `src/main/voice.js` and pushed.\n\n' +
      '- 122 tests pass\n- see D:\\Personal\\automation\\session-deck\\test\n\n' +
      '```js\nconst a = 1;\n```\n\nFull notes at https://example.com/notes',
  );
  assert.match(said, /^Done\./);
  assert.doesNotMatch(said, /```|const a/, 'no code');
  assert.doesNotMatch(said, /D:\\|src\/main/, 'no file paths');
  assert.doesNotMatch(said, /https?:/, 'no links');
  assert.doesNotMatch(said, /^[-*]\s/m, 'no bullet points');
  assert.match(said, /122 tests pass/, 'the words themselves are kept');
});

test('a long answer is cut to something sayable, and says where the rest is', () => {
  const long = Array.from({ length: 12 }, (_, i) => `This is sentence number ${i + 1} of a long written answer.`).join(' ');
  const said = voice.speakable(long);
  assert.ok(said.length < 500, `kept to ${said.length} characters`);
  assert.match(said, /The rest is on screen\.$/);
  assert.match(said, /^This is sentence number 1/, 'it starts at the beginning');
  // A short answer is said as it is, with nothing added.
  assert.strictEqual(voice.speakable('All three tests pass now.'), 'All three tests pass now.');
});

test('a reply that is only code or only a path is not spoken at all', () => {
  assert.strictEqual(voice.speakable('```\nnpm test\n```'), '');
  assert.strictEqual(voice.speakable('D:\\Personal\\automation\\session-deck'), '');
  assert.strictEqual(voice.speakable('   '), '');
});

test('what is said is broken into sentences, so the first words come quickly', () => {
  assert.deepStrictEqual(voice.sentences('One thing. And another! Really?'), ['One thing.', 'And another!', 'Really?']);
  assert.deepStrictEqual(voice.sentences('No full stop here'), ['No full stop here']);
  assert.deepStrictEqual(voice.sentences(''), []);
});

test('the rules a session is given in voice mode are about speaking, not writing', () => {
  assert.match(voice.VOICE_RULES, /read out loud/);
  assert.match(voice.VOICE_RULES, /one or two short spoken sentences/i);
  assert.match(voice.VOICE_RULES, /Never read code, file paths/);
  assert.ok(voice.VOICE_RULES.length < 1200, 'short enough to send on every voice session');
});

test('sound survives the trip to the speech process and back', () => {
  const made = new Float32Array(2048);
  for (let i = 0; i < made.length; i++) made[i] = Math.sin(i / 7) * 0.8;
  const back = voice.pcmFloats(voice.pcmBase64(made));
  assert.strictEqual(back.length, made.length);
  for (let i = 0; i < made.length; i += 97) assert.ok(Math.abs(back[i] - made[i]) < 0.001, `sample ${i} came back as ${back[i]}`);
  // Anything louder than full scale is held at the edge rather than wrapping.
  assert.ok(Math.abs(voice.pcmFloats(voice.pcmBase64(new Float32Array([2, -2])))[0] - 1) < 0.002);
});

test('a wav is read whether it holds whole numbers or floats', () => {
  const made = new Float32Array(1600);
  for (let i = 0; i < made.length; i++) made[i] = Math.sin(i / 11) * 0.5;
  // What Loop writes: 16-bit at 24 kHz.
  const own = host._test.readWav(host._test.wavOf(made, 24000));
  assert.strictEqual(own.rate, 24000);
  assert.ok(Math.abs(own.pcm[40] - made[40]) < 0.001);

  // What Kokoro writes: 32-bit floats. Read as whole numbers it is noise, and
  // the ear then hears an engine instead of words.
  const data = Buffer.allocUnsafe(made.length * 4);
  made.forEach((v, i) => data.writeFloatLE(v, i * 4));
  const head = Buffer.alloc(44);
  head.write('RIFF', 0);
  head.writeUInt32LE(36 + data.length, 4);
  head.write('WAVEfmt ', 8);
  head.writeUInt32LE(16, 16);
  head.writeUInt16LE(3, 20); // floats
  head.writeUInt16LE(1, 22);
  head.writeUInt32LE(24000, 24);
  head.writeUInt16LE(32, 34);
  head.write('data', 36);
  head.writeUInt32LE(data.length, 40);
  const read = host._test.readWav(Buffer.concat([head, data]));
  assert.ok(Math.abs(read.pcm[40] - made[40]) < 0.001, 'floats are read as floats');
});

test('sound is moved to the rate the ear listens at', () => {
  const at48 = new Float32Array(4800); // a tenth of a second
  for (let i = 0; i < at48.length; i++) at48[i] = Math.sin(i / 24);
  const at16 = host._test.resample(at48, 48000, 16000);
  assert.strictEqual(at16.length, 1600);
  assert.strictEqual(host._test.resample(at16, 16000, 16000), at16, 'already right: left alone');
});

test('the names of this user’s own things are put back into what was heard', () => {
  const names = ['Venli', 'Prismaple', 'EventHive', 'Bhillon', 'Kappnin', 'PixelLens'];
  // Exactly what the ear wrote for these, measured on real clips.
  assert.strictEqual(voice.fixNames('Ask Venly to run the tests.', names), 'Ask Venli to run the tests.');
  assert.strictEqual(voice.fixNames('Deploy the Venly app to Prismable.', names), 'Deploy the Venli app to Prismaple.');
  assert.strictEqual(voice.fixNames('Open the Billon stock admin.', names), 'Open the Bhillon stock admin.');
  assert.strictEqual(voice.fixNames('What is Kapnan doing right now?', names), 'What is Kappnin doing right now?');
  // A name the ear split into two words.
  assert.strictEqual(voice.fixNames('Check the Event Hive certificates.', names), 'Check the EventHive certificates.');
  // The user's own spelling of a name they said correctly.
  assert.strictEqual(voice.fixNames('ask venli about it', names), 'ask Venli about it');
});

test('ordinary words are never turned into project names', () => {
  const names = ['Venli', 'Prismaple', 'EventHive', 'Bhillon', 'Kappnin', 'Loop', 'Admin Panel'];
  for (const said of [
    'push the branch and run the tests',
    'please check the server logs again',
    'that looks done, close the session',
    'what changed in the login page',
  ]) {
    assert.strictEqual(voice.fixNames(said, names), said, said);
  }
  // Nothing to go on: what was heard is left exactly as it was.
  assert.strictEqual(voice.fixNames('Ask Venly to run it', []), 'Ask Venly to run it');
});
