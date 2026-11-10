// The background tasks list: what is running, what finished, and how long each
// one took. The PC is stood in for, so this is about what the page shows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/main.dart';
import 'package:loop_app/tasks.dart';
import 'package:loop_app/theme.dart';

Map<String, dynamic> task(
  String name, {
  String status = 'running',
  String kind = 'Bash',
  int secs = 0,
  String id = 'b1',
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return {
    'id': id,
    'kind': kind,
    'name': name,
    'status': status,
    'started': now - secs * 1000,
    'ended': status == 'running' ? 0 : now,
    'note': status == 'failed' ? 'Background command failed (exit code 1)' : '',
    'file': 'C:/tasks/$id.output',
  };
}

Future<void> openPage(WidgetTester tester) async {
  // A phone-shaped surface: the sheet is sized against the screen it is on.
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: loopTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  showTasks(context, dir: 'D--x', sessionId: 'abc'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120)); // the sheet rising
  }
}

void main() {
  tearDown(() => bridge.onAsk = null);

  testWidgets('what is running is listed above what has finished', (
    tester,
  ) async {
    bridge.onAsk = (m) => m['t'] == 'tasks'
        ? {
            'tasks': [
              task('The build', secs: 32),
              task('The old one', status: 'done', secs: 80, id: 'b2'),
              task('The broken one', status: 'failed', secs: 5, id: 'b3'),
            ],
          }
        : null;
    await openPage(tester);

    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Finished 2'), findsOneWidget);
    expect(find.text('The build'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    // A running task says how long it has been going, in seconds. It is still
    // going as the test runs, so the second it is on is not pinned down.
    expect(find.textContaining(RegExp(r'^3[0-9]s$')), findsOneWidget);
    expect(find.text('1m 20s'), findsOneWidget);

    // Running comes first on the page.
    final running = tester.getTopLeft(find.text('The build')).dy;
    final done = tester.getTopLeft(find.text('The old one')).dy;
    expect(running, lessThan(done));
  });

  testWidgets('with nothing running it says so instead of looking broken', (
    tester,
  ) async {
    bridge.onAsk = (m) => m['t'] == 'tasks' ? {'tasks': <dynamic>[]} : null;
    await openPage(tester);
    expect(find.text('Nothing running in the background'), findsOneWidget);
  });

  testWidgets('opening one shows what it printed', (tester) async {
    bridge.onAsk = (m) => m['t'] == 'tasks'
        ? {
            'tasks': [task('The build', secs: 3)],
          }
        : {'text': 'line one\nline two'};
    await openPage(tester);
    await tester.tap(find.text('The build'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('line two'), findsOneWidget);
    // And back to the list from there, without the sheet closing.
    await tester.tap(find.byTooltip('Back to the list'));
    await tester.pump();
    expect(find.text('Running'), findsOneWidget);
  });

  test('a duration reads the way a person would say it', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    String age(int from, int to) =>
        taskAge({'started': now - from, 'ended': to == 0 ? 0 : now - to});
    expect(age(9000, 0), '9s');
    expect(age(95000, 0), '1m 35s');
    expect(age(3600000 + 600000, 0), '1h 10m');
    expect(taskAge({'started': 0, 'ended': 0}), '');
  });
}
