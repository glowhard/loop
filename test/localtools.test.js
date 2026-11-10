// A session waits for the tools served on this PC, so none of them start red.
const test = require('node:test');
const assert = require('node:assert');
const net = require('net');
const localTools = require('../src/main/localtools');

test('only http tools on this PC are waited for, the account and the folder both', () => {
  const config = {
    mcpServers: {
      a: { type: 'http', url: 'http://127.0.0.1:7801/a' },
      b: { type: 'http', url: 'http://127.0.0.1:7801/b' },
      c: { type: 'http', url: 'https://mcp.example.com/mcp' },
      d: { command: 'node', args: ['x.js'] },
      e: { type: 'sse', url: 'http://localhost:9000/sse' },
    },
    projects: { 'D:/work/app': { mcpServers: { f: { type: 'http', url: 'http://127.0.0.1:7900/f' } } } },
  };
  assert.deepStrictEqual(localTools.localPorts(config, 'D:\\work\\app').sort(), ['127.0.0.1:7801', '127.0.0.1:7900', 'localhost:9000']);
  assert.deepStrictEqual(localTools.localPorts(config, 'D:\\other').sort(), ['127.0.0.1:7801', 'localhost:9000']);
});

const freePort = () =>
  new Promise((resolve) => {
    const s = net.createServer().listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });
const cfg = (port) => ({ mcpServers: { t: { type: 'http', url: `http://127.0.0.1:${port}/t` } } });

test('a session waits for a tool that is still starting', async () => {
  const port = await freePort();
  let server;
  setTimeout(() => (server = net.createServer().listen(port, '127.0.0.1')), 300);
  const t = Date.now();
  assert.strictEqual(await localTools.ready({}, '', { config: cfg(port), wait: 5000, every: 50 }), true);
  assert.ok(Date.now() - t >= 250);
  server.close();
});

test('a tool that never comes up is waited for once, then skipped', async () => {
  const port = await freePort();
  assert.strictEqual(await localTools.ready({}, '', { config: cfg(port), wait: 200, every: 50 }), false);
  const t = Date.now();
  assert.strictEqual(await localTools.ready({}, '', { config: cfg(port), wait: 5000, every: 50 }), true);
  assert.ok(Date.now() - t < 1500);
});
