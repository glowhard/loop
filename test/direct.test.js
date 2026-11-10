// Stopping a session that has no terminal: the phone's Esc, which used to go
// nowhere because there was no screen to send it to.
const test = require('node:test');
const assert = require('node:assert');
const path = require('path');
const direct = require('../src/main/direct');

const fake = path.join(__dirname, 'fake', 'claude.js');
const id = (n) => `00000000-0000-4000-8000-00000000000${n}`;
const until = async (ok, limit = 8000) => {
  const t0 = Date.now();
  while (Date.now() - t0 < limit) {
    if (ok()) return true;
    await new Promise((r) => setTimeout(r, 50));
  }
  return false;
};
const run = (sessionId, mode) =>
  direct.send({ sessionId, cwd: __dirname, settings: {}, text: 'do something long', spawn: { cmd: process.execPath, args: [fake, mode] } });

test.after(() => direct.stopAll());

test('an interrupt ends the turn and keeps the session', async () => {
  const s = id(1);
  assert.strictEqual(await run(s, 'obeys'), null);
  assert.ok(await until(() => direct.turn(s) === 'busy'), 'it should be working');
  assert.strictEqual(direct.interrupt(s), true);
  assert.ok(await until(() => direct.turn(s) === 'idle'), 'the turn should be over');
  // The session itself is still there, so the next message carries on.
  assert.strictEqual(direct.running(s), true);
});

test('an interrupt it has taken is given the time it needs', async () => {
  const s = id(4);
  await run(s, 'slow');
  assert.ok(await until(() => direct.turn(s) === 'busy'));
  assert.strictEqual(direct.interrupt(s), true);
  // It said it would stop, so it is not killed for being slow about it.
  await new Promise((r) => setTimeout(r, 10000));
  assert.strictEqual(direct.running(s), true);
});

test('a turn that will not let go is killed, so the session is free again', async () => {
  const s = id(2);
  await run(s, 'deaf');
  assert.ok(await until(() => direct.turn(s) === 'busy'));
  assert.strictEqual(direct.interrupt(s), true);
  assert.ok(await until(() => !direct.running(s), 12000), 'the runner should be gone');
  assert.strictEqual(direct.turn(s), null);
});

test('a question on screen is refused rather than interrupted', async () => {
  const s = id(3);
  const asked = [];
  direct.setAskListener((sessionId, ask) => sessionId === s && asked.push(ask));
  await run(s, 'asks');
  assert.ok(await until(() => Boolean(direct.asks()[s])), 'it should be waiting on a question');
  assert.strictEqual(direct.interrupt(s), true);
  // The question is taken off the phone and the session is free, not killed.
  assert.ok(await until(() => !direct.asks()[s]));
  assert.strictEqual(asked[asked.length - 1], null);
  assert.strictEqual(direct.running(s), true);
});

test('a turn Claude starts by itself does not leave the next one looking idle', async () => {
  const s = id(5);
  await run(s, 'self');
  // The first message is answered, then Claude works a turn of its own.
  assert.ok(await until(() => direct.turn(s) === 'idle'));
  await new Promise((r) => setTimeout(r, 900));
  assert.strictEqual(direct.turn(s), 'idle', 'its own turn is over');
  // The next message is being worked on: busy, so the phone shows Stop.
  assert.strictEqual(await direct.send({ sessionId: s, cwd: __dirname, settings: {}, text: 'again' }), null);
  await new Promise((r) => setTimeout(r, 400));
  assert.strictEqual(direct.turn(s), 'busy');
  direct.stop(s);
});

test('there is nothing to stop in a session that is not running', () => {
  assert.strictEqual(direct.interrupt(id(9)), false);
});

test('only a few sessions stay warm, so ten of them do not cost ten Claudes', async () => {
  direct.stopAll(); // whatever the tests above left running
  const many = ['a', 'b', 'c', 'd', 'e'].map((x) => `00000000-0000-4000-8000-0000000000${x}0`);
  for (const s of many) {
    await run(s, 'quick');
    assert.ok(await until(() => direct.turn(s) === 'idle'), `${s} should be ready`);
  }
  const warm = many.filter((s) => direct.running(s));
  assert.strictEqual(warm.length, direct.WARM);
  // The one just used stays, and the oldest are the ones let go.
  assert.deepStrictEqual(warm, many.slice(-direct.WARM));
});

test('a session in the middle of something is never the one let go', async () => {
  direct.stopAll();
  const busy = '00000000-0000-4000-8000-0000000000f0';
  await run(busy, 'deaf'); // it never finishes its turn
  assert.ok(await until(() => direct.turn(busy) === 'busy'));
  for (const x of ['g', 'h', 'i', 'j']) {
    const s = `00000000-0000-4000-8000-0000000000${x}0`;
    await run(s, 'quick');
    await until(() => direct.turn(s) === 'idle');
  }
  assert.strictEqual(direct.running(busy), true, 'the working one should still be there');
});
