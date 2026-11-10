const test = require('node:test');
const assert = require('node:assert');
const { encodePath, UUID_RE, peek } = require('../src/main/scanner');

test('encodePath matches how Claude Code names project folders', () => {
  assert.strictEqual(encodePath('D:\\Personal\\automation'), 'D--Personal-automation');
  assert.strictEqual(encodePath('D:\\Jobs\\Acme\\LMS\\lms_tech'), 'D--Jobs-Acme-LMS-lms-tech');
  assert.strictEqual(encodePath('D:\\'), 'D--');
});

test('UUID_RE accepts session ids and rejects anything else', () => {
  assert.ok(UUID_RE.test('00e3cdef-bb15-4768-861e-a547d98e1ba1'));
  assert.ok(!UUID_RE.test('../../etc/passwd'));
  assert.ok(!UUID_RE.test('00e3cdef-bb15-4768-861e-a547d98e1ba1 & calc'));
});

test('peek refuses ids that could escape the projects folder', async () => {
  assert.deepStrictEqual(await peek('..', '00e3cdef-bb15-4768-861e-a547d98e1ba1'), []);
  assert.deepStrictEqual(await peek('D--x', 'not-a-uuid'), []);
});
