import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'main.dart';

/// Telling you when a session wants you, while you are in another app.
///
/// Two kinds, deliberately different: a session asking a question interrupts,
/// a session finishing does not. Tapping either opens that chat.
class Alerts {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static final _shown =
      <String, String>{}; // session id -> what it was last told about
  static void Function(String dir, String sessionId, String title)? onOpen;

  static const _asking = AndroidNotificationDetails(
    'asking',
    'A session is asking you something',
    channelDescription: 'A session cannot go on until you answer.',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
    color: Color(0xFF7CC4F0),
    styleInformation: BigTextStyleInformation(''),
  );
  static const _done = AndroidNotificationDetails(
    'finished',
    'A session finished',
    channelDescription: 'A session finished what it was doing.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    groupKey: 'finished',
    color: Color(0xFF57C98A),
    // A finished goal waits quietly in the shade: only what needs you makes a sound.
    playSound: false,
    enableVibration: false,
  );

  static Future<void> start() async {
    // A browser tab has no notifications of its own.
    if (_ready || kIsWeb) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_loop'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final parts = (r.payload ?? '').split('\u0001');
        if (parts.length == 3) onOpen?.call(parts[0], parts[1], parts[2]);
      },
    );
    // Asked for once. A refusal only means it stays quiet, never a crash.
    _ready = true;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      // already asked, or refused: nothing more to do
    }
  }

  /// Called whenever the PC's list changes. Only new things are announced, and
  /// never for the chat you are looking at.
  static Future<void> check(
    List<Map<String, dynamic>> running, {
    String? openChat,
    required bool away,
  }) async {
    if (!_ready) return;
    final seen = <String>{};
    for (final r in running) {
      final id = r['id'] as String? ?? '';
      final ask = r['ask'] as Map?;
      if (id.isEmpty || ask == null) continue;
      seen.add(id);
      final what = 'ask:${ask['question']}';
      if (_shown[id] == what) continue;
      _shown[id] = what;
      if (id == openChat && !away) continue; // it is on screen already
      await _plugin.show(
        id: id.hashCode & 0x7fffffff,
        title: '${r['title']} is asking',
        body: ask['question'] as String? ?? 'It needs an answer to go on.',
        notificationDetails: NotificationDetails(
          android: _asking,
          iOS: const DarwinNotificationDetails(
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        payload: '${r['dir']}\u0001$id\u0001${r['title']}',
      );
    }
    // A question that was answered is no longer worth a notification.
    for (final id in _shown.keys.toList()) {
      if (!seen.contains(id) && _shown[id]!.startsWith('ask:')) {
        _shown.remove(id);
        await _plugin.cancel(id: id.hashCode & 0x7fffffff);
      }
    }
  }

  /// A session that finished while you were elsewhere: quiet, and grouped.
  static Future<void> finished(
    Map<String, dynamic> r, {
    String? openChat,
    required bool away,
  }) async {
    if (!_ready) return;
    final id = r['id'] as String? ?? '';
    if (id.isEmpty || (id == openChat && !away)) return;
    await _plugin.show(
      id: (id.hashCode & 0x7fffffff) ^ 1,
      title: '${r['title']} finished',
      body: '${r['project']} · waiting for you',
      notificationDetails: const NotificationDetails(
        android: _done,
        iOS: DarwinNotificationDetails(presentSound: false),
      ),
      payload: '${r['dir']}\u0001$id\u0001${r['title']}',
    );
  }

  static Future<void> clearFor(String sessionId) async {
    if (!_ready) return; // never set up: in a browser, or in tests
    final n = sessionId.hashCode & 0x7fffffff;
    await _plugin.cancel(id: n);
    await _plugin.cancel(id: n ^ 1);
  }
}

/// The app's own idea of whether you are looking at it.
class Watching extends StatefulWidget {
  const Watching({super.key, required this.child});
  final Widget child;

  /// True while the app is not the thing you are looking at.
  static bool away = false;

  @override
  State<Watching> createState() => _WatchingState();
}

class _WatchingState extends State<Watching> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Alerts.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    Watching.away = s != AppLifecycleState.resumed;
    if (!Watching.away) bridge.wake();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
