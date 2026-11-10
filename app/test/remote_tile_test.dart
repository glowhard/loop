// The Remote Control switch in a session's options: it says what is actually
// true, and refuses to pretend for a session Loop does not run.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/main.dart';
import 'package:loop_app/sessions.dart';
import 'package:loop_app/theme.dart';

void main() {
  final sent = <Map<String, dynamic>>[];
  late Map<String, dynamic> state;

  setUp(() {
    sent.clear();
    state = {'on': false, 'live': false, 'running': true, 'where': ''};
    bridge.onAsk = (m) {
      sent.add(m);
      return switch (m['action']) {
        'remoteState' => state,
        'remote' => {'on': m['on']},
        _ => null,
      };
    };
  });
  tearDown(() => bridge.onAsk = null);

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        theme: loopTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => sessionSheet(
                  context,
                  'proj-a',
                  's1',
                  () {},
                  session: {'id': 's1', 'title': 'Dev one', 'lamp': 'idle'},
                ),
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

  testWidgets('a session running in the Claude desktop app says where to switch it', (t) async {
    state = {
      'on': false,
      'live': false,
      'running': true,
      'where': 'the Claude desktop app',
    };
    await open(t);
    expect(find.text('Remote Control'), findsOneWidget);
    expect(
      find.textContaining('Runs in the Claude desktop app, which owns this switch'),
      findsOneWidget,
    );
    // The switch cannot be flipped from here, so it does not pretend to be.
    final tile = t.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.onChanged, isNull);
  });

  testWidgets('a session that is really connected shows as on', (t) async {
    state = {'on': false, 'live': true, 'running': true, 'where': ''};
    await open(t);
    expect(find.text('Connected to claude.ai.'), findsOneWidget);
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).value, true);
  });

  testWidgets('switching it on asks the PC, then reads back what happened', (t) async {
    await open(t);
    expect(find.textContaining("Claude's own switch"), findsOneWidget);
    state = {'on': true, 'live': true, 'running': true, 'where': ''};
    await t.tap(find.byType(SwitchListTile));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    final asked = sent.firstWhere((m) => m['action'] == 'remote');
    expect(asked['sessionId'], 's1');
    expect(asked['on'], true);
    // And it looked again rather than trusting its own guess.
    expect(sent.where((m) => m['action'] == 'remoteState').length, 2);
    expect(find.text('Connected to claude.ai.'), findsOneWidget);
  });

  testWidgets('one that is off but wanted on says it connects at its next start', (t) async {
    state = {'on': true, 'live': false, 'running': false, 'where': ''};
    await open(t);
    expect(find.text('Connects as soon as Loop starts it.'), findsOneWidget);
  });
}
