// What you read while a session starts, and the way out of it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/chat.dart';
import 'package:loop_app/facts.dart';
import 'package:loop_app/main.dart';
import 'package:loop_app/starting.dart';

void main() {
  testWidgets('it turns by itself, by hand, and offers the way out', (t) async {
    var closed = 0;
    Future<void> show(bool ready) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StartingCard(ready: ready, onClose: () => closed++),
        ),
      ),
    );

    // the turn needs a frame to finish, then one to drop the old card
    Future<void> settle() async {
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
    }

    await show(false);
    expect(find.textContaining('Starting the session'), findsOneWidget);
    expect(find.text('Session ready'), findsNothing);

    // One card at a time, once the turn has finished.
    String shown() {
      final on = kFacts
          .where((f) => find.text(f.title).evaluate().isNotEmpty)
          .map((f) => f.title)
          .toList();
      expect(on.length, 1, reason: 'one card showing, not ${on.length}');
      return on.single;
    }

    final first = shown();

    // it turns on its own
    await t.pump(const Duration(seconds: 10));
    await settle();
    expect(shown(), isNot(first));

    // and when you ask it to
    final second = shown();
    await t.tap(find.byIcon(Icons.chevron_right));
    await settle();
    expect(shown(), isNot(second));
    await t.tap(find.byIcon(Icons.chevron_left));
    await settle();
    expect(shown(), second, reason: 'back goes back');

    // the session comes up: the button appears and closes it
    await show(true);
    await settle();
    expect(find.textContaining('Starting the session'), findsNothing);
    expect(find.text('Session ready'), findsOneWidget);
    await t.tap(find.text('Session ready'));
    expect(closed, 1);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  });

  testWidgets('the chat shows it while a session starts, and not after', (
    t,
  ) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const MaterialApp(
        home: ChatPage(dir: 'demo', sessionId: 'abc', title: 'Demo'),
      ),
    );
    await t.pump();
    bridge.chatLoaded = true;

    void live(String lamp, String status) {
      bridge.chatLive = {'lamp': lamp, 'status': status};
      bridge.notifyListeners();
    }

    // nothing yet
    live('idle', '');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(StartingCard), findsNothing);

    // the PC says the session is being started
    live('busy', 'Starting the session');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(StartingCard), findsOneWidget);
    expect(find.text('Session ready'), findsNothing);

    // it is up and working: the way out appears
    live('busy', 'Thinking');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(StartingCard), findsOneWidget);
    expect(find.text('Session ready'), findsOneWidget);

    // the turn ends and it goes by itself
    live('idle', '');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(StartingCard), findsNothing);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  test('every card says something, once', () {
    expect(kFacts.length, greaterThan(40));
    final titles = kFacts.map((f) => f.title).toSet();
    expect(titles.length, kFacts.length, reason: 'no repeats');
    for (final f in kFacts) {
      expect(f.tag.isNotEmpty, true);
      expect(f.title.length, lessThan(46), reason: '"${f.title}" is too long');
      expect(f.body.length, greaterThan(80), reason: '"${f.title}" is thin');
      expect(f.body.length, lessThan(300), reason: '"${f.title}" is long');
    }
  });
}
