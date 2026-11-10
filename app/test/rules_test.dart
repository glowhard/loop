// The rules screen: what holds for every team, what this project adds, and how
// long the CEO leaves a quiet team alone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/main.dart';
import 'package:loop_app/rules.dart';
import 'package:loop_app/theme.dart';

void main() {
  final sent = <Map<String, dynamic>>[];

  setUp(() {
    sent.clear();
    bridge.onAsk = (m) {
      sent.add(m);
      return switch (m['action']) {
        'rules' => {
          'dir': 'proj-a',
          'house': '1. Save tokens above all.\n2. One task, one owner.',
          'rules': '',
          'mins': 30,
          'policy': 'Never deploy on a Friday.',
          'inForce': 30,
          'memberRules': {'s2': 'Ask the CTO first.'},
        },
        'policy' => {'ok': true},
        _ => null,
      };
    };
  });
  tearDown(() => bridge.onAsk = null);

  Future<void> open(WidgetTester t, {Size size = const Size(390, 844)}) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        theme: loopTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showRules(context, 'proj-a'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('it shows the company, the project and the clock', (t) async {
    await open(t);
    expect(find.text('Rules'), findsOneWidget);
    expect(find.text('The company'), findsOneWidget);
    expect(
      find.text('The CEO asks for an update after 30 minutes of quiet.'),
      findsOneWidget,
    );
    // While nothing is written, the rules Loop ships with are there to read.
    expect(find.textContaining('Save tokens'), findsNothing);
    await t.tap(find.text('Read the rules Loop ships with'));
    await t.pump();
    expect(find.textContaining('Save tokens above all'), findsOneWidget);

    // What this project adds is further down, where a scroll reaches it.
    await t.drag(find.byType(ListView), const Offset(0, -500));
    await t.pump();
    expect(find.text('This project'), findsOneWidget);
    expect(find.text('Never deploy on a Friday.'), findsOneWidget);
  });

  testWidgets('writing the company rules sends them with the clock', (t) async {
    await open(t);
    await t.enterText(find.byType(TextField).first, 'Ship on Tuesdays.');
    await t.tap(find.text('45 min'));
    await t.pump();
    expect(
      find.text('The CEO asks for an update after 45 minutes of quiet.'),
      findsOneWidget,
    );
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    final wrote = sent.lastWhere((m) => m['action'] == 'policy');
    expect(wrote['scope'], 'company');
    expect(wrote['text'], 'Ship on Tuesdays.');
    expect(wrote['mins'], 45);
  });

  testWidgets('the project rules go up on their own, unchanged ones stay put', (
    t,
  ) async {
    await open(t);
    await t.drag(find.byType(ListView), const Offset(0, -500));
    await t.pump();
    await t.enterText(find.byType(TextField).last, 'Ask before migrations.');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    final wrote = sent.where((m) => m['action'] == 'policy').toList();
    expect(wrote.length, 1); // the company box was not touched
    expect(wrote.single['scope'], 'project');
    expect(wrote.single['text'], 'Ask before migrations.');
  });

  testWidgets('turning the clock off says so in words', (t) async {
    await open(t);
    await t.tap(find.text('Off'));
    await t.pump();
    expect(
      find.text('The CEO is not asked to chase updates.'),
      findsOneWidget,
    );
  });

  testWidgets('on a wide screen it opens as a dialog', (t) async {
    await open(t, size: const Size(1400, 900));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('The company'), findsOneWidget);
  });

  testWidgets('rules for one member are read and written for that member', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        theme: loopTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showMemberRules(context, 'proj-a', {
                  'id': 's2',
                  'title': 'Dev one',
                }),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('Rules for Dev one'), findsOneWidget);
    expect(find.text('Ask the CTO first.'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Ask the CTO before deploying.');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    final wrote = sent.lastWhere((m) => m['action'] == 'policy');
    expect(wrote['scope'], 'member');
    expect(wrote['session'], 'Dev one');
    expect(wrote['text'], 'Ask the CTO before deploying.');
  });
}
