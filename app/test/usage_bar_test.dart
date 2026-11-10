import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/chat.dart';

void main() {
  final now = DateTime(2026, 10, 16, 17, 55);
  test('a reset within a day reads as time left', () {
    final at = DateTime(2026, 10, 16, 22, 20).millisecondsSinceEpoch;
    expect(UsageBar.resets(at, now), 'Resets in 4 hr 25 min');
  });
  test('a reset further off reads as a day and a time', () {
    final at = DateTime(2026, 10, 18, 22, 30).millisecondsSinceEpoch;
    expect(UsageBar.resets(at, now), 'Resets Sun 10:30 PM');
  });
  test('no reset time, no line', () {
    expect(UsageBar.resets(null, now), '');
  });
}
