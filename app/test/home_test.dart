// Home: the two front doors and only what needs you. The PC is stood in for.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/home.dart';
import 'package:loop_app/main.dart';
import 'package:loop_app/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> lead(String key, String lamp, Map<String, dynamic>? report) => {
  'key': key,
  'id': key == 'ceo' ? '11111111-1111-4111-8111-111111111111' : '22222222-2222-4222-8222-222222222222',
  'title': 'Demo $key',
  'lamp': lamp,
  'status': '',
  'asking': false,
  'report': report,
};

void main() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final asked = <Map<String, dynamic>>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    asked.clear();
    bridge.onAsk = (m) {
      asked.add(m);
      if (m['action'] == 'home') {
        return {
          'projects': [
            {
              'dir': 'C--demo',
              'title': 'Demo',
              'mtime': now,
              'leads': [
                lead('ceo', 'idle', {'kind': 'plan', 'at': now - 60000, 'lead': 'pricing page', 'bullets': ['Marketing drafts copy', 'CTO builds the page', 'I review'], 'need': '', 'goal': 'add a pricing page', 'goalAt': now - 90000}),
                lead('cto', 'idle', {'kind': 'done', 'at': now - 30000, 'lead': 'about page is in', 'bullets': ['about.html added', 'linked from index'], 'need': 'go live?', 'goal': 'add an about page', 'goalAt': now - 720000}),
              ],
            },
          ],
        };
      }
      if (m['action'] == 'tokens') return {'fresh': 31400, 'cached': 210000, 'calls': 46, 'sessions': 3};
      return null;
    };
  });

  tearDown(() => bridge.onAsk = null);

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(theme: loopTheme(), home: const Scaffold(body: HomePage())));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('two doors, a plan to OK and a report to hear', (t) async {
    await open(t);
    expect(find.text('CEO'), findsOneWidget);
    expect(find.text('CTO'), findsOneWidget);
    expect(find.text('Give a goal'), findsNWidgets(2));
    expect(find.text('PLAN'), findsOneWidget);
    expect(find.text('Add a pricing page'), findsOneWidget); // the goal, first letter up
    expect(find.text('OK, go ahead'), findsOneWidget);
    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('Add an about page'), findsOneWidget);
    expect(find.text('Listen'), findsOneWidget);
    expect(find.text('go live?'), findsOneWidget);
    // the report's cost, the whole team since the goal was given
    expect(find.text('31.4k tokens · 11 min · 3 sessions'), findsOneWidget);
    // going live is held, never tapped
    expect(find.text('Go live · hold', findRichText: true), findsOneWidget);
    await t.binding.setSurfaceSize(null);
  });

  testWidgets('OK on a plan sends "go ahead" only to a lead that is waiting', (t) async {
    await open(t);
    await t.ensureVisible(find.text('OK, go ahead'));
    await t.tap(find.text('OK, go ahead'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('PLAN'), findsNothing, reason: 'the card goes to Earlier');
    expect(find.textContaining('Earlier today'), findsOneWidget);
  });
}
