// On a wide screen there is room for the list and the conversation at once, as
// on the desktop. On a phone there is not, so a chat opens on top instead.
import 'package:flutter/foundation.dart';

class Pane {
  /// Wide enough for two columns. Set by the shell as it is laid out.
  static bool side = false;

  /// The chat showing beside the list, if there is one.
  static final open = ValueNotifier<Map<String, String>?>(null);

  static void show({
    required String dir,
    required String sessionId,
    required String title,
    String project = '',
    String server = '',
  }) => open.value = {
    'dir': dir,
    'sessionId': sessionId,
    'title': title,
    'project': project,
    'server': server,
  };

  static void close() => open.value = null;
}
