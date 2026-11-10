// A stand-in for Claude Code's stream-json mode, for the interrupt tests.
// Argument: "obeys" answers an interrupt and ends the turn, as Claude Code
// does; "slow" answers it and takes its time; "deaf" ignores it, which is what
// a wedged turn looks like; "asks" stops to ask a question instead.
const mode = process.argv[2];
const NL = String.fromCharCode(10);
let line = '';
let self = 0;
process.stdout.write('{"type":"system","subtype":"init"}\n');
process.stdin.on('data', (d) => {
  line += d.toString();
  const parts = line.split('\n');
  line = parts.pop();
  for (const p of parts) {
    if (!p.trim()) continue;
    const m = JSON.parse(p);
    if (m.type === 'user') {
      // Done at once, for the tests about how many stay warm.
      if (mode === 'quick') {
        process.stdout.write('{"type":"result","subtype":"success"}' + NL);
        continue;
      }
      // Done at once, and then a turn of its own, the way Claude Code answers
      // a background command finishing with nobody having said anything. The
      // next message is worked on without an end.
      if (mode === 'self') {
        self = (self || 0) + 1;
        if (self > 1) {
          process.stdout.write('{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","name":"Bash"}}}' + NL);
          continue;
        }
        process.stdout.write('{"type":"result","subtype":"success"}' + NL);
        setTimeout(() => {
          process.stdout.write('{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"text"}}}' + NL);
          process.stdout.write('{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"}}}' + NL);
          process.stdout.write('{"type":"result","subtype":"success"}' + NL);
        }, 300);
        continue;
      }
      // It starts answering and then keeps working, with no end of turn.
      process.stdout.write('{"type":"stream_event","event":{"delta":{"type":"text_delta","text":"working"}}}\n');
        if (mode === 'asks') {
        process.stdout.write(
          JSON.stringify({
            type: 'control_request',
            request_id: 'q1',
            request: { subtype: 'can_use_tool', tool_name: 'AskUserQuestion', input: { questions: [{ question: 'Which one?', options: [{ label: 'A' }, { label: 'B' }] }] } },
          }) + NL,
        );
      }
    }
    if (m.type === 'control_response') process.stdout.write(JSON.stringify({ seen: 'answer', was: m.response.response.behavior }) + NL);
    if (m.type === 'control_request' && m.request && m.request.subtype === 'interrupt') {
      if (mode === 'deaf') continue;
      process.stdout.write(JSON.stringify({ type: 'control_response', response: { subtype: 'success', request_id: m.request_id, response: { still_queued: [] } } }) + NL);
      // Claude Code puts its tools down first and writes the result after.
      if (mode === 'obeys') setTimeout(() => process.stdout.write('{"type":"result","subtype":"error_during_execution"}' + NL), 200);
    }
  }
});
