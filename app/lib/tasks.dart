import 'dart:async';

import 'package:flutter/material.dart';

import 'main.dart';
import 'theme.dart';

/// What a session left running in the background: commands that keep going
/// while the conversation moves on, and agents it started. It comes up from the
/// bottom over the chat, because it is something you glance at and put away,
/// not somewhere you go.
Future<void> showTasks(
  BuildContext context, {
  required String dir,
  required String sessionId,
  String server = '',
}) => showLoopSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => TasksSheet(dir: dir, sessionId: sessionId, server: server),
);

class TasksSheet extends StatelessWidget {
  const TasksSheet({
    super.key,
    required this.dir,
    required this.sessionId,
    this.server = '',
  });
  final String dir;
  final String sessionId;
  final String server;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      // Tall enough to read a list without hiding the chat behind it.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      child: TasksBody(dir: dir, sessionId: sessionId, server: server),
    ),
  );
}

/// The list itself, with one task's output in place of it when you open one.
/// The phone shows this in a sheet and a wide window in the side panel; it is
/// the same thing either way.
class TasksBody extends StatefulWidget {
  const TasksBody({
    super.key,
    required this.dir,
    required this.sessionId,
    this.server = '',
    this.title = 'Background tasks',
  });
  final String dir;
  final String sessionId;
  final String server;
  final String title;

  @override
  State<TasksBody> createState() => _TasksBodyState();
}

class _TasksBodyState extends State<TasksBody> {
  List<Map<String, dynamic>> _tasks = [];
  Map<String, dynamic>? _open; // the one whose output is being read
  bool _first = true;
  Timer? _again;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _again?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final list = await bridge.bgTasks(
      widget.dir,
      widget.sessionId,
      widget.server,
    );
    if (!mounted) return;
    setState(() {
      if (list.isNotEmpty || _tasks.isEmpty) _tasks = list;
      _first = false;
    });
    // While something is running, how long it has been going is the thing you
    // are watching, so the list keeps itself up to date. Once everything has
    // finished there is nothing to watch, and asking again would be waste.
    _again?.cancel();
    if (list.any((t) => t['status'] == 'running')) {
      _again = Timer(const Duration(seconds: 5), _load);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    final running = _tasks.where((t) => t['status'] == 'running').toList();
    final over = _tasks.where((t) => t['status'] != 'running').toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head(
          title: open == null
              ? widget.title
              : ((open['name'] as String? ?? '').trim().isEmpty
                    ? 'A command'
                    : open['name'] as String),
          onBack: open == null ? null : () => setState(() => _open = null),
          onRefresh: open == null ? _load : null,
        ),
        if (open != null)
          Flexible(
            child: _Output(key: ValueKey(open['id']), task: open),
          )
        else
          Flexible(
            child: _first
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(0, 24, 0, 40),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: C.accent,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    children: [
                      if (_tasks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(0, 20, 0, 36),
                          child: _Quiet(),
                        ),
                      if (running.isNotEmpty) ...[
                        const _Group('Running'),
                        for (final t in running)
                          _TaskCard(
                            task: t,
                            onOpen: () => setState(() => _open = t),
                          ),
                      ],
                      if (over.isNotEmpty) ...[
                        _Group('Finished ${over.length}'),
                        for (final t in over)
                          _TaskCard(
                            task: t,
                            onOpen: () => setState(() => _open = t),
                          ),
                      ],
                    ],
                  ),
          ),
      ],
    );
  }
}

/// The title row: back into the list from one task's output, and the
/// way to ask the PC again.
class _Head extends StatelessWidget {
  const _Head({required this.title, this.onBack, this.onRefresh});
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(onBack == null ? 20 : 6, 4, 8, 8),
    child: Row(
      children: [
        if (onBack != null)
          IconButton(
            tooltip: 'Back to the list',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
          ),
        ),
        if (onRefresh != null)
          IconButton(
            tooltip: 'Check again',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 19),
          ),
      ],
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Text(text, style: const TextStyle(fontSize: 12.5, color: C.text3)),
  );
}

class _Quiet extends StatelessWidget {
  const _Quiet();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Icon(Icons.schedule, size: 28, color: C.text3),
      SizedBox(height: 10),
      Text(
        'Nothing running in the background',
        style: TextStyle(fontSize: 14, color: C.text2),
      ),
      SizedBox(height: 4),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Long commands and agents this session starts show up here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: C.text3),
        ),
      ),
    ],
  );
}

/// How long a task has been going, or how long it took.
String taskAge(Map<String, dynamic> t) {
  final from = (t['started'] as num?)?.toInt() ?? 0;
  final to = (t['ended'] as num?)?.toInt() ?? 0;
  if (from == 0) return '';
  final end = to > 0 ? to : DateTime.now().millisecondsSinceEpoch;
  final secs = ((end - from) / 1000).round();
  if (secs < 0) return '';
  if (secs < 60) return '${secs}s';
  final mins = secs ~/ 60;
  if (mins < 60) return '${mins}m ${(secs % 60).toString().padLeft(2, '0')}s';
  return '${mins ~/ 60}h ${mins % 60}m';
}

/// One task: what it is, how it ended, and how long it took.
class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onOpen});
  final Map<String, dynamic> task;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final status = task['status'] as String? ?? '';
    final running = status == 'running';
    final failed = status == 'failed';
    final name = (task['name'] as String? ?? '').trim();
    final colour = running
        ? C.busy
        : failed
        ? C.danger
        : C.text3;
    final said = switch (status) {
      'running' => '',
      'done' => 'Completed',
      'failed' => 'Failed',
      'stopped' => 'Stopped',
      _ => status,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: running ? C.raised : C.well,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: running ? C.lineStrong : C.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty ? 'A command' : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.3,
                          fontWeight: running
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: running ? C.text : C.text2,
                        ),
                      ),
                    ),
                    if (running)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 2),
                        child: SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: C.busy,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      task['kind'] == 'Agent'
                          ? Icons.smart_toy_outlined
                          : Icons.terminal,
                      size: 13,
                      color: C.text3,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      task['kind'] as String? ?? 'Bash',
                      style: const TextStyle(fontSize: 11.5, color: C.text3),
                    ),
                    if (said.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Text(
                        said,
                        style: TextStyle(fontSize: 11.5, color: colour),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      taskAge(task),
                      style: const TextStyle(fontSize: 11.5, color: C.text3),
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

/// What one task has printed so far, inside the same sheet as the list.
class _Output extends StatefulWidget {
  const _Output({super.key, required this.task});
  final Map<String, dynamic> task;

  @override
  State<_Output> createState() => _OutputState();
}

class _OutputState extends State<_Output> {
  String? _text;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final out = await bridge.bgOutput(widget.task['id'] as String? ?? '');
    if (!mounted) return;
    setState(() {
      _text = out ?? '';
      _failed = out == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.task['note'] as String? ?? '';
    final running = widget.task['status'] == 'running';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  note.isNotEmpty
                      ? note
                      : running
                      ? 'Still running · ${taskAge(widget.task)}'
                      : taskAge(widget.task),
                  style: const TextStyle(fontSize: 12.5, color: C.text2),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() => _text = null);
                  _load();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
                style: TextButton.styleFrom(
                  foregroundColor: C.text2,
                  textStyle: const TextStyle(fontSize: 12.5),
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: C.codeWell,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _text == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: C.accent,
                        ),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(
                      _text!.trim().isEmpty
                          ? (_failed
                                ? 'That output could not be read.'
                                : 'Nothing printed yet.')
                          : _text!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                        color: C.text2,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
