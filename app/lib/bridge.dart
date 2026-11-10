import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart';

import 'upload.dart';

/// One PC running Loop. Over Tailscale the address works from anywhere.
class Conn {
  Conn({
    required this.name,
    required this.host,
    required this.port,
    required this.code,
    this.secure = false,
    this.key = '',
    this.direct = '',
  });
  final String name;
  final String host;
  final int port;
  final String code;

  /// Reached over a secure connection (wss). A page served from the web can
  /// only open those, and the PC answers them under its own tailnet name.
  final bool secure;

  /// The way in through a relay, when the PC is reached by an ordinary web
  /// address rather than directly. The relay passes bytes to that PC and no
  /// other; the pairing code is still what gets past the PC itself.
  final String key;

  /// The PC's own address ("name:port"), tried before the relay because it is
  /// far quicker. Empty when there is none to try.
  final String direct;

  String get where => '$host:$port';
  Map<String, dynamic> toJson() => {
    'secure': secure,
    'key': key,
    'direct': direct,
    'name': name,
    'host': host,
    'port': port,
    'code': code,
  };
  static Conn fromJson(Map<String, dynamic> j) => Conn(
    name: j['name'] ?? 'PC',
    host: j['host'] ?? '',
    port: j['port'] ?? 8787,
    code: j['code'] ?? '',
    secure: j['secure'] == true,
    key: j['key'] ?? '',
    direct: j['direct'] ?? '',
  );
}

class Reply {
  Reply(this.ok, {this.text, this.data, this.busy = false});
  final bool ok;
  final String? text;
  final dynamic data;
  final bool busy;
}

enum Link { off, connecting, on, denied, lost }

/// A message typed while the PC could not be reached. It is kept on the phone,
/// saved so closing the app does not lose it, and sent as soon as the PC
/// answers again.
class Waiting {
  Waiting({
    required this.id,
    required this.dir,
    required this.sessionId,
    required this.server,
    required this.title,
    required this.text,
    this.pictures = const [],
    this.why = '',
    this.afterTurn = false,
  });

  final String id;
  final String dir;
  final String sessionId;
  final String server;
  final String title; // the session's name, for the list of waiting messages
  final String text;
  final List<({String name, Uint8List bytes})> pictures;

  /// Why it is still waiting, shown under it.
  String why;

  /// Waiting for this session to finish what it is doing, not for the PC.
  final bool afterTurn;
  bool sending = false;

  Map<String, dynamic> toJson() => {
    'id': id,
    'dir': dir,
    'sessionId': sessionId,
    'server': server,
    'title': title,
    'text': text,
    'why': why,
    'afterTurn': afterTurn,
    'pics': [
      for (final p in pictures) {'name': p.name, 'b64': base64Encode(p.bytes)},
    ],
  };

  static Waiting fromJson(Map<String, dynamic> j) => Waiting(
    id: j['id'] as String,
    dir: j['dir'] as String? ?? '',
    sessionId: j['sessionId'] as String? ?? '',
    server: j['server'] as String? ?? '',
    title: j['title'] as String? ?? '',
    text: j['text'] as String? ?? '',
    why: j['why'] as String? ?? '',
    afterTurn: j['afterTurn'] == true,
    pictures: [
      for (final p in (j['pics'] as List? ?? const []))
        (
          name: (p as Map)['name'] as String? ?? 'picture.jpg',
          bytes: base64Decode(p['b64'] as String),
        ),
    ],
  );
}

/// Everything the app knows about the PC it is connected to, and the only place
/// that talks to it.
class Bridge extends ChangeNotifier {
  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  Timer? _retry;
  Timer? _hello; // gives up when a connection goes quiet before saying hello
  int _seq = 0;
  int _tries = 0;

  /// Which machine the lists show: 'all', 'pc', or 'srv:' plus a server id. The phone's own
  /// choice; the PC window keeps showing whatever it shows.
  String scope = 'all';
  void setScope(String s) {
    scope = s;
    notifyListeners();
  }

  bool inScope(Map<String, dynamic> row) {
    final server = row['server'] as String? ?? '';
    if (scope == 'all') return true;
    if (scope == 'pc') return server.isEmpty;
    return 'srv:$server' == scope;
  }

  final _keptWaits = <String, Completer<dynamic>>{};
  final _keptCache = <String, dynamic>{};

  /// A step's output or a picture, fetched once when it is first shown.
  Future<dynamic> kept(String ref) async {
    if (_keptCache.containsKey(ref)) return _keptCache[ref];
    final c = _keptWaits.putIfAbsent(ref, () {
      _raw({'t': 'kept', 'ref': ref});
      return Completer<dynamic>();
    });
    final v = await c.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => null,
    );
    if (v != null) {
      _keptCache[ref] = v;
      if (_keptCache.length > 400) _keptCache.remove(_keptCache.keys.first);
    }
    return v;
  }

  final _pending = <int, Completer<Reply>>{};

  Link link = Link.off;
  String problem = '';

  /// The last thing that went wrong, kept so a retry does not hide it.
  String lastError = '';

  /// True once the short way to the PC has been given up on for this run, so
  /// the relay is used instead.
  bool _longWay = false;
  bool _tryingShort = false;

  /// Whether this is going the long way round, through the relay.
  bool get viaRelay => _longWay || (conn?.direct.isEmpty ?? true);
  Conn? conn;
  List<Conn> saved = [];

  Map<String, dynamic> state = const {};
  final terminals = <String, Terminal>{};
  String? watching;
  String watchingTitle = '';

  /// The terminal you were in, so a dropped connection puts you back in it.
  String? _resume;

  /// Sessions that just went from working to waiting for you; the shell shows them.
  final finished = StreamController<Map<String, dynamic>>.broadcast();

  /// Called with the running list on every update, on screen or not, so the
  /// phone can still tell you when something wants you.
  void Function(List<Map<String, dynamic>>)? onRunning;
  final _lamps = <String, String>{};

  /// What finished while you were elsewhere, newest last, for the Inbox.
  final finishedList = <Map<String, dynamic>>[];

  void clearFinished() {
    finishedList.clear();
    notifyListeners();
  }

  /// An answer to any session's question, from a card on Home: options picked
  /// ("1" or "1,3"), "skip", or words of your own. A session with a terminal
  /// open takes the option's key instead.
  void answerFor(String sessionId, String keys, String words, {bool direct = true}) {
    if (direct) {
      _raw({'t': 'answer', 'sessionId': sessionId, 'key': keys, 'text': words});
    } else {
      _raw({'t': 'key', 'sessionId': sessionId, 'd': words.isNotEmpty ? words : keys});
    }
  }

  /// A message to any session without opening its chat, as from a Home card.
  Future<Reply> sendTo(String dir, String sessionId, String text) => _ask({
    't': 'send',
    'dir': dir,
    'sessionId': sessionId,
    'text': text,
    'uploads': const [],
  }, wait: const Duration(seconds: 120));

  /// A key for any running session, such as an answer from the Inbox.
  void keyFor(String sessionId, String d) =>
      _raw({'t': 'key', 'sessionId': sessionId, 'd': d});

  /// Terminal text size, kept on this phone.
  double fontSize = 12;

  // ---- the chat open right now ----
  Map<String, String>? chatOf; // dir, sessionId, server

  /// Sessions /clear moved to a new conversation id: old id -> new id.
  final moves = <String, String>{};

  /// The id a session has now, after any /clear.
  String current(String id) {
    var at = id;
    for (var i = 0; i < 20 && moves[at] != null; i++) {
      at = moves[at]!;
    }
    return at;
  }
  final chatItems = <Map<String, dynamic>>[];
  final _toolAt = <String, int>{}; // tool id -> its index in chatItems
  bool chatLoaded = false;

  /// Goes up only when the conversation itself changes. A status word ticking
  /// while Claude works must not rebuild every message.
  int chatVersion = 0;
  bool chatEarlier = false;
  bool loadingEarlier = false;

  /// One screen further back in this conversation.
  void loadEarlier() {
    if (loadingEarlier || !chatEarlier) return;
    loadingEarlier = true;
    notifyListeners();
    _raw({'t': 'earlier'});
  }

  Map<String, dynamic> chatLive = const {}; // lamp, open, ask, status
  DateTime? busySince; // when the current run started, for its timer

  /// The answer being written right now, before it reaches the conversation
  /// file. Shown as it arrives, then replaced by the real message.
  String draft = '';

  /// How much of the draft is on screen. Claude often sends a whole answer in
  /// one burst after thinking; shown at a steady pace instead, it reads as
  /// writing rather than appearing all at once, and never falls more than
  /// about three quarters of a second behind.
  int draftShown = 0;
  Timer? _reveal;
  int _ticksLeft = 0; // of the ~0.7s in which what has arrived must be shown

  void _revealSoon() {
    // Whatever has arrived is spread evenly over the next 0.7s: a burst types
    // out instead of appearing, and the screen is never further behind.
    // Twelve steps of 60ms rather than 23 of 30: the words still appear as
    // they are written, and the chat is rebuilt half as often, which is what
    // the scrolling felt like under a long answer.
    _ticksLeft = 12;
    _reveal ??= Timer.periodic(const Duration(milliseconds: 60), (t) {
      final left = draft.length - draftShown;
      if (left <= 0) {
        t.cancel();
        _reveal = null;
        return;
      }
      final step = (left / (_ticksLeft < 1 ? 1 : _ticksLeft)).ceil();
      if (_ticksLeft > 0) _ticksLeft--;
      draftShown += step < 2 ? 2 : step;
      if (draftShown > draft.length) draftShown = draft.length;
      notifyListeners();
    });
  }

  void _dropDraft() {
    draft = '';
    draftShown = 0;
    _reveal?.cancel();
    _reveal = null;
  }

  String _streamed =
      ''; // this turn's words as they came, to know the finished copy
  Timer? _draftGone;
  int chatArrived = 0; // messages that came in live since the chat opened

  List<Map<String, dynamic>> get projects => _list('projects');
  List<Map<String, dynamic>> get running => _list('running');
  List<Map<String, dynamic>> get recent => _list('recent');
  List<Map<String, dynamic>> get tabs => _list('tabs');
  List<Map<String, dynamic>> get accounts => _list('accounts');
  List<Map<String, dynamic>> get servers => _list('servers');
  List<Map<String, dynamic>> get roles => _list('roles');
  List<Map<String, dynamic>> get prompts => _list('prompts');
  List<Map<String, dynamic>> get workspaces => _list('workspaces');
  String get host => (state['host'] ?? conn?.name ?? '') as String;

  List<Map<String, dynamic>> _list(String key) =>
      ((state[key] ?? const []) as List).cast<Map<String, dynamic>>();

  // ---- messages waiting for the PC ----

  /// In the order they were written; the first one goes first.
  final outbox = <Waiting>[];
  int _queued = 0;

  List<Waiting> waitingFor(String sessionId) =>
      outbox.where((w) => w.sessionId == sessionId).toList();

  /// Whether that session is working on something this moment.
  bool busyNow(String sessionId) {
    if (chatOf?['sessionId'] == sessionId) {
      final lamp = chatLive['lamp'] as String? ?? '';
      if (lamp.isNotEmpty) return lamp == 'busy';
    }
    for (final r in running) {
      if (r['id'] == sessionId) return (r['lamp'] as String? ?? '') == 'busy';
    }
    return false;
  }

  /// Keep a message for later. [why] says what it is waiting for.
  Waiting queue({
    required String dir,
    required String sessionId,
    required String server,
    required String title,
    required String text,
    List<Upload> pictures = const [],
    String why = '',
    bool afterTurn = false,
  }) {
    final w = Waiting(
      // Its own name, even for two written in the same instant.
      id: '${DateTime.now().microsecondsSinceEpoch}-${++_queued}',
      dir: dir,
      sessionId: sessionId,
      server: server,
      title: title,
      text: text,
      pictures: [for (final u in pictures) (name: u.name, bytes: u.bytes)],
      why: why,
      afterTurn: afterTurn,
    );
    outbox.add(w);
    notifyListeners();
    _saveOutbox();
    _flush(); // if there is nothing to wait for, it goes at once
    return w;
  }

  void unqueue(String id) {
    outbox.removeWhere((w) => w.id == id);
    notifyListeners();
    _saveOutbox();
  }

  Future<void> _saveOutbox() async {
    try {
      final p = await SharedPreferences.getInstance();
      var pictureBytes = 0;
      final out = [];
      for (final w in outbox) {
        final j = w.toJson();
        for (final x in j['pics'] as List) {
          pictureBytes += (x['b64'] as String).length;
        }
        // More than a phone should hold: the words are kept, the pictures are not.
        if (pictureBytes > 3 * 1024 * 1024) j['pics'] = const [];
        out.add(j);
      }
      await p.setString('outbox', jsonEncode(out));
    } catch (_) {
      // The phone would not keep it. It is still in hand until the app closes.
    }
  }

  bool _flushing = false;
  int _flushGen = 0;
  Timer? _flushAgain;

  static bool _worthRetry(String why) => RegExp(
    r'did not answer|not open|not connected|would not start|closed while starting|another window',
    caseSensitive: false,
  ).hasMatch(why);

  void _retryFlushSoon() {
    _flushAgain?.cancel();
    _flushAgain = Timer(const Duration(seconds: 20), () {
      if (link == Link.on && outbox.isNotEmpty) _flush();
    });
  }

  /// Send what has been waiting, oldest first. Stops at the first one the PC
  /// will not take, so the reason can be shown rather than repeated.
  Future<void> _flush() async {
    if (_flushing || link != Link.on || outbox.isEmpty) return;
    final gen = ++_flushGen;
    _flushing = true;
    try {
      // One session takes one message per pass: the next waits until the PC
      // says that turn has started, so they arrive in order and never overlap.
      final justSent = <String>{};
      while (link == Link.on && gen == _flushGen) {
        Waiting? free;
        for (final x in outbox) {
          if (justSent.contains(x.sessionId) || busyNow(x.sessionId)) continue;
          free = x;
          break;
        }
        if (free == null) break;
        final w = free;
        w.sending = true;
        w.why = '';
        notifyListeners();
        final tokens = <String>[];
        String? lost;
        for (final p in w.pictures) {
          final t = await upload(p.name, p.bytes, server: w.server).done.future;
          if (t == null) {
            lost = 'A picture could not be sent.';
            break;
          }
          tokens.add(t);
        }
        if (lost == null) {
          final r = await _ask({
            't': 'send',
            'dir': w.dir,
            'sessionId': w.sessionId,
            'text': w.text,
            'uploads': tokens,
          }, wait: const Duration(seconds: 120));
          if (gen != _flushGen) break; // a newer connection took over
          if (r.ok) {
            justSent.add(w.sessionId);
            outbox.remove(w);
            notifyListeners();
            await _saveOutbox();
            continue;
          }
          lost = r.text ?? 'The PC could not take it.';
        }
        w.sending = false;
        w.why = lost;
        notifyListeners();
        await _saveOutbox();
        // Not answered, or the session would not start: worth another go in a
        // moment rather than leaving it to be tapped by hand.
        if (_worthRetry(lost)) _retryFlushSoon();
        break;
      }
    } finally {
      _flushing = false;
    }
  }

  // ---- saved PCs ----

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    fontSize = p.getDouble('fontSize') ?? 12;
    saved = (jsonDecode(p.getString('conns') ?? '[]') as List)
        .map((e) => Conn.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    try {
      outbox
        ..clear()
        ..addAll([
          for (final e in jsonDecode(p.getString('outbox') ?? '[]') as List)
            Waiting.fromJson((e as Map).cast<String, dynamic>()),
        ]);
    } catch (_) {
      // nothing kept, or kept by an older version of the app
    }
    notifyListeners();
    if (saved.isNotEmpty) connect(saved.first);
  }

  Future<void> remember(Conn c) async {
    saved = [c, ...saved.where((x) => x.where != c.where)];
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'conns',
      jsonEncode(saved.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    fontSize = size.clamp(8, 22).toDouble();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('fontSize', fontSize);
  }

  /// Back from the background: phones drop sockets there, so try at once.
  void wake() {
    final c = conn;
    if (c != null && link != Link.on && link != Link.denied) connect(c);
  }

  Future<void> forget(Conn c) async {
    saved = saved.where((x) => x.where != c.where).toList();
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'conns',
      jsonEncode(saved.map((e) => e.toJson()).toList()),
    );
    if (conn?.where == c.where) disconnect();
    notifyListeners();
  }

  // ---- the connection ----

  void connect(Conn c) {
    disconnect(keep: true);
    conn = c;
    link = Link.connecting;
    problem = '';
    notifyListeners();
    try {
      // In a browser the page's own connection is used; on a phone, pings keep
      // a mobile link open and show a dead one within seconds.
      // The short way is straight to the PC and is worth trying first: it is
      // a few milliseconds against a few hundred through a relay. If it cannot
      // be reached — away from your tailnet — the relay takes over.
      final short = c.direct.isNotEmpty && !_longWay;
      final url = short
          ? Uri.parse('wss://${c.direct}/ws')
          : c.key.isNotEmpty
          ? Uri.parse('wss://${c.host}/ws?k=${Uri.encodeQueryComponent(c.key)}')
          : Uri.parse('${c.secure ? 'wss' : 'ws'}://${c.host}:${c.port}/ws');
      _tryingShort = short;
      final ws = kIsWeb
          ? WebSocketChannel.connect(url)
          : IOWebSocketChannel.connect(
              url,
              pingInterval: const Duration(seconds: 10),
              connectTimeout: const Duration(seconds: 8),
            );
      _ws = ws;
      // A PC that is off refuses the connection: that arrives here, never as a
      // crash, and the next try is scheduled.
      ws.sink.done.catchError((Object _) {});
      // Listening is what opens it; what is written before it opens is kept and
      // sent once it does, so there is nothing to wait for.
      _sub = ws.stream.listen(
        _onMessage,
        onError: _onDrop,
        onDone: _onDrop,
        cancelOnError: true,
      );
      _raw({'t': 'hello', 'token': c.code});
      // Nothing at all within a few seconds means it is not there.
      _hello?.cancel();
      _hello = Timer(const Duration(seconds: 8), () {
        if (_ws != ws || link == Link.on) return;
        // The short way did not answer: there is a longer one.
        if (_tryingShort && c.key.isNotEmpty) {
          _longWay = true;
          _hello = null;
          return connect(c);
        }
        lastError = 'No answer from ${c.host}:${c.port}.';
        problem = lastError;
        _onDrop();
      });
    } catch (e) {
      // Kept until the next success: the retries must not wipe the reason.
      lastError = '$e';
      debugPrint('Loop: could not connect: $e');
      problem = '$e';
      link = Link.lost;
      notifyListeners();
      _scheduleRetry();
    }
  }

  void disconnect({bool keep = false}) {
    _retry?.cancel();
    _hello?.cancel();
    _sub?.cancel();
    _ws?.sink.close();
    _ws = null;
    _sub = null;
    if (watching != null) _resume = watching;
    if (!keep) _resume = null;
    watching = null;
    terminals.clear();
    for (final c in _pending.values) {
      c.complete(Reply(false, text: 'The connection to the PC closed.'));
    }
    _pending.clear();
    if (!keep) {
      link = Link.off;
      state = const {};
      notifyListeners();
    }
  }

  void _onDrop([Object? e]) {
    if (link == Link.denied) return;
    link = Link.lost;
    if (e != null) {
      problem = 'Lost the connection to ${conn?.name ?? 'the PC'}.';
    }
    // Nothing asked of the PC can be answered now: say so at once rather than
    // leave a tap waiting half a minute for a timeout.
    final gone = 'Lost the connection to ${conn?.name ?? 'the PC'}.';
    for (final c in _pending.values.toList()) {
      if (!c.isCompleted) c.complete(Reply(false, text: gone));
    }
    _pending.clear();
    for (final w in _upWaits.values.toList()) {
      if (!w.isCompleted) w.complete({'failed': gone});
    }
    _upWaits.clear();
    _flushGen++; // the queue starts again on the next connection
    _flushAgain?.cancel();
    notifyListeners();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    final c = conn;
    if (c == null) return;
    // Quick at first (a blip), slower if the PC is really away.
    final wait = Duration(
      milliseconds: (700 * (1 << _tries.clamp(0, 4))).clamp(700, 8000),
    );
    _tries++;
    _retry = Timer(wait, () => connect(c));
  }

  void _raw(Map<String, dynamic> m) {
    try {
      _ws?.sink.add(jsonEncode(m));
    } catch (_) {
      _onDrop();
    }
  }

  /// A message as if it came from the PC, for tests.
  @visibleForTesting
  void hear(Map<String, dynamic> m) => _onMessage(jsonEncode(m));

  void _onMessage(dynamic raw) {
    final m = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
    switch (m['t']) {
      case 'ready':
        _tries = 0;
        lastError = '';
        _tryingShort = false;
        _hello?.cancel();
        link = Link.on;
        problem = '';
        _raw({'t': 'sub'});
        final chat = chatOf;
        if (chat != null) {
          chatOpen(chat['dir']!, chat['sessionId']!, chat['server']!);
        }
        final back = _resume;
        _resume = null;
        if (back != null) watch(back);
        notifyListeners();
        _flush();
      case 'denied':
        link = Link.denied;
        problem = (m['why'] ?? 'That pairing code was refused.') as String;
        notifyListeners();
      case 'state':
        if (m['closed'] == true) {
          problem = 'Loop is not open on the PC.';
        } else {
          state = (m['s'] as Map).cast<String, dynamic>();
          problem = '';
          _noticeFinished();
          if (outbox.isNotEmpty) _flush();
          onRunning?.call(running);
        }
        notifyListeners();
      case 'screen':
        final id = m['tabId'] as String;
        final term = _terminal(id);
        term.write(m['d'] as String? ?? '');
        watching = id;
        watchingTitle = (m['title'] ?? '') as String;
        notifyListeners();
      case 'data':
        _terminal(m['tabId'] as String).write(m['d'] as String? ?? '');
      case 'chat':
        if (m['sessionId'] != chatOf?['sessionId']) return;
        if (m['reset'] == true) {
          // What is on screen is kept until the fresh copy is in hand, so
          // coming back to a chat never shows an empty page.
          _remember();
          chatItems.clear();
          _toolAt.clear();
          chatVersion++;
          chatEarlier = m['earlier'] == true;
        }
        if (m['before'] == true) {
          // Older messages go in front; the newest stay where they are.
          final older = <Map<String, dynamic>>[];
          for (final raw in (m['items'] as List? ?? const [])) {
            older.add((raw as Map).cast<String, dynamic>());
          }
          chatItems.insertAll(0, older);
          _reindex();
          chatEarlier = m['earlier'] == true;
          loadingEarlier = false;
          chatVersion++;
          notifyListeners();
          return;
        }
        final fresh = m['reset'] != true;
        for (final raw in (m['items'] as List? ?? const [])) {
          final item = (raw as Map).cast<String, dynamic>();
          if (fresh) {
            item['fresh'] = true;
            if (item['k'] == 'text' || item['k'] == 'user' || item['k'] == 'peer') chatArrived++;
          }
          _addChat(item);
        }
        chatLoaded = true;
        notifyListeners();
      case 'draft':
        if (m['sessionId'] != chatOf?['sessionId']) return;
        if (m['done'] == true) {
          // The finished message is about to arrive from the conversation
          // itself and takes the draft's place; until then the words stay, so
          // nothing blinks. If it never comes, they go anyway.
          _draftGone?.cancel();
          _draftGone = Timer(const Duration(seconds: 4), () {
            if (draft.isEmpty) return;
            _dropDraft();
            notifyListeners();
          });
          return;
        }
        final piece = m['d'] as String? ?? '';
        if (piece.isEmpty) return;
        _draftGone?.cancel();
        draft += piece;
        _streamed += piece;
        _revealSoon();
      case 'moved':
        // /clear: the same session, a new conversation. The PC already sends
        // the new one's (empty) chat; the open chat takes the new id.
        final from = m['from'] as String? ?? '';
        final to = m['to'] as String? ?? '';
        if (from.isEmpty || to.isEmpty) return;
        moves[from] = to;
        if (chatOf?['sessionId'] == from) {
          chatOf = {...chatOf!, 'sessionId': to};
          // The /clear that started it belongs to the old conversation: the
          // new one starts empty, so nothing waits to be replaced.
          chatItems.removeWhere((x) => x['pending'] == true);
          chatVersion++;
        }
        notifyListeners();
      case 'live':
        if (m['sessionId'] != chatOf?['sessionId']) return;
        final was = chatLive['lamp'];
        if (m['lamp'] == 'busy' && was != 'busy') busySince = DateTime.now();
        if (m['lamp'] != 'busy') busySince = null;
        if (was == 'busy' && m['lamp'] == 'idle') HapticFeedback.lightImpact();
        if (m['ask'] != null && chatLive['ask'] == null) {
          HapticFeedback.mediumImpact();
        }
        chatLive = m;
        notifyListeners();
      case 'upgot':
        _upWaits['${m['up']}:${m['i']}']?.complete(m);
      case 'upfar':
        final up = _upFar[m['up']];
        if (up == null) return;
        final p = (m['p'] as num?)?.toDouble() ?? 0;
        if (m['done'] == true) {
          _upFar.remove(up.id);
          final token = _farToken.remove(up.id);
          if (m['failed'] != null || token == null) {
            up.fail(
              m['failed'] as String? ?? 'The picture did not reach the server.',
            );
          } else {
            up.finish(token);
          }
        } else {
          up.progress.value = 0.6 + 0.4 * (p > 0.99 ? 0.99 : p);
        }
      case 'kept':
        final k = _keptWaits.remove(m['ref']);
        k?.complete(m['data']);
      case 'done':
        final c = _pending.remove(m['id']);
        c?.complete(
          Reply(
            m['ok'] == true,
            text: m['text'] as String?,
            data: m['data'],
            busy: m['busy'] == true,
          ),
        );
    }
  }

  /// Your message shows the moment you send it; the copy from the PC replaces it.
  void addPending(String text, {List<Upload> pictures = const []}) {
    chatVersion++;
    chatItems.add({
      'k': 'user',
      'id': 'pending-${DateTime.now().microsecondsSinceEpoch}',
      'text': text,
      'pending': true,
      'fresh': true,
      // the phone's own copies, shown until the PC has written them down
      if (pictures.isNotEmpty)
        'images': [
          for (final u in pictures) {'bytes': u.bytes, 'upload': u},
        ],
    });
    notifyListeners();
  }

  void dropPending(String text) {
    chatVersion++;
    chatItems.removeWhere((x) => x['pending'] == true && x['text'] == text);
    notifyListeners();
  }

  // A tool's result joins the tool it answers, so the chat shows them as one row.
  void _addChat(Map<String, dynamic> item) {
    if (item['k'] == 'text') {
      // Already seen word by word as it was written: it does not type itself
      // out a second time, it simply replaces the draft.
      final t = (item['text'] as String? ?? '').trim();
      final head = t.length > 40 ? t.substring(0, 40) : t;
      if (head.isNotEmpty && _streamed.contains(head)) {
        // It carries on typing from where the draft had got to.
        final shown = draftShown < t.length ? draftShown : t.length;
        item['fresh'] = shown < t.length - 8;
        item['typeFrom'] = shown;
      }
      if (draft.isNotEmpty) {
        _dropDraft();
        _draftGone?.cancel();
      }
    }
    if (item['k'] == 'user') {
      _streamed = '';
      final at = chatItems.indexWhere((x) => x['pending'] == true);
      if (at >= 0) {
        chatItems.removeAt(at);
        _reindex();
        item['fresh'] =
            false; // it is already on screen; do not animate it twice
      }
    }
    if (item['k'] == 'result') {
      final at = _toolAt[item['id']];
      if (at != null) {
        chatItems[at] = {
          ...chatItems[at],
          'done': true,
          'has': item['has'] == true,
          'ok': item['ok'],
        };
        chatVersion++;
      }
      return;
    }
    if (item['k'] == 'text' && draft.isNotEmpty) _dropDraft();
    // Belt and braces: the same message is never listed twice.
    final id = item['id'];
    if (id != null &&
        chatItems.any((x) => x['id'] == id && x['k'] == item['k'])) {
      return;
    }
    if (item['k'] == 'tool') _toolAt[item['id'] as String] = chatItems.length;
    chatItems.add(item);
    chatVersion++;
  }

  void _reindex() {
    _toolAt.clear();
    for (var i = 0; i < chatItems.length; i++) {
      if (chatItems[i]['k'] == 'tool') {
        _toolAt[chatItems[i]['id'] as String] = i;
      }
    }
  }

  /// The last screen of each chat you have had open, so going back into one
  /// shows it at once instead of an empty page while the PC is asked again.
  final _seen = <String, List<Map<String, dynamic>>>{};

  void _remember() {
    final id = chatOf?['sessionId'];
    if (id == null || chatItems.isEmpty) return;
    _seen[id] = [
      for (final x in chatItems.where((x) => x['pending'] != true))
        {...x, 'fresh': false},
    ];
    // A handful of chats is plenty; the rest are asked for again.
    while (_seen.length > 8) {
      _seen.remove(_seen.keys.first);
    }
  }

  void chatOpen(String dir, String sessionId, String server) {
    _remember(); // keep the one being left behind
    if (chatOf?['sessionId'] != sessionId) _keptCache.clear();
    chatOf = {'dir': dir, 'sessionId': sessionId, 'server': server};
    chatItems.clear();
    _toolAt.clear();
    chatVersion++;
    // What was on screen last time, until the PC catches us up.
    final had = _seen[sessionId];
    chatLoaded = had != null && had.isNotEmpty;
    if (chatLoaded) {
      chatItems.addAll(had!.map((x) => {...x}));
      _reindex();
    }
    chatLive = const {};
    _dropDraft();
    busySince = null;
    chatArrived = 0;
    _raw({'t': 'chat', 'dir': dir, 'sessionId': sessionId, 'server': server});
  }

  void chatClose() {
    if (chatOf == null) return;
    _remember();
    chatOf = null;
    _raw({'t': 'unchat'});
  }

  /// A message, with the pictures already sent ahead by [upload].
  Future<Reply> chatSend(String text, List<String> uploads) {
    final c = chatOf;
    if (c == null) return Future.value(Reply(false, text: 'No chat is open.'));
    return _ask({
      't': 'send',
      'dir': c['dir'],
      'sessionId': c['sessionId'],
      'text': text,
      'uploads': uploads,
    }, wait: const Duration(seconds: 120));
  }

  // ---- pictures, sent the moment they are chosen ----

  final _upWaits = <String, Completer<Map<String, dynamic>>>{};
  final _upFar = <String, Upload>{};
  static const _piece = 64 * 1024; // base64 characters in one piece

  /// Start sending a picture to the PC now; for a server session it goes on
  /// to the server too. Its progress fills [Upload.progress].
  Upload upload(String name, Uint8List bytes, {String? server}) {
    final up = Upload(name, bytes);
    _sendUpload(up, server ?? chatOf?['server'] ?? '');
    return up;
  }

  Future<void> _sendUpload(Upload up, String server) async {
    final b64 = base64Encode(up.bytes);
    final of = (b64.length / _piece).ceil();
    // On a server the last part of the ring is the copy from the PC to it.
    final near = server.isEmpty ? 1.0 : 0.6;
    void piece(int i) {
      _upWaits['${up.id}:$i'] = Completer();
      final end = (i + 1) * _piece > b64.length ? b64.length : (i + 1) * _piece;
      _raw({
        't': 'up',
        'up': up.id,
        'i': i,
        'of': of,
        'name': up.name,
        'd': b64.substring(i * _piece, end),
        if (server.isNotEmpty) 'server': server,
      });
    }

    // A few pieces in flight at once: a long way off, each round trip counts.
    var next = 0;
    while (next < of && next < 4) {
      piece(next++);
    }
    String? token;
    for (var i = 0; i < of; i++) {
      final w = _upWaits['${up.id}:$i'];
      if (w == null) return up.fail('The picture could not be sent.');
      final m = await w.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => {'failed': 'The PC stopped answering.'},
      );
      _upWaits.remove('${up.id}:$i');
      if (m['failed'] != null) {
        for (var j = i; j < next; j++) {
          _upWaits.remove('${up.id}:$j');
        }
        return up.fail(m['failed'] as String);
      }
      token = m['token'] as String? ?? token;
      up.progress.value = (i + 1) / of * near;
      if (next < of) piece(next++);
    }
    if (token == null) return up.fail('The picture could not be sent.');
    if (server.isEmpty) return up.finish(token);
    up.progress.value = near;
    _upFar[up.id] = up;
    // the copy to the server reports itself; it gets two minutes
    up.done.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        _upFar.remove(up.id);
        up.fail('The picture could not be copied to the server.');
        return null;
      },
    );
    _farToken[up.id] = token;
  }

  final _farToken = <String, String>{};

  /// A whole answer to a question from a session with no terminal: options
  /// picked ("1" or "1,3"), "skip", or words of your own.
  void chatAnswer(String keys, String words) {
    final c = chatOf;
    if (c != null) {
      _raw({
        't': 'answer',
        'sessionId': c['sessionId'],
        'key': keys,
        'text': words,
      });
    }
  }

  void chatKey(String d) {
    final c = chatOf;
    if (c != null) _raw({'t': 'key', 'sessionId': c['sessionId'], 'd': d});
  }

  void _noticeFinished() {
    final seen = <String>{};
    for (final r in running) {
      final id = r['id'] as String;
      final lamp = r['lamp'] as String? ?? '';
      seen.add(id);
      if (_lamps[id] == 'busy' && lamp == 'idle') {
        final done = {...r, 'doneAt': DateTime.now().millisecondsSinceEpoch};
        finishedList.removeWhere((x) => x['id'] == id);
        finishedList.add(done);
        if (finishedList.length > 30) finishedList.removeAt(0);
        finished.add(done);
      }
      _lamps[id] = lamp;
    }
    _lamps.removeWhere((id, _) => !seen.contains(id));
  }

  // ---- terminals ----

  Terminal _terminal(String tabId) => terminals.putIfAbsent(tabId, () {
    final t = Terminal(maxLines: 4000);
    t.onOutput = (data) => _raw({'t': 'in', 'tabId': tabId, 'd': data});
    t.onResize = (cols, rows, _, __) =>
        _raw({'t': 'size', 'tabId': tabId, 'cols': cols, 'rows': rows});
    return t;
  });

  Terminal terminalFor(String tabId) => _terminal(tabId);

  /// Show a terminal that Loop already has open.
  Future<Reply> watch(String tabId, {int cols = 60, int rows = 24}) {
    terminals.remove(tabId);
    watching = tabId;
    return _ask({'t': 'watch', 'tabId': tabId, 'cols': cols, 'rows': rows});
  }

  void unwatch() {
    _resume = null;
    if (watching == null) return;
    _raw({'t': 'unwatch'});
    watching = null;
    notifyListeners();
  }

  /// Move a session into Loop, wherever it is running: the copy in another
  /// terminal or in the Claude desktop app stops and Loop takes it on. Safe to
  /// call for a session that is already here, which does nothing.
  Future<Reply> bring(String dir, String sessionId) =>
      act('bring', {'dir': dir, 'sessionId': sessionId});

  /// Open a saved session and start showing it.
  Future<Reply> open(
    String dir,
    String sessionId, {
    bool force = false,
    int cols = 60,
    int rows = 24,
  }) => act('open', {
    'dir': dir,
    'sessionId': sessionId,
    'force': force,
    'cols': cols,
    'rows': rows,
  });

  void keys(String data) {
    final id = watching;
    if (id != null) _raw({'t': 'in', 'tabId': id, 'd': data});
  }

  Future<Reply> prompt(String text) {
    final id = watching;
    if (id == null) {
      return Future.value(Reply(false, text: 'No session is open.'));
    }
    return _ask({'t': 'prompt', 'tabId': id, 'text': text});
  }

  Future<Reply> sendImage(String name, Uint8List bytes) {
    final id = watching;
    if (id == null) {
      return Future.value(Reply(false, text: 'No session is open.'));
    }
    return _ask({
      't': 'image',
      'tabId': id,
      'name': name,
      'b64': base64Encode(bytes),
    });
  }

  // ---- anything else Loop can do ----

  /// Stands in for the PC in tests: given a request, it answers with the data
  /// the PC would have sent. Null means "let it go to the PC as usual".
  @visibleForTesting
  Map<String, dynamic>? Function(Map<String, dynamic>)? onAsk;

  Future<Reply> act(
    String action, [
    Map<String, dynamic> args = const {},
    Duration wait = const Duration(seconds: 30),
  ]) {
    final m = {'t': 'do', 'action': action, ...args};
    final fake = onAsk?.call(m);
    if (fake != null) return Future.value(Reply(true, data: fake));
    if (onAsk != null) return Future.value(Reply(true));
    return _ask(m, wait: wait);
  }

  /// What a session has running in the background: the commands it left
  /// running and the agents it started. Read from the PC each time, because
  /// the whole point is how far along they are now.
  Future<List<Map<String, dynamic>>> bgTasks(
    String dir,
    String sessionId,
    String server,
  ) async {
    final m = {
      't': 'tasks',
      'dir': dir,
      'sessionId': sessionId,
      'server': server,
    };
    final fake = onAsk?.call(m);
    if (fake == null && onAsk != null) return [];
    final d = fake ?? ((await _ask(m)).data as Map?);
    return [
      for (final x in (d?['tasks'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ];
  }

  /// What one of them has printed so far, by its id. Ask for the list first:
  /// the PC answers only for a task it has just named.
  Future<String?> bgOutput(String task) async {
    final m = {'t': 'taskout', 'task': task};
    final fake = onAsk?.call(m);
    if (fake != null) return fake['text'] as String? ?? '';
    if (onAsk != null) return '';
    final r = await _ask(m);
    if (!r.ok) return null;
    return ((r.data as Map?)?['text'] as String?) ?? '';
  }

  Future<Reply> _ask(
    Map<String, dynamic> m, {
    Duration wait = const Duration(seconds: 30),
  }) {
    if (link != Link.on) {
      return Future.value(Reply(false, text: 'Not connected to the PC.'));
    }
    final id = ++_seq;
    final c = Completer<Reply>();
    _pending[id] = c;
    _raw({...m, 'id': id});
    return c.future.timeout(
      wait,
      onTimeout: () {
        _pending.remove(id);
        return Reply(
          false,
          text: 'The PC did not answer. It may be asking something on screen.',
        );
      },
    );
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
