// Questions asked one after another: what was picked on one must not show on,
// or lock, the next.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/chat.dart';
import 'package:loop_app/main.dart';

Map<String, dynamic> question(int n, String text, List<String> answers) => {
  'question': text,
  'context': ['Question $n of 3'],
  'direct': true,
  'options': [
    for (var i = 0; i < answers.length; i++)
      {'key': '${i + 1}', 'label': answers[i], 'on': i == 0},
  ],
};

void main() {
  testWidgets('the next question starts unpicked and can be answered', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532); // a phone
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatPage(dir: 'demo', sessionId: 'abc', title: 'Demo'),
      ),
    );
    await tester.pump();

    void ask(Map<String, dynamic>? a) {
      bridge.chatLoaded = true;
      bridge.chatLive = {'lamp': 'busy', 'ask': a};
      bridge.notifyListeners();
    }

    ask(question(1, 'How do you get there?', ['Walk', 'Bus', 'Long drive']));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Long drive'));
    await tester.pump(const Duration(milliseconds: 600));
    // picked: the tick is on it
    expect(find.byIcon(Icons.check), findsOneWidget);

    ask(
      question(2, 'Where do you usually head?', [
        'Park or nature',
        'City streets',
        'Long drive',
      ]),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Where do you usually head?'), findsOneWidget);
    // nothing picked yet, and every answer can be tapped
    expect(find.byIcon(Icons.check), findsNothing);
    for (final label in ['Park or nature', 'City streets', 'Long drive']) {
      final ink = tester.widget<InkWell>(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      );
      expect(ink.onTap, isNotNull, reason: '$label should be tappable');
    }
    await tester.tap(find.text('City streets'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byIcon(Icons.check), findsOneWidget);

    // the same question asked again later is new as well
    ask(null);
    await tester.pump(const Duration(milliseconds: 600));
    ask(
      question(2, 'Where do you usually head?', [
        'Park or nature',
        'City streets',
        'Long drive',
      ]),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byIcon(Icons.check), findsNothing);

    // let the page's own waits run out before the test ends
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
