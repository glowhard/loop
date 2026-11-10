// A whole answer that arrives in one burst (as Claude sends it after thinking)
// is shown at a steady pace, not all at once, and the finished message carries
// on from where the draft got to.
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/main.dart';

void main() {
  testWidgets('a burst is revealed over about three quarters of a second', (
    t,
  ) async {
    {
      bridge.chatOpen('demo', 'abc', '');
      final answer = List.generate(
        110,
        (i) => 'word${i % 10} ',
      ).join(); // ~660 chars
      // the 68 pieces Claude sent within 70ms, here all at once
      for (var i = 0; i < answer.length; i += 10) {
        bridge.hear({
          't': 'draft',
          'sessionId': 'abc',
          'd': answer.substring(
            i,
            i + 10 > answer.length ? answer.length : i + 10,
          ),
        });
      }
      expect(bridge.draft.length, answer.length);
      expect(bridge.draftShown, 0, reason: 'nothing jumps onto the screen');

      final seen = <int>[];
      for (var ms = 0; ms < 1200; ms += 100) {
        await t.pump(const Duration(milliseconds: 100));
        seen.add(bridge.draftShown);
      }
      // it grows steadily...
      expect(seen.first, greaterThan(0));
      expect(seen.first, lessThan(answer.length ~/ 2));
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
      // ...and is all there within about a second
      expect(seen[9], answer.length);

      // The finished message part way through: it continues, not restarts.
      bridge.hear({'t': 'draft', 'sessionId': 'abc', 'd': 'and more ' * 30});
      await t.pump(const Duration(milliseconds: 90));
      final shown = bridge.draftShown;
      bridge.hear({
        't': 'chat',
        'sessionId': 'abc',
        'items': [
          {'k': 'text', 'id': 't1', 'text': answer + 'and more ' * 30},
        ],
      });
      final item = bridge.chatItems.firstWhere((x) => x['id'] == 't1');
      expect(item['typeFrom'], shown);
      expect(item['fresh'], true);
      expect(bridge.draft, isEmpty);
      bridge.chatClose();
      await t.pump(const Duration(seconds: 5));
    }
  });
}
