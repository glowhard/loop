// The question card: choose then Next, type your own, Skip, several at once.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/question.dart';

Map<String, dynamic> q({
  int at = 1,
  int of = 2,
  bool multi = false,
  String text = 'Which fruit?',
}) => {
  'kind': 'question',
  'question': text,
  'header': 'Fruit',
  'at': at,
  'of': of,
  'multi': multi,
  'options': [
    {'key': '1', 'label': 'Apple', 'desc': 'Crisp'},
    {'key': '2', 'label': 'Banana', 'desc': ''},
    {'key': '3', 'label': 'Cherry', 'desc': ''},
  ],
};

void main() {
  late List<List<String>> sent;

  Future<void> show(WidgetTester t, Map<String, dynamic> ask) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuestionCard(
              key: ValueKey('${ask['at']}${ask['question']}'),
              ask: ask,
              onAnswer: (k, w) => sent.add([k, w]),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
  }

  FilledButton next(WidgetTester t) =>
      t.widget<FilledButton>(find.byType(FilledButton));

  setUp(() => sent = []);

  testWidgets('choosing does not send; Next does', (t) async {
    await show(t, q());
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Crisp'), findsOneWidget); // the description shows
    expect(next(t).onPressed, isNull); // nothing chosen yet
    await t.tap(find.text('Cherry'));
    await t.pump();
    expect(sent, isEmpty);
    await t.tap(find.text('Banana')); // changing your mind
    await t.pump();
    await t.tap(find.text('Next'));
    await t.pump();
    expect(sent, [
      ['2', ''],
    ]);
  });

  testWidgets('the last question says Submit', (t) async {
    await show(t, q(at: 2, of: 2));
    expect(find.text('Submit'), findsOneWidget);
  });

  testWidgets('typing your own answer', (t) async {
    await show(t, q());
    await t.tap(find.text('Type your own answer'));
    await t.pump();
    expect(next(t).onPressed, isNull); // empty words are not an answer
    await t.enterText(find.byType(TextField), 'Mango');
    await t.pump();
    await t.tap(find.text('Next'));
    await t.pump();
    expect(sent, [
      ['', 'Mango'],
    ]);
  });

  testWidgets('Skip moves on without an answer', (t) async {
    await show(t, q());
    await t.tap(find.text('Skip'));
    await t.pump();
    expect(sent, [
      ['skip', ''],
    ]);
    // and it cannot be answered twice while the next one comes
    await t.tap(find.text('Skip'), warnIfMissed: false);
    await t.pump();
    expect(sent.length, 1);
  });

  testWidgets('several at once where allowed', (t) async {
    await show(t, q(multi: true));
    expect(find.text('Choose any that apply'), findsOneWidget);
    await t.tap(find.text('Cherry'));
    await t.tap(find.text('Apple'));
    await t.tap(find.text('Banana'));
    await t.tap(find.text('Banana')); // and back off again
    await t.pump();
    await t.tap(find.text('Next'));
    await t.pump();
    expect(sent, [
      ['1,3', ''],
    ]);
  });

  testWidgets('the next question is a fresh card', (t) async {
    await show(t, q());
    await t.tap(find.text('Cherry'));
    await t.pump();
    await t.tap(find.text('Next'));
    await t.pump();
    await show(t, q(at: 2, text: 'Which drink?'));
    expect(find.text('Which drink?'), findsOneWidget);
    expect(next(t).onPressed, isNull); // nothing carried over
    await t.tap(find.text('Apple'));
    await t.pump();
    await t.tap(find.text('Submit'));
    await t.pump();
    expect(sent, [
      ['3', ''],
      ['1', ''],
    ]);
  });
}
