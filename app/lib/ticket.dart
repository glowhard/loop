import 'package:flutter/material.dart';

import 'main.dart';
import 'theme.dart';

/// A ticket on a project's board: the card it is on a list, and the whole of it
/// when you open one — what it says, who has it, what has happened to it, and
/// everything anyone wrote under it.

const ticketStages = ['todo', 'doing', 'review', 'blocked', 'done'];

Color stageColour(String status) => switch (status) {
  'done' => C.idle,
  'review' => C.accent,
  'doing' => C.busy,
  'blocked' => C.danger,
  _ => C.text3,
};

String stageWord(String status) => switch (status) {
  'todo' => 'To do',
  'doing' => 'Doing',
  'review' => 'Review',
  'blocked' => 'Blocked',
  'done' => 'Done',
  _ => status,
};

/// "just now", "14 minutes ago", "3 days ago" — close enough to read at a
/// glance, which is all a timestamp on a ticket is for.
String whenWords(int ms) {
  if (ms <= 0) return '';
  final mins = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(ms))
      .inMinutes;
  if (mins < 1) return 'just now';
  if (mins < 60) return '$mins minute${mins == 1 ? '' : 's'} ago';
  final hours = mins ~/ 60;
  if (hours < 24) return '$hours hour${hours == 1 ? '' : 's'} ago';
  final days = hours ~/ 24;
  if (days < 30) return '$days day${days == 1 ? '' : 's'} ago';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day}/${d.month}/${d.year}';
}

/// One ticket, as a line on a list.
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.task,
    required this.dir,
    required this.onChanged,
  });
  final Map<String, dynamic> task;
  final String dir;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = task['status'] as String? ?? 'todo';
    final colour = stageColour(status);
    final who = (task['assignee'] as String? ?? '').trim();
    final done = ((task['progress'] as num?)?.round() ?? 0).clamp(0, 100);
    final said = ((task['notes'] as List?) ?? const [])
        .where((n) => (n as Map)['kind'] == null)
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: C.panel,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              showTicket(context, dir: dir, task: task, onChanged: onChanged),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task['title'] as String? ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, height: 1.35),
                ),
                // How far along, as whoever holds it judges it.
                if (done > 0 && status != 'done') ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: done / 100,
                      minHeight: 3,
                      backgroundColor: C.line,
                      valueColor: const AlwaysStoppedAnimation(C.busy),
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colour.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        stageWord(status),
                        style: TextStyle(
                          color: colour,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      task['id'] as String? ?? '',
                      style: const TextStyle(fontSize: 11, color: C.text3),
                    ),
                    if (said > 0) ...[
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.mode_comment_outlined,
                        size: 11,
                        color: C.text3,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$said',
                        style: const TextStyle(fontSize: 11, color: C.text3),
                      ),
                    ],
                    if (done > 0 && status != 'done') ...[
                      const SizedBox(width: 10),
                      Text(
                        '$done%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: C.busy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (who.isNotEmpty)
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Face(name: who),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                who,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: C.text3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Initials in a circle, so who holds a ticket reads at a glance.
class _Face extends StatelessWidget {
  const _Face({required this.name, this.size = 18});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bits = name
        .trim()
        .split(RegExp(r'[\s·_-]+'))
        .where((x) => x.isNotEmpty)
        .toList();
    final letters = bits.isEmpty
        ? '?'
        : (bits.length == 1
              ? bits.first.characters.first
              : bits.first.characters.first + bits[1].characters.first);
    final tone = C.accent.withValues(
      alpha: 0.18 + (name.codeUnits.fold<int>(0, (a, b) => a + b) % 5) * 0.04,
    );
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      child: Text(
        letters.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
          color: C.text,
        ),
      ),
    );
  }
}

/// The whole ticket. A dialog where there is room for one, and the full height
/// of the screen on a phone.
Future<void> showTicket(
  BuildContext context, {
  required String dir,
  required Map<String, dynamic> task,
  required VoidCallback onChanged,
}) {
  final wide = MediaQuery.of(context).size.width >= 760;
  final view = TicketView(dir: dir, task: task, onChanged: onChanged);
  if (!wide) {
    return showLoopSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          child: view,
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: C.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: view,
      ),
    ),
  );
}

class TicketView extends StatefulWidget {
  const TicketView({
    super.key,
    required this.dir,
    required this.task,
    required this.onChanged,
  });
  final String dir;
  final Map<String, dynamic> task;
  final VoidCallback onChanged;

  @override
  State<TicketView> createState() => _TicketViewState();
}

class _TicketViewState extends State<TicketView> {
  late Map<String, dynamic> _task = {...widget.task};
  final _say = TextEditingController();
  bool _busy = false;
  bool _editing = false;
  final _title = TextEditingController();
  final _details = TextEditingController();

  @override
  void dispose() {
    _say.dispose();
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  /// Every change goes the same way: ask the PC, take back the ticket it
  /// returns, and let whoever opened this know the board moved.
  Future<void> _change(Map<String, dynamic> change) async {
    setState(() => _busy = true);
    final r = await bridge.act('taskUpdate', {
      'dir': widget.dir,
      'id': _task['id'],
      'change': change,
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      final back = r.data;
      if (back is Map) _task = Map<String, dynamic>.from(back);
    });
    widget.onChanged();
  }

  Future<void> _comment() async {
    final text = _say.text.trim();
    if (text.isEmpty) return;
    _say.clear();
    await _change({'note': text});
  }

  Future<void> _assign() async {
    final r = await bridge.act('sessions', {'dir': widget.dir});
    if (!mounted) return;
    final people = [
      for (final s in ((r.data as Map?)?['sessions'] as List? ?? const []))
        Map<String, dynamic>.from(s as Map),
    ];
    final picked = await showLoopSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Text(
                  'Who is doing this?',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_off_outlined, size: 20),
                title: const Text('Nobody'),
                onTap: () => Navigator.pop(sheet, <String, dynamic>{}),
              ),
              for (final s in people)
                ListTile(
                  leading: _Face(name: s['title'] as String? ?? '?', size: 22),
                  title: Text(s['title'] as String? ?? ''),
                  subtitle: (s['roleTitle'] as String? ?? '').isEmpty
                      ? null
                      : Text(
                          s['roleTitle'] as String,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: C.text3,
                          ),
                        ),
                  onTap: () => Navigator.pop(sheet, s),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await _change({
      'assignee': picked['title'] ?? '',
      'assigneeId': picked['id'] ?? '',
    });
  }

  void _edit() {
    _title.text = _task['title'] as String? ?? '';
    _details.text = _task['details'] as String? ?? '';
    setState(() => _editing = true);
  }

  Future<void> _saveEdit() async {
    setState(() => _editing = false);
    await _change({
      'title': _title.text.trim(),
      'details': _details.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _task['status'] as String? ?? 'todo';
    final who = (_task['assignee'] as String? ?? '').trim();
    final notes = [
      for (final n in ((_task['notes'] as List?) ?? const []))
        Map<String, dynamic>.from(n as Map),
    ].reversed.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopRow(
          id: _task['id'] as String? ?? '',
          status: status,
          busy: _busy,
          onEdit: _editing ? null : _edit,
          onClose: () => Navigator.of(context).maybePop(),
        ),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            children: [
              if (_editing) ...[
                TextField(
                  controller: _title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _details,
                  maxLines: 6,
                  minLines: 3,
                  style: const TextStyle(fontSize: 13.5, height: 1.45),
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _editing = false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: _saveEdit,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  _task['title'] as String? ?? '',
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                if ((_task['details'] as String? ?? '').trim().isEmpty)
                  InkWell(
                    onTap: _edit,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'No description yet. Tap to write one.',
                        style: TextStyle(fontSize: 13, color: C.text3),
                      ),
                    ),
                  )
                else
                  SelectableText(
                    _task['details'] as String,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: C.text2,
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              _Facts(
                who: who,
                created: (_task['created'] as num?)?.toInt() ?? 0,
                updated: (_task['updated'] as num?)?.toInt() ?? 0,
                by: _task['createdBy'] as String? ?? '',
                onAssign: _busy ? null : _assign,
              ),
              const SizedBox(height: 16),
              const _Label('Status'),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in ticketStages)
                    _Stage(
                      stage: s,
                      on: s == status,
                      onTap: _busy || s == status
                          ? null
                          : () => _change({'status': s}),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // Order within a column is priority: the top one is taken next.
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _change({'rank': 'top'}),
                  icon: const Icon(Icons.vertical_align_top, size: 16),
                  label: const Text('Make it the next one taken'),
                  style: TextButton.styleFrom(
                    foregroundColor: C.text2,
                    textStyle: const TextStyle(fontSize: 12.5),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const _Label('How far along'),
              _Progress(
                percent: ((_task['progress'] as num?)?.round() ?? 0).clamp(
                  0,
                  100,
                ),
                busy: _busy,
                onSet: (pc) => _change({'progress': pc}),
              ),
              const SizedBox(height: 12),
              _Label('Activity${notes.isEmpty ? '' : ' · ${notes.length}'}'),
              const SizedBox(height: 8),
              if (notes.isEmpty)
                const Text(
                  'Nothing has happened to this ticket yet.',
                  style: TextStyle(fontSize: 12.5, color: C.text3),
                ),
              for (final n in notes) _Entry(note: n),
            ],
          ),
        ),
        _SayBox(controller: _say, busy: _busy, onSend: _comment),
      ],
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.id,
    required this.status,
    required this.busy,
    required this.onEdit,
    required this.onClose,
  });
  final String id;
  final String status;
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 10, 4),
    child: Row(
      children: [
        Text(
          id,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: C.text3,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: stageColour(status).withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            stageWord(status),
            style: TextStyle(
              color: stageColour(status),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (busy) ...[
          const SizedBox(width: 10),
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: C.accent),
          ),
        ],
        const Spacer(),
        if (onEdit != null)
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            style: IconButton.styleFrom(foregroundColor: C.text3),
          ),
        IconButton(
          tooltip: 'Close',
          onPressed: onClose,
          icon: const Icon(Icons.close, size: 19),
          style: IconButton.styleFrom(foregroundColor: C.text3),
        ),
      ],
    ),
  );
}

class _Facts extends StatelessWidget {
  const _Facts({
    required this.who,
    required this.created,
    required this.updated,
    required this.by,
    required this.onAssign,
  });
  final String who;
  final int created;
  final int updated;
  final String by;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: C.well,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: C.line),
    ),
    child: Column(
      children: [
        Row(
          children: [
            const SizedBox(
              width: 92,
              child: Text(
                'Assignee',
                style: TextStyle(fontSize: 12, color: C.text3),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: onAssign,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      if (who.isEmpty)
                        const Text(
                          'Nobody yet',
                          style: TextStyle(fontSize: 12.5, color: C.text3),
                        )
                      else ...[
                        _Face(name: who, size: 20),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            who,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: C.text,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      const Icon(Icons.unfold_more, size: 14, color: C.text3),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (created > 0) ...[
          const SizedBox(height: 6),
          _Fact(
            label: 'Created',
            value: whenWords(created) + (by.isEmpty ? '' : ' by $by'),
          ),
        ],
        if (updated > 0) ...[
          const SizedBox(height: 6),
          _Fact(label: 'Last change', value: whenWords(updated)),
        ],
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 92,
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: C.text3),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontSize: 12.5, color: C.text2),
        ),
      ),
    ],
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      color: C.text3,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _Stage extends StatelessWidget {
  const _Stage({required this.stage, required this.on, required this.onTap});
  final String stage;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colour = stageColour(stage);
    return Material(
      color: on ? colour.withValues(alpha: 0.18) : C.well,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: on ? colour.withValues(alpha: 0.5) : C.line,
            ),
          ),
          child: Text(
            stageWord(stage),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              color: on ? colour : C.text2,
            ),
          ),
        ),
      ),
    );
  }
}

/// One thing that happened: a comment someone wrote, or a move the board made.
class _Entry extends StatelessWidget {
  const _Entry({required this.note});
  final Map<String, dynamic> note;

  @override
  Widget build(BuildContext context) {
    final kind = note['kind'] as String? ?? '';
    final by = (note['by'] as String? ?? '').trim();
    final at = (note['at'] as num?)?.toInt() ?? 0;
    final text = note['text'] as String? ?? '';
    if (kind.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Icon(
                kind == 'assign'
                    ? Icons.person_outline
                    : Icons.swap_horiz_rounded,
                size: 14,
                color: C.text3,
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: by.isEmpty ? 'Someone ' : '$by ',
                      style: const TextStyle(
                        color: C.text2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: text),
                    TextSpan(
                      text: at > 0 ? ' · ${whenWords(at)}' : '',
                      style: const TextStyle(color: C.text3),
                    ),
                  ],
                ),
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: C.text3,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Face(name: by.isEmpty ? '?' : by, size: 24),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        by.isEmpty ? 'Someone' : by,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: C.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      whenWords(at),
                      style: const TextStyle(fontSize: 11, color: C.text3),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                SelectableText(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: C.text2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SayBox extends StatelessWidget {
  const _SayBox({
    required this.controller,
    required this.busy,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: C.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            style: const TextStyle(fontSize: 13.5),
            decoration: const InputDecoration(
              hintText: 'Write a comment…',
              hintStyle: TextStyle(fontSize: 13.5, color: C.text3),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Add the comment',
          onPressed: busy ? null : onSend,
          icon: const Icon(Icons.send_rounded, size: 19),
          style: IconButton.styleFrom(foregroundColor: C.accent),
        ),
      ],
    ),
  );
}

/// How far along a ticket is. Whoever holds it sets this, and it is what the
/// board shows you, so it only moves when someone moves it.
class _Progress extends StatefulWidget {
  const _Progress({
    required this.percent,
    required this.busy,
    required this.onSet,
  });
  final int percent;
  final bool busy;
  final void Function(int) onSet;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final shown = _dragging ?? widget.percent.toDouble();
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: C.busy,
              inactiveTrackColor: C.line,
              thumbColor: C.busy,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: shown,
              max: 100,
              divisions: 20,
              onChanged: widget.busy
                  ? null
                  : (v) => setState(() => _dragging = v),
              onChangeEnd: (v) {
                setState(() => _dragging = null);
                widget.onSet(v.round());
              },
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${shown.round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12.5, color: C.text2),
          ),
        ),
      ],
    );
  }
}
