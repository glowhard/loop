// Everything as folders: projects, the team inside one, and what making a team
// actually asks the PC to do.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/browse.dart';
import 'package:loop_app/main.dart';

void main() {
  Future<void> phone(WidgetTester t, Widget child) async {
    // A phone-shaped surface, so what is off the bottom of one really is.
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await t.pump();
  }

  // A sheet needs a few frames to be where it will stay.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  setUp(() {
    bridge.hear({'t': 'ready', 'host': 'PC', 'window': true});
    bridge.hear({
      't': 'state',
      's': {
        'projects': [
          {
            'dir': 'proj-a',
            'title': 'Acme',
            'count': 3,
            'live': 1,
            'team': true,
            'server': '',
            'mtime': 200,
          },
          {
            'dir': 'proj-b',
            'title': 'claude-test',
            'count': 1,
            'live': 0,
            'team': false,
            'server': 'my-server',
            'mtime': 100,
          },
        ],
        'running': [
          {
            'id': 's1',
            'dir': 'proj-a',
            'title': 'Bookings',
            'project': 'Acme',
            'lamp': 'busy',
          },
        ],
        'recent': [
          {
            'id': 's2',
            'dir': 'proj-a',
            'title': 'Reports',
            'project': 'Acme',
            'lamp': '',
          },
        ],
        'roles': [
          {'key': 'ceo', 'title': 'CEO', 'duty': 'Runs the place'},
          {'key': 'dev', 'title': 'Developer', 'duty': 'Writes the code'},
        ],
        'workspaces': const [],
      },
    });
  });

  tearDown(() => bridge.disconnect());

  testWidgets('the projects are listed as folders, with what is in them', (
    t,
  ) async {
    await phone(t, BrowsePage(onOpen: () {}));
    await t.pump(const Duration(milliseconds: 200));

    // what you were last in comes first
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);

    // then every project, with its own count
    expect(find.text('Projects · 2'), findsOneWidget);
    expect(find.text('Acme'), findsWidgets);
    expect(find.text('claude-test'), findsOneWidget);
    expect(find.textContaining('3 sessions'), findsOneWidget);
    expect(find.textContaining('team'), findsWidgets);

    // and searching narrows it
    await t.enterText(find.byType(TextField).first, 'claude');
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Acme'), findsNothing);
    expect(find.text('claude-test'), findsOneWidget);
  });

  testWidgets('a project with no team offers to make one', (t) async {
    final asked = <Map<String, dynamic>>[];
    bridge.onAsk = (m) {
      asked.add(m);
      // the PC's answer to "what is in this project"
      if (m['action'] == 'sessions') {
        return {
          'dir': 'proj-b',
          'team': false,
          'canTeam': true,
          'teamRoles': const [],
          'sessions': [
            {
              'id': 's9',
              'title': 'Test Claude Frontend',
              'lamp': '',
              'roleKey': '',
            },
          ],
        };
      }
      return null;
    };
    await phone(
      t,
      ProjectBrowse(
        project: const {'dir': 'proj-b', 'title': 'claude-test'},
        onOpen: () {},
      ),
    );
    await settle(t);

    expect(find.text('No team here'), findsOneWidget);
    expect(find.text('Create a team'), findsOneWidget);
    expect(find.text('Test Claude Frontend'), findsOneWidget);

    // picking roles asks the PC to add each one
    await t.tap(find.text('Create a team'));
    await settle(t);
    expect(find.text('Roles for this team'), findsOneWidget);
    await t.tap(find.text('CEO'));
    await t.pump();
    await t.tap(find.text('Developer'));
    await t.pump();
    await t.tap(find.textContaining('Use 2 roles'));
    await settle(t);

    final made = asked.where((m) => m['teamAction'] == 'add_role').toList();
    expect(made.length, 2, reason: 'one for each role picked');
    expect(made.map((m) => m['role']), containsAll(['CEO', 'Developer']));
    expect(made.first['dir'], 'proj-b');
  });

  testWidgets('a long role name keeps its place; the brief is not a preview', (
    t,
  ) async {
    bridge.onAsk = (m) => m['action'] != 'sessions'
        ? null
        : {
            'dir': 'proj-a',
            'team': true,
            'canTeam': true,
            'teamRoles': [
              {
                'key': 'devops',
                'title': 'DevOps engineer',
                'duty':
                    'Owns builds, deployments, environments and the '
                    'machines they run on, end to end',
              },
            ],
            'sessions': [
              {
                'id': 's1',
                'title': 'DevOps',
                'lamp': 'idle',
                'roleKey': 'devops',
                'status': 'Idle, waiting for you',
                'last':
                    "You are the DevOps · Engineer of PixelLens. "
                    'Rename this session and call role_brief.',
              },
            ],
          };
    await phone(
      t,
      ProjectBrowse(
        project: const {'dir': 'proj-a', 'title': 'pixellens'},
        onOpen: () {},
      ),
    );
    await settle(t);

    // the role is readable in full, not cut short to make room for its duty
    final name = t.widget<Text>(find.text('DevOps engineer'));
    expect(name.overflow, TextOverflow.ellipsis);
    expect(
      t.getSize(find.text('DevOps engineer')).width,
      lessThan(t.getSize(find.byType(ProjectBrowse)).width),
    );
    expect(
      find.text('DevOps engineer'),
      findsOneWidget,
      reason: 'the whole name, not "DevOps engin…"',
    );

    // what a member was told when it started is not a useful preview
    expect(find.textContaining('Rename this session'), findsNothing);
    expect(find.text('Idle, waiting for you'), findsOneWidget);
  });

  testWidgets('a team shows its roles, who holds them, and empty seats', (
    t,
  ) async {
    bridge.onAsk = (m) => m['action'] != 'sessions'
        ? null
        : {
            'dir': 'proj-a',
            'team': true,
            'canTeam': true,
            'teamRoles': [
              {
                'key': 'ceo',
                'title': 'CEO',
                'duty': 'Runs the place',
                'manages': true,
              },
              {'key': 'dev', 'title': 'Developer', 'duty': 'Writes the code'},
            ],
            'sessions': [
              {
                'id': 's1',
                'title': 'Boss',
                'lamp': 'idle',
                'roleKey': 'ceo',
                'role': 'CEO',
              },
              {'id': 's3', 'title': 'Loose end', 'lamp': '', 'roleKey': ''},
            ],
          };
    await phone(
      t,
      ProjectBrowse(
        project: const {'dir': 'proj-a', 'title': 'Acme'},
        onOpen: () {},
      ),
    );
    await settle(t);

    expect(find.text('Team'), findsOneWidget);
    expect(find.text('CEO'), findsOneWidget);
    expect(
      find.text('Boss'),
      findsOneWidget,
      reason: 'under the role it holds',
    );
    expect(find.text('Developer'), findsOneWidget);
    expect(find.text('Nobody yet'), findsOneWidget, reason: 'the empty seat');
    expect(find.text('No role · 1'), findsOneWidget);
    expect(find.text('Loose end'), findsOneWidget);
  });
}
