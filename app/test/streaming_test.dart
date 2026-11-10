// An answer as it is being written: markdown from the first word, with
// half-written markup healed until the rest of it arrives.
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/chat.dart';

void main() {
  test('an open code fence is closed, so the rest is not swallowed', () {
    expect(
      healMarkdown('Here is the fix:\n```dart\nfinal x = 1;'),
      'Here is the fix:\n```dart\nfinal x = 1;\n```',
    );
    // One that is already closed is left exactly as it is.
    const whole = 'Here:\n```dart\nfinal x = 1;\n```\nand that is all.';
    expect(healMarkdown(whole), whole);
  });

  test('a bold run or a code span half-typed is balanced, not shown raw', () {
    expect(healMarkdown('It is **very'), 'It is **very**');
    expect(healMarkdown('It is **very** clear'), 'It is **very** clear');
    expect(healMarkdown('Call `memory_sea'), 'Call `memory_sea`');
    expect(healMarkdown('Call `memory_search` first'), 'Call `memory_search` first');
    // Stars inside a finished code span are code, not markup.
    expect(healMarkdown('Use `a ** b` here'), 'Use `a ** b` here');
  });

  test('a link whose address has not arrived shows as its words', () {
    expect(healMarkdown('See [the docs](https://exa'), 'See the docs');
    expect(healMarkdown('See [the do'), 'See the do');
    expect(
      healMarkdown('See [the docs](https://example.com) now'),
      'See [the docs](https://example.com) now',
    );
  });

  test('a heading or a list arriving mid-line is left alone', () {
    expect(healMarkdown('## What changed\n\n- the switch'), '## What changed\n\n- the switch');
    expect(healMarkdown(''), '');
  });
}
