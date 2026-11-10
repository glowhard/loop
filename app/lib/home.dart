import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat.dart' show UsageBar;
import 'main.dart';
import 'mic.dart';
import 'sessions.dart';
import 'theme.dart';
import 'voice.dart';

/// Home: what the app opens to. Two front doors per project - the CEO for
/// business, the CTO for tech - each a spoken goal away, and under them only
/// what needs you: a plan to OK, a question to answer, a report to hear.
/// When nothing does, the screen is calm and nearly empty.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _projects = [];
  String _dir = '';
  Timer? _poll;
  Timer? _usageAgain;
  bool _loaded = false;
  int? _weekly; // % of the weekly limit, for the ring
  final _cards = <String, Map<String, dynamic>>{}; // card id -> {state, line, day}
  final _since = <String, DateTime>{}; // lead id -> when it was first seen working

  @override
  void initState() {
    super.initState();
    _restore();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _usage();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _usageAgain?.cancel();
    Voice.I.stopSpeaking();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString('homeProject');
      if (saved != null && saved.isNotEmpty) _dir = saved;
      final today = _today();
      for (final s in p.getStringList('homeCards') ?? const <String>[]) {
        final parts = s.split('\u0001');
        if (parts.length == 4 && parts[3] == today) _cards[parts[0]] = {'state': parts[1], 'line': parts[2], 'day': parts[3]};
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  Future<void> _mark(String id, String state, String line) async {
    setState(() => _cards[id] = {'state': state, 'line': line, 'day': _today()});
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('homeCards', [
        for (final e in _cards.entries) [e.key, e.value['state'], e.value['line'], e.value['day']].join('\u0001'),
      ]);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    final r = await bridge.act('home');
    if (!mounted || !r.ok || r.data is! Map) return;
    final list = ((r.data['projects'] ?? const []) as List).cast<Map>().map((m) => m.cast<String, dynamic>()).toList()
      ..sort((a, b) => ((b['mtime'] ?? 0) as num).compareTo((a['mtime'] ?? 0) as num));
    for (final p in list) {
      for (final l in ((p['leads'] ?? const []) as List).cast<Map>()) {
        final id = l['id'] as String;
        if (l['lamp'] == 'busy') {
          _since.putIfAbsent(id, DateTime.now);
        } else {
          _since.remove(id);
        }
      }
    }
    setState(() {
      _projects = list;
      _loaded = true;
      if (_dir.isEmpty || !list.any((p) => p['dir'] == _dir)) _dir = list.isEmpty ? '' : list.first['dir'] as String;
    });
  }

  Future<void> _usage() async {
    if (!mounted) return;
    final dir = _dir.isNotEmpty ? _dir : (_projects.isNotEmpty ? _projects.first['dir'] as String : '');
    if (dir.isEmpty) {
      _usageAgain = Timer(const Duration(seconds: 6), _usage);
      return;
    }
    final r = await bridge.act('info', {'dir': dir, 'what': 'usage'}, const Duration(seconds: 160));
    if (!mounted || !r.ok || r.data is! Map) return;
    final limits = ((r.data['limits'] ?? const []) as List).cast<Map>();
    final week = limits.firstWhere((l) => l['label'] == 'Weekly', orElse: () => const {});
    setState(() => _weekly = (week['pct'] as num?)?.toInt());
    // The ring is a glance, not a meter: once every quarter of an hour is plenty.
    _usageAgain = Timer(const Duration(minutes: 15), _usage);
  }

  Map<String, dynamic>? get _project => _projects.where((p) => p['dir'] == _dir).firstOrNull ?? _projects.firstOrNull;

  // ---- doing things ----

  Future<void> _goal(Map<String, dynamic> project, Map<String, dynamic> lead) async {
    final who = lead['key'] == 'ceo' ? 'CEO' : 'CTO';
    final said = await askByVoice(context, title: 'Goal for $who · ${project['title']}');
    if (!mounted || said == null) return;
    if (said.typeInstead) return _openChat(project, lead, focus: true);
    final r = await bridge.act('goal', {'dir': project['dir'], 'sessionId': lead['id'], 'text': said.text});
    if (!mounted) return;
    say(context, r.ok ? 'Given to $who.' : r.text, bad: !r.ok);
    _refresh();
  }

  Future<void> _change(Map<String, dynamic> project, Map<String, dynamic> lead, String cardId, String title, String prefix) async {
    final said = await askByVoice(context, title: title);
    if (!mounted || said == null) return;
    if (said.typeInstead) return _openChat(project, lead, focus: true);
    final r = await bridge.sendTo(project['dir'] as String, lead['id'] as String, '$prefix${said.text}');
    if (!mounted) return;
    if (!r.ok) return say(context, r.text, bad: true);
    _mark(cardId, 'answered', 'Change sent · ${said.text}');
  }

  void _openChat(Map<String, dynamic> project, Map<String, dynamic> lead, {bool focus = false}) {
    openSession(context, project['dir'] as String, lead['id'] as String, () {}, title: lead['title'] as String?);
  }

  // ---- what is on screen ----

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bridge,
      builder: (context, _) {
        final project = _project;
        final feed = _feed();
        final earlier = _cards.entries.where((e) => e.value['state'] != 'live').toList();
        return Column(
          children: [
            _TopBar(
              project: project?['title'] as String? ?? (_loaded ? 'No team yet' : ''),
              weekly: _weekly,
              onProject: _pickProject,
              onUsage: _showUsage,
            ),
            Expanded(
              child: RefreshIndicator(
                color: C.accent,
                backgroundColor: C.panel,
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (project != null) _doors(project),
                    if (project == null && _loaded)
                      const _Empty(
                        icon: Icons.groups_outlined,
                        title: 'No team yet',
                        line: 'Set up a team with a CEO and a CTO in Loop on the PC.',
                      ),
                    const SizedBox(height: 24),
                    if (feed.any((c) => c.needsYou)) _FeedHead(title: 'Needs you', count: feed.where((c) => c.needsYou).length, colour: C.busy),
                    for (final c in feed.where((c) => c.needsYou)) Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
                    if (feed.any((c) => !c.needsYou)) ...[
                      if (feed.any((c) => c.needsYou)) const SizedBox(height: 8),
                      _FeedHead(title: 'Done', count: feed.where((c) => !c.needsYou).length, colour: C.idle),
                    ],
                    for (final c in feed.where((c) => !c.needsYou)) Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
                    if (feed.isEmpty && _loaded && project != null)
                      const _Empty(icon: Icons.check_circle_outline, title: 'Nothing needs you', line: 'Speak a goal to the CEO or CTO'),
                    if (earlier.isNotEmpty) _Earlier(lines: [for (final e in earlier.reversed) e.value['line'] as String]),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _doors(Map<String, dynamic> project) {
    final leads = ((project['leads'] ?? const []) as List).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    Map<String, dynamic>? lead(String key) => leads.where((l) => l['key'] == key).firstOrNull;
    Widget door(String key) {
      final l = lead(key);
      if (l == null) return _Door.missing(key);
      return _Door(
        lead: l,
        since: _since[l['id']],
        onGoal: () => _goal(project, l),
        onChat: () => _openChat(project, l),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: door('ceo')),
        const SizedBox(width: 12),
        Expanded(child: door('cto')),
      ],
    );
  }

  /// Need from you first, then plans, then reports; newest first in each.
  List<_Card> _feed() {
    final needs = <_Card>[];
    for (final r in bridge.running.where((r) => r['ask'] != null)) {
      needs.add(_NeedCard(key: ValueKey('need-${r['id']}-${(r['ask'] as Map)['question']}'), row: r, onSaid: _mark));
    }
    final plans = <_Card>[];
    final dones = <_Card>[];
    for (final p in _projects) {
      for (final l in ((p['leads'] ?? const []) as List).cast<Map>().map((m) => m.cast<String, dynamic>())) {
        final rep = l['report'];
        if (rep is! Map) continue;
        final report = rep.cast<String, dynamic>();
        final id = '${l['id']}@${report['at']}';
        if (_cards.containsKey(id)) continue;
        if (report['kind'] == 'plan') {
          plans.add(_PlanCard(key: ValueKey(id), id: id, project: p, lead: l, report: report, home: this));
        } else {
          dones.add(_DoneCard(key: ValueKey(id), id: id, project: p, lead: l, report: report, home: this));
        }
      }
    }
    int newest(_Card a, _Card b) => b.at.compareTo(a.at);
    return [...needs, ...(plans..sort(newest)), ...(dones..sort(newest))];
  }

  Future<void> _pickProject() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: C.idle, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text('${bridge.state['host'] ?? 'This PC'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.text3)),
                ],
              ),
            ),
            for (final p in _projects)
              ListTile(
                minTileHeight: 56,
                title: Text(p['title'] as String? ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: Text(_needsLine(p), style: TextStyle(fontSize: 12, color: _needs(p) > 0 ? C.busy : C.text3)),
                trailing: p['dir'] == _dir ? const Icon(Icons.check, color: C.accent) : null,
                onTap: () => Navigator.pop(sheet, p['dir'] as String),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _dir = picked);
    try {
      (await SharedPreferences.getInstance()).setString('homeProject', picked);
    } catch (_) {}
  }

  int _needs(Map<String, dynamic> p) => bridge.running.where((r) => r['ask'] != null && r['dir'] == p['dir']).length;
  String _needsLine(Map<String, dynamic> p) => _needs(p) > 0 ? '${_needs(p)} need you' : 'All quiet';

  Future<void> _showUsage() async {
    final dir = _dir;
    if (dir.isEmpty) return;
    say(context, 'Asking for usage…');
    final r = await bridge.act('info', {'dir': dir, 'what': 'usage'}, const Duration(seconds: 160));
    if (!mounted) return;
    if (!r.ok || r.data is! Map) return say(context, r.text, bad: true);
    final limits = ((r.data['limits'] ?? const []) as List).cast<Map>();
    final week = limits.firstWhere((l) => l['label'] == 'Weekly', orElse: () => const {});
    setState(() => _weekly = (week['pct'] as num?)?.toInt() ?? _weekly);
    showLoopSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Usage', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              for (final l in limits) UsageBar(limit: l),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- top bar ----------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.project, required this.weekly, required this.onProject, required this.onUsage});
  final String project;
  final int? weekly;
  final VoidCallback onProject;
  final VoidCallback onUsage;

  @override
  Widget build(BuildContext context) {
    final w = weekly;
    final ring = w == null ? C.text3 : w >= 95 ? C.danger : w >= 80 ? C.busy : C.text2; // shown only once read
    return Container(
      height: 56,
      color: C.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (project.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onProject,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: C.raised, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(project, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.text)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.unfold_more, size: 16, color: C.text3),
                  ],
                ),
              ),
            ),
          const Spacer(),
          if (w != null)
          Tooltip(
            message: 'Usage',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onUsage,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(value: w / 100, strokeWidth: 3, backgroundColor: C.raised, color: ring),
                    ),
                    Text('$w', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text, fontFeatures: [FontFeature.tabularFigures()])),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- the two doors ----------

class _Door extends StatelessWidget {
  const _Door({required this.lead, required this.since, required this.onGoal, required this.onChat}) : missingKey = null;
  const _Door.missing(String key) : lead = const {}, since = null, onGoal = null, onChat = null, missingKey = key;
  final Map<String, dynamic> lead;
  final DateTime? since;
  final VoidCallback? onGoal;
  final VoidCallback? onChat;
  final String? missingKey;

  @override
  Widget build(BuildContext context) {
    final key = missingKey ?? lead['key'] as String? ?? 'ceo';
    final name = key == 'ceo' ? 'CEO' : 'CTO';
    final sub = key == 'ceo' ? 'Business' : 'Tech';
    final lamp = lead['lamp'] as String? ?? '';
    final busy = lamp == 'busy';
    final asking = lead['asking'] == true;
    final mins = since == null ? 0 : DateTime.now().difference(since!).inMinutes;
    final state = missingKey != null
        ? 'No $name on this team'
        : asking
        ? 'Waiting for you'
        : busy
        ? 'Working${mins > 0 ? ' · ${mins}m' : ''}'
        : lamp == 'idle'
        ? 'Ready'
        : 'Asleep · wakes when you give a goal';
    final lampColour = asking ? C.busy : busy ? C.busy : lamp == 'idle' ? C.idle : C.off;
    return GestureDetector(
      onTap: onGoal,
      onLongPress: onChat,
      child: Container(
        height: 176, // room for a two-line state above the mic
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: lampColour, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: C.text)),
                const Spacer(),
                if (onChat != null)
                  SizedBox(
                    width: 40,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'Open chat',
                      onPressed: onChat,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18, color: C.text3),
                    ),
                  ),
              ],
            ),
            Text(sub, style: const TextStyle(fontSize: 12, color: C.text3)),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                state,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: asking ? C.busy : (missingKey != null || lamp.isEmpty ? C.text3 : C.text2),
                  fontWeight: asking ? FontWeight.w600 : FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (missingKey == null)
              SizedBox(
                height: 44,
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: busy ? C.raised2 : C.accent,
                    foregroundColor: busy ? C.text : C.accentInk,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: onGoal,
                  icon: const Icon(Icons.mic, size: 20),
                  label: Text(busy ? 'Add to goal' : 'Give a goal', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------- the cards ----------

abstract class _Card extends StatefulWidget {
  const _Card({super.key});
  int get at;
  bool get needsYou => false;
}

/// The shell every card shares: a stripe in its colour, a header that opens
/// the lead's chat, and the body.
class _Shell extends StatelessWidget {
  const _Shell({required this.colour, required this.tag, required this.who, required this.when, required this.child, this.onHeader, this.unread = false});
  final Color colour;
  final String tag;
  final String who;
  final String when;
  final Widget child;
  final VoidCallback? onHeader;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: colour),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: onHeader,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            if (unread) ...[
                              Container(width: 8, height: 8, decoration: BoxDecoration(color: colour, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                            ],
                            Text(tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: colour)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(who, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.text3))),
                            Text(when, style: const TextStyle(fontSize: 12, color: C.text3, fontFeatures: [FontFeature.tabularFigures()])),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _ago(int at) {
  if (at <= 0) return '';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// A goal as a title: first letter up, the stored words untouched.
String _title(String g) => g.isEmpty ? g : g[0].toUpperCase() + g.substring(1);

String _who(Map project, Map lead) => '${project['title']} · ${lead['key'] == 'ceo' ? 'CEO' : 'CTO'}';

class _Bullets extends StatefulWidget {
  const _Bullets(this.items, {required this.most});
  final List<String> items;
  final int most;

  @override
  State<_Bullets> createState() => _BulletsState();
}

class _BulletsState extends State<_Bullets> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    // A bullet longer than about two lines on a phone is clamped; more than
    // the card holds are folded. Either way, Show all opens them in place.
    final more = items.length > widget.most || items.any((b) => b.length > 90);
    final shown = _all ? items : items.take(widget.most).toList();
    return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < shown.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: C.text3, shape: BoxShape.circle)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  shown[i],
                  maxLines: _all ? null : 2,
                  overflow: _all ? null : TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.45, color: C.text),
                ),
              ),
            ],
          ),
        ),
      if (more && !_all)
        GestureDetector(
          onTap: () => setState(() => _all = true),
          child: const Padding(
            padding: EdgeInsets.only(top: 2, bottom: 4),
            child: Text('Show all', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text2)),
          ),
        ),
    ],
  );
  }
}

Widget _two(Widget left, Widget right) => Row(
  children: [
    Expanded(child: left),
    const SizedBox(width: 8),
    Expanded(child: right),
  ],
);

Widget _secondary(String label, VoidCallback onTap, {bool mic = false}) => SizedBox(
  height: 48,
  child: OutlinedButton(
    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    onPressed: onTap,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (mic) ...[const Icon(Icons.mic, size: 18), const SizedBox(width: 6)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
      ],
    ),
  ),
);

Widget _primary(String label, VoidCallback? onTap) => SizedBox(
  height: 48,
  child: FilledButton(
    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    onPressed: onTap,
    child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
  ),
);

// (a) Plan OK?

class _PlanCard extends _Card {
  const _PlanCard({super.key, required this.id, required this.project, required this.lead, required this.report, required this.home});
  final String id;
  final Map<String, dynamic> project;
  final Map<String, dynamic> lead;
  final Map<String, dynamic> report;
  final _HomePageState home;

  @override
  int get at => (report['at'] as num?)?.toInt() ?? 0;
  @override
  bool get needsYou => true;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final goal = (r['goal'] as String? ?? '').isNotEmpty ? r['goal'] as String : r['lead'] as String? ?? '';
    final bullets = ((r['bullets'] ?? const []) as List).cast<String>();
    return _Shell(
      colour: C.accent,
      tag: 'PLAN',
      who: _who(widget.project, widget.lead),
      when: _ago(widget.at),
      onHeader: () => widget.home._openChat(widget.project, widget.lead),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title(goal), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.text)),
          const SizedBox(height: 10),
          _Bullets(bullets, most: 3),
          const SizedBox(height: 8),
          _two(
            _secondary('Change', () => widget.home._change(widget.project, widget.lead, widget.id, 'Change the plan', 'Change the plan: '), mic: true),
            _primary('OK, go ahead', () async {
              HapticFeedback.lightImpact();
              // A lead already at work needs no "go ahead": saying it would cost a turn.
              if (widget.lead['lamp'] != 'busy') {
                await bridge.sendTo(widget.project['dir'] as String, widget.lead['id'] as String, 'OK, go ahead.');
              }
              widget.home._mark(widget.id, 'answered', "Plan OK'd · $goal");
            }),
          ),
        ],
      ),
    );
  }
}

// (b) Need from you: a question, or one of the five things the gate holds back.

class _NeedCard extends _Card {
  const _NeedCard({super.key, required this.row, required this.onSaid});
  final Map<String, dynamic> row;
  final Future<void> Function(String id, String state, String line) onSaid;

  @override
  int get at => 1 << 50; // always on top
  @override
  bool get needsYou => true;

  @override
  State<_NeedCard> createState() => _NeedCardState();
}

class _NeedCardState extends State<_NeedCard> {
  String? _said;
  final _chosen = <String>{};

  static final _risky = RegExp(r'\b(live|deploy|production|pay|spend|customer|delete|key|access|publish|merge)', caseSensitive: false);

  Future<void> _send(String keys, String words, String shown) async {
    final r = widget.row;
    final ask = (r['ask'] as Map).cast<String, dynamic>();
    // A tap on a question that has moved on must never reach the session.
    final now = bridge.running.where((x) => x['id'] == r['id']).firstOrNull;
    final still = now != null && now['ask'] is Map && (now['ask'] as Map)['question'] == ask['question'];
    if (!still) {
      setState(() => _said = '');
      say(context, 'That question already moved on');
      return;
    }
    HapticFeedback.selectionClick();
    bridge.answerFor(r['id'] as String, keys, words, direct: ask['direct'] == true);
    setState(() => _said = shown);
    widget.onSaid('${r['id']}@${ask['question']}', 'answered', 'You said: $shown');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final ask = (r['ask'] as Map).cast<String, dynamic>();
    final options = ((ask['options'] ?? const []) as List).cast<Map>();
    final gate = ask['gate'] == true;
    final multi = ask['multi'] == true;
    final context0 = ((ask['context'] ?? const []) is List ? (ask['context'] as List).join(' · ') : '${ask['context']}').trim();
    final question = ask['question'] as String? ?? '';
    final title = '${r['project'] ?? ''} · ${r['title'] ?? ''}';
    if (_said != null) {
      return _Shell(
        colour: C.busy,
        tag: 'NEEDS YOU',
        who: title,
        when: '',
        child: Row(
          children: [
            Icon(_said!.isEmpty ? Icons.history : Icons.check, size: 16, color: _said!.isEmpty ? C.text3 : C.idle),
            const SizedBox(width: 6),
            Expanded(child: Text(_said!.isEmpty ? 'No longer needed' : 'You said: $_said', style: const TextStyle(fontSize: 13, color: C.text2))),
          ],
        ),
      );
    }
    final buttons = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      final o = options[i];
      final key = o['key'] as String? ?? '${i + 1}';
      var label = (o['label'] as String? ?? '').trim();
      final recommended = label.contains('(Recommended)');
      label = label.replaceAll('(Recommended)', '').trim();
      final primary = gate ? i == 0 : (i == 0 && recommended);
      final hold = (gate && i == 0) || (!gate && primary && _risky.hasMatch('$question $label'));
      final numbered = '${i + 1}  $label';
      if (multi) {
        final on = _chosen.contains(key);
        buttons.add(
          Material(
            color: on ? C.raised2 : C.raised,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => on ? _chosen.remove(key) : _chosen.add(key)),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Expanded(child: Text(numbered, style: const TextStyle(fontSize: 15, color: C.text))),
                    Icon(on ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: on ? C.accent : C.text3),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      } else if (hold) {
        buttons.add(HoldButton(label: label, primary: true, onHeld: () => _send(key, '', label)));
      } else {
        buttons.add(primary ? _primary(numbered, () => _send(key, '', label)) : _secondary(numbered, () => _send(key, '', label)));
      }
      buttons.add(const SizedBox(height: 8));
    }
    if (multi) {
      buttons.add(_primary('Done', _chosen.isEmpty ? null : () => _send((_chosen.toList()..sort()).join(','), '', '${_chosen.length} picked')));
      buttons.add(const SizedBox(height: 8));
    }
    buttons.add(
      _secondary('Say something else', () async {
        final said = await askByVoice(context, title: (ask['header'] as String? ?? '').isNotEmpty ? ask['header'] as String : 'Your answer');
        if (said == null || said.typeInstead || said.text.isEmpty || !mounted) return;
        _send('', gate ? 'No, and ${said.text}' : said.text, said.text);
      }, mic: true),
    );
    return _Shell(
      colour: C.busy,
      tag: 'NEEDS YOU',
      who: title,
      when: '',
      onHeader: () => openSession(context, r['dir'] as String, r['id'] as String, () {}, title: r['title'] as String?),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(question, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.text, height: 1.35)),
          if (context0.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(context0, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: C.text2)),
          ],
          const SizedBox(height: 12),
          ...buttons,
        ],
      ),
    );
  }
}

// (c) Done: the report, to hear rather than read, and what it cost.

class _DoneCard extends _Card {
  const _DoneCard({super.key, required this.id, required this.project, required this.lead, required this.report, required this.home});
  final String id;
  final Map<String, dynamic> project;
  final Map<String, dynamic> lead;
  final Map<String, dynamic> report;
  final _HomePageState home;

  @override
  int get at => (report['at'] as num?)?.toInt() ?? 0;

  @override
  State<_DoneCard> createState() => _DoneCardState();
}

class _DoneCardState extends State<_DoneCard> {
  Map<String, dynamic>? _tokens;
  bool _open = false;
  bool _unread = true;
  bool _going = false;
  Timer? _seen;

  static final _ships = RegExp(r'\b(live|deploy|ship|push|release|production|publish)', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _seen = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _unread = false);
    });
    _cost();
  }

  @override
  void dispose() {
    _seen?.cancel();
    super.dispose();
  }

  Future<void> _cost() async {
    final since = (widget.report['goalAt'] as num?)?.toInt() ?? 0;
    if (since <= 0) return;
    final r = await bridge.act('tokens', {'dir': widget.project['dir'], 'since': since});
    if (mounted && r.ok && r.data is Map) setState(() => _tokens = (r.data as Map).cast<String, dynamic>());
  }

  static String _n(num v) => v < 1000 ? '${v.round()}' : v < 1000000 ? '${(v / 1000).toStringAsFixed(1)}k' : '${(v / 1000000).toStringAsFixed(1)}M';

  String get _spoken {
    final r = widget.report;
    final bullets = ((r['bullets'] ?? const []) as List).cast<String>();
    final need = r['need'] as String? ?? '';
    return [r['goal'] ?? r['lead'] ?? '', ...bullets, if (need.isNotEmpty) 'Need from you: $need'].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final goal = (r['goal'] as String? ?? '').isNotEmpty ? r['goal'] as String : r['lead'] as String? ?? '';
    final bullets = ((r['bullets'] ?? const []) as List).cast<String>();
    final need = r['need'] as String? ?? '';
    final ships = _ships.hasMatch(need);
    final words = _spoken.split(RegExp(r'\s+')).length;
    final secs = (words / 2.6).round();
    final length = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final mins = (((r['at'] as num?) ?? 0) - ((r['goalAt'] as num?) ?? 0)) ~/ 60000;
    final t = _tokens;
    return _Shell(
      colour: C.idle,
      tag: 'DONE',
      unread: _unread,
      who: _who(widget.project, widget.lead),
      when: _ago(widget.at),
      onHeader: () => widget.home._openChat(widget.project, widget.lead),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title(goal), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.text)),
          const SizedBox(height: 10),
          ValueListenableBuilder<String?>(
            valueListenable: Voice.I.speaking,
            builder: (context, playing, _) {
              final on = playing == widget.id;
              return InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => on ? Voice.I.stopSpeaking() : Voice.I.speak(widget.id, _spoken),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(color: C.raised, shape: BoxShape.circle),
                        child: Icon(on ? Icons.pause : Icons.play_arrow, size: 24, color: C.accent),
                      ),
                      const SizedBox(width: 12),
                      Text(on ? 'Playing' : 'Listen', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: C.text)),
                      Text(' · $length', style: const TextStyle(fontSize: 13, color: C.text3, fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _Bullets(bullets, most: 5),
          if (need.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.arrow_forward, size: 16, color: C.busy)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(need, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.busy))),
                ],
              ),
            ),
          if (t != null && ((t['calls'] as num?) ?? 0) > 0) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _open = !_open),
              child: Text(
                _open
                    ? 'Fresh ${_n(t['fresh'] as num)} · Cached ${_n(t['cached'] as num)} · ${t['calls']} calls'
                    : '${_n(t['fresh'] as num)} tokens${mins > 0 ? ' · $mins min' : ''} · ${t['sessions']} session${t['sessions'] == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: C.text3, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_going)
            const Text('Going live…', style: TextStyle(fontSize: 13, color: C.text2))
          else
            _two(
              _secondary('Change', () => widget.home._change(widget.project, widget.lead, widget.id, 'Change · $goal', 'Change: '), mic: true),
              ships
                  ? HoldButton(
                      label: 'Go live',
                      onHeld: () async {
                        setState(() => _going = true);
                        await bridge.sendTo(widget.project['dir'] as String, widget.lead['id'] as String, 'Go live.');
                        widget.home._mark(widget.id, 'answered', 'Going live · $goal');
                      },
                    )
                  : _secondary('Looks good', () {
                      Voice.I.stopSpeaking();
                      widget.home._mark(widget.id, 'archived', '✓ $goal');
                    }),
            ),
        ],
      ),
    );
  }
}

// ---------- the rest ----------

class _FeedHead extends StatelessWidget {
  const _FeedHead({required this.title, required this.count, required this.colour});
  final String title;
  final int count;
  final Color colour;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    child: Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text2)),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: colour.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colour)),
          ),
        ],
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.line});
  final IconData icon;
  final String title;
  final String line;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 48),
    child: Column(
      children: [
        Icon(icon, size: 28, color: C.text3),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.text2)),
        const SizedBox(height: 4),
        Text(line, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: C.text3)),
      ],
    ),
  );
}

class _Earlier extends StatefulWidget {
  const _Earlier({required this.lines});
  final List<String> lines;

  @override
  State<_Earlier> createState() => _EarlierState();
}

class _EarlierState extends State<_Earlier> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InkWell(
        onTap: () => setState(() => _open = !_open),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              Text('Earlier today · ${widget.lines.length}', style: const TextStyle(fontSize: 13, color: C.text3)),
              const SizedBox(width: 4),
              Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: C.text3),
            ],
          ),
        ),
      ),
      if (_open)
        for (final l in widget.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: C.text2)),
          ),
    ],
  );
}
