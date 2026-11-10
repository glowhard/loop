// The rules a team works by: the company's, the project's on top of them, and
// any written for one member alone. Who may change them, and who may write on
// the company shelf.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const memory = require('../src/main/memory');

const { callTool, setRootForTest, rulesFor, companyRules } = memory._test;
const ceo = '11111111-1111-4111-8111-111111111111';
const dev = '22222222-2222-4222-8222-222222222222';
const dir = 'C--rules-test';
const roles = [
  { key: 'ceo', title: 'CEO' },
  { key: 'pm', title: 'Project manager', manages: true },
  { key: 'dev', title: 'Developer' },
];
let team = null;
let company = {};

test.before(() => {
  setRootForTest(fs.mkdtempSync(path.join(os.tmpdir(), 'loop-rules-')));
  memory.setTeamLookup(() => team);
  memory.setCompanyLookup(() => company);
});

test.beforeEach(() => {
  team = { roles, members: { [ceo]: 'ceo', [dev]: 'dev' } };
  company = {};
});

test('with nothing written, every team works by the rules Loop ships with', () => {
  const house = memory.housePlain();
  assert.match(house, /Save tokens above all/);
  assert.match(house, /Two front doors/);
  assert.match(house, /No relay/);
  assert.match(house, /Need from you:/);
  assert.doesNotMatch(house, /Ask the user first, always/); // Loop forces no permission asks: Claude Code handles them
  assert.match(house, /Never answer a reply, and never send an acknowledgement/); // no ping-pong between members
  assert.doesNotMatch(house, /project manager/); // the old relay chain is gone
  assert.strictEqual(companyRules(), house);

  const mine = rulesFor(dir, dev);
  assert.match(mine, /^The company's rules\. The CEO sets them/);
  assert.match(mine, /Save tokens above all/);
  // No clock unless someone sets one: the lean team reports when work moves.
  assert.doesNotMatch(mine, /No update for/);
});

test('the company, the project and one member stack in that order', () => {
  company = { rules: 'Ship on Tuesdays.' };
  team.policy = 'This project never touches production.';
  team.memberRules = { [dev]: 'Ask the CTO before adding a dependency.' };

  const mine = rulesFor(dir, dev);
  assert.match(mine, /Ship on Tuesdays\./);
  assert.match(mine, /This project's own rules, on top of the company's:\nThis project never touches production\./);
  assert.match(mine, /Rules for you in particular:\nAsk the CTO before adding a dependency\./);
  assert.ok(mine.indexOf('Ship on Tuesdays') < mine.indexOf('never touches production'), 'the company comes first');
  // What one member was told is not told to another.
  assert.doesNotMatch(rulesFor(dir, ceo), /adding a dependency/);
  // Written rules replace the default ones rather than joining them.
  assert.doesNotMatch(mine, /Save tokens above all/);
});

test('how long the CEO waits is the company\u2019s, unless the project says otherwise', () => {
  assert.strictEqual(memory.checkMins(dir), 0); // off unless someone sets it
  company = { checkMins: 45 };
  assert.match(rulesFor(dir, dev), /No update for 45 minutes/);
  assert.strictEqual(memory.checkMins(dir), 45);
  team.checkMins = 10;
  assert.strictEqual(memory.checkMins(dir), 10);
  team.checkMins = 0; // off for this project
  assert.strictEqual(memory.checkMins(dir), 0);
  assert.doesNotMatch(rulesFor(dir, dev), /No update for/);
});

test('the company shelf is read by everyone and written by the CEO alone', async () => {
  const wrote = await callTool(
    'memory_save',
    { title: 'Expenses policy', content: 'Anything over a hundred goes through the CEO.', scope: 'company' },
    { dir, sessionId: ceo },
  );
  assert.match(wrote, /the company shelf, where every project reads it/);

  const refused = await callTool('memory_save', { title: 'My own policy', content: 'No reviews.', scope: 'company' }, { dir, sessionId: dev });
  assert.match(refused, /The company shelf is the CEO/);

  // Everyone reads it, and it is the same shelf from any project.
  for (const me of [ceo, dev]) {
    assert.match(await callTool('memory_list', { scope: 'company' }, { dir, sessionId: me }), /Expenses policy/);
    assert.match(await callTool('memory_search', { query: 'expenses hundred' }, { dir: 'C--other-project', sessionId: me }), /goes through the CEO/);
  }

  // The developer cannot delete it either.
  const id = (await memory.list(dir, 'company')).notes[0].id;
  assert.match(await callTool('memory_delete', { id }, { dir, sessionId: dev }), /Only the CEO removes/);
  assert.match(await callTool('memory_delete', { id }, { dir, sessionId: ceo }), /^Deleted "Expenses policy"/);
});

test("a sub-session reads its main session's notes, and nobody else's", async () => {
  const main = '33333333-3333-4333-8333-333333333333';
  const child = '44444444-4444-4444-8444-444444444444';
  const other = '55555555-5555-4555-8555-555555555555';
  memory.setSubLookup((id) => (id === child ? { parent: main } : null));
  await callTool('memory_save', { title: 'Login decision', content: 'Use magic links, not passwords.' }, { dir, sessionId: main });
  await callTool('memory_save', { title: 'Unrelated', content: 'Billing runs on Fridays.' }, { dir, sessionId: other });
  const mine = await callTool('memory_list', { scope: 'parent' }, { dir, sessionId: child });
  assert.match(mine, /Login decision/);
  assert.doesNotMatch(mine, /Unrelated/);
  // A session with no main session has no parent notes.
  assert.match(await callTool('memory_list', { scope: 'parent' }, { dir, sessionId: other }), /empty/i);
  memory.setSubLookup(() => null);
});

test('what a member is told at start carries the rules, briefly', () => {
  const brief = memory.startBrief(dir, dev);
  assert.match(brief, /Save tokens above all/);
  assert.match(brief, /scope "company"/);
  assert.doesNotMatch(brief, /\n/); // one paragraph: it goes in a system prompt
});
