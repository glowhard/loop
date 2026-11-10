import 'package:flutter/material.dart';

import 'alerts.dart';
import 'bridge.dart';
import 'stay_connected.dart';
import 'pair.dart';
import 'sessions.dart';
import 'shell.dart';
import 'theme.dart';
import 'voice.dart';

void main() {
  // A widget that throws shows a small line instead of a red page or, in a
  // release build, an empty box: the rest of the screen keeps working.
  ErrorWidget.builder = (details) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    alignment: Alignment.centerLeft,
    child: const Text(
      'This part could not be shown.',
      style: TextStyle(color: C.text3, fontSize: 12.5),
    ),
  );
  runApp(const LoopApp());
  // The language chosen for speaking and reading aloud, from last time.
  Voice.I.load();
}

final bridge = Bridge();
final navigatorKey = GlobalKey<NavigatorState>();

class LoopApp extends StatefulWidget {
  const LoopApp({super.key});

  @override
  State<LoopApp> createState() => _LoopAppState();
}

class _LoopAppState extends State<LoopApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bridge.load();
    StayConnected.load();
    // Tapping a notification opens that conversation.
    // Driven by the data, not by the screen: a backgrounded app draws nothing.
    bridge.onRunning = (running) => Alerts.check(
      running,
      openChat: bridge.chatOf?['sessionId'],
      away: Watching.away,
    );
    bridge.finished.stream.listen(
      (r) => Alerts.finished(
        r,
        openChat: bridge.chatOf?['sessionId'],
        away: Watching.away,
      ),
    );
    Alerts.onOpen = (dir, sessionId, title) {
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      nav.popUntil((r) => r.isFirst);
      openSession(nav.context, dir, sessionId, () {}, title: title);
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back to the app: reconnect now rather than at the next retry.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    Watching.away = s != AppLifecycleState.resumed;
    if (s == AppLifecycleState.resumed) bridge.wake();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Loop',
      debugShowCheckedModeBanner: false,
      theme: loopTheme(),
      home: Watching(
        child: AnimatedBuilder(
          animation: bridge,
          builder: (context, _) => bridge.saved.isEmpty
              ? const PairPage(first: true)
              : const LoopShell(),
        ),
      ),
    );
  }
}

/// A short message at the bottom of the screen, the same wording the PC uses.
void say(BuildContext context, String? text, {bool bad = false}) {
  if (text == null || text.isEmpty) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: bad ? C.danger.withValues(alpha: 0.95) : C.raised2,
      ),
    );
}
