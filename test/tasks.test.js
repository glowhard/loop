// What a session is running in the background, read from its conversation file.
const test = require('node:test');
const assert = require('node:assert');
const { readTasks } = require('../src/main/tasks');

const OUT = 'C:\tasks\bkgpnyw32.output';
const line = (o) => JSON.stringify(o);
const used = (id, name, bg) => line({ type: 'assistant', timestamp: '2026-10-12T10:00:00.000Z', message: { content: [{ type: 'tool_use', id, name: 'Bash', input: { command: 'npm test', description: name, ...(bg ? { run_in_background: true } : {}) } }] } });
const said = (id, text, at = '2026-10-12T10:00:01.000Z') => line({ type: 'user', timestamp: at, message: { content: [{ type: 'tool_result', tool_use_id: id, content: text }] } });
const ended = (id, status, at = '2026-10-12T10:00:31.000Z') =>
  line({
    type: 'queue-operation',
    operation: 'enqueue',
    timestamp: at,
    content: `<task-notification>\n<task-id>${id}</task-id>\n<output-file>${OUT}</output-file>\n<status>${status}</status>\n<summary>Background command "The long one" ${status} (exit code 0)</summary>\n</task-notification>`,
  });

test('a background command is followed from its start to how it ended', () => {
  const tasks = readTasks(
    [
      used('toolu_1', 'The long one', true),
      said('toolu_1', `Command running in background with ID: bkgpnyw32. Output is being written to: ${OUT}. You will be notified when it completes.`),
      ended('bkgpnyw32', 'completed'),
    ].join('\n'),
  );
  assert.strictEqual(tasks.length, 1);
  assert.deepStrictEqual(
    { ...tasks[0], started: 0, ended: 0, note: '' },
    { id: 'bkgpnyw32', kind: 'Bash', name: 'The long one', status: 'done', started: 0, ended: 0, note: '', file: OUT },
  );
  // Long enough to show "30s" next to it in the app.
  assert.strictEqual(tasks[0].ended - tasks[0].started, 31000);
});

test('what is still running comes first, newest at the top', () => {
  const tasks = readTasks(
    [
      used('a', 'Finished one', true),
      said('a', 'Command running in background with ID: aaa. Output is being written to: C:\a.output'),
      ended('aaa', 'completed'),
      used('b', 'Still going', true),
      said('b', 'Command running in background with ID: bbb. Output is being written to: C:\b.output'),
      used('c', 'Also going', true),
      said('c', 'Command running in background with ID: ccc. Output is being written to: C:\c.output'),
    ].join('\n'),
  );
  assert.deepStrictEqual(
    tasks.map((t) => `${t.name}:${t.status}`),
    ['Also going:running', 'Still going:running', 'Finished one:done'],
  );
});

test('a command the harness moved to the background is picked up too, and a failure says so', () => {
  const tasks = readTasks(
    [
      used('toolu_9', 'Watch the build', false), // started in the foreground
      said('toolu_9', 'Command was moved to the background (ID: bmoved) so that a message that arrived while it was running can reach you. Output is being written to: C:\m.output'),
      ended('bmoved', 'failed'),
    ].join('\n'),
  );
  assert.strictEqual(tasks[0].status, 'failed');
  assert.strictEqual(tasks[0].name, 'Watch the build');
  assert.match(tasks[0].note, /failed/);
});

test('an agent keeps going after it is launched, and ends like any other task', () => {
  const agent = (id) => line({ type: 'assistant', timestamp: '2026-10-12T10:00:00.000Z', message: { content: [{ type: 'tool_use', id, name: 'Agent', input: { description: 'Review the diff', prompt: 'look at it' } }] } });
  const receipt = 'Async agent launched successfully. (This tool result is internal metadata.)\nagentId: a847c6e3d56e7428a';
  let tasks = readTasks(agent('t1'));
  assert.deepStrictEqual([tasks[0].kind, tasks[0].name, tasks[0].status], ['Agent', 'Review the diff', 'running']);

  // The receipt is not the answer: an agent that has only just started is still
  // running, under the id it will report back with.
  tasks = readTasks([agent('t1'), said('t1', receipt)].join('\n'));
  assert.strictEqual(tasks[0].status, 'running');
  assert.strictEqual(tasks[0].id, 'a847c6e3d56e7428a');

  // It ends the way a background command does, and that notice can arrive as a
  // message rather than a queued one.
  const told = line({
    type: 'user',
    timestamp: '2026-10-12T10:02:00.000Z',
    message: { content: '<task-notification>\n<task-id>a847c6e3d56e7428a</task-id>\n<status>completed</status>\n<summary>Agent finished</summary>\n</task-notification>' },
  });
  tasks = readTasks([agent('t1'), said('t1', receipt), told].join('\n'));
  assert.strictEqual(tasks[0].status, 'done');
  assert.strictEqual(tasks[0].ended - tasks[0].started, 120000);

  // An agent that answers in its own result is finished there and then.
  tasks = readTasks([agent('t2'), said('t2', 'Here is what I found')].join('\n'));
  assert.strictEqual(tasks[0].status, 'done');
});

test('an ordinary command is not a background task', () => {
  assert.deepStrictEqual(readTasks([used('toolu_2', 'Quick one', false), said('toolu_2', 'all good')].join('\n')), []);
});

test('a command that merely printed those words is not mistaken for one', () => {
  const grep = ['Command running in background with ID: bi77lts0g', 'Command running in background with ID: bdd735f0o'].join('\n');
  assert.deepStrictEqual(readTasks([used('toolu_3', 'Search the transcript', false), said('toolu_3', grep)].join('\n')), []);
});
