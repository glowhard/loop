import 'package:flutter/material.dart';

import 'chat.dart';
import 'main.dart';
import 'pane.dart';
import 'team.dart';
import 'terminal.dart';
import 'rules.dart';
import 'theme.dart';

/// A dot in the colour Loop uses for the same state.
class Lamp extends StatelessWidget {
  const Lamp(this.name, {super.key, this.size = 9});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: C.lamp(name),
      shape: BoxShape.circle,
      boxShadow: name == 'busy'
          ? [BoxShadow(color: C.busy.withValues(alpha: 0.45), blurRadius: 6)]
          : null,
    ),
  );
}

/// What is running right now, across this PC and its servers.
class NowPage extends StatelessWidget {
  const NowPage({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final running = bridge.running;
    final tabs = bridge.tabs.where((t) => t['kind'] == 'shell').toList();
    final recent = ((bridge.state['recent'] ?? const []) as List)
        .cast<Map<String, dynamic>>();
    return RefreshIndicator(
      color: C.accent,
      backgroundColor: C.panel,
      onRefresh: () => bridge.act('scan'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Text('Running', style: _head),
          const SizedBox(height: 2),
          Text(
            running.isEmpty
                ? 'Nothing is running on ${bridge.host}.'
                : '${running.length} session${running.length == 1 ? '' : 's'} on ${bridge.host} and its servers.',
            style: const TextStyle(color: C.text2, fontSize: 13),
          ),
          const SizedBox(height: 14),
          for (final r in running)
            _Row(
              title: r['title'] as String? ?? '',
              subtitle:
                  '${r['project']}${(r['server'] ?? '') == '' ? '' : ' · on a server'}',
              lamp: r['lamp'] as String? ?? '',
              open: r['open'] != null,
              onTap: () => openSession(
                context,
                r['dir'] as String,
                r['id'] as String,
                onOpen,
              ),
              onLong: () => sessionSheet(
                context,
                r['dir'] as String,
                r['id'] as String,
                onOpen,
              ),
            ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('Recent', style: _head),
            const SizedBox(height: 10),
            for (final r in recent)
              _Row(
                title: r['title'] as String? ?? '',
                subtitle: '${r['project']} · ${_ago(r['mtime'] as num? ?? 0)}',
                lamp: '',
                onTap: () => openSession(
                  context,
                  r['dir'] as String,
                  r['id'] as String,
                  onOpen,
                  title: r['title'] as String?,
                ),
                onLong: () => sessionSheet(
                  context,
                  r['dir'] as String,
                  r['id'] as String,
                  onOpen,
                ),
              ),
          ],
          if (tabs.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('Terminals', style: _head),
            const SizedBox(height: 10),
            for (final t in tabs)
              _Row(
                title: t['title'] as String? ?? '',
                subtitle: t['kind'] == 'shell'
                    ? 'Terminal'
                    : (t['exited'] == true ? 'Closed' : 'Session'),
                lamp: t['lamp'] as String? ?? '',
                open: true,
                watched: t['watched'] == true,
                onTap: () async {
                  if (t['kind'] != 'shell' &&
                      (t['sessionId'] as String? ?? '').isNotEmpty) {
                    return openSession(
                      context,
                      t['dir'] as String,
                      t['sessionId'] as String,
                      onOpen,
                      title: t['title'] as String?,
                    );
                  }
                  await bridge.watch(t['id'] as String);
                  if (context.mounted) await _pushTerminal(context);
                },
                onLong: () => _tabSheet(context, t),
              ),
          ],
          if (running.isEmpty && tabs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Text(
                'Open a session from Projects and it shows up here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.text3),
              ),
            ),
        ],
      ),
    );
  }

  static const _head = TextStyle(fontSize: 19, fontWeight: FontWeight.w600);
}

/// Projects, then the sessions inside one.
class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = bridge.projects;
    final q = _q.toLowerCase();
    final list =
        all
            .where(bridge.inScope)
            .where(
              (p) =>
                  q.isEmpty || (p['title'] as String).toLowerCase().contains(q),
            )
            .toList()
          ..sort(
            (a, b) =>
                ((b['mtime'] ?? 0) as num).compareTo((a['mtime'] ?? 0) as num),
          );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
              hintText: 'Find a project',
              prefixIcon: Icon(Icons.search, color: C.text3),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: C.accent,
            backgroundColor: C.panel,
            onRefresh: () => bridge.act('scan'),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final p = list[i];
                final server = (p['server'] as String? ?? '').isNotEmpty;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: C.panel,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: C.line),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    leading: Icon(
                      server ? Icons.dns_outlined : Icons.folder_outlined,
                      color: server ? C.shell : C.accent,
                    ),
                    title: Text(
                      p['title'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        '${p['count']} session${p['count'] == 1 ? '' : 's'}',
                        if ((p['live'] as int? ?? 0) > 0)
                          '${p['live']} running',
                        if (p['team'] == true) 'team',
                        if (server) 'on a server',
                      ].join(' · '),
                      style: const TextStyle(color: C.text3, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: C.text3),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProjectPage(project: p, onOpen: widget.onOpen),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class ProjectPage extends StatefulWidget {
  const ProjectPage({super.key, required this.project, required this.onOpen});
  final Map<String, dynamic> project;
  final VoidCallback onOpen;

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  bool _team = false;

  String get dir => widget.project['dir'] as String;

  @override
  void initState() {
    super.initState();
    _load();
    bridge.addListener(_load);
  }

  @override
  void dispose() {
    bridge.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final r = await bridge.act('sessions', {'dir': dir});
    if (!mounted || r.data == null) return;
    setState(() {
      _sessions = ((r.data['sessions'] ?? []) as List)
          .cast<Map<String, dynamic>>();
      _team = r.data['team'] == true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sessions that hold a role are shown under it, as the PC groups them.
    final groups = <String, List<Map<String, dynamic>>>{};
    // A sub-session goes right under the session that started it.
    final ids = {for (final s in _sessions) s['id']};
    bool under(Map<String, dynamic> s) =>
        (s['parent'] as String? ?? '').isNotEmpty && ids.contains(s['parent']);
    for (final s in _sessions.where((x) => !under(x))) {
      groups
          .putIfAbsent(
            (s['role'] as String?)?.isNotEmpty == true
                ? s['role'] as String
                : 'Other sessions',
            () => [],
          )
          .add(s);
    }
    for (final g in groups.values) {
      for (var i = g.length - 1; i >= 0; i--) {
        final kids = _sessions.where((x) => under(x) && x['parent'] == g[i]['id']);
        g.insertAll(i + 1, kids);
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project['title'] as String? ?? ''),
        actions: [
          IconButton(
            tooltip: 'Team and board',
            icon: const Icon(Icons.groups_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(
                    title: Text('${widget.project['title']} team'),
                  ),
                  body: TeamPage(dir: dir),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'New session',
            icon: const Icon(Icons.add),
            onPressed: () => _newSession(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                if (_sessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text(
                      'No sessions here yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: C.text3),
                    ),
                  ),
                for (final g in groups.entries) ...[
                  if (_team || groups.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 12, 0, 6),
                      child: Text(
                        g.key,
                        style: const TextStyle(
                          color: C.text2,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  for (final s in g.value)
                    _Row(
                      title: s['title'] as String? ?? '',
                      subtitle: (s['last'] as String? ?? '').isEmpty
                          ? (s['status'] as String? ?? '')
                          : s['last'] as String,
                      lamp: s['lamp'] as String? ?? '',
                      open: s['open'] != null,
                      pinned: s['pinned'] == true,
                      sub: s['sub'] as Map<String, dynamic>?,
                      onTap: () => openSession(
                        context,
                        dir,
                        s['id'] as String,
                        widget.onOpen,
                      ),
                      onLong: () => sessionSheet(
                        context,
                        dir,
                        s['id'] as String,
                        widget.onOpen,
                        session: s,
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  Future<void> _newSession(BuildContext context) async {
    final name = await askText(
      context,
      title: 'New session',
      hint: 'Backend developer',
      confirm: 'Start',
    );
    if (name == null) return;
    final r = await bridge.act('newSession', {
      'dir': dir,
      'name': name,
      'cols': 60,
      'rows': 24,
    });
    if (!context.mounted) return;
    say(context, r.ok ? 'Started "$name".' : r.text, bad: !r.ok);
    if (r.ok) {
      Navigator.pop(context);
      widget.onOpen();
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.lamp,
    required this.onTap,
    this.onLong,
    this.open = false,
    this.pinned = false,
    this.watched = false,
    this.sub,
  });
  final Map<String, dynamic>? sub; // set for a sub-session: status, branch, task
  final String title;
  final String subtitle;
  final String lamp;
  final bool open;
  final bool pinned;
  final bool watched;
  final VoidCallback onTap;
  final VoidCallback? onLong;

  @override
  Widget build(BuildContext context) {
    final sub = this.sub;
    return Padding(
      padding: EdgeInsets.only(bottom: 8, left: sub == null ? 0 : 22),
      child: Material(
        color: C.panel,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLong,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: watched ? C.accent : C.line),
            ),
            child: Row(
              children: [
                Lamp(lamp),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (sub != null)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Text('↳', style: TextStyle(color: C.text3)),
                            ),
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (sub != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                sub['status'] == 'working' ? 'working' : sub['status'] == 'done' ? 'handed back' : '${sub['status']}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: sub['status'] == 'done' ? C.idle : C.text3,
                                ),
                              ),
                            ),
                          if (pinned)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.push_pin,
                                size: 12,
                                color: C.text3,
                              ),
                            ),
                          if (open)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.terminal,
                                size: 13,
                                color: C.accent,
                              ),
                            ),
                        ],
                      ),
                      if (subtitle.isNotEmpty || (sub?['branch'] as String? ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            (sub?['branch'] as String? ?? '').isNotEmpty ? 'branch ${sub!['branch']}' : subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: C.text3,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 18, color: C.text3),
                  onPressed: onLong,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- opening, and everything you can do to one session ----------

/// A session opens as a chat. Reading it needs nothing on the PC; the session is
/// only started there when you send it something.
Future<void> openSession(
  BuildContext context,
  String dir,
  String id,
  VoidCallback onOpen, {
  String? title,
}) async {
  final p = bridge.projects.cast<Map<String, dynamic>?>().firstWhere(
    (x) => x?['dir'] == dir,
    orElse: () => null,
  );
  var name = title;
  if (name == null) {
    for (final r in bridge.running) {
      if (r['id'] == id) name = r['title'] as String?;
    }
  }
  name ??= (await _findSession(dir, id))?['title'] as String? ?? 'Session';
  if (!context.mounted) return;
  // Beside the list where there is room, on top of it where there is not.
  if (Pane.side) {
    return Pane.show(
      dir: dir,
      sessionId: id,
      title: name,
      project: p?['title'] as String? ?? '',
      server: p?['server'] as String? ?? '',
    );
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatPage(
        dir: dir,
        sessionId: id,
        title: name!,
        project: p?['title'] as String? ?? '',
        server: p?['server'] as String? ?? '',
      ),
    ),
  );
}

/// The raw terminal of a session, for the rare thing the chat cannot show.
Future<void> openTerminal(
  BuildContext context,
  String dir,
  String id,
  VoidCallback onOpen,
) async {
  // Wherever it was running, it comes here: a copy in another terminal or in
  // the Claude desktop app stops, and Loop carries the same conversation on.
  final r = await bridge.open(dir, id, force: true);
  if (!context.mounted) return;
  if (r.ok) return _pushTerminal(context);
  say(context, r.text, bad: true);
}

/// Open the terminal screen for whatever tab is being watched.
Future<void> pushTerminal(BuildContext context) => _pushTerminal(context);

Future<void> _pushTerminal(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(bridge.watchingTitle)),
        body: const SafeArea(top: false, child: TerminalPage()),
      ),
    ),
  );
  bridge.unwatch();
}

Future<void> sessionSheet(
  BuildContext context,
  String dir,
  String id,
  VoidCallback onOpen, {
  Map<String, dynamic>? session,
}) async {
  final s = session ?? await _findSession(dir, id);
  if (!context.mounted || s == null) return;
  final title = s['title'] as String? ?? 'Session';
  final onServer = bridge.projects.any(
    (p) => p['dir'] == dir && (p['server'] as String? ?? '').isNotEmpty,
  );
  await showLoopSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              children: [
                Lamp(s['lamp'] as String? ?? ''),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: Text(s['open'] != null ? 'Go to its terminal' : 'Open'),
            onTap: () {
              Navigator.pop(sheetContext);
              openSession(context, dir, id, onOpen);
            },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Rename'),
            subtitle: const Text(
              'The name teammates message it by',
              style: TextStyle(color: C.text3, fontSize: 12),
            ),
            onTap: () async {
              Navigator.pop(sheetContext);
              final name = await askText(
                context,
                title: 'Rename',
                value: title,
                confirm: 'Rename',
              );
              if (name == null || !context.mounted) return;
              final r = await bridge.act('rename', {
                'sessionId': id,
                'name': name,
              });
              if (context.mounted) say(context, r.text, bad: !r.ok);
            },
          ),
          if (!onServer)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Claude account'),
              subtitle: Text(
                _accountName(s['account'] as String? ?? ''),
                style: const TextStyle(color: C.text3, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                accountSheet(context, dir, id, s);
              },
            ),
          if (bridge.roles.isNotEmpty && (s['roleKey'] as String? ?? '').isNotEmpty)
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Rules for this member'),
              subtitle: const Text(
                "Only this one reads them, on top of the company's",
                style: TextStyle(color: C.text3, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                showMemberRules(context, dir, s);
              },
            ),
          if (bridge.roles.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Team role'),
              subtitle: Text(
                (s['role'] as String? ?? '').isEmpty
                    ? 'No role'
                    : s['role'] as String,
                style: const TextStyle(color: C.text3, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _roleSheet(context, dir, id, s);
              },
            ),
          if (!onServer && (s['parent'] as String? ?? '').isEmpty)
            ListTile(
              leading: const Icon(Icons.subdirectory_arrow_right),
              title: const Text('New sub-session'),
              subtitle: const Text(
                'Runs one task beside this session and hands the result back to it',
                style: TextStyle(color: C.text3, fontSize: 12),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await startSubSession(context, dir, id, title);
              },
            ),
          if (s['sub'] is Map && ((s['sub'] as Map)['result'] as String? ?? '').isNotEmpty)
            ListTile(
              leading: const Icon(Icons.assignment_turned_in_outlined),
              title: const Text('What it handed back'),
              onTap: () {
                Navigator.pop(sheetContext);
                final sub = s['sub'] as Map;
                showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(title),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        (sub['branch'] as String? ?? '').isNotEmpty
                            ? '${sub['result']}\n\nBranch: ${sub['branch']}'
                            : '${sub['result']}',
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                    ],
                  ),
                );
              },
            ),
          if (s['sub'] is Map && (s['sub'] as Map)['status'] != 'closed')
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Delete sub-session'),
              subtitle: const Text(
                'It stops and leaves the list; its branch stays',
                style: TextStyle(color: C.text3, fontSize: 12),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                final r = await bridge.act('subClose', {'sessionId': id});
                if (context.mounted) say(context, r.text, bad: !r.ok);
              },
            ),
          _RemoteTile(dir: dir, id: id, wanted: s['remote'] == true),
          ListTile(
            leading: Icon(
              s['pinned'] == true ? Icons.push_pin : Icons.push_pin_outlined,
            ),
            title: Text(s['pinned'] == true ? 'Unpin' : 'Pin to this project'),
            onTap: () {
              Navigator.pop(sheetContext);
              bridge.act('pin', {'sessionId': id});
            },
          ),
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('Peek at the last messages'),
            onTap: () {
              Navigator.pop(sheetContext);
              _peek(context, dir, id, title);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: C.danger),
            title: const Text(
              'Delete session',
              style: TextStyle(color: C.danger),
            ),
            subtitle: const Text(
              'Kept in the trash for 30 days',
              style: TextStyle(color: C.text3, fontSize: 12),
            ),
            onTap: () async {
              Navigator.pop(sheetContext);
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text('Delete "$title"?'),
                  content: const Text(
                    'It goes to the trash and is deleted for good after 30 days.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: C.danger),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              final r = await bridge.act('trash', {
                'dir': dir,
                'sessionId': id,
              });
              if (context.mounted) say(context, r.text, bad: !r.ok);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

Future<Map<String, dynamic>?> _findSession(String dir, String id) async {
  final r = await bridge.act('sessions', {'dir': dir});
  if (r.data == null) return null;
  final list = ((r.data['sessions'] ?? []) as List)
      .cast<Map<String, dynamic>>();
  for (final s in list) {
    if (s['id'] == id) return s;
  }
  return null;
}

String _accountName(String id) {
  for (final a in bridge.accounts) {
    if (a['id'] == id) {
      return '${a['name']}${(a['who'] as String? ?? '').isEmpty ? '' : ' · ${a['who']}'}';
    }
  }
  return 'The project account';
}

void accountSheet(
  BuildContext context,
  String dir,
  String id,
  Map<String, dynamic> s,
) {
  showLoopSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 2),
            child: Text(
              'Run this session as',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              'Switching restarts the session on the other account and keeps the conversation.',
              style: TextStyle(color: C.text3, fontSize: 12),
            ),
          ),
          for (final a in bridge.accounts)
            ListTile(
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: _color(a['color'] as String?),
                child: Text(
                  (a['name'] as String? ?? '?').characters.take(2).toString(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: C.accentInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(a['name'] as String? ?? ''),
              subtitle: (a['who'] as String? ?? '').isEmpty
                  ? null
                  : Text(
                      a['who'] as String,
                      style: const TextStyle(color: C.text3, fontSize: 12),
                    ),
              trailing: s['account'] == a['id']
                  ? const Icon(Icons.check, color: C.accent)
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                final r = await bridge.act('account', {
                  'dir': dir,
                  'sessionId': id,
                  'account': a['id'],
                });
                if (context.mounted) say(context, r.text, bad: !r.ok);
              },
            ),
          ListTile(
            leading: const Icon(Icons.undo),
            title: const Text('Follow the project'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final r = await bridge.act('account', {
                'dir': dir,
                'sessionId': id,
                'account': '',
              });
              if (context.mounted) say(context, r.text, bad: !r.ok);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

void _roleSheet(
  BuildContext context,
  String dir,
  String id,
  Map<String, dynamic> s,
) {
  showLoopSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Text(
              'Team role',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          for (final r in bridge.roles)
            ListTile(
              title: Text(r['title'] as String? ?? ''),
              subtitle: Text(
                r['duty'] as String? ?? '',
                maxLines: 2,
                style: const TextStyle(color: C.text3, fontSize: 12),
              ),
              trailing: s['roleKey'] == r['key']
                  ? const Icon(Icons.check, color: C.accent)
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                final out = await bridge.act('role', {
                  'dir': dir,
                  'sessionId': id,
                  'roleKey': r['key'],
                });
                if (context.mounted) say(context, out.text, bad: !out.ok);
              },
            ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('No role'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final out = await bridge.act('role', {
                'dir': dir,
                'sessionId': id,
                'roleKey': '',
              });
              if (context.mounted) say(context, out.text, bad: !out.ok);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

Future<void> _peek(
  BuildContext context,
  String dir,
  String id,
  String title,
) async {
  final r = await bridge.act('peek', {'dir': dir, 'sessionId': id});
  if (!context.mounted) return;
  final turns = ((r.data ?? []) as List).cast<Map<String, dynamic>>();
  showLoopSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (turns.isEmpty)
            const Text(
              'Nothing was said in this session yet.',
              style: TextStyle(color: C.text3),
            ),
          for (final t in turns)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t['role'] == 'user' ? 'You' : 'Claude',
                    style: TextStyle(
                      color: t['role'] == 'user' ? C.accent : C.idle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    t['text'] as String? ?? '',
                    style: const TextStyle(height: 1.4),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

void _tabSheet(BuildContext context, Map<String, dynamic> t) {
  showLoopSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Text(
              t['title'] as String? ?? '',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Close this terminal'),
            subtitle: const Text(
              'The conversation is saved',
              style: TextStyle(color: C.text3, fontSize: 12),
            ),
            onTap: () async {
              Navigator.pop(sheetContext);
              final r = await bridge.act('close', {'tabId': t['id']});
              if (context.mounted) say(context, r.text, bad: !r.ok);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

Color _color(String? css) {
  if (css == null || !css.startsWith('#') || css.length < 7) return C.accent;
  return Color(int.parse('FF${css.substring(1, 7)}', radix: 16));
}

/// One short answer, the way the PC asks for one.
/// Start a sub-session of [parentId]: the task, and what to hand back.
Future<void> startSubSession(BuildContext context, String dir, String parentId, String parentTitle) async {
  final task = TextEditingController();
  final returns = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Sub-session of $parentTitle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: task,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Task',
              hintText: 'What should it do? It gets the last messages and notes of this session.',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: returns,
            decoration: const InputDecoration(
              labelText: 'What to hand back (optional)',
              hintText: 'Default: the branch and commits for code, a short report otherwise',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start')),
      ],
    ),
  );
  final t = task.text.trim();
  final back = returns.text.trim();
  task.dispose();
  returns.dispose();
  if (ok != true || t.isEmpty || !context.mounted) return;
  final r = await bridge.act('subStart', {'dir': dir, 'sessionId': parentId, 'task': t, 'returns': back});
  if (context.mounted) say(context, r.text, bad: !r.ok);
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String value = '',
  String? hint,
  String confirm = 'Save',
}) async {
  final c = TextEditingController(text: value);
  final out = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, c.text.trim()),
          child: Text(confirm),
        ),
      ],
    ),
  );
  c.dispose();
  return (out == null || out.isEmpty) ? null : out;
}

String _ago(num ms) {
  final s = (DateTime.now().millisecondsSinceEpoch - ms) / 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return '${(s / 60).floor()}m ago';
  if (s < 86400) return '${(s / 3600).floor()}h ago';
  return '${(s / 86400).floor()}d ago';
}


/// Claude's own Remote Control switch, as it really stands.
///
/// Loop can only work it on a session it runs: a terminal here, or one it runs
/// in the background. A session running in the Claude desktop app or another
/// terminal window owns its own switch, so this one says where to go instead of
/// pretending. While it is loading it shows what Loop has the switch set to.
class _RemoteTile extends StatefulWidget {
  const _RemoteTile({required this.dir, required this.id, required this.wanted});
  final String dir;
  final String id;
  final bool wanted;

  @override
  State<_RemoteTile> createState() => _RemoteTileState();
}

class _RemoteTileState extends State<_RemoteTile> {
  late bool _on = widget.wanted;
  bool _live = false;
  bool _busy = false;
  String _where = ''; // where it runs, when that is not Loop
  String _said = '';

  @override
  void initState() {
    super.initState();
    _look();
  }

  Future<void> _look() async {
    final r = await bridge.act('remoteState', {
      'dir': widget.dir,
      'sessionId': widget.id,
    });
    if (!mounted || r.data == null) return;
    setState(() {
      _on = r.data['on'] == true;
      _live = r.data['live'] == true;
      _where = r.data['where'] as String? ?? '';
    });
  }

  Future<void> _set(bool v) async {
    setState(() {
      _busy = true;
      _said = '';
    });
    final r = await bridge.act('remote', {
      'dir': widget.dir,
      'sessionId': widget.id,
      'on': v,
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _said = r.ok ? '' : (r.text ?? '');
    });
    if (!r.ok && mounted) say(context, r.text, bad: true);
    await _look();
  }

  @override
  Widget build(BuildContext context) {
    final elsewhere = _where.isNotEmpty;
    final about = _said.isNotEmpty
        ? _said
        : elsewhere
        ? 'Runs in $_where, which owns this switch. Turn it on there, or open the session here first.'
        : _live
        ? 'Connected to claude.ai.'
        : _on
        ? 'Connects as soon as Loop starts it.'
        : "Claude's own switch: connects this session to claude.ai. Nothing to do with this app.";
    return SwitchListTile(
      secondary: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_outlined),
      title: const Text('Remote Control'),
      subtitle: Text(
        about,
        style: TextStyle(
          color: elsewhere || _said.isNotEmpty ? C.busy : C.text3,
          fontSize: 12,
        ),
      ),
      value: _live || _on,
      onChanged: _busy || elsewhere ? null : _set,
    );
  }
}
