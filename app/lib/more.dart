import 'package:flutter/material.dart';

import 'main.dart';
import 'stay_connected.dart';
import 'pair.dart';
import 'theme.dart';

/// The rest of Loop: the PCs this phone knows, the servers they reach, the
/// accounts, what is in the trash, and a project's knowledge base.
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: bridge,
    builder: (context, _) => _page(context),
  );

  Widget _page(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const Text(
          'More',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        _Section(title: 'This phone', child: const ConnectionsCard()),
        _Section(
          title: 'Servers',
          subtitle:
              'Sessions on these run over there and keep running when you close the app.',
          child: Column(
            children: [
              if (bridge.servers.isEmpty)
                const ListTile(
                  dense: true,
                  title: Text(
                    'No servers set up',
                    style: TextStyle(color: C.text3),
                  ),
                  subtitle: Text(
                    'Add one in Loop on the PC.',
                    style: TextStyle(color: C.text3, fontSize: 12),
                  ),
                ),
              for (final s in bridge.servers)
                ListTile(
                  leading: const Icon(Icons.dns_outlined, color: C.shell),
                  title: Text(s['name'] as String? ?? ''),
                  subtitle: Text(
                    '${s['state'] ?? ''} · ${s['sessions'] ?? 0} sessions',
                    style: const TextStyle(color: C.text3, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () =>
                        bridge.act('serverRefresh', {'id': s['id']}),
                  ),
                ),
            ],
          ),
        ),
        _Section(
          title: 'Claude accounts',
          subtitle:
              'New sessions use the project account unless you pick another one for a session.',
          child: Column(
            children: [
              for (final a in bridge.accounts)
                ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: C.raised2,
                    child: Text(
                      (a['name'] as String? ?? '?').characters
                          .take(2)
                          .toString(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(a['name'] as String? ?? ''),
                  subtitle: Text(
                    (a['who'] as String? ?? '').isEmpty
                        ? 'Signed in on the PC'
                        : a['who'] as String,
                    style: const TextStyle(color: C.text3, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        _Section(
          title: 'Alerts',
          subtitle:
              'A session asking something interrupts; one finishing stays quiet.',
          child: _StayConnected(),
        ),
        _Section(
          title: 'Trash',
          subtitle: 'Deleted sessions are kept for 30 days.',
          child: _Trash(),
        ),
        _Section(
          title: 'Knowledge',
          child: ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Notes and tasks of a project'),
            trailing: const Icon(Icons.chevron_right, color: C.text3),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const KnowledgePage())),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Loop · your sessions, wherever you are',
          textAlign: TextAlign.center,
          style: TextStyle(color: C.text3, fontSize: 11),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: C.text2,
            ),
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
            child: Text(
              subtitle!,
              style: const TextStyle(
                color: C.text3,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: C.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.line),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: child,
        ),
      ],
    ),
  );
}

class _Trash extends StatefulWidget {
  @override
  State<_Trash> createState() => _TrashState();
}

class _TrashState extends State<_Trash> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await bridge.act('trashList');
    if (!mounted) return;
    setState(() {
      _items = ((r.data ?? []) as List).cast<Map<String, dynamic>>();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const ListTile(
        dense: true,
        title: Text('…', style: TextStyle(color: C.text3)),
      );
    }
    if (_items.isEmpty) {
      return const ListTile(
        dense: true,
        title: Text('Nothing in the trash', style: TextStyle(color: C.text3)),
      );
    }
    return Column(
      children: [
        for (final t in _items)
          ListTile(
            dense: true,
            title: Text(t['title'] as String? ?? 'Session'),
            subtitle: Text(
              '${t['daysLeft'] ?? ''} days left',
              style: const TextStyle(color: C.text3, fontSize: 12),
            ),
            trailing: TextButton(
              onPressed: () async {
                final r = await bridge.act('restore', {
                  'dir': t['dir'],
                  'sessionId': t['sessionId'],
                });
                if (!context.mounted) return;
                say(context, r.text, bad: !r.ok);
                _load();
              },
              child: const Text('Restore'),
            ),
          ),
      ],
    );
  }
}

/// A project's notes and tasks, the same ones the sessions read and write.
class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key});

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  String? _dir;
  Map<String, dynamic>? _notes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (bridge.projects.isNotEmpty) {
      _dir = bridge.projects.first['dir'] as String;
      _load();
    }
  }

  Future<void> _load() async {
    if (_dir == null) return;
    setState(() => _loading = true);
    final r = await bridge.act('notes', {'dir': _dir, 'scope': 'project'});
    if (!mounted) return;
    setState(() {
      _notes = r.data is Map ? (r.data as Map).cast<String, dynamic>() : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final notes = ((_notes?['notes'] ?? []) as List)
        .cast<Map<String, dynamic>>();
    final project = bridge.projects.cast<Map<String, dynamic>?>().firstWhere(
      (p) => p?['dir'] == _dir,
      orElse: () => null,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge'),
        actions: [
          TextButton(
            onPressed: () => showLoopSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (sheetContext) => SafeArea(
                child: DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.6,
                  builder: (_, controller) => ListView(
                    controller: controller,
                    children: [
                      for (final p in bridge.projects)
                        ListTile(
                          title: Text(p['title'] as String? ?? ''),
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
            ),
            child: Text(project?['title'] as String? ?? 'Pick'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if (notes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text(
                      'No notes in this project yet.\nSessions write here as they work.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: C.text3, height: 1.5),
                    ),
                  ),
                for (final n in notes)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: C.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n['title'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          n['text'] as String? ?? '',
                          style: const TextStyle(color: C.text2, height: 1.4),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Whether Loop holds the connection open while you are in another app.
class _StayConnected extends StatefulWidget {
  @override
  State<_StayConnected> createState() => _StayConnectedState();
}

class _StayConnectedState extends State<_StayConnected> {
  @override
  Widget build(BuildContext context) => SwitchListTile(
    value: StayConnected.on,
    title: const Text('Reach me when the app is closed'),
    subtitle: const Text(
      'Loop keeps one quiet notification so your PC can still reach this phone. Off, Android stops the app after a while and alerts dry up.',
      style: TextStyle(color: C.text3, fontSize: 12, height: 1.35),
    ),
    onChanged: (v) async {
      await StayConnected.set(v);
      if (mounted) setState(() {});
    },
  );
}
