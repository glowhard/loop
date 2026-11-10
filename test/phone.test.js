// The phone bridge: reading Claude's question off a screen, and what a chat
// looks like once the heavy parts are left behind for the phone to ask for.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const transcript = require('../src/main/transcript');

// screenAsk lives in the renderer, which has no module system: take the function out.
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'renderer', 'phone.js'), 'utf8');
const from = src.indexOf('function screenAsk(tab) {');
// With menuAsk, which reads the choices that come without numbers.
const body = src.slice(from, src.indexOf('// The line Claude shows while it works', from));
const screenAsk = new Function('screenRows', body + '; return screenAsk;')((t) => t.rows);

test('a question with a description under each answer', () => {
  const ask = screenAsk({
    rows: [
      ' [ ] Colour',
      'Which colour do you prefer?',
      '> 1. Red',
      '     The colour red',
      '  2. Blue',
      '     The colour blue',
      '  3. Type something.',
      '────────────────',
      '  4. Chat about this',
      'Enter to select · ↑/↓ to navigate',
    ],
  });
  assert.equal(ask.question, 'Which colour do you prefer?');
  assert.deepEqual(ask.options.map((o) => o.label), ['Red', 'Blue', 'Type something.', 'Chat about this']);
  assert.equal(ask.options[0].on, true);
});

test('a permission prompt, with what it is about', () => {
  const ask = screenAsk({
    rows: [
      '│ Edit file                     │',
      '│  2 +const b = 2;              │',
      'Do you want to make this edit to app.js?',
      '❯ 1. Yes',
      '  2. Yes, allow all edits during this session (shift+tab)',
      '  3. No, and tell Claude what to do differently (esc)',
    ],
  });
  assert.match(ask.question, /make this edit/);
  assert.equal(ask.options.length, 3);
  assert.equal(ask.options[2].label, 'No, and tell Claude what to do differently');
  assert.ok(ask.context.join(' ').includes('Edit file'));
});

test('a numbered list in ordinary writing is not a question', () => {
  // This is what Claude had written on screen when the app offered a question
  // card that answered nothing: plain text, with the box to type in below it.
  assert.equal(
    screenAsk({
      rows: [
        'Watch for four things as it answers:',
        '1. Your message should appear the instant you hit send',
        '2. The words should start arriving in roughly two seconds',
        '3. The markdown should render as a proper numbered list',
        '4. Scrolling while it writes should stay smooth',
        '',
        '>',
        '  bypass permissions on (shift+tab to cycle)',
      ],
    }),
    null,
  );
});

test('a question that has been answered is not still a question', () => {
  // The words stay on screen afterwards; what goes is the cursor mark, and the
  // box to type in comes back.
  assert.equal(
    screenAsk({
      rows: [
        'Which colour do you prefer?',
        '  1. Red',
        '  2. Blue',
        '● Red',
        '>',
      ],
    }),
    null,
  );
});

test('a choice without numbers, on a short screen, is a question answered with arrows', () => {
  // Claude Code 2.1 asking whether to trust a new folder, captured from a real
  // terminal: the dialog at the top, the rest of the screen blank.
  const rows = [
    '────────────────────────────────────────',
    ' Accessing workspace:',
    '',
    ' /root/work/loop-demo',
    '',
    " Quick safety check: Is this a project you created or one you trust? (Like your own code, a well-known open source",
    ' project, or work from your team). If not, take a moment to review what is in this folder first.',
    '',
    ' Security guide',
    '',
    ' ❯ No, exit',
    '   Yes, I trust this folder',
    '',
    ' Enter to confirm · Esc to cancel',
    ...Array(30).fill(''),
  ];
  const ask = screenAsk({ rows });
  assert.ok(ask, 'the dialog is seen though it sits above thirty blank rows');
  assert.strictEqual(ask.question, 'Quick safety check: Is this a project you created or one you trust?');
  assert.deepStrictEqual(
    ask.options.map((o) => [o.label, o.key, o.on]),
    [
      ['No, exit', '\r', true],
      ['Yes, I trust this folder', '\x1b[B\r', false],
    ],
  );
});

test("a question's context is what Claude drew for it, not the chat above", () => {
  // Captured from Claude Code 2.1: an earlier answer is still on screen above the rule.
  const ask = screenAsk({
    rows: [
      '● User answered Claude’s questions:',
      '  ⎿  · Red or blue? → Blue',
      '● You picked blue.',
      '✻ Cogitated for 4s · done 9:43 PM',
      '❯ Use the AskUserQuestion tool to ask me one question: small, medium or large.',
      '────────────────────────────────────────────────────────────',
      '←  ☐ Size  ✔ Submit  →',
      '',
      'Small, medium or large?',
      '',
      '❯ 1. Small',
      '  2. Medium',
      '  3. Large',
      '  4. Type something.',
      '────────────────────────────────────────────────────────────',
      '  5. Chat about this',
      '',
      'Enter to select · Tab/Arrow keys to navigate · Esc to cancel',
    ],
  });
  assert.strictEqual(ask.question, 'Small, medium or large?');
  assert.ok(!ask.context.some((l) => /blue|Cogitated|AskUserQuestion/.test(l)), JSON.stringify(ask.context));
});

test('a typing box under a choice means nothing is waiting', () => {
  const ask = screenAsk({ rows: ['Pick one?', '❯ Fast', '  Careful', '', '❯ ', '? for shortcuts'] });
  assert.strictEqual(ask, null);
});

test('an ordinary screen is not a question', () => {
  assert.equal(screenAsk({ rows: ['● Created note.txt', '✻ Crunched for 6s', '>'] }), null);
});

test('a chat travels without its outputs, which are fetched by the step id', () => {
  const kept = new Map();
  const slim = transcript.slim(
    [
      { k: 'tool', id: 't1', name: 'Edit', title: 'Edited file', sub: 'app.js', kind: 'edit', detail: 'C:/p/app.js', diff: { old: 'a\nb', new: 'a\nb\nc' } },
      { k: 'result', id: 't1', ok: true, text: 'x'.repeat(900) },
      { k: 'user', id: 'u1', text: 'look', images: [{ type: 'image/png', b64: 'QUJD' }] },
    ],
    kept,
  );
  const sent = JSON.stringify(slim);
  assert.ok(sent.length < 400, `a step line should be small, was ${sent.length}`);
  assert.ok(!sent.includes('xxxx'), 'the output stays on the PC');
  assert.ok(!sent.includes('QUJD'), 'the picture stays on the PC');
  assert.deepEqual(slim[0].lines, { add: 3, del: 2 });
  assert.equal(slim[1].has, true);
  assert.equal(slim[2].images[0].ref, 'u1:0');
  // and the phone can ask for both; the picture is only made small when it is
  assert.equal(kept.get('t1').result.length, 900);
  assert.deepEqual(kept.get('img:u1:0'), { img: true, b64: 'QUJD' });
});

test('a picture sent from the phone shows as a picture again', () => {
  const items = transcript.parse([
    JSON.stringify({
      type: 'user',
      uuid: 'u9',
      timestamp: '2026-01-01T00:00:00Z',
      message: { role: 'user', content: 'see C:\\x\\phone-uploads\\phone-ab12cd-9f.png now' },
    }),
  ]);
  assert.equal(items[0].text, 'see now');
  assert.equal(items[0].images.length, 1);
});

test('a slash command run from the phone shows its answer', () => {
  // The records Claude Code writes for /usage and /compact in a session with no terminal.
  const usage = 'You are currently using your subscription to power your Claude Code usage\n\nCurrent session: 28% used';
  const items = transcript.parse([
    JSON.stringify({ type: 'user', uuid: 'c1', timestamp: '2026-01-01T00:00:00Z', message: { role: 'user', content: '<local-command-caveat>The command below was run directly in Claude Code</local-command-caveat>' } }),
    JSON.stringify({ type: 'user', uuid: 'c2', timestamp: '2026-01-01T00:00:01Z', message: { role: 'user', content: '<command-name>/usage</command-name>\n<command-message>usage</command-message>\n<command-args></command-args>' } }),
    JSON.stringify({ type: 'system', subtype: 'local_command', uuid: 'c3', timestamp: '2026-01-01T00:00:02Z', content: `<local-command-stdout>${usage}</local-command-stdout>` }),
    // /compact typed in a terminal: its answer keeps colour codes, and the summary it writes is for Claude
    JSON.stringify({ type: 'user', uuid: 'c4', timestamp: '2026-01-01T00:00:03Z', message: { role: 'user', content: '<local-command-stdout>\u001b[2mCompacted \u001b[22m</local-command-stdout>' } }),
    JSON.stringify({ type: 'user', uuid: 'c5', isCompactSummary: true, timestamp: '2026-01-01T00:00:04Z', message: { role: 'user', content: 'This session is being continued from a previous conversation.' } }),
  ]);
  assert.deepEqual(
    items.map((i) => [i.k, i.text]),
    [
      ['user', '/usage'],
      ['text', 'You are currently using your subscription to power your Claude Code usage  \n\nCurrent session: 28% used  '], // shown as an answer, its lines kept apart
      ['note', 'Compacted'], // a one-liner stays a note
    ],
  );
});

test('/context is cut to its summary, tables kept whole', () => {
  const full = '## Context Usage\n\n**Model:** haiku\n\n| Category | Tokens |\n|---|---|\n| System | 3.5k |\n\n### MCP Tools\n\n| Tool | Tokens |\n| a | 1 |';
  const t = transcript.commandText(full);
  assert.ok(!t.includes('MCP Tools'), 'the per-tool list is dropped');
  assert.ok(t.includes('| Category | Tokens |\n|---|---|\n| System | 3.5k |'), 'table rows stay as they are');
});

// ---------- a session comes here when you open it ----------
// Clicking a session on the phone or the web moves it into Loop, wherever it
// was working. bringHere is that move; it lives in the renderer too.
function bringRunner({ live, stopped = true, otherWindow = false }) {
  const bodyFrom = src.indexOf('async function bringHere(p, s) {');
  const fn = src.slice(bodyFrom, src.indexOf('\n}\n', bodyFrom) + 2);
  const calls = { closed: 0, found: 0 };
  const S = { live: new Map(live ? [['s1', live]] : []) };
  const deck = {
    findTab: async () => (calls.found++, otherWindow),
    closeElsewhere: async () => (calls.closed++, stopped ? (S.live.delete('s1'), true) : false),
  };
  const scope = {
    S,
    deck,
    tabFor: () => null,
    whereItRuns: () => 'the Claude desktop app',
    sleep: () => Promise.resolve(),
  };
  const keys = Object.keys(scope);
  const bringHere = new Function(...keys, fn + '; return bringHere;')(...keys.map((k) => scope[k]));
  return { bringHere, calls, S };
}

const proj = { dir: 'C--p', server: '', exists: true };
const sess = { id: 's1' };

test('a session running in another program is taken over, not refused', async () => {
  const r = bringRunner({ live: { status: 'busy', entrypoint: 'claude-desktop' } });
  assert.deepEqual(await r.bringHere(proj, sess), { ok: true });
  assert.equal(r.calls.closed, 1); // the copy there was stopped
  assert.equal(r.S.live.has('s1'), false);
});

test('nothing is stopped for a session that is not running, or is already ours', async () => {
  const idle = bringRunner({ live: null });
  assert.deepEqual(await idle.bringHere(proj, sess), { ok: true });
  assert.equal(idle.calls.closed, 0);

  const ours = bringRunner({ live: { status: 'busy', bg: true } });
  assert.deepEqual(await ours.bringHere(proj, sess), { ok: true });
  assert.equal(ours.calls.closed, 0);
});

test('when the copy will not let go, the move says so instead of pretending', async () => {
  const r = bringRunner({ live: { status: 'idle', entrypoint: 'cli' }, stopped: false });
  const out = await r.bringHere(proj, sess);
  assert.equal(out.ok, false);
  assert.match(out.text, /Could not stop the copy in the Claude desktop app/);

  // A second Loop window on the same PC is the one case left alone.
  const two = bringRunner({ live: { status: 'idle' }, otherWindow: true });
  const both = await two.bringHere(proj, sess);
  assert.equal(both.ok, false);
  assert.match(both.text, /another Loop window/);
  assert.equal(two.calls.closed, 0);
});

test('a session on a server stays on its server', async () => {
  const r = bringRunner({ live: { status: 'busy' } });
  assert.deepEqual(await r.bringHere({ ...proj, server: 'srv1' }, sess), { ok: true });
  assert.equal(r.calls.closed, 0);
});

test('/usage is read as limits, the way Claude Desktop shows them', () => {
  const text = [
    'You are currently using your subscription to power your Claude Code usage',
    '',
    'Current session: 3% used · resets Oct 16, 10:20pm (Asia/Kolkata)',
    'Current week (all models): 29% used · resets Oct 18, 10:30pm (Asia/Kolkata)',
    'Current week (Fable): 0% used · resets Oct 18, 10:30pm (Asia/Kolkata)',
  ].join('\n');
  const now = new Date(2026, 9, 16, 18, 0).getTime(); // 16 Oct, 6pm on this PC
  const l = transcript.usageLimits(text, now);
  assert.deepEqual(
    l.map((x) => [x.label, x.pct]),
    [
      ['Session limit', 3],
      ['Weekly', 29],
      ['Weekly (Fable)', 0],
    ],
  );
  assert.equal(l[0].resetsAt, new Date(2026, 9, 16, 22, 20).getTime());
  assert.equal(l[1].resetsAt, new Date(2026, 9, 18, 22, 30).getTime());
});

test('a goal is charged once per model call, from when it was given', () => {
  const at = (s) => `2026-10-16T12:00:${String(s).padStart(2, '0')}Z`;
  const call = (id, s, u) => JSON.stringify({ type: 'assistant', timestamp: at(s), message: { id, usage: u } });
  const u = { input_tokens: 2, cache_creation_input_tokens: 100, cache_read_input_tokens: 5000, output_tokens: 50 };
  const lines = [
    call('before', 1, u), // before the goal: not counted
    call('m1', 10, u),
    call('m1', 10, u), // the same call, written again for its next block
    call('m2', 20, u),
    JSON.stringify({ type: 'user', timestamp: at(30), message: { content: 'hi' } }),
  ];
  assert.deepEqual(transcript.tokensSince(lines, Date.parse(at(5))), { fresh: 304, cached: 10000, calls: 2 });
});

test("Home reads the lead's latest plan or report, and the goal it answers", () => {
  const turns = [
    { role: 'user', text: 'New goal from the user for the team: add an about page | Call role_brief. Do small jobs yourself', at: 1 },
    { role: 'assistant', text: '**Plan:** about page\n\n- Dev builds about.html\n- Link it from index\n- I review the commit\n\nNeed from you: nothing', at: 2 },
  ];
  const plan = transcript.leadReport(turns);
  assert.deepEqual(plan, { kind: 'plan', at: 2, lead: 'about page', bullets: ['Dev builds about.html', 'Link it from index', 'I review the commit'], need: '', goal: 'add an about page', goalAt: 1 });
  turns.push({ role: 'user', text: 'From LeanDemo Dev on the team: T2 done 15f4944', at: 3 }, { role: 'assistant', text: 'Done: the about page is in\n1. about.html added\n2. linked from index.html\n**Need from you:** go live?', at: 4 });
  const done = transcript.leadReport(turns);
  assert.equal(done.kind, 'done');
  assert.deepEqual(done.bullets, ['about.html added', 'linked from index.html']);
  assert.equal(done.need, 'go live?');
  assert.equal(done.goal, 'add an about page'); // a teammate's message is not the goal
  assert.equal(transcript.leadReport([{ role: 'assistant', text: 'Sure, looking now.', at: 1 }]), null);
});

test('without Plan: or Done:, an unmarked report is a Done card, and only once the work is back', () => {
  const goal = { role: 'user', text: 'add a FAQ page, the developer builds it', at: 1 };
  const hand = { role: 'tool', name: 'mcp__team-memory__team_manage', text: 'tell', at: 2 };
  const plan = { role: 'assistant', text: 'The FAQ ticket is on the board.\n\n- Dev builds faq.html\n- I review\n\nNeed from you: nothing.', at: 3 };
  // handed over, no answer yet, and not marked Plan: no card (it could be a progress note)
  assert.equal(transcript.leadReport([goal, hand, plan]), null);
  // the teammate answered, and the lead reported: the report
  const reply = { role: 'user', text: 'From LeanDemo Dev on the team: T4 done, 269c77a', at: 4 };
  const report = { role: 'assistant', text: 'T4 is done.\n- faq.html added\nNeed from you: nothing.', at: 5 };
  const r = transcript.leadReport([goal, hand, plan, reply, report]);
  assert.equal(r.kind, 'done');
  assert.equal(r.goal, 'add a FAQ page, the developer builds it');
  // a small job done alone, no hand-over: the report
  assert.equal(transcript.leadReport([goal, { role: 'assistant', text: 'Fixed the typo.\n- one line in index.html\nNeed from you: nothing', at: 2 }]).kind, 'done');
  // a message with neither: no card
  assert.equal(transcript.leadReport([goal, { role: 'assistant', text: 'Looking into it.', at: 2 }]), null);
});

test("a card's title is the user's goal, without the app's own prefix", () => {
  const r = transcript.leadReport([
    { role: 'user', text: 'New technical goal: add faq.html with three questions', at: 1 },
    { role: 'assistant', text: 'Done: FAQ is in\n- faq.html added\nNeed from you: nothing', at: 2 },
  ]);
  assert.equal(r.goal, 'add faq.html with three questions');
});

test("Loop's own instructions on a hand-over are not shown in the chat", () => {
  const items = transcript.parse([
    JSON.stringify({ type: 'user', uuid: 'h1', timestamp: '2026-01-01T00:00:00Z', message: { role: 'user', content: 'From LeanDemo Dev on the team: T4 done, 269c77a | If this is work for you: when it is done, reply to LeanDemo Dev with team_manage (action tell)' } }),
    JSON.stringify({ type: 'user', uuid: 'h2', timestamp: '2026-01-01T00:00:01Z', message: { role: 'user', content: 'New goal from the user for the team: add a FAQ | Call role_brief. Do small jobs yourself' } }),
  ]);
  // A teammate's message is shown as from that session, by name, not as the user's.
  assert.deepEqual(items.map((i) => [i.k, i.from || '', i.text]), [
    ['peer', 'LeanDemo Dev', 'T4 done, 269c77a'],
    ['user', '', 'New goal from the user for the team: add a FAQ'],
  ]);
  const now = transcript.parse([
    JSON.stringify({ type: 'user', uuid: 'h3', timestamp: '2026-01-01T00:00:02Z', message: { role: 'user', content: 'Session message from "Admin Developer": branch sub/fix-1 ready | If this is work for you: reply' } }),
  ]);
  assert.deepEqual([now[0].k, now[0].from, now[0].text], ['peer', 'Admin Developer', 'branch sub/fix-1 ready']);
});
