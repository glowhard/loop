const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const trash = require('../src/main/trash');

const id = '11111111-1111-4111-8111-111111111111';
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'loop-trash-'));
const projects = path.join(tmp, 'projects');
const root = path.join(tmp, 'trash');
trash._test.setRoots(root, projects);

test('a deleted session can be put back, and is removed after 30 days', async () => {
  fs.mkdirSync(path.join(projects, 'demo', id, 'subagents'), { recursive: true });
  fs.writeFileSync(path.join(projects, 'demo', id + '.jsonl'), 'talk');
  fs.writeFileSync(path.join(projects, 'demo', id, 'subagents', 'a.jsonl'), 'sub');

  assert.equal(await trash.put('..', id, 'x'), false);
  assert.equal(await trash.put('demo', 'not-an-id', 'x'), false);
  assert.equal(await trash.put('demo', id, 'Extra one'), true);
  assert.equal(fs.existsSync(path.join(projects, 'demo', id + '.jsonl')), false);
  assert.equal(fs.existsSync(path.join(projects, 'demo', id)), false);
  let items = await trash.list();
  assert.deepEqual(items.map((t) => [t.dir, t.id, t.title]), [['demo', id, 'Extra one']]);

  assert.equal(await trash.restore('demo', id), true);
  assert.equal(fs.readFileSync(path.join(projects, 'demo', id + '.jsonl'), 'utf8'), 'talk');
  assert.equal(fs.readFileSync(path.join(projects, 'demo', id, 'subagents', 'a.jsonl'), 'utf8'), 'sub');
  assert.deepEqual(await trash.list(), []);
  assert.equal(await trash.restore('demo', id), false);

  await trash.put('demo', id, 'Extra one');
  assert.equal(await trash.purge(Date.now() + trash.KEEP_MS - 60000), 0);
  assert.equal((await trash.list()).length, 1);
  assert.equal(await trash.purge(Date.now() + trash.KEEP_MS + 60000), 1);
  assert.deepEqual(await trash.list(), []);
  assert.equal(fs.existsSync(path.join(root, 'demo', id + '.jsonl')), false);
  fs.rmSync(tmp, { recursive: true, force: true });
});
