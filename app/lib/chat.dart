import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';

import 'alerts.dart';
import 'bridge.dart' show Link, Reply, Waiting;
import 'main.dart';
import 'mic.dart';
import 'motion.dart';
import 'question.dart';
import 'sessions.dart';
import 'pane.dart';
import 'side.dart';
import 'terminal.dart';
import 'starting.dart';
import 'talk.dart';
import 'theme.dart';
import 'upload.dart';

/// One session as a conversation, laid out like the Claude app: your messages in
/// bubbles, Claude's answers as plain text, its tool steps as quiet lines, and
/// its questions as a card with buttons.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.dir,
    required this.sessionId,
    required this.title,
    this.project = '',
    this.server = '',
    this.onBack,
  });
  final String dir;
  final String sessionId;
  final String title;
  final String project;
  final String server;

  /// Set when the chat sits beside the list rather than on top of it: the way
  /// out is to put it away, not to go back a page.
  final VoidCallback? onBack;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// The session this chat shows. /clear gives it a new conversation id, and
  /// the chat follows it rather than staying on the old one.
  String get _sid => bridge.current(widget.sessionId);

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _pics = <Upload>[]; // on their way already
  Map<String, dynamic>? _session;
  bool _sending = false;
  bool _away = false; // scrolled up, away from the newest message
  // Right at the newest line. While an answer is being written the list grows
  // from the bottom, so anyone who has scrolled even a little is reading
  // something older: the words must not shove it up the screen under them.
  bool _pinned = true;
  double? _grewTo; // how far the list reached last frame, while one is written
  int _seenArrived = 0;
  bool _starting = false; // a session is being started: something to read
  bool _hidNews =
      false; // you closed it; it stays closed until the next message
  String? _answered; // the option picked on the question on screen now
  String? _answeredOf; // which question that was: the next one starts unpicked
  List<Widget> _rowsCache = const [];
  String _rowsFor = '';

  @override
  void initState() {
    super.initState();
    bridge.chatOpen(widget.dir, _sid, widget.server);
    // Opening a session brings it here, wherever it was working: a copy in
    // another terminal or in the Claude desktop app stops, and Loop carries the
    // same conversation on. Nothing to confirm; it is the user's own session.
    bridge.bring(widget.dir, _sid);
    _input.addListener(_onType);
    _focus.addListener(() => setState(() {}));
    // On a computer, Enter sends and Shift+Enter starts a new line, as in the
    // Claude apps. A phone's keyboard keeps Enter for a new line.
    _focus.onKeyEvent = (node, event) {
      final computer = kIsWeb &&
          defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS;
      if (!computer ||
          event is! KeyDownEvent ||
          event.logicalKey != LogicalKeyboardKey.enter ||
          HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      _send();
      return KeyEventResult.handled;
    };
    _scroll.addListener(() {
      final away = _scroll.hasClients && _scroll.offset > 240;
      final pinned = !_scroll.hasClients || _scroll.offset <= 24;
      if (away != _away || pinned != _pinned) {
        setState(() {
          _away = away;
          _pinned = pinned;
        });
      }
      if (!away) _seenArrived = bridge.chatArrived;
    });
    _loadSession();
  }

  Future<void> _loadSession() async {
    final r = await bridge.act('sessions', {'dir': widget.dir});
    if (!mounted || r.data == null) return;
    for (final s
        in ((r.data['sessions'] ?? const []) as List)
            .cast<Map<String, dynamic>>()) {
      if (s['id'] == _sid) setState(() => _session = s);
    }
  }

  void _onType() {
    setState(() {});
  }

  /// The commands that match what is typed after a leading "/".
  List<List<String>> get _matches {
    final t = _input.text;
    if (!t.startsWith('/') || t.contains('\n')) return const [];
    final typed = t.substring(1).toLowerCase();
    // Once a whole command is typed and a space follows, the list steps aside.
    if (typed.contains(' ')) return const [];
    final all = [
      ...kCommands,
      for (final p in bridge.prompts)
        [p['name'] as String? ?? '', p['text'] as String? ?? '', 'saved'],
    ];
    final starts = <List<String>>[];
    final holds = <List<String>>[];
    for (final c in all) {
      final name = c[0].replaceFirst('/', '').toLowerCase();
      if (typed.isEmpty || name.startsWith(typed)) {
        starts.add(c);
      } else if (name.contains(typed) || c[1].toLowerCase().contains(typed)) {
        holds.add(c);
      }
    }
    return [...starts, ...holds].take(6).toList();
  }

  void _useCommand(List<String> c) {
    if (c.length > 2 && c[2] == 'saved') {
      _input.text = c[1];
    } else {
      _input.text = '${c[0]} ';
    }
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _focus.requestFocus();
    setState(() {});
  }

  @override
  void dispose() {
    bridge.chatClose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _pics.isEmpty) || _sending) return;
    // These open a panel on the PC rather than writing an answer, so typed
    // here they open the same sheets as the buttons.
    final bare = _pics.isEmpty ? text.toLowerCase() : '';
    final opens = <String, VoidCallback>{
      '/usage': () => _info('usage'),
      '/cost': () => _info('usage'),
      '/context': () => _info('context'),
      '/model': _models,
      '/effort': _effort,
    }[bare];
    if (opens != null) {
      _input.clear();
      setState(() {});
      opens();
      return;
    }
    setState(() {
      _sending = true;
      _hidNews = false;
      _starting = false;
    });
    final pics = List.of(_pics);
    _input.clear();
    _pics.clear();
    // On screen now, not after the round trip.
    // The PC is not there: keep it, and send it the moment it is.
    if (bridge.link != Link.on) {
      bridge.queue(
        dir: widget.dir,
        sessionId: _sid,
        server: widget.server,
        title: _session?['title'] as String? ?? widget.title,
        text: text,
        pictures: pics,
        why: '',
      );
      setState(() => _sending = false);
      _toBottom();
      return;
    }
    // It is still answering: the message waits rather than interrupting, and
    // goes by itself the moment that answer is finished.
    if (bridge.busyNow(_sid) ||
        bridge.waitingFor(_sid).isNotEmpty) {
      bridge.queue(
        dir: widget.dir,
        sessionId: _sid,
        server: widget.server,
        title: _session?['title'] as String? ?? widget.title,
        text: text,
        pictures: pics,
        afterTurn: true,
      );
      setState(() => _sending = false);
      _toBottom();
      return;
    }
    final shown = text;
    bridge.addPending(shown, pictures: pics);
    _toBottom();
    // It is on screen and the box is empty: you can write the next one while
    // this one is still on its way.
    setState(() => _sending = false);
    // The pictures set off when they were chosen; the message waits for them.
    final tokens = <String>[];
    String? lost;
    for (final p in pics) {
      final t = await p.done.future;
      if (t == null) {
        lost = p.error ?? 'A picture could not be sent.';
        break;
      }
      tokens.add(t);
    }
    final r = lost != null
        ? Reply(false, text: lost)
        : await bridge.chatSend(text, tokens);
    if (!mounted) return;
    if (!r.ok && _worthWaiting(r.text ?? '')) {
      bridge.dropPending(shown);
      bridge.queue(
        dir: widget.dir,
        sessionId: _sid,
        server: widget.server,
        title: _session?['title'] as String? ?? widget.title,
        text: text,
        pictures: pics,
        why: r.text ?? '',
      );
      _toBottom();
      return;
    }
    if (!r.ok) {
      // Give the words back so nothing typed is lost.
      bridge.dropPending(shown);
      // Only give the words back if you have not started writing the next one.
      if (_input.text.trim().isEmpty) _input.text = text;
      // the ones that got there are kept; the others go again
      _pics.addAll([
        for (final p in pics)
          p.error == null ? p : bridge.upload(p.name, p.bytes),
      ]);
      say(context, r.text, bad: true);
    }
  }

  /// Whether a refusal from the PC is one that waiting could fix.
  static bool _worthWaiting(String why) => RegExp(
    r'not connected|would not start|not open|did not answer|unreachable|no answer|timed out|closed while starting',
    caseSensitive: false,
  ).hasMatch(why);

  /// Hold the reader's place while an answer is being written.
  ///
  /// The list grows from the bottom, so every line that arrives pushes what is
  /// above it up the screen - which, if you had scrolled up to read something,
  /// drags that something away under your eyes. Each frame, whatever height the
  /// list gained is handed back to the scroll offset, so the words stay where
  /// they are. At the newest line there is nothing to hold: the bottom is where
  /// you already are. A drag is left alone, so this never fights a finger.
  void _holdPlace() {
    if (!mounted || !_scroll.hasClients) return;
    final at = _scroll.position;
    final was = _grewTo;
    _grewTo = at.maxScrollExtent;
    if (was == null || _pinned) return;
    final gained = at.maxScrollExtent - was;
    if (gained <= 0.5 || gained > 4000) return; // shrank, or a whole page arrived
    if (at.isScrollingNotifier.value) return; // their finger is on it
    _scroll.jumpTo((_scroll.offset + gained).clamp(0.0, at.maxScrollExtent));
  }

  void _toBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _pick(ImageSource source) async {
    final picker = ImagePicker();
    // Pictures are shrunk on the phone: a 4 MB photo crosses the link as ~300 KB.
    if (source == ImageSource.gallery) {
      for (final f in await picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
        limit: 6,
      )) {
        _pics.add(bridge.upload(f.name, await f.readAsBytes()));
      }
    } else {
      final f = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (f != null) _pics.add(bridge.upload(f.name, await f.readAsBytes()));
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bridge,
      builder: (context, _) {
        final live = bridge.chatLive;
        final lamp = live['lamp'] as String? ?? '';
        final ask = live['ask'] as Map?;
        final askId = ask == null
            ? null
            : '${ask['at']}|${ask['question']}|${(ask['context'] as List?)?.join('|')}';
        // A pick belongs to the one question it answered: the next question,
        // or the same one asked again later, starts with nothing picked.
        if (ask == null) _answeredOf = null;
        final picked = askId != null && askId == _answeredOf ? _answered : null;
        // Rebuilt only when the conversation changed.
        // A CEO's or CTO's chat reads as plan, then report: the work between
        // is folded into one row per turn.
        final lead = const ['ceo', 'cto'].contains(_session?['roleKey']);
        final rowsKey = '${bridge.chatVersion}|$lead|$lamp';
        if (_rowsFor != rowsKey) {
          _rowsCache = lead ? _leadRows(bridge.chatItems, lamp == 'busy') : _rows(bridge.chatItems);
          _rowsFor = rowsKey;
        }
        var rows = _rowsCache;
        final waiting = bridge.waitingFor(_sid);
        if (waiting.isNotEmpty) {
          rows = [
            ...rows,
            for (final w in waiting)
              _WaitingBubble(
                key: ValueKey('w${w.id}'),
                waiting: w,
                onDrop: () => bridge.unqueue(w.id),
              ),
          ];
        }
        if (bridge.draft.isNotEmpty) {
          rows = [
            ...rows,
            _Writing(text: bridge.draft.substring(0, bridge.draftShown)),
          ];
          // Reading something further up while it writes: give the scroll
          // offset back every pixel the list gains, so nothing moves.
          WidgetsBinding.instance.addPostFrameCallback((_) => _holdPlace());
        } else {
          _grewTo = null;
        }
        // Starting a session takes several seconds. The PC says so plainly,
        // and the wait is more useful spent reading something.
        final status = live['status'] as String? ?? '';
        if (status == 'Starting the session') _starting = true;
        if (lamp != 'busy') _starting = false;
        final news = _starting && !_hidNews;
        final ready = status != 'Starting the session';
        final newReply = _away && bridge.chatArrived > _seenArrived;
        return Scaffold(
          backgroundColor: C.well,
          body: Column(
            children: [
              _Header(
                onBack: widget.onBack,
                title: _session?['title'] as String? ?? widget.title,
                project: [
                  widget.project,
                  if (widget.server.isNotEmpty) 'server',
                ].where((x) => x.isNotEmpty).join(' · '),
                lamp: lamp,
                account: _session?['account'] as String? ?? '',
                onAccount: _session == null
                    ? null
                    : () => accountSheet(
                        context,
                        widget.dir,
                        _sid,
                        _session!,
                      ),
                onMenu: _menu,
              ),
              Expanded(
                child: Stack(
                  children: [
                    if (!bridge.chatLoaded)
                      const Skeleton(lines: 9)
                    else if (rows.isEmpty)
                      const _Empty()
                    else
                      ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: rows.length + (bridge.chatEarlier ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == rows.length) {
                            return _Earlier(
                              busy: bridge.loadingEarlier,
                              onTap: bridge.loadEarlier,
                            );
                          }
                          return rows[rows.length - 1 - i];
                        },
                      ),
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AnimatedScale(
                          scale: _away ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutBack,
                          child: Material(
                            color: C.raised2,
                            shape: const StadiumBorder(),
                            elevation: 4,
                            child: InkWell(
                              customBorder: const StadiumBorder(),
                              onTap: _toBottom,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: newReply ? 14 : 8,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.arrow_downward,
                                      size: 16,
                                      color: C.text,
                                    ),
                                    if (newReply) ...[
                                      const SizedBox(width: 6),
                                      const Text(
                                        'New reply',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (lamp == 'busy' &&
                  ask == null &&
                  bridge.draft.isEmpty &&
                  !news)
                _Working(
                  status: live['status'] as String? ?? '',
                  since: bridge.busySince,
                ),
              if (ask != null && ask['kind'] == 'question')
                QuestionCard(
                  key: ValueKey(askId),
                  ask: ask.cast<String, dynamic>(),
                  onAnswer: (keys, words) {
                    bridge.chatAnswer(keys, words);
                    Alerts.clearFor(_sid);
                  },
                )
              else if (ask != null)
                _AskCard(
                  key: ValueKey(askId),
                  ask: ask.cast<String, dynamic>(),
                  picked: picked,
                  onPick: (key, label) {
                    setState(() {
                      _answered = key;
                      _answeredOf = askId;
                    });
                    bridge.chatKey(key);
                    Alerts.clearFor(_sid);
                    if (RegExp(
                      r'tell Claude|differently',
                      caseSensitive: false,
                    ).hasMatch(label)) {
                      _focus.requestFocus();
                    }
                  },
                ),
              if (news)
                StartingCard(
                  ready: ready,
                  onClose: () => setState(() => _hidNews = true),
                ),
              if (bridge.link != Link.on)
                _OfflineLine(
                  link: bridge.link,
                  name: bridge.conn?.name ?? 'your PC',
                  waiting: waiting.length,
                ),
              if (_matches.isNotEmpty)
                _CommandList(matches: _matches, onPick: _useCommand),
              if (_running > 0) _BgLine(count: _running, onOpen: _tasks),
              _Composer(
                input: _input,
                focus: _focus,
                pics: _pics,
                busy: lamp == 'busy',
                // A question from a session with no terminal also takes
                // words of your own as the answer.
                asking: ask != null && ask['direct'] != true,
                sending: _sending,
                onSend: _send,
                onTalk: () => openTalk(
                  context,
                  dir: widget.dir,
                  sessionId: _sid,
                  server: (_session?['server'] as String?) ?? widget.server,
                  title: _session?['title'] as String? ?? widget.title,
                ),
                onMic: () async {
                  final said = await askByVoice(context, title: _session?['title'] as String? ?? widget.title);
                  if (!mounted || said == null) return;
                  if (said.typeInstead) return _focus.requestFocus();
                  _input.text = said.text;
                  _send();
                },
                onStop: () {
                  HapticFeedback.mediumImpact();
                  bridge.chatKey('\x1b');
                },
                onPick: _pick,
                onRemovePic: (i) => setState(() => _pics.removeAt(i)),
                onCommands: () {
                  _input.text = '/';
                  _input.selection = const TextSelection.collapsed(offset: 1);
                  _focus.requestFocus();
                  setState(() {});
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// How many background commands this session has going, counted from the
  /// chat itself: each one says so when it starts, and the notice that it has
  /// finished arrives the same way.
  int get _running {
    final started = <String>{};
    final over = <String>{};
    for (final it in bridge.chatItems) {
      final task = it['task'] as String?;
      if (task == null || task.isEmpty) continue;
      if (it['k'] == 'result') started.add(task);
      if (it['k'] == 'task') over.add(task);
    }
    return started.difference(over).length;
  }

  /// The list of what this session has running in the background.
  void _tasks() => _open(Side.tasks);

  /// One of the sections that sit beside a conversation. On a wide screen they
  /// are in the panel on the right; here they come up from the bottom.
  void _open(Side bit) => showSide(context, bit, {
    'dir': widget.dir,
    'sessionId': _sid,
    'server': (_session?['server'] as String?) ?? '',
  });

  void _menu() {
    showLoopSheet<void>(
      context: context,
      // It scrolls: on a phone the list is taller than the sheet.
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Session options'),
              subtitle: const Text(
                'Rename, account, role, Remote Control, delete',
                style: TextStyle(color: C.text3, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheet);
                sessionSheet(
                  context,
                  widget.dir,
                  _sid,
                  () {},
                  session: _session,
                );
              },
            ),
            // On a wide screen these live in the panel beside the
            // conversation; repeating them here would be two doors to one room.
            if (!Pane.side)
              for (final bit in Side.values)
                ListTile(
                  leading: Icon(bit.icon),
                  title: Text(bit.title),
                  subtitle: Text(
                    bit.about,
                    style: const TextStyle(color: C.text3, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(sheet);
                    _open(bit);
                  },
                ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Model'),
              subtitle: const Text(
                'Which Claude this session runs on',
                style: TextStyle(color: C.text3, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheet);
                _models();
              },
            ),
            ListTile(
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('Effort'),
              subtitle: const Text(
                'How much thinking goes into each answer',
                style: TextStyle(color: C.text3, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheet);
                _effort();
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_usage),
              title: const Text('Usage'),
              subtitle: const Text(
                'How much of your plan is left',
                style: TextStyle(color: C.text3, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheet);
                _info('usage');
              },
            ),
            ListTile(
              leading: const Icon(Icons.pie_chart_outline),
              title: const Text('Context'),
              subtitle: const Text(
                "What is filling this session's memory",
                style: TextStyle(color: C.text3, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheet);
                _info('context');
              },
            ),
            ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('Terminal view'),
              subtitle: const Text(
                'The raw screen, for anything the chat cannot show',
                style: TextStyle(color: C.text3, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheet);
                _terminal();
              },
            ),
            ListTile(
              leading: const Icon(Icons.stop_circle_outlined),
              title: const Text('Interrupt'),
              onTap: () {
                Navigator.pop(sheet);
                bridge.chatKey('\x1b');
              },
            ),
            const SizedBox(height: 8),
          ],
          ),
        ),
      ),
    );
  }

  /// How hard it thinks before answering, as /effort does on the PC.
  /// Usage or context, read for you by Claude Code on the PC. It costs no
  /// tokens and works whether or not the session is open there.
  Future<void> _info(String what) async {
    final title = what == 'usage' ? 'Usage' : 'Context';
    say(
      context,
      what == 'usage'
          ? 'Asking for usage…'
          : 'Reading the context. With the session open on the PC this takes up to a minute.',
    );
    final r = await bridge.act('info', {
      'dir': widget.dir,
      'sessionId': _sid,
      'what': what,
    }, const Duration(seconds: 160));
    if (!mounted) return;
    if (!r.ok) return say(context, r.text, bad: true);
    // Answered by the session itself: it is in the conversation, not a sheet.
    if (r.data is Map && r.data['inChat'] == true) return _toBottom();
    // Usage reads as Claude Desktop shows it: one bar per limit.
    final limits = r.data is Map ? r.data['limits'] : null;
    if (limits is List && limits.isNotEmpty) {
      showLoopSheet<void>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Usage',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                for (final l in limits.cast<Map>()) UsageBar(limit: l),
              ],
            ),
          ),
        ),
      );
      return;
    }
    showLoopSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheet).size.height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                MarkdownBody(data: r.text ?? '', selectable: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _effort() {
    const levels = [
      ['Low', 'low', 'Quick answers, least thinking'],
      ['Medium', 'medium', 'The usual balance'],
      ['High', 'high', 'Slower, for knotty problems'],
      ['Max', 'max', 'As far as it goes'],
    ];
    showLoopSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Effort',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'How much thinking goes into each answer, for this session.',
                  style: TextStyle(color: C.text3, fontSize: 12),
                ),
              ),
            ),
            for (final e in levels)
              ListTile(
                title: Text(e[0]),
                subtitle: Text(
                  e[2],
                  style: const TextStyle(color: C.text3, fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(sheet);
                  final r = await bridge.chatSend('/effort ${e[1]}', const []);
                  if (mounted) {
                    say(context, r.ok ? 'Effort: ${e[0]}' : r.text, bad: !r.ok);
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Switch the model this session runs on, as /model does on the PC.
  void _models() {
    const models = [
      ['Opus 5.5', 'claude-opus-5-5', 'The most capable'],
      ['Sonnet 5.5', 'claude-sonnet-5-5', 'Quick and strong'],
      ['Haiku 5.5', 'claude-haiku-5-5', 'Fastest, for small jobs'],
      ['Fable 5.1', 'claude-fable-5-1', 'Writing and long prose'],
      ['Default', 'default', "Back to whatever this session's account uses"],
      ['Opusplan', 'opusplan', 'Opus while it plans, Sonnet while it works'],
    ];
    showLoopSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Model',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'It changes from the next message on, for this session only.',
                  style: TextStyle(color: C.text3, fontSize: 12),
                ),
              ),
            ),
            for (final m in models)
              ListTile(
                title: Text(m[0]),
                subtitle: m[2].isEmpty
                    ? null
                    : Text(
                        m[2],
                        style: const TextStyle(color: C.text3, fontSize: 12),
                      ),
                onTap: () async {
                  Navigator.pop(sheet);
                  final r = await bridge.chatSend('/model ${m[1]}', const []);
                  if (mounted) {
                    say(
                      context,
                      r.ok ? 'Switching to ${m[0]}…' : r.text,
                      bad: !r.ok,
                    );
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _terminal() async {
    final r = await bridge.open(widget.dir, _sid);
    if (!mounted) return;
    if (!r.ok) return say(context, r.text, bad: true);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: const SafeArea(top: false, child: TerminalPage()),
        ),
      ),
    );
    bridge.unwatch();
  }

  /// A lead's chat: per turn, the answers worth reading - the last one, and
  /// any plan or report (a "Need from you" line, or Plan: / Done:) - with
  /// everything before each folded into "Worked · N steps · 4m".
  List<Widget> _leadRows(List<Map<String, dynamic>> items, bool busy) {
    final out = <Widget>[];
    final report = RegExp(r'^\s*(?:\*\*)?(?:Plan|Done)\b|^\s*(?:\*\*)?Need from you', multiLine: true, caseSensitive: false);
    var turn = <Map<String, dynamic>>[];
    void close(bool last) {
      if (turn.isEmpty) return;
      final lastText = turn.lastIndexWhere((x) => x['k'] == 'text');
      var folded = <Map<String, dynamic>>[];
      for (var i = 0; i < turn.length; i++) {
        final it = turn[i];
        final show = it['k'] == 'text' && (i == lastText && !(last && busy) || report.hasMatch(it['text'] as String? ?? ''));
        if (!show) {
          folded.add(it);
          continue;
        }
        if (folded.isNotEmpty) out.add(_WorkedRow(key: ValueKey('w${folded.first['id']}'), items: folded, until: it['at'], rows: _rows));
        folded = [];
        out.addAll(_rows([it]));
      }
      if (folded.isNotEmpty) {
        out.add(_WorkedRow(key: ValueKey('w${folded.first['id']}'), items: folded, running: last && busy, rows: _rows));
      }
      turn = [];
    }

    for (final it in items) {
      if (it['k'] == 'user' || it['k'] == 'peer') {
        close(false);
        out.addAll(_rows([it]));
      } else {
        turn.add(it);
      }
    }
    close(true);
    return out;
  }

  /// Messages in order, with tool steps between answers kept together.
  List<Widget> _rows(List<Map<String, dynamic>> items) {
    final out = <Widget>[];
    var tools = <Map<String, dynamic>>[];
    void flush() {
      if (tools.isEmpty) return;
      final run = tools;
      tools = [];
      final fresh = run.any((t) => t['fresh'] == true);
      out.add(
        Arrive(
          key: ValueKey('g${run.first['id']}'),
          enabled: fresh,
          child: _StepsLine(tools: run),
        ),
      );
    }

    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final fresh = it['fresh'] == true;
      switch (it['k']) {
        case 'tool':
          tools.add(it);
        case 'user':
          flush();
          out.add(
            Arrive(
              key: ValueKey('u${it['id']}'),
              enabled: fresh,
              child: _UserBubble(item: it),
            ),
          );
        case 'text':
          flush();
          // Copy sits under the last answer of a turn, as in the Claude app.
          final endOfTurn =
              i == items.length - 1 ||
              items[i + 1]['k'] == 'user' ||
              items[i + 1]['k'] == 'peer';
          out.add(
            Arrive(
              key: ValueKey('a${it['id']}'),
              enabled: fresh,
              child: _ClaudeText(
                text: it['text'] as String? ?? '',
                typeIn: fresh,
                from: (it['typeFrom'] as num?)?.toInt() ?? 0,
                id: it['id'],
                actions: endOfTurn,
              ),
            ),
          );
        case 'peer':
          flush();
          out.add(
            Arrive(
              key: ValueKey('p${it['id']}'),
              enabled: fresh,
              child: _PeerBubble(item: it),
            ),
          );
        case 'note':
          flush();
          out.add(_Note(it['text'] as String? ?? ''));
      }
    }
    flush();
    return out;
  }
}

// ---------- header ----------

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    this.onBack,
    required this.project,
    required this.lamp,
    required this.account,
    required this.onMenu,
    this.onAccount,
  });
  final String title;
  final String project;
  final String lamp;
  final String account;
  final VoidCallback? onBack;
  final VoidCallback onMenu;
  final VoidCallback? onAccount;

  @override
  Widget build(BuildContext context) {
    final accounts = bridge.accounts;
    String? accountName;
    for (final a in accounts) {
      if (a['id'] == account) accountName = a['name'] as String?;
    }
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: const BoxDecoration(
        color: C.chrome,
        border: Border(bottom: BorderSide(color: C.line)),
      ),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                onBack == null ? Icons.arrow_back_ios_new : Icons.close,
                size: 20,
              ),
              onPressed: onBack ?? () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PulseDot(color: C.lamp(lamp), pulse: lamp == 'busy'),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (project.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 1),
                      child: Text(
                        project,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: C.text3),
                      ),
                    ),
                ],
              ),
            ),
            if (accounts.length > 1 && accountName != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Material(
                  color: C.raised,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: onAccount,
                    child: Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      child: Text(
                        accountName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: C.text2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: C.text2),
              onPressed: onMenu,
            ),
          ],
        ),
      ),
    );
  }
}

/// A status dot; while busy it breathes.
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    required this.color,
    this.pulse = false,
    this.size = 8,
  });
  final Color color;
  final bool pulse;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.pulse && _c.isAnimating) _c.value = 0;
    if (!widget.pulse) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.pulse) return dot;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.35).animate(curve),
      child: FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.55).animate(curve),
        child: dot,
      ),
    );
  }
}

// ---------- messages ----------

/// A message from another session (a teammate, or a sub-session handing its
/// work back): on the left, with who sent it, so it is not read as the user's.
class _PeerBubble extends StatelessWidget {
  const _PeerBubble({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final from = item['from'] as String? ?? 'another session';
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: C.panel,
              border: Border.all(color: C.lineStrong),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.forum_outlined, size: 13, color: C.accent),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        from,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: C.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                SelectableText(
                  item['text'] as String? ?? '',
                  style: const TextStyle(fontSize: 15, height: 1.4, color: C.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final images = ((item['images'] ?? const []) as List).cast<Map>();
    final text = item['text'] as String? ?? '';
    final command = item['command'] == true;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: item['pending'] == true ? 0.6 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // The message first, as you wrote it.
            if (text.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: const BoxDecoration(
                    color: C.bubble,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(6),
                    ),
                  ),
                  child: SelectableText(
                    text,
                    style: TextStyle(
                      fontSize: command ? 14 : 15.5,
                      height: 1.4,
                      color: C.text,
                      fontFamily: command ? 'monospace' : null,
                      fontWeight: command ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ),
            // Then what came with it, in one row that scrolls sideways.
            if (images.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: text.isEmpty ? 0 : 6),
                child: SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    reverse: true, // the row hugs the right, like the bubble
                    shrinkWrap: true,
                    itemCount: images.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      // reversed, so the first picture still reads first
                      final img = images[images.length - 1 - i];
                      return _Thumb(
                        ref: img['ref'] as String? ?? '',
                        bytes: img['bytes'] as Uint8List?,
                        upload: img['upload'] as Upload?,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One attachment under a message: a square you can tap to see whole.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.ref, this.bytes, this.upload});
  final String ref;
  final Upload? upload; // still on its way: a ring shows how far
  final Uint8List? bytes; // a picture still on its way, from the phone itself

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        height: 84,
        child: Material(
          color: C.raised,
          child: InkWell(
            onTap: ref.isEmpty && bytes == null
                ? null
                : () => Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      barrierColor: Colors.black,
                      pageBuilder: (_, __, ___) =>
                          _PictureView(ref: ref, bytes: bytes),
                      transitionsBuilder: (_, a, __, child) =>
                          FadeTransition(opacity: a, child: child),
                    ),
                  ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                bytes != null
                    ? Image.memory(
                        bytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : _Picture(ref: ref, fill: true),
                if (upload != null) UploadRing(upload: upload!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A picture on its own, pinch to zoom, tap to close.
class _PictureView extends StatelessWidget {
  const _PictureView({required this.ref, this.bytes});
  final String ref;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: bytes != null
                      ? Image.memory(bytes!, fit: BoxFit.contain)
                      : _Picture(ref: ref, whole: true),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClaudeText extends StatelessWidget {
  const _ClaudeText({
    required this.text,
    this.typeIn = false,
    this.actions = false,
    this.id,
    this.from = 0,
  });
  final String text;
  final bool typeIn;
  final bool actions;
  final Object? id;
  final int from; // already shown while it was being written

  static final _sheet = () {
    const body = TextStyle(fontSize: 15.5, height: 1.55, color: C.text);
    return MarkdownStyleSheet(
      p: body,
      listBullet: body.copyWith(color: C.text3),
      listIndent: 20,
      h1: body.copyWith(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3),
      h2: body.copyWith(
        fontSize: 17.5,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      h3: body.copyWith(
        fontSize: 15.5,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      h1Padding: const EdgeInsets.only(top: 20, bottom: 8),
      h2Padding: const EdgeInsets.only(top: 20, bottom: 8),
      h3Padding: const EdgeInsets.only(top: 16, bottom: 6),
      strong: const TextStyle(fontWeight: FontWeight.w700, color: C.text),
      em: const TextStyle(fontStyle: FontStyle.italic),
      a: const TextStyle(color: C.accent),
      code: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13.5,
        color: C.text,
        backgroundColor: C.panel,
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: C.codeWell,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.line),
      ),
      blockquote: body.copyWith(color: C.text2),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: C.accentDim, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      tableBorder: TableBorder.all(color: C.line),
      tableHead: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      tableBody: const TextStyle(fontSize: 13.5),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(top: BorderSide(color: C.line)),
      ),
      blockSpacing: 10,
    );
  }();

  @override
  Widget build(BuildContext context) {
    final md = TypeIn(
      text: text,
      enabled: typeIn,
      from: from,
      id: id == null ? null : 't$id',
      builder: (shown) => MarkdownBody(
        data: shown,
        selectable: true,
        softLineBreak: true,
        styleSheet: _sheet,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          md,
          if (actions)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _SmallAction(
                icon: Icons.copy_rounded,
                tip: 'Copy',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  HapticFeedback.selectionClick();
                  say(context, 'Copied');
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.icon,
    required this.tip,
    required this.onTap,
  });
  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: InkResponse(
      onTap: onTap,
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 17, color: C.text3),
      ),
    ),
  );
}

// ---------- tool steps ----------

IconData toolIcon(String kind, String name) => switch (kind) {
  'read' =>
    name == 'Grep' || name == 'Glob'
        ? Icons.search
        : Icons.description_outlined,
  'edit' => Icons.edit_outlined,
  'run' => Icons.terminal,
  'web' => Icons.language,
  'agent' => Icons.smart_toy_outlined,
  'plan' => Icons.checklist,
  'ask' => Icons.help_outline,
  _ => Icons.extension_outlined,
};

/// One step on one quiet line: what was done and to what. Tap to see the result.
class ToolLine extends StatefulWidget {
  const ToolLine({super.key, required this.tool, this.inSheet = false});
  final Map<String, dynamic> tool;
  final bool inSheet;

  @override
  State<ToolLine> createState() => _ToolLineState();
}

class _ToolLineState extends State<ToolLine> {
  bool _open = false;
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tool;
    final pending = t['done'] != true;
    final failed = t['ok'] == false;
    final title = (t['title'] as String?) ?? (t['label'] as String? ?? 'Step');
    final sub = t['sub'] as String? ?? '';
    final head = Row(
      children: [
        if (!widget.inSheet) ...[
          SizedBox(
            width: 16,
            child: pending
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: C.text2,
                    ),
                  )
                : Icon(
                    toolIcon(
                      t['kind'] as String? ?? '',
                      t['name'] as String? ?? '',
                    ),
                    size: 15,
                    color: failed ? C.danger : C.text3,
                  ),
          ),
          const SizedBox(width: 8),
        ],
        if (pending)
          Flexible(
            child: Shimmer(
              child: Text(
                t['doing'] as String? ?? title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          )
        else ...[
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: failed ? C.danger : C.text2,
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: C.text3),
              ),
            ),
          ] else
            const Spacer(),
          _diffCount(t),
        ],
        AnimatedRotation(
          turns: _open ? 0.25 : 0,
          duration: const Duration(milliseconds: 160),
          child: const Icon(Icons.chevron_right, size: 16, color: C.text3),
        ),
      ],
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(height: 36, child: head),
          ),
          if (_open)
            FutureBuilder<dynamic>(
              future: bridge.kept(t['id'] as String),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: C.text3,
                      backgroundColor: C.raised,
                    ),
                  );
                }
                final more = snap.data is Map
                    ? (snap.data as Map).cast<String, dynamic>()
                    : const <String, dynamic>{};
                return _detail({...t, ...more});
              },
            ),
        ],
      ),
    );
  }

  Widget _diffCount(Map<String, dynamic> t) {
    final d = t['lines'] as Map?;
    if (d == null) return const SizedBox(width: 4);
    final del = d['del'] ?? 0;
    final add = d['add'] ?? 0;
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 4),
      child: Row(
        children: [
          Text('+$add', style: mono.copyWith(color: C.idle)),
          const SizedBox(width: 4),
          Text('−$del', style: mono.copyWith(color: C.danger)),
        ],
      ),
    );
  }

  Widget _detail(Map<String, dynamic> t) {
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.45,
      color: C.text2,
    );
    final diff = t['diff'] as Map?;
    final todos = (t['todos'] as List?)?.cast<Map>();
    final result = t['result'] as String? ?? '';
    final detail = t['detail'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: C.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.isNotEmpty && diff == null)
            SelectableText(detail, style: mono.copyWith(color: C.text)),
          if (diff != null) ...[
            _DiffBlock(text: diff['old'] as String? ?? '', added: false),
            const SizedBox(height: 4),
            _DiffBlock(text: diff['new'] as String? ?? '', added: true),
          ],
          if ((t['body'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(t['body'] as String, style: mono),
          ],
          if (todos != null)
            for (final td in todos)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      td['status'] == 'completed'
                          ? Icons.check_circle
                          : td['status'] == 'in_progress'
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 15,
                      color: td['status'] == 'completed'
                          ? C.idle
                          : (td['status'] == 'in_progress' ? C.busy : C.text3),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        td['text'] as String? ?? '',
                        style: const TextStyle(fontSize: 13, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
          if (result.isNotEmpty) ...[
            if (detail.isNotEmpty || diff != null || todos != null)
              const Divider(height: 18),
            Text(
              result,
              maxLines: _more ? null : 12,
              overflow: _more ? null : TextOverflow.fade,
              style: mono.copyWith(
                color: t['ok'] == false ? C.danger : C.text2,
              ),
            ),
            if (!_more && '\n'.allMatches(result).length > 11)
              GestureDetector(
                onTap: () => setState(() => _more = true),
                child: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Show more',
                    style: TextStyle(fontSize: 12, color: C.accent),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// The work of one turn in a lead's chat, folded: "Worked · 23 steps · 4m",
/// or "Working · 7 steps" while it runs. Tap to see the steps as usual.
class _WorkedRow extends StatefulWidget {
  const _WorkedRow({super.key, required this.items, required this.rows, this.running = false, this.until});
  final List<Map<String, dynamic>> items;
  final List<Widget> Function(List<Map<String, dynamic>>) rows;
  final bool running;
  final Object? until;

  @override
  State<_WorkedRow> createState() => _WorkedRowState();
}

class _WorkedRowState extends State<_WorkedRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final steps = widget.items.where((x) => x['k'] == 'tool').length;
    final from = (widget.items.first['at'] as num?)?.toInt() ?? 0;
    final to = (widget.until as num?)?.toInt() ?? (widget.items.last['at'] as num?)?.toInt() ?? from;
    final mins = from > 0 && to > from ? ((to - from) / 60000).round() : 0;
    final label = widget.running
        ? 'Working · $steps step${steps == 1 ? '' : 's'}'
        : 'Worked · $steps step${steps == 1 ? '' : 's'}${mins > 0 ? ' · ${mins}m' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                if (widget.running)
                  const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: C.text3))
                else
                  const Icon(Icons.check_circle_outline, size: 15, color: C.text3),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text2, fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(width: 2),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.chevron_right, size: 18, color: C.text3),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: _open ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.rows(widget.items)) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// More than three steps in a row: one line that says what they were, which
/// opens the full list as a sheet, as the Claude app does.
class _StepsLine extends StatelessWidget {
  const _StepsLine({required this.tools});
  final List<Map<String, dynamic>> tools;

  static String summary(List<Map<String, dynamic>> tools) {
    final counts = <String, int>{};
    for (final t in tools) {
      counts[t['kind'] as String? ?? 'tool'] =
          (counts[t['kind'] as String? ?? 'tool'] ?? 0) + 1;
    }
    String n(int c, String one, String many) => c == 1 ? one : '$c $many';
    final parts = <String>[
      if (counts['read'] != null)
        n(counts['read']!, 'read a file', 'files read'),
      if (counts['edit'] != null)
        n(counts['edit']!, 'edited a file', 'files edited'),
      if (counts['run'] != null) n(counts['run']!, 'ran a command', 'commands'),
      if (counts['web'] != null) 'browsed the web',
      if (counts['agent'] != null)
        n(counts['agent']!, 'ran an agent', 'agents'),
    ];
    if (tools.length == 1) {
      final t = tools.first;
      final sub = t['sub'] as String? ?? '';
      return sub.isEmpty
          ? (t['title'] as String? ?? 'Used a tool')
          : '${t['title']} · $sub';
    }
    final head = 'Used ${tools.length} tools';
    return parts.isEmpty ? head : '$head, ${parts.take(2).join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final pending = tools.last['done'] != true;
    final failed = tools.where((t) => t['ok'] == false).length;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _open(context),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Flexible(
              child: pending
                  ? Shimmer(
                      child: Text(
                        tools.last['doing'] as String? ?? 'Working',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      summary(tools),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, color: C.text3),
                    ),
            ),
            if (failed > 0)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '· $failed failed',
                  style: const TextStyle(fontSize: 12.5, color: C.danger),
                ),
              ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 18, color: C.text3),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    showLoopSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.panel,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: (0.2 + tools.length * 0.075).clamp(0.25, 0.7),
        minChildSize: 0.2,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Row(
              children: [
                CloseCircle(onTap: () => Navigator.pop(sheet)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    summary(tools),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < tools.length; i++)
              _TimelineStep(tool: tools[i], last: i == tools.length - 1),
          ],
        ),
      ),
    );
  }
}

/// One step in the sheet: an icon on a thin line, what was done, and to what.
class _TimelineStep extends StatelessWidget {
  const _TimelineStep({required this.tool, required this.last});
  final Map<String, dynamic> tool;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Icon(
                  toolIcon(
                    tool['kind'] as String? ?? '',
                    tool['name'] as String? ?? '',
                  ),
                  size: 18,
                  color: tool['ok'] == false ? C.danger : C.text2,
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: C.lineStrong,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ToolLine(tool: tool, inSheet: true),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffBlock extends StatelessWidget {
  const _DiffBlock({required this.text, required this.added});
  final String text;
  final bool added;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final colour = added ? C.idle : C.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border(
          left: BorderSide(color: colour.withValues(alpha: 0.7), width: 3),
        ),
      ),
      child: Text(
        text,
        maxLines: 24,
        overflow: TextOverflow.fade,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.45,
          color: colour,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: C.text3, fontSize: 12, height: 1.4),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Text(
        'Nothing said here yet.\nSend the first message below.',
        textAlign: TextAlign.center,
        style: TextStyle(color: C.text3, height: 1.5),
      ),
    ),
  );
}

// ---------- working, asking, typing ----------

class _Working extends StatelessWidget {
  const _Working({required this.status, required this.since});
  final String status;
  final DateTime? since;

  @override
  Widget build(BuildContext context) {
    // "Pondering… (12s · ↓ 300 tokens)": the word shimmers, the timer is ours.
    final word = status.isEmpty ? 'Working…' : status.split('(').first.trim();
    return Container(
      width: double.infinity,
      color: C.well,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          const PulseDot(color: C.accent, pulse: true),
          const SizedBox(width: 8),
          Flexible(
            child: Shimmer(
              base: C.text3,
              child: Text(
                word,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (since != null) ...[
            const Text(' · ', style: TextStyle(fontSize: 13, color: C.text3)),
            Elapsed(
              since: since!,
              style: const TextStyle(fontSize: 13, color: C.text3),
            ),
          ],
        ],
      ),
    );
  }
}

class _AskCard extends StatelessWidget {
  const _AskCard({
    super.key,
    required this.ask,
    required this.onPick,
    this.picked,
  });
  final Map<String, dynamic> ask;
  final void Function(String key, String label) onPick;
  final String? picked;

  @override
  Widget build(BuildContext context) {
    final options = ((ask['options'] ?? const []) as List).cast<Map>();
    final detail = ((ask['context'] ?? const []) as List).cast<String>();
    return Arrive(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        decoration: BoxDecoration(
          color: C.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.lineStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: C.accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ask['question'] as String? ?? 'Claude is asking',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 110),
                          child: SingleChildScrollView(
                            child: Text(
                              detail.join('\n'),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.4,
                                color: C.text2,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      for (var i = 0; i < options.length; i++)
                        _option(options[i], i == 0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(Map o, bool first) {
    final key = o['key'] as String? ?? '';
    final label = o['label'] as String? ?? '';
    final isPicked = picked == key;
    final done = picked != null;
    final risky = RegExp(
      r'^No\b|reject|deny|discard',
      caseSensitive: false,
    ).hasMatch(label);
    final bg = first ? C.accent : C.raised;
    final fg = first ? C.accentInk : (risky ? C.danger : C.text);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: done && !isPicked ? 0.4 : 1,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: first ? BorderSide.none : const BorderSide(color: C.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: done
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onPick(key, label);
                  },
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Text(
                    '$key.',
                    style: TextStyle(
                      fontSize: 13,
                      color: fg.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: fg,
                        fontWeight: first ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isPicked)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(Icons.check, size: 18, color: fg),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Something is still running in the background: a quiet line that says how
/// much, and opens the list.
class _BgLine extends StatelessWidget {
  const _BgLine({required this.count, required this.onOpen});
  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    child: Material(
      color: C.panel,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(
            children: [
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: C.busy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 task running in the background'
                      : '$count tasks running in the background',
                  style: const TextStyle(fontSize: 12.5, color: C.text2),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: C.text3),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.focus,
    required this.pics,
    required this.busy,
    required this.asking,
    required this.sending,
    required this.onSend,
    required this.onStop,
    required this.onMic,
    required this.onTalk,
    required this.onPick,
    required this.onRemovePic,
    required this.onCommands,
  });
  final TextEditingController input;
  final FocusNode focus;
  final List<Upload> pics;
  final bool busy;
  final bool asking;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onMic;
  final VoidCallback onTalk;
  final Future<void> Function(ImageSource) onPick;
  final void Function(int) onRemovePic;
  final VoidCallback onCommands;

  @override
  Widget build(BuildContext context) {
    final has = !asking && (input.text.trim().isNotEmpty || pics.isNotEmpty);
    final stop = busy && !has;
    Widget circle(IconData icon, String tip, VoidCallback onTap) => Tooltip(
      message: tip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20, color: C.text2),
        ),
      ),
    );
    return Container(
      decoration: const BoxDecoration(
        color: C.chrome,
        border: Border(top: BorderSide(color: C.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: C.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: focus.hasFocus ? C.lineStrong : C.line),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pics.isNotEmpty)
              SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  itemCount: pics.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 60,
                          height: 60,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(pics[i].bytes, fit: BoxFit.cover),
                              UploadRing(upload: pics[i], size: 24),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: GestureDetector(
                          onTap: () => onRemovePic(i),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                circle(
                  Icons.add,
                  'Photo or camera',
                  () => showLoopSheet<void>(
                    context: context,
                    builder: (sheet) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.photo_library_outlined),
                            title: const Text('Photos'),
                            onTap: () {
                              Navigator.pop(sheet);
                              onPick(ImageSource.gallery);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.photo_camera_outlined),
                            title: const Text('Camera'),
                            onTap: () {
                              Navigator.pop(sheet);
                              onPick(ImageSource.camera);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.bolt_outlined),
                            title: const Text('Commands'),
                            subtitle: const Text(
                              'Or type / in the message box',
                              style: TextStyle(color: C.text3, fontSize: 12),
                            ),
                            onTap: () {
                              Navigator.pop(sheet);
                              onCommands();
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
                // Hands free: speak and be read back to, without the keyboard
                // or the screen.
                if (!asking) circle(Icons.graphic_eq, 'Voice mode', onTalk),
                Expanded(
                  child: TextField(
                    controller: input,
                    focusNode: focus,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 15.5, height: 1.4),
                    decoration: InputDecoration(
                      hintText: asking ? 'Answer above first' : 'Message…',
                      hintStyle: const TextStyle(
                        fontSize: 15.5,
                        color: C.text3,
                      ),
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(6, 10, 6, 10),
                    ),
                  ),
                ),
                SizedBox(
                  width: 38,
                  height: 38,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (c, a) =>
                        ScaleTransition(scale: a, child: c),
                    child: sending
                        ? const Padding(
                            key: ValueKey('s'),
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: C.accent,
                            ),
                          )
                        : stop
                        ? Material(
                            key: const ValueKey('stop'),
                            color: C.raised2,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onStop,
                              child: Center(
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: C.text,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          )
                        // Empty, it is the mic: speak instead of typing.
                        : Material(
                            key: ValueKey(has),
                            color: has ? C.accent : C.raised2,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: has ? onSend : (asking ? null : onMic),
                              child: Icon(
                                has ? Icons.arrow_upward_rounded : Icons.mic,
                                size: 20,
                                color: has ? C.accentInk : C.text,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A picture in a message, fetched from the PC the first time it is shown.
class _Picture extends StatelessWidget {
  const _Picture({required this.ref, this.fill = false, this.whole = false});
  final String ref;
  final bool fill; // cover a square, as a thumbnail
  final bool whole; // all of it, as large as it goes

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: fill ? null : 160,
      height: fill ? null : 110,
      color: C.raised,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: C.text3),
    );
    if (ref.isEmpty) return box;
    return FutureBuilder<dynamic>(
      future: _pictures.putIfAbsent(ref, () => bridge.kept('img:$ref')),
      builder: (context, snap) {
        final b64 = snap.data is String ? snap.data as String : '';
        if (b64.isEmpty) {
          _pictures.remove(ref); // ask again next time
          return box;
        }
        final bytes = _bytes.putIfAbsent(ref, () => base64Decode(b64));
        final image = Image.memory(
          bytes,
          fit: whole ? BoxFit.contain : BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => box,
        );
        if (fill || whole) return image;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: image,
        );
      },
    );
  }
}

// Asked for once per picture: a row of thumbnails rebuilds often.
final Map<String, Future<dynamic>> _pictures = {};
final Map<String, Uint8List> _bytes = {};

/// What Claude Code can be told to do, as the app offers it.
const kCommands = [
  ['/compact', 'Summarise the conversation to free up room'],
  ['/clear', 'Start over in this session'],
  ['/model', 'Change the model'],
  ['/effort', 'How much thinking goes into each answer'],
  ['/usage', 'How much of your plan is left'],
  ['/context', 'What is using the context window'],
  ['/review', 'Review the current changes'],
];

/// One plan limit: its name, how much is used, a bar, and when it resets.
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.limit, this.now});
  final Map limit;
  final DateTime? now;

  /// "Resets in 4 hr 25 min" within a day, else "Resets Sun 10:30 PM".
  static String resets(int? at, DateTime now) {
    if (at == null) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(at);
    final left = t.difference(now);
    if (left.isNegative) return 'Resets soon';
    if (left.inHours < 24) {
      final h = left.inHours;
      final m = left.inMinutes % 60;
      return h > 0 ? 'Resets in $h hr $m min' : 'Resets in $m min';
    }
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    return 'Resets ${days[t.weekday - 1]} $h12:$mm ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final pct = ((limit['pct'] as num?) ?? 0).clamp(0, 100).toDouble();
    final when = resets((limit['resetsAt'] as num?)?.toInt(), now ?? DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  limit['label'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${pct.round()}% used',
                style: const TextStyle(color: C.text2, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 8,
              backgroundColor: C.line,
              color: pct >= 90 ? Colors.redAccent : pct >= 75 ? Colors.orangeAccent : C.accent,
            ),
          ),
          if (when.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(when, style: const TextStyle(color: C.text3, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// The matching commands, just above the box, newest Claude-app style: type
/// "/cle" and only Clear is left.
class _CommandList extends StatelessWidget {
  const _CommandList({required this.matches, required this.onPick});
  final List<List<String>> matches;
  final void Function(List<String>) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      decoration: BoxDecoration(
        color: C.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in matches)
            InkWell(
              onTap: () => onPick(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      c.length > 2 && c[2] == 'saved'
                          ? Icons.bookmark_outline
                          : Icons.bolt_outlined,
                      size: 16,
                      color: C.text3,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      c[0],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: C.text,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c[1],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12, color: C.text3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The way back through a long conversation.
class _Earlier extends StatelessWidget {
  const _Earlier({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Center(
      child: busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: C.text3),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.expand_less, size: 18),
              label: const Text('Earlier messages'),
              style: OutlinedButton.styleFrom(
                foregroundColor: C.text2,
                side: const BorderSide(color: C.line),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
    ),
  );
}

/// The answer as it is being written, before the conversation has it.
/// A message still waiting for the PC: it looks like one you sent, greyed,
/// with what it is waiting for underneath.
class _WaitingBubble extends StatelessWidget {
  const _WaitingBubble({
    super.key,
    required this.waiting,
    required this.onDrop,
  });
  final Waiting waiting;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final failed = waiting.why.isNotEmpty && !waiting.sending;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (waiting.pictures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  shrinkWrap: true,
                  itemCount: waiting.pictures.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, i) => Opacity(
                    opacity: 0.55,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        waiting.pictures[waiting.pictures.length - 1 - i].bytes,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (waiting.text.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: C.bubble.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: Text(
                  waiting.text,
                  style: const TextStyle(
                    fontSize: 15.5,
                    height: 1.4,
                    color: C.text2,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (waiting.sending)
                  const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: C.text3,
                    ),
                  )
                else
                  Icon(
                    failed ? Icons.error_outline : Icons.schedule,
                    size: 13,
                    color: failed ? C.danger : C.text3,
                  ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    waiting.sending
                        ? 'Sending…'
                        : failed
                        ? waiting.why
                        : waiting.afterTurn
                        ? 'Waiting for this answer to finish'
                        : 'Waiting — it will send itself',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: failed ? C.danger : C.text3,
                    ),
                  ),
                ),
                if (!waiting.sending)
                  TextButton(
                    onPressed: onDrop,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 24),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: C.text3,
                      textStyle: const TextStyle(fontSize: 11.5),
                    ),
                    child: const Text('Remove'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Above the box while the PC cannot be reached.
class _OfflineLine extends StatelessWidget {
  const _OfflineLine({
    required this.link,
    required this.name,
    required this.waiting,
  });
  final Link link;
  final String name;
  final int waiting;

  @override
  Widget build(BuildContext context) {
    final trying = link == Link.connecting;
    final words = link == Link.denied
        ? 'This phone is no longer paired with $name.'
        : trying
        ? 'Reaching $name…'
        : waiting > 0
        ? '$name is not answering. ${waiting == 1 ? '1 message waits' : '$waiting messages wait'} and will send themselves.'
        : '$name is not answering. What you write is kept and sent when it is back.';
    return Container(
      width: double.infinity,
      color: C.chrome,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: trying
                ? const CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: C.busy,
                  )
                : const Icon(Icons.cloud_off, size: 13, color: C.text3),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              words,
              style: const TextStyle(fontSize: 12, color: C.text2),
            ),
          ),
        ],
      ),
    );
  }
}

/// The answer being written right now.
///
/// It is drawn as markdown while it arrives, not as the raw text: a heading
/// looks like a heading from the first word, and nothing re-lays-out when the
/// finished message takes its place. Half-written markup is healed for as long
/// as it is half-written - an open code fence is closed, a lone `**` is
/// balanced - so the page never flashes stray asterisks or swallows a
/// paragraph into a code block that has not been closed yet.
///
/// Markdown is parsed again at most ten times a second however fast the words
/// arrive, which is what keeps the list from juddering under a long answer.
class _Writing extends StatefulWidget {
  const _Writing({required this.text});
  final String text;

  @override
  State<_Writing> createState() => _WritingState();
}

class _WritingState extends State<_Writing> {
  static const _gap = Duration(milliseconds: 100);
  late String _shown = widget.text;
  DateTime _at = DateTime.now();
  Timer? _soon;

  @override
  void didUpdateWidget(_Writing old) {
    super.didUpdateWidget(old);
    if (widget.text == _shown) return;
    final since = DateTime.now().difference(_at);
    if (since >= _gap) {
      _soon?.cancel();
      _soon = null;
      setState(() {
        _shown = widget.text;
        _at = DateTime.now();
      });
      return;
    }
    // Too soon after the last one: show what has arrived when the gap is up.
    _soon ??= Timer(_gap - since, () {
      _soon = null;
      if (!mounted) return;
      setState(() {
        _shown = widget.text;
        _at = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _soon?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The same markdown a finished answer gets, so nothing shifts when it
        // lands; the block at the end is the caret.
        MarkdownBody(
          data: '${healMarkdown(_shown)}█',
          selectable: false,
          softLineBreak: true,
          styleSheet: _ClaudeText._sheet,
        ),
      ],
    ),
  );
}

/// Markdown that is only half-written, made safe to render.
///
/// While an answer streams in, the text can stop anywhere: inside a code fence,
/// between the stars of a bold run, after one backtick. Rendering that as it
/// stands turns the rest of the answer into a code block, or shows the stars.
/// This closes what is open, and nothing else: it never changes text that is
/// already whole.
String healMarkdown(String partial) {
  var out = partial;
  // An open code fence swallows everything after it: close it.
  final fences = RegExp(r'^\s*```', multiLine: true).allMatches(out).length;
  if (fences.isOdd) out += '\n```';
  // The rest only matters outside code, so count on the text with code removed.
  final bare = out
      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
      .replaceAll(RegExp(r'`[^`\n]*`'), '');
  if ('`'.allMatches(bare).length.isOdd) out += '`';
  if (RegExp(r'\*\*').allMatches(bare).length.isOdd) out += '**';
  // A link whose address has not arrived yet shows as its text alone.
  out = out.replaceFirstMapped(
    RegExp(r'\[([^\]\n]*)\]\([^)\n]*$'),
    (m) => m[1] ?? '',
  );
  // ...and one whose brackets are still open shows as what is inside them.
  out = out.replaceFirstMapped(RegExp(r'\[([^\]\n]*)$'), (m) => m[1] ?? '');
  return out;
}

class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: Container(
      width: 7,
      height: 15,
      margin: const EdgeInsets.only(left: 3),
      decoration: BoxDecoration(
        color: C.accent,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}
