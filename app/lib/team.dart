import 'package:flutter/material.dart';

import 'main.dart';
import 'sessions.dart';
import 'ticket.dart';
import 'theme.dart';

/// The team of one project: who holds which role, what the tickets say, and the
/// one box that gives the whole team a goal.
class TeamPage extends StatefulWidget {
  const TeamPage({super.key, this.dir});
  final String? dir;

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  String? _dir;
  final _goal = TextEditingController();
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = false;
  bool _giving = false;

  @override
  void initState() {
    super.initState();
    bridge.addListener(_onState);
    _pick();
  }

  @override
  void dispose() {
    bridge.removeListener(_onState);
    _goal.dispose();
    super.dispose();
  }

  void _onState() {
    if (_dir == null) _pick();
  }

  void _pick() {
    if (widget.dir != null) {
      if (_dir == null) {
        _dir = widget.dir;
        _load();
      }
      return;
    }
    final withTeam = bridge.projects.where((p) => p['team'] == true).toList();
    final choice = withTeam.isNotEmpty
        ? withTeam.first
        : (bridge.projects.isNotEmpty ? bridge.projects.first : null);
    if (choice != null && _dir != choice['dir']) {
      _dir = choice['dir'] as String;
      _load();
    }
  }

  Future<void> _load() async {
    if (_dir == null) return;
    setState(() => _loading = true);
    final s = await bridge.act('sessions', {'dir': _dir});
    final t = await bridge.act('tasks', {'dir': _dir});
    if (!mounted) return;
    setState(() {
      _sessions = s.data == null
          ? []
          : ((s.data['sessions'] ?? []) as List).cast<Map<String, dynamic>>();
      _tasks = ((t.data ?? []) as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  Future<void> _give() async {
    final text = _goal.text.trim();
    if (text.isEmpty || _dir == null) return;
    setState(() => _giving = true);
    final r = await bridge.act('goal', {'dir': _dir, 'text': text});
    if (!mounted) return;
    setState(() => _giving = false);
    say(context, r.text, bad: !r.ok);
    if (!r.ok) return;
    _goal.clear();
    await _load();
    // Straight into the session that took it, so the work can be watched
    // rather than guessed at.
    final who = r.data as Map?;
    if (who != null && mounted) {
      await openSession(
        context,
        who['dir'] as String,
        who['sessionId'] as String,
        () {},
        title: who['title'] as String?,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = bridge.projects.cast<Map<String, dynamic>?>().firstWhere(
      (p) => p?['dir'] == _dir,
      orElse: () => null,
    );
    final hasTeam = project?['team'] == true;
    final held = <String, List<Map<String, dynamic>>>{};
    for (final s in _sessions) {
      final role = s['role'] as String? ?? '';
      if (role.isNotEmpty) held.putIfAbsent(role, () => []).add(s);
    }
    return RefreshIndicator(
      color: C.accent,
      backgroundColor: C.panel,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Row(
            children: [
              const Text(
                'Team',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _projectSheet,
                icon: const Icon(Icons.folder_outlined, size: 16),
                label: Text(
                  project?['title'] as String? ?? 'Pick a project',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          if (!hasTeam)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Text(
                'This project has no team yet.\nSet one up in Loop on the PC, then give it goals from here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.text3, height: 1.5),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Give the team a goal',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'It goes to the one in charge, who passes it down the roles and reports back.',
                    style: TextStyle(
                      color: C.text3,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _goal,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Add a dark mode to the settings page',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _giving ? null : _give,
                      child: _giving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: C.accentInk,
                              ),
                            )
                          : const Text('Give it'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Who is in it',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (_loading && held.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: C.accent),
                ),
              ),
            for (final r in held.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: C.panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.key,
                        style: const TextStyle(
                          color: C.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final s in r.value)
                        InkWell(
                          onTap: () => sessionSheet(
                            context,
                            _dir!,
                            s['id'] as String,
                            () {},
                            session: s,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Lamp(s['lamp'] as String? ?? ''),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(s['title'] as String? ?? ''),
                                ),
                                Text(
                                  s['status'] as String? ?? '',
                                  style: const TextStyle(
                                    color: C.text3,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text(
                  'The board',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${_tasks.length} ticket${_tasks.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: C.text3, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_tasks.isEmpty)
              const Text('No tickets yet.', style: TextStyle(color: C.text3))
            else
              for (final t in _tasks)
                TicketCard(task: t, dir: _dir!, onChanged: _load),
          ],
        ],
      ),
    );
  }

  void _projectSheet() {
    showLoopSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (_, controller) => ListView(
            controller: controller,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  'Which project',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              for (final p in bridge.projects)
                ListTile(
                  leading: Icon(
                    p['team'] == true ? Icons.groups : Icons.folder_outlined,
                    color: p['team'] == true ? C.accent : C.text3,
                  ),
                  title: Text(p['title'] as String? ?? ''),
                  subtitle: p['team'] == true
                      ? const Text(
                          'Has a team',
                          style: TextStyle(color: C.text3, fontSize: 12),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() => _dir = p['dir'] as String);
                    _load();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
