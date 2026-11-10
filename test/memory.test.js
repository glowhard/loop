const test = require('node:test');
const assert = require('node:assert');
const { _test } = require('../src/main/memory');
const { rank, chunk, terms, estimateTokens, parseNote } = _test;

const note = (id, title, body, tags = []) => ({ id, scope: 'project', title, body, tags, author: '', updated: 0 });

test('terms lowercases, splits camelCase, drops stop words and stems', () => {
  assert.deepStrictEqual(terms('The deployScripts are running'), ['deploy', 'script', 'runn']);
});

test('chunk keeps passages near the size limit and never drops text', () => {
  const para = 'word '.repeat(120).trim();
  const parts = chunk([para, para, para].join('\n\n'));
  assert.strictEqual(parts.length, 3);
  for (const p of parts) assert.ok(estimateTokens(p) <= 260);
  assert.deepStrictEqual(chunk(''), ['']);
});

test('rank puts the matching note first and ignores unrelated ones', () => {
  const notes = [
    note('a', 'Database backups', 'Postgres dumps run nightly at 2am to the backup bucket.'),
    note('b', 'Deploy process', 'Deploys go through git: commit, push, then pull on the server.'),
    note('c', 'Design tokens', 'Petrol slate chrome with amber and green lamps.'),
  ];
  const hits = rank(notes, 'how do we deploy to the server');
  assert.strictEqual(hits[0].note.id, 'b');
  assert.ok(!hits.some((h) => h.note.id === 'c'));
});

test('a title match outranks a passing mention in the body', () => {
  const notes = [
    note('a', 'Staging server', 'Address and login steps for the box.'),
    note('b', 'Misc', 'Someone mentioned staging once in a long unrelated paragraph about other things entirely.'),
  ];
  assert.strictEqual(rank(notes, 'staging')[0].note.id, 'a');
});

test('rank returns nothing for a query of only stop words', () => {
  assert.deepStrictEqual(rank([note('a', 'x', 'y')], 'the and of'), []);
});

test('parseNote reads our front matter', () => {
  const n = parseNote(
    '---\ntitle: Hello there\ntags: a, b\nauthor: Ops AI\nupdated: 2026-10-01T00:00:00.000Z\n---\n\nBody text\n',
    'C:/m/hello-1.md',
    'project',
  );
  assert.strictEqual(n.title, 'Hello there');
  assert.deepStrictEqual(n.tags, ['a', 'b']);
  assert.strictEqual(n.author, 'Ops AI');
  assert.strictEqual(n.body, 'Body text');
  assert.strictEqual(n.id, 'hello-1');
});

test('parseNote reads Claude Code memory files', () => {
  const raw =
    '---\nname: branch-workflow\ndescription: "Always branch first"\nmetadata:\n  type: feedback\n  modified: 2026-09-28T06:41:21.865Z\n---\n\nDetails here.';
  const n = parseNote(raw, 'C:/m/feedback_branch.md', 'claude');
  assert.strictEqual(n.title, 'branch workflow');
  assert.ok(n.body.startsWith('Always branch first'));
  assert.ok(n.updated > 0);
});
