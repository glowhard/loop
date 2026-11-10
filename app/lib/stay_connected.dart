import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Staying connected while the app is not on screen.
///
/// Android freezes an ordinary app soon after you leave it, and a frozen app
/// hears nothing from your PC. With this on, Loop keeps one quiet, permanent
/// notification and stays connected, so a session asking something reaches you
/// hours later. It is yours to switch off; the app works either way.
class StayConnected {
  static bool on = false;
  static bool running = false;

  static Future<void> load() async {
    if (!_android) return;
    final p = await SharedPreferences.getInstance();
    on = p.getBool('keepAlive') ?? true;
    if (on) await start();
  }

  static Future<void> set(bool want) async {
    on = want;
    final p = await SharedPreferences.getInstance();
    await p.setBool('keepAlive', want);
    if (want) {
      await start();
    } else {
      await stop();
    }
  }

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> start() async {
    if (!_android || running) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'connected',
        channelName: 'Connected to your PC',
        channelDescription:
            'Keeps Loop connected so your sessions can reach you.',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
        showWhen: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        autoRunOnBoot: false,
      ),
    );
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          serviceId: 4301,
          notificationTitle: 'Loop is connected',
          notificationText: 'Your sessions can reach you.',
          notificationIcon: const NotificationIcon(
            metaDataName: 'dev.loop.NOTIFICATION_ICON',
          ),
        );
      }
      running = true;
    } catch (_) {
      // refused or unavailable: the app simply stays quiet in the background
    }
  }

  static Future<void> stop() async {
    running = false;
    if (!_android) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {
      // not running
    }
  }
}
