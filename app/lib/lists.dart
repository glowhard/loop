import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat.dart';
import 'main.dart';
import 'motion.dart';
import 'sessions.dart';
import 'theme.dart';

/// Waiting first, then working, then the most recent.
int _rank(Map<String, dynamic> r) =>
    r['ask'] != null ? 0 : (r['lamp'] == 'busy' ? 1 : 2);

String ago(num ms) {
  if (ms <= 0) return '';
  final s = (DateTime.now().millisecondsSinceEpoch - ms) / 1000;
  if (s < 60) return 'now';
  if (s < 3600) return '${(s / 60).floor()}m';
  if (s < 86400) return '${(s / 3600).floor()}h';
  return '${(s / 86400).floor()}d';
}

/// Every conversation, newest and busiest first, as flat rows like the Claude app.
class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  String _q = '';

  // Used as a const page, so it listens for itself.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: bridge,
    builder: (context, _) => _page(context),
  );

  Widget _page(BuildContext context) {
    final running = bridge.running;
    final recent = ((bridge.state['recent'] ?? const []) as List)
        .cast<Map<String, dynamic>>();
    final q = _q.toLowerCase();
    final rows =
        [...running, ...recent]
            .where(bridge.inScope)
            .where(
              (r) =>
                  q.isEmpty ||
                  '${r['title']} ${r['project']}'.toLowerCase().contains(q),
            )
            .toList()
          ..sort((a, b) {
            final r = _rank(a).compareTo(_rank(b));
            return r != 0
                ? r
                : ((b['mtime'] ?? 0) as num).compareTo(
                    (a['mtime'] ?? 0) as num,
                  );
          });
    if (bridge.state.isEmpty) return const Skeleton(lines: 8);
    return RefreshIndicator(
      color: C.accent,
      backgroundColor: C.panel,
      onRefresh: () => bridge.act('scan'),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: rows.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: SizedBox(
                height: 44,
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    hintText: 'Search chats',
                    prefixIcon: const Icon(
                      Icons.search,
                      color: C.text3,
                      size: 20,
                    ),
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: C.panel,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: C.lineStrong),
                    ),
                  ),
                ),
              ),
            );
          }
          return ChatRow(row: rows[i - 1]);
        },
      ),
    );
  }
}

class ChatRow extends StatelessWidget {
  const ChatRow({super.key, required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final lamp = row['lamp'] as String? ?? '';
    final ask = row['ask'] as Map?;
    final busy = lamp == 'busy';
    final project = row['project'] as String? ?? '';
    final server = (row['server'] as String? ?? '').isNotEmpty;
    Widget preview;
    if (ask != null) {
      preview = Text(
        'Waiting for you — ${ask['question'] ?? 'a question'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13,
          color: C.accent,
          fontWeight: FontWeight.w500,
        ),
      );
    } else if (busy) {
      final s = (row['status'] as String? ?? '').isEmpty
          ? 'Working…'
          : row['status'] as String;
      preview = Shimmer(
        base: C.busy,
        glow: const Color(0xFFFFE2A8),
        child: Text(
          s,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Colors.white),
        ),
      );
    } else {
      preview = Text(
        (row['last'] as String? ?? '').isEmpty
            ? project
            : row['last'] as String,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: C.text3),
      );
    }
    return InkWell(
      onTap: () => openSession(
        context,
        row['dir'] as String,
        row['id'] as String,
        () {},
        title: row['title'] as String?,
      ),
      onLongPress: () {
        HapticFeedback.selectionClick();
        sessionSheet(context, row['dir'] as String, row['id'] as String, () {});
      },
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: C.raised,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      project.isEmpty
                          ? '?'
                          : project.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: C.text2,
                      ),
                    ),
                  ),
                  if (lamp.isNotEmpty)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: ask != null ? C.accent : C.lamp(lamp),
                          shape: BoxShape.circle,
                          border: Border.all(color: C.chrome, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          row['title'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Sessions in different projects can share a name: the
                      // project tells them apart.
                      if (project.isNotEmpty || server)
                        Flexible(
                          flex: 0,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              '  · ${project.isEmpty ? 'server' : project}${server && project.isNotEmpty ? ' (server)' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: C.text3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  preview,
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              busy || ask != null ? '' : ago(row['mtime'] as num? ?? 0),
              style: const TextStyle(
                fontSize: 11,
                color: C.text3,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything that needs you, from every machine: questions you can answer right
/// here, and what finished while you were away.
class InboxPage extends StatelessWidget {
  const InboxPage({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: bridge,
    builder: (context, _) => _page(context),
  );

  Widget _page(BuildContext context) {
    final waiting = bridge.running.where((r) => r['ask'] != null).toList();
    final done = bridge.finishedList.reversed.toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const _Head('Waiting for you'),
        if (waiting.isEmpty) const _Quiet('No session is asking anything.'),
        for (final r in waiting) _WaitingCard(row: r),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(child: _Head('Finished')),
            if (done.isNotEmpty)
              TextButton(
                onPressed: bridge.clearFinished,
                child: const Text('Clear', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        if (done.isEmpty)
          const _Quiet(
            'Sessions that finish while you are elsewhere show up here.',
          ),
        for (final r in done)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => openSession(
              context,
              r['dir'] as String,
              r['id'] as String,
              () {},
              title: r['title'] as String?,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 16, color: C.idle),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r['title'] as String? ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${r['project'] ?? ''} · ${ago(r['doneAt'] as num? ?? 0)} ago',
                          style: const TextStyle(fontSize: 12, color: C.text3),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: C.text3),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: C.text2,
      ),
    ),
  );
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(text, style: const TextStyle(fontSize: 13, color: C.text3)),
  );
}

/// A question answered without opening the chat.
class _WaitingCard extends StatefulWidget {
  const _WaitingCard({required this.row});
  final Map<String, dynamic> row;

  @override
  State<_WaitingCard> createState() => _WaitingCardState();
}

class _WaitingCardState extends State<_WaitingCard> {
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final ask = (r['ask'] as Map).cast<String, dynamic>();
    final options = ((ask['options'] ?? const []) as List).cast<Map>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: C.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: C.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => openSession(
                        context,
                        r['dir'] as String,
                        r['id'] as String,
                        () {},
                        title: r['title'] as String?,
                      ),
                      child: Text(
                        '${r['title']} · ${r['project']}',
                        style: const TextStyle(fontSize: 12, color: C.text3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ask['question'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < options.length; i++)
                          SizedBox(
                            height: 36,
                            child:
                                (i == 0
                                ? FilledButton.new
                                : OutlinedButton.new)(
                                  onPressed: _picked != null
                                      ? null
                                      : () {
                                          HapticFeedback.selectionClick();
                                          setState(
                                            () => _picked =
                                                options[i]['key'] as String,
                                          );
                                          bridge.keyFor(
                                            r['id'] as String,
                                            options[i]['key'] as String,
                                          );
                                        },
                                  style: ButtonStyle(
                                    padding: const WidgetStatePropertyAll(
                                      EdgeInsets.symmetric(horizontal: 12),
                                    ),
                                    shape: WidgetStatePropertyAll(
                                      RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 230,
                                        ),
                                        child: Text(
                                          options[i]['label'] as String? ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      if (_picked == options[i]['key'])
                                        const Padding(
                                          padding: EdgeInsets.only(left: 6),
                                          child: Icon(Icons.check, size: 15),
                                        ),
                                    ],
                                  ),
                                ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Above the tab bar whenever anything is working or waiting, anywhere.
class WorkingBar extends StatelessWidget {
  const WorkingBar({super.key, required this.onTap});
  final VoidCallback onTap;

  /// When each session was first seen working, for "· 3m".
  static final _since = <String, DateTime>{};

  @override
  Widget build(BuildContext context) {
    final working = bridge.running
        .where((r) => r['lamp'] == 'busy' && r['ask'] == null)
        .toList();
    final busy = working.length;
    _since.removeWhere((id, _) => !working.any((r) => r['id'] == id));
    for (final r in working) {
      _since.putIfAbsent(r['id'] as String, DateTime.now);
    }
    // A lead first, then whoever has been at it longest.
    working.sort((a, b) {
      final la = RegExp(r'\b(CEO|CTO)\b').hasMatch('${a['title']} ${a['role'] ?? ''}') ? 0 : 1;
      final lb = RegExp(r'\b(CEO|CTO)\b').hasMatch('${b['title']} ${b['role'] ?? ''}') ? 0 : 1;
      return la != lb ? la - lb : _since[a['id']]!.compareTo(_since[b['id']]!);
    });
    final first = working.isEmpty ? null : working.first;
    final mins = first == null ? 0 : DateTime.now().difference(_since[first['id']]!).inMinutes;
    final name = first == null ? '' : busy == 1 ? '${first['title']}' : '${first['title']} + ${busy - 1}';
    final tail = busy == 1 ? ' working · ${mins < 1 ? '<1' : mins}m' : ' working';
    final waiting = bridge.running.where((r) => r['ask'] != null).length;
    final show = busy + waiting > 0;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Material(
              color: C.panel,
              child: InkWell(
                onTap: busy == 1 && first != null
                    ? () => openSession(context, first['dir'] as String, first['id'] as String, () {}, title: first['title'] as String?)
                    : onTap,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: C.line)),
                  ),
                  child: Row(
                    children: [
                      PulseDot(
                        color: waiting > 0 ? C.accent : C.busy,
                        pulse: true,
                        size: 7,
                      ),
                      const SizedBox(width: 10),
                      if (busy > 0)
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: C.text2,
                            ),
                          ),
                        ),
                      if (busy > 0)
                        Text(
                          tail,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: C.text2,
                          ),
                        ),
                      if (busy > 0 && waiting > 0)
                        const Text(
                          ' · ',
                          style: TextStyle(fontSize: 12.5, color: C.text3),
                        ),
                      if (waiting > 0)
                        Text(
                          '$waiting waiting for you',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: C.accent,
                          ),
                        ),
                      const Spacer(),
                      const Icon(Icons.chevron_right, size: 16, color: C.text3),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
