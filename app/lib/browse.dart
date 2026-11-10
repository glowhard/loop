// Everything as folders, the way the desktop shows it: the projects, the team
// inside a project, and the sessions under the role each one holds.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lists.dart' show ChatsPage;
import 'main.dart';
import 'sessions.dart';
import 'team.dart';
import 'rules.dart';
import 'theme.dart';

/// The top of the tree: what you were last in, then every project.
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bridge,
      builder: (context, _) {
        final q = _q.toLowerCase();
        final projects =
            bridge.projects
                .where(bridge.inScope)
                .where(
                  (p) =>
                      q.isEmpty ||
                      (p['title'] as String? ?? '').toLowerCase().contains(q),
                )
                .toList()
              ..sort(
                (a, b) => ((b['mtime'] ?? 0) as num).compareTo(
                  (a['mtime'] ?? 0) as num,
                ),
              );
        // What is running comes first, then what you had open recently.
        final recent = [...bridge.running, ...bridge.recent]
            .where(
              (r) =>
                  q.isEmpty ||
                  '${r['title']} ${r['project']}'.toLowerCase().contains(q),
            )
            .take(q.isEmpty ? 5 : 8)
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  hintText: 'Find a project or session',
                  prefixIcon: Icon(Icons.search, color: C.text3),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: C.accent,
                backgroundColor: C.panel,
                onRefresh: () => bridge.act('scan'),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 28),
                  children: [
                    if (recent.isNotEmpty) ...[
                      const _Label('Recent'),
                      for (final r in recent)
                        _Line(
                          icon: Icons.chat_bubble_outline,
                          colour: C.accent,
                          title: r['title'] as String? ?? '',
                          under: [
                            r['project'] as String? ?? '',
                            if ((r['lamp'] as String? ?? '') == 'busy')
                              'working',
                          ].where((x) => x.isNotEmpty).join(' · '),
                          lamp: r['lamp'] as String? ?? '',
                          onTap: () => openSession(
                            context,
                            r['dir'] as String,
                            r['id'] as String,
                            widget.onOpen,
                            title: r['title'] as String?,
                          ),
                        ),
                      if (q.isEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: const Text('Recent')),
                                  body: const ChatsPage(),
                                ),
                              ),
                            ),
                            child: const Text('See all'),
                          ),
                        ),
                      const SizedBox(height: 6),
                    ],
                    _Label('Projects', count: projects.length),
                    for (final p in projects)
                      _Line(
                        icon: (p['server'] as String? ?? '').isNotEmpty
                            ? Icons.dns_outlined
                            : Icons.folder_outlined,
                        colour: (p['server'] as String? ?? '').isNotEmpty
                            ? C.shell
                            : C.accent,
                        title: p['title'] as String? ?? '',
                        under: [
                          '${p['count']} session${p['count'] == 1 ? '' : 's'}',
                          if ((p['live'] as int? ?? 0) > 0)
                            '${p['live']} running',
                          if (p['team'] == true) 'team',
                        ].join(' · '),
                        chevron: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProjectBrowse(
                              project: p,
                              onOpen: widget.onOpen,
                            ),
                          ),
                        ),
                      ),
                    if (projects.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Text(
                          'Nothing here yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: C.text3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One project: its team, and its sessions under the role each one holds.
class ProjectBrowse extends StatefulWidget {
  const ProjectBrowse({super.key, required this.project, required this.onOpen});
  final Map<String, dynamic> project;
  final VoidCallback onOpen;

  @override
  State<ProjectBrowse> createState() => _ProjectBrowseState();
}

class _ProjectBrowseState extends State<ProjectBrowse> {
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _roles = []; // the team's own roles
  String _policy = ''; // the rules the user set for this team
  bool _team = false;
  bool _canTeam = true;
  bool _loading = true;

  String get dir => widget.project['dir'] as String;
  String get title => widget.project['title'] as String? ?? '';

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
      _roles = ((r.data['teamRoles'] ?? []) as List)
          .cast<Map<String, dynamic>>();
      _team = r.data['team'] == true;
      _policy = r.data['policy'] as String? ?? '';
      _canTeam = r.data['canTeam'] != false;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _holding(String roleKey) =>
      _sessions.where((s) => s['roleKey'] == roleKey).toList();

  @override
  Widget build(BuildContext context) {
    final loose = _sessions
        .where((s) => !_roles.any((r) => r['key'] == s['roleKey']))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_team)
            IconButton(
              tooltip: 'Goal and board',
              icon: const Icon(Icons.assignment_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text('$title board')),
                    body: TeamPage(dir: dir),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'New session',
            icon: const Icon(Icons.add),
            onPressed: _newSession,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.accent))
          : RefreshIndicator(
              color: C.accent,
              backgroundColor: C.panel,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
                children: [
                  if (_canTeam) _teamPart(),
                  if (loose.isNotEmpty) ...[
                    _Label(_team ? 'No role' : 'Sessions', count: loose.length),
                    for (final s in loose) _session(s),
                  ],
                  if (_sessions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Text(
                        'No sessions here yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: C.text3),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _teamPart() {
    if (!_team) {
      return Card(
        margin: const EdgeInsets.fromLTRB(2, 6, 2, 14),
        color: C.panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: C.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No team here',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'A team gives each session a role, so work can be handed '
                'between them and the board keeps track.',
                style: TextStyle(fontSize: 13, color: C.text2, height: 1.4),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _makeTeam,
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: const Text('Create a team'),
                style: FilledButton.styleFrom(
                  backgroundColor: C.accent,
                  foregroundColor: C.accentInk,
                  minimumSize: const Size(0, 40),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _Label('Team')),
            TextButton.icon(
              onPressed: _rules,
              icon: const Icon(Icons.gavel_outlined, size: 15),
              label: const Text('Rules'),
              style: TextButton.styleFrom(
                foregroundColor: _policy.isEmpty ? C.text3 : C.accent,
                textStyle: const TextStyle(fontSize: 12.5),
              ),
            ),
            TextButton.icon(
              onPressed: _addRole,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add role'),
              style: TextButton.styleFrom(
                foregroundColor: C.accent,
                textStyle: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
        for (final r in _roles)
          _RoleCard(
            title: r['title'] as String? ?? '',
            duty: r['duty'] as String? ?? '',
            manages: r['manages'] == true,
            onMenu: () => _roleMenu(r),
            onStart: () => _startInRole(r),
            onFill: () => _fillSeat(r),
            members: [
              for (final s in _holding(r['key'] as String? ?? '')) _session(s),
            ],
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _session(Map<String, dynamic> s) => _Line(
    icon: Icons.chat_bubble_outline,
    colour: C.text2,
    title: s['title'] as String? ?? '',
    under: _under(s),
    lamp: s['lamp'] as String? ?? '',
    onTap: () => openSession(
      context,
      dir,
      s['id'] as String,
      widget.onOpen,
      title: s['title'] as String?,
    ),
    onLong: () => sessionSheet(
      context,
      dir,
      s['id'] as String,
      widget.onOpen,
      session: s,
    ),
  );

  /// What a session is doing, or the last thing said to it. The brief a team
  /// member is started with is not worth repeating under its name.
  static String _under(Map<String, dynamic> s) {
    final lamp = s['lamp'] as String? ?? '';
    final status = s['status'] as String? ?? '';
    final last = (s['last'] as String? ?? '').trim();
    final brief = RegExp(
      r"^You are the .*(project's team|Rename this ses)",
      caseSensitive: false,
    ).hasMatch(last);
    if (lamp == 'busy') return status.isEmpty ? 'Working' : status;
    if (last.isEmpty || brief) return status;
    return last;
  }

  /// The rules: the company's, which hold for every team, and this project's on
  /// top of them. The CEO may rewrite them too; no other member may.
  Future<void> _rules() async {
    await showRules(context, dir);
    if (!mounted) return;
    _load();
  }

  // ---- making and changing the team ----

  Future<void> _makeTeam() async {
    final picked = await showLoopSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickRoles(roles: bridge.roles),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    for (final r in picked) {
      await bridge.act('team', {
        'dir': dir,
        'teamAction': 'add_role',
        'role': r['title'],
        'duty': r['duty'] ?? '',
      });
    }
    await _load();
    if (mounted) {
      say(
        context,
        'Team created with ${picked.length} role${picked.length == 1 ? '' : 's'}.',
      );
    }
  }

  Future<void> _addRole() async {
    final picked = await showLoopSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickRoles(
        roles: bridge.roles
            .where((r) => !_roles.any((x) => x['key'] == r['key']))
            .toList(),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    for (final r in picked) {
      await bridge.act('team', {
        'dir': dir,
        'teamAction': 'add_role',
        'role': r['title'],
        'duty': r['duty'] ?? '',
      });
    }
    await _load();
  }

  Future<void> _roleMenu(Map<String, dynamic> role) async {
    final who = _holding(role['key'] as String? ?? '');
    final what = await showLoopSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _Menu(
        title: role['title'] as String? ?? '',
        items: [
          ('start', Icons.play_arrow_outlined, 'Start a session in this role'),
          ('fill', Icons.person_add_outlined, 'Give the role to a session'),
          if (who.isNotEmpty)
            (
              'clear',
              Icons.person_remove_outlined,
              'Take the role off ${who.first['title']}',
            ),
          ('drop', Icons.delete_outline, 'Remove this role from the team'),
        ],
      ),
    );
    if (what == null || !mounted) return;
    if (what == 'start') return _startInRole(role);
    if (what == 'fill') return _fillSeat(role);
    if (what == 'clear') {
      await bridge.act('team', {
        'dir': dir,
        'teamAction': 'unassign',
        'session': who.first['id'],
      });
      return _load();
    }
    if (what == 'drop') {
      await bridge.act('team', {
        'dir': dir,
        'teamAction': 'drop_role',
        'role': role['title'],
      });
      return _load();
    }
  }

  Future<void> _startInRole(Map<String, dynamic> role) async {
    final name = await askText(
      context,
      title: 'Start a session',
      hint: role['title'] as String? ?? '',
      confirm: 'Start',
    );
    if (name == null || !mounted) return;
    final r = await bridge.act('team', {
      'dir': dir,
      'teamAction': 'start',
      'role': role['title'],
      'name': name,
    });
    if (!mounted) return;
    say(context, r.text, bad: !r.ok);
    await _load();
  }

  Future<void> _fillSeat(Map<String, dynamic> role) async {
    final free = _sessions
        .where((s) => (s['roleKey'] as String? ?? '').isEmpty)
        .toList();
    if (free.isEmpty) {
      say(context, 'Every session here already holds a role.', bad: true);
      return;
    }
    final id = await showLoopSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _Menu(
        title: 'Who is the ${role['title']}?',
        items: [
          for (final s in free)
            (
              s['id'] as String,
              Icons.chat_bubble_outline,
              s['title'] as String? ?? '',
            ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    final r = await bridge.act('team', {
      'dir': dir,
      'teamAction': 'assign',
      'session': id,
      'role': role['title'],
    });
    if (!mounted) return;
    say(context, r.text, bad: !r.ok);
    await _load();
  }

  Future<void> _newSession() async {
    final name = await askText(
      context,
      title: 'New session',
      hint: 'Backend developer',
      confirm: 'Start',
    );
    if (name == null || !mounted) return;
    final r = await bridge.act('newSession', {
      'dir': dir,
      'name': name,
      'cols': 60,
      'rows': 24,
    });
    if (!mounted) return;
    say(context, r.ok ? 'Started "$name".' : r.text, bad: !r.ok);
    await _load();
  }
}

// ---- the small pieces ----

class _Label extends StatelessWidget {
  const _Label(this.text, {this.count});
  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
    child: Text(
      count == null ? text : '$text · $count',
      style: const TextStyle(
        fontSize: 12,
        color: C.text3,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.colour,
    required this.title,
    required this.under,
    this.lamp = '',
    this.chevron = false,
    this.onTap,
    this.onLong,
  });
  final IconData icon;
  final Color colour;
  final String title;
  final String under;
  final String lamp;
  final bool chevron;
  final VoidCallback? onTap;
  final VoidCallback? onLong;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLong == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onLong!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 21, color: colour),
                    if (lamp.isNotEmpty)
                      Positioned(
                        left: 13,
                        bottom: -2,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: C.lamp(lamp),
                            shape: BoxShape.circle,
                            border: Border.all(color: C.well, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (under.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          under,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: C.text3),
                        ),
                      ),
                  ],
                ),
              ),
              if (chevron)
                const Icon(Icons.chevron_right, size: 18, color: C.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// One role, with whoever holds it. Kept as a card so a team of eight reads
/// as eight things rather than one long list.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.duty,
    required this.manages,
    required this.members,
    required this.onMenu,
    required this.onStart,
    required this.onFill,
  });
  final String title;
  final String duty;
  final bool manages;
  final List<Widget> members;
  final VoidCallback onMenu;
  final VoidCallback onStart;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: C.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The role, which is the thing being scanned: given the full width,
          // with what it owns on a line of its own underneath.
          Material(
            color: C.raised.withValues(alpha: 0.5),
            child: InkWell(
              onTap: onMenu,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        manages
                            ? Icons.workspace_premium_outlined
                            : Icons.badge_outlined,
                        size: 15,
                        color: manages ? C.busy : C.text3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: C.text,
                            ),
                          ),
                          if (duty.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                duty,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: C.text3,
                                  height: 1.3,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.more_horiz, size: 18, color: C.text3),
                  ],
                ),
              ),
            ),
          ),
          if (members.isEmpty)
            _EmptySeat(onStart: onStart, onFill: onFill)
          else
            ...members,
        ],
      ),
    );
  }
}

class _EmptySeat extends StatelessWidget {
  const _EmptySeat({required this.onStart, required this.onFill});
  final VoidCallback onStart;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7, right: 4),
          child: Text(
            'Nobody yet',
            style: TextStyle(fontSize: 12.5, color: C.text3),
          ),
        ),
        TextButton(
          onPressed: onFill,
          style: TextButton.styleFrom(
            foregroundColor: C.text2,
            textStyle: const TextStyle(fontSize: 12.5),
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: const Text('Give to a session'),
        ),
        TextButton(
          onPressed: onStart,
          style: TextButton.styleFrom(
            foregroundColor: C.accent,
            textStyle: const TextStyle(fontSize: 12.5),
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: const Text('Start one'),
        ),
      ],
    ),
  );
}

/// Which roles the team should have, picked from the ones Loop knows, or new.
class _PickRoles extends StatefulWidget {
  const _PickRoles({required this.roles});
  final List<Map<String, dynamic>> roles;

  @override
  State<_PickRoles> createState() => _PickRolesState();
}

class _PickRolesState extends State<_PickRoles> {
  final _chosen = <Map<String, dynamic>>[];
  final _own = TextEditingController();

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 2),
            child: Text(
              'Roles for this team',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Pick the ones you want. A session takes a role, and the work is '
              'handed between them.',
              style: TextStyle(fontSize: 12.5, color: C.text2, height: 1.4),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final r in widget.roles)
                  CheckboxListTile(
                    dense: true,
                    value: _chosen.any((x) => x['key'] == r['key']),
                    onChanged: (on) => setState(() {
                      if (on == true) {
                        _chosen.add(r);
                      } else {
                        _chosen.removeWhere((x) => x['key'] == r['key']);
                      }
                    }),
                    activeColor: C.accent,
                    checkColor: C.accentInk,
                    title: Text(
                      r['title'] as String? ?? '',
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: (r['duty'] as String? ?? '').isEmpty
                        ? null
                        : Text(
                            r['duty'] as String,
                            maxLines: 2,
                            style: const TextStyle(
                              fontSize: 12,
                              color: C.text3,
                            ),
                          ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _own,
                    decoration: const InputDecoration(
                      hintText: 'Or a role of your own',
                    ),
                    onSubmitted: (_) => _addOwn(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addOwn,
                  icon: const Icon(Icons.add, color: C.accent),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: FilledButton(
              onPressed: _chosen.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_chosen),
              style: FilledButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: C.accentInk,
                disabledBackgroundColor: C.raised,
                minimumSize: const Size(0, 44),
              ),
              child: Text(
                _chosen.isEmpty
                    ? 'Pick at least one'
                    : 'Use ${_chosen.length} role${_chosen.length == 1 ? '' : 's'}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addOwn() {
    final name = _own.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _chosen.add({'key': 'own-$name', 'title': name, 'duty': ''});
      _own.clear();
    });
  }
}

/// A short list of things to do, as a sheet.
class _Menu extends StatelessWidget {
  const _Menu({required this.title, required this.items});
  final String title;
  final List<(String, IconData, String)> items;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.8,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final (id, icon, label) in items)
                ListTile(
                  leading: Icon(icon, size: 20, color: C.text2),
                  title: Text(label, style: const TextStyle(fontSize: 14)),
                  onTap: () => Navigator.of(context).pop(id),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    ),
  );
}
