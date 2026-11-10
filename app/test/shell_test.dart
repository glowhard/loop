// The whole way through, as a person goes: the places along the bottom, the
// projects as folders, a session opened from one, and the same thing on a wide
// screen where the conversation sits beside the list instead of on top of it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/browse.dart';
import 'package:loop_app/chat.dart';
import 'package:loop_app/main.dart';
import 'package:loop_app/pane.dart';
import 'package:loop_app/shell.dart';
import 'package:loop_app/theme.dart';

void main() {
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  // Both the surface and what the app is told about it, so a layout that
  // asks how wide the screen is gets the same answer as the renderer.
  Future<void> size(WidgetTester t, Size s) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = s;
    await t.binding.setSurfaceSize(s);
  }

  Future<void> open(WidgetTester t, Size wh) async {
    await size(t, wh);
    addTearDown(() {
      t.view.reset();
      return t.binding.setSurfaceSize(null);
    });
    await t.pumpWidget(
      MaterialApp(theme: loopTheme(), home: const LoopShell()),
    );
    await settle(t);
  }

  setUp(() {
    Pane.close();
    bridge.hear({'t': 'ready', 'host': 'PC', 'window': true});
    bridge.hear({
      't': 'state',
      's': {
        'projects': [
          {
            'dir': 'proj-a',
            'title': 'Acme',
            'count': 2,
            'live': 1,
            'team': true,
            'server': '',
            'mtime': 200,
          },
        ],
        'running': const [],
        'recent': const [],
        'roles': const [],
        'workspaces': const [],
        'tabs': const [],
        'accounts': const [],
      },
    });
    bridge.onAsk = (m) => m['action'] != 'sessions'
        ? null
        : {
            'dir': 'proj-a',
            'team': true,
            'canTeam': true,
            'teamRoles': [
              {'key': 'dev', 'title': 'Developer', 'duty': 'Writes the code'},
            ],
            'sessions': [
              {
                'id': 's1',
                'title': 'Bookings',
                'lamp': 'idle',
                'roleKey': 'dev',
                'role': 'Developer',
                'last': 'thanks',
              },
            ],
          };
  });

  // The app opens on Home; the folders are one tab along.
  Future<void> toProjects(WidgetTester t) async {
    final tab = find.descendant(of: find.byWidgetPredicate((w) => w is NavigationBar || w is NavigationRail), matching: find.text('Projects'));
    if (tab.evaluate().isNotEmpty) {
      await t.tap(tab.first);
      await settle(t);
    }
  }

  tearDown(() {
    bridge.onAsk = null;
    bridge.disconnect();
    Pane.close();
  });

  testWidgets('on a phone: folders, then a project, then a chat on top', (
    t,
  ) async {
    await open(t, const Size(390, 844));

    // three places to go: Home first, then the folders, then the rest
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Projects'), findsWidgets);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Inbox'), findsNothing, reason: 'Home is the inbox now');
    await toProjects(t);

    // the project is a folder, with what is inside it
    expect(find.text('Acme'), findsOneWidget);
    expect(find.textContaining('2 sessions'), findsOneWidget);

    await toProjects(t);
    await t.tap(find.text('Acme'));
    await settle(t);
    expect(find.byType(ProjectBrowse), findsOneWidget);
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('Developer'), findsOneWidget);
    expect(find.text('Bookings'), findsOneWidget, reason: 'under its role');

    // a session opens as a page of its own, not beside the list
    await t.tap(find.text('Bookings'));
    await settle(t);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(Pane.open.value, isNull, reason: 'no room for two columns here');
  });

  testWidgets('on a wide screen: the chat sits beside the list', (t) async {
    await open(t, const Size(1400, 900));

    // one rail, one list, and room for the conversation
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Pick a session on the left'), findsOneWidget);

    await toProjects(t);
    await t.tap(find.text('Acme'));
    await settle(t);
    await t.tap(find.text('Bookings'));
    await settle(t);

    // it opened in the pane, with the list still there
    expect(Pane.open.value?['sessionId'], 's1');
    expect(find.byType(ChatPage), findsOneWidget);
    expect(
      find.byType(ProjectBrowse),
      findsOneWidget,
      reason: 'the list stays',
    );
    expect(find.text('Pick a session on the left'), findsNothing);

    // and the way out puts it away rather than going back a page
    await t.tap(find.byIcon(Icons.close).first);
    await settle(t);
    expect(Pane.open.value, isNull);
    expect(find.text('Pick a session on the left'), findsOneWidget);
  });

  testWidgets('narrowing the window puts the side chat away', (t) async {
    await open(t, const Size(1400, 900));
    await toProjects(t);
    await t.tap(find.text('Acme'));
    await settle(t);
    await t.tap(find.text('Bookings'));
    await settle(t);
    expect(Pane.open.value, isNotNull);

    await size(t, const Size(390, 844));
    await settle(t);
    expect(Pane.open.value, isNull, reason: 'no second column to show it in');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Acme'), findsOneWidget, reason: 'back at the folders');
  });
}
