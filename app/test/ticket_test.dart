// A ticket opened in full: what it says, who has it, what has happened to it,
// and the things you can do to it from there.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/main.dart';
import 'package:loop_app/theme.dart';
import 'package:loop_app/ticket.dart';

void main() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final sent = <Map<String, dynamic>>[];

  Map<String, dynamic> ticket() => {
    'id': 'T4',
    'title': 'Build the login page',
    'details': 'Email and password, with the forgotten-password link.',
    'status': 'doing',
    'progress': 60,
    'assignee': 'Dev one',
    'assigneeId': 'abc',
    'createdBy': 'you',
    'created': now - 3 * 24 * 3600 * 1000,
    'updated': now - 20 * 60 * 1000,
    'notes': [
      {
        'by': 'you',
        'at': now - 2 * 3600 * 1000,
        'text': 'Start with the form.',
      },
      {
        'by': 'Planner',
        'at': now - 3600 * 1000,
        'kind': 'status',
        'text': 'moved it from todo to doing',
      },
      {
        'by': 'Dev one',
        'at': now - 1800 * 1000,
        'text': 'Form is up, styling next.',
      },
    ],
  };

  setUp(() {
    sent.clear();
    bridge.onAsk = (m) {
      sent.add(m);
      return switch (m['action']) {
        'taskUpdate' => {...ticket(), ...?(m['change'] as Map?)},
        'sessions' => {
          'sessions': [
            {'id': 's1', 'title': 'Planner', 'roleTitle': 'Project manager'},
            {'id': 's2', 'title': 'Dev one', 'roleTitle': 'Developer'},
          ],
        },
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
                onPressed: () => showTicket(
                  context,
                  dir: 'proj-a',
                  task: ticket(),
                  onChanged: () {},
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

  testWidgets('it shows the whole ticket, comments and moves alike', (t) async {
    await open(t);
    expect(find.text('T4'), findsOneWidget);
    expect(find.text('Build the login page'), findsOneWidget);
    expect(find.textContaining('forgotten-password'), findsOneWidget);
    expect(find.text('Dev one'), findsWidgets); // assignee, and a comment
    expect(find.textContaining('3 days ago'), findsOneWidget); // created
    expect(find.text('Activity · 3'), findsOneWidget);
    expect(find.textContaining('Form is up'), findsOneWidget);
    // The rest of the activity is further down, where a scroll reaches it.
    await t.dragFrom(const Offset(195, 300), const Offset(0, -400));
    await t.pump();
    expect(find.textContaining('Start with the form'), findsOneWidget);
    expect(find.textContaining('moved it from todo to doing'), findsOneWidget);
  });

  testWidgets('moving it sends the new status and nothing else', (t) async {
    await open(t);
    await t.tap(find.text('Review'));
    await t.pump();
    final change = sent.lastWhere((m) => m['action'] == 'taskUpdate');
    expect(change['id'], 'T4');
    expect(change['change'], {'status': 'review'});
  });

  testWidgets('a comment goes up as a note on the ticket', (t) async {
    await open(t);
    await t.enterText(find.byType(TextField).last, 'Looks good to me');
    await t.tap(find.byTooltip('Add the comment'));
    await t.pump();
    final change = sent.lastWhere((m) => m['action'] == 'taskUpdate');
    expect(change['change'], {'note': 'Looks good to me'});
  });

  testWidgets('handing it to someone asks who, then assigns them', (t) async {
    await open(t);
    await t.tap(
      find.text('Nobody yet').evaluate().isEmpty
          ? find.text('Dev one').first
          : find.text('Nobody yet'),
    );
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('Who is doing this?'), findsOneWidget);
    await t.tap(find.text('Planner').last);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    final change = sent.lastWhere((m) => m['action'] == 'taskUpdate');
    expect(change['change'], {'assignee': 'Planner', 'assigneeId': 's1'});
  });

  testWidgets('how far along it is can be read and moved', (t) async {
    await open(t);
    expect(find.text('How far along'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget); // what the ticket says now

    // Dragging the slider sends the new number, and nothing else.
    final slider = find.byType(Slider);
    await t.drag(slider, const Offset(400, 0));
    await t.pump();
    final change = sent.lastWhere((m) => m['action'] == 'taskUpdate');
    expect((change['change'] as Map).keys.toList(), ['progress']);
    expect((change['change'] as Map)['progress'], 100);
  });

  testWidgets('on a wide screen it opens as a dialog, not a sheet', (t) async {
    await open(t, size: const Size(1400, 900));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Build the login page'), findsOneWidget);

    // With the room for it, the whole activity is there, newest first.
    expect(
      t.getTopLeft(find.textContaining('Form is up')).dy,
      lessThan(t.getTopLeft(find.textContaining('moved it from todo')).dy),
    );
  });
}
