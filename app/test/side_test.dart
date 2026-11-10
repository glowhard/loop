// The panel beside a conversation: the sections it holds, folding it away, and
// the fact that a phone gets the same sections as sheets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/main.dart';
import 'package:loop_app/side.dart';
import 'package:loop_app/theme.dart';

void main() {
  const open = {'dir': 'proj-a', 'sessionId': 'abc', 'server': ''};

  setUp(() {
    bridge.onAsk = (m) => switch (m['t'] ?? m['action']) {
      'tasks' when m['t'] == 'tasks' => {
        'tasks': [
          {
            'id': 'b1',
            'kind': 'Bash',
            'name': 'The build',
            'status': 'running',
            'started': DateTime.now().millisecondsSinceEpoch - 4000,
            'ended': 0,
            'note': '',
            'file': 'C:/t/b1.output',
          },
        ],
      },
      _ => null,
    };
  });
  tearDown(() => bridge.onAsk = null);

  Future<void> panel(WidgetTester t, {bool folded = false}) async {
    var shown = !folded;
    await t.pumpWidget(
      MaterialApp(
        theme: loopTheme(),
        home: StatefulBuilder(
          builder: (context, set) => Scaffold(
            body: Row(
              children: [
                const Expanded(child: SizedBox()),
                if (shown)
                  SidePanel(open: open, onClose: () => set(() => shown = false))
                else
                  SideRail(onOpen: (_) => set(() => shown = true)),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
  }

  testWidgets('it opens on the background tasks, and the sections switch', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await panel(t);

    expect(find.text('Background tasks'), findsOneWidget);
    expect(find.text('The build'), findsOneWidget);

    await t.tap(find.byTooltip('Terminals'));
    await t.pump();
    expect(find.text('Terminals'), findsOneWidget);
    expect(find.text('No terminal open'), findsOneWidget);
    expect(find.text('The build'), findsNothing);
  });

  testWidgets('folding it leaves a strip that brings it straight back', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await panel(t);

    await t.tap(find.byTooltip('Hide this panel'));
    await t.pump();
    expect(find.text('Background tasks'), findsNothing);

    // The strip still names what is behind it.
    await t.tap(find.byTooltip('Tickets'));
    await t.pump();
    await t.pump();
    expect(find.text('Background tasks'), findsOneWidget);
  });

  testWidgets('a phone gets the same section from the bottom', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        theme: loopTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showSide(context, Side.tasks, open),
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
    expect(find.text('Background tasks'), findsOneWidget);
    expect(find.text('The build'), findsOneWidget);
  });
}
