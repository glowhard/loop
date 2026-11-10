import 'dart:async';

import 'package:flutter/material.dart';

import 'alerts.dart';
import 'bridge.dart';
import 'browse.dart';
import 'chat.dart';
import 'home.dart';
import 'lists.dart';
import 'pane.dart';
import 'main.dart';
import 'more.dart';
import 'sessions.dart';
import 'side.dart';
import 'theme.dart';

/// Three places: Home (the two front doors and what needs you), the projects
/// with your recent chats, and everything else.
class LoopShell extends StatefulWidget {
  const LoopShell({super.key});

  @override
  State<LoopShell> createState() => _LoopShellState();
}

class _LoopShellState extends State<LoopShell> {
  int _tab = 0;
  // The column on a wide screen is a Navigator built once; it follows the tab through this.
  final _tabNow = ValueNotifier<int>(0);
  final _listNav = GlobalKey<NavigatorState>();
  StreamSubscription? _done;

  void go(int i) {
    // Switching places starts that column again at the top.
    _listNav.currentState?.popUntil((r) => r.isFirst);
    setState(() => _tab = i);
    _tabNow.value = i;
  }

  @override
  void initState() {
    super.initState();
    // A session that finished while you looked elsewhere says so, with a way in.
    _done = bridge.finished.stream.listen((r) {
      if (!mounted || bridge.chatOf?['sessionId'] == r['id']) return;
      if (Watching.away) return; // the notification said it already
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text('${r['title']} finished'),
            action: SnackBarAction(
              label: 'Open',
              textColor: C.accent,
              onPressed: () => openSession(
                context,
                r['dir'] as String,
                r['id'] as String,
                () {},
                title: r['title'] as String?,
              ),
            ),
          ),
        );
    });
  }

  bool _side = true; // the panel beside the conversation, until it is folded

  @override
  void dispose() {
    _done?.cancel();
    _tabNow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bridge,
      builder: (context, _) {
        final waiting = bridge.running.where((r) => r['ask'] != null).length;
        // Two columns where there is room for them, one where there is not.
        final wide = MediaQuery.of(context).size.width >= 900;
        // A third column needs a window wide enough that the conversation does
        // not end up squeezed between two lists.
        final room = MediaQuery.of(context).size.width >= 1240;
        Pane.side = wide;
        if (!wide && Pane.open.value != null) Pane.close();
        final pages = [
          const HomePage(),
          BrowsePage(onOpen: () {}),
          const MorePage(),
        ];
        Widget listFor(int tab) => Column(
          children: [
            // Home's own top bar is the only bar there; the feed is every project anyway.
            if (tab != 0) const LinkBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
              ),
            ),
            if (wide) WorkingBar(onTap: () => go(0)),
          ],
        );
        final list = listFor(_tab);
        final bar = NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: go,
          destinations: _spots(waiting),
        );
        if (!wide) {
          return Scaffold(
            body: SafeArea(bottom: false, child: list),
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                WorkingBar(onTap: () => go(0)),
                bar,
              ],
            ),
          );
        }
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: go,
                  backgroundColor: C.chrome,
                  indicatorColor: C.raised2,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _spots(waiting))
                      NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ),
                  ],
                ),
                // Going into a project stays in this column, as on a desktop,
                // rather than covering the conversation beside it.
                SizedBox(
                  width: 380,
                  child: Navigator(
                    key: _listNav,
                    onGenerateRoute: (_) => MaterialPageRoute(
                      builder: (_) => ValueListenableBuilder<int>(
                        valueListenable: _tabNow,
                        builder: (context, tab, _) => listFor(tab),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1, color: C.line),
                Expanded(
                  child: ValueListenableBuilder<Map<String, String>?>(
                    valueListenable: Pane.open,
                    builder: (context, open, _) => open == null
                        ? const _Nothing()
                        : ChatPage(
                            key: ValueKey(open['sessionId']),
                            dir: open['dir']!,
                            sessionId: open['sessionId']!,
                            title: open['title']!,
                            project: open['project'] ?? '',
                            server: open['server'] ?? '',
                            onBack: Pane.close,
                          ),
                  ),
                ),
                // Beside the conversation: what it has running, the board, the
                // terminals. Only where there is room for a third column.
                if (room)
                  ValueListenableBuilder<Map<String, String>?>(
                    valueListenable: Pane.open,
                    builder: (context, open, _) => open == null
                        ? const SizedBox.shrink()
                        : _side
                        ? SidePanel(
                            open: open,
                            onClose: () => setState(() => _side = false),
                          )
                        : SideRail(onOpen: (_) => setState(() => _side = true)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The machine chip at the top: which PC, and whether it can be reached.
/// The same places, whether they sit along the bottom or down the side.
List<NavigationDestination> _spots(int waiting) => [
  // What waits for you shows on Home: its feed is the inbox.
  NavigationDestination(
    icon: Badge(
      isLabelVisible: waiting > 0,
      label: Text('$waiting'),
      backgroundColor: C.busy,
      textColor: C.accentInk,
      child: const Icon(Icons.home_outlined),
    ),
    selectedIcon: Badge(
      isLabelVisible: waiting > 0,
      label: Text('$waiting'),
      backgroundColor: C.busy,
      textColor: C.accentInk,
      child: const Icon(Icons.home),
    ),
    label: 'Home',
  ),
  const NavigationDestination(
    icon: Icon(Icons.folder_outlined),
    selectedIcon: Icon(Icons.folder),
    label: 'Projects',
  ),
  const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
];

/// The right half before a chat has been chosen.
class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.chat_bubble_outline, size: 34, color: C.off),
        SizedBox(height: 10),
        Text(
          'Pick a session on the left',
          style: TextStyle(color: C.text3, fontSize: 13.5),
        ),
      ],
    ),
  );
}

/// Which workspace the lists belong to, the same grouping the desktop uses.
/// Changing it here changes it there: it is one window onto one Loop.
class _Workspace extends StatelessWidget {
  const _Workspace();

  @override
  Widget build(BuildContext context) {
    final all = bridge.workspaces
        .where((w) => (w['server'] as String? ?? '').isEmpty)
        .toList();
    if (all.length < 2) return const SizedBox.shrink();
    final now = bridge.state['activeWorkspace'] as String? ?? 'all';
    final here = all.firstWhere((w) => w['id'] == now, orElse: () => all.first);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: C.raised,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showLoopSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (sheet) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 6, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Workspace',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  for (final w in all)
                    ListTile(
                      leading: Icon(
                        w['id'] == now
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: w['id'] == now ? C.accent : C.text3,
                        size: 20,
                      ),
                      title: Text(w['name'] as String? ?? ''),
                      onTap: () {
                        Navigator.pop(sheet);
                        bridge.act('workspace', {'id': w['id']});
                      },
                    ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.workspaces_outlined, size: 13, color: C.text3),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                    here['name'] as String? ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: C.text2,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.unfold_more, size: 13, color: C.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LinkBar extends StatelessWidget {
  const LinkBar({super.key});

  // const where it is used, so it listens for itself.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: bridge,
    builder: (context, _) => _bar(context),
  );

  Widget _bar(BuildContext context) {
    final bad = bridge.link != Link.on;
    final waiting = bridge.outbox.length;
    final text = bridge.link == Link.on
        ? (bridge.problem.isEmpty ? bridge.host : bridge.problem)
        : switch (bridge.link) {
            Link.connecting =>
              'Connecting to ${bridge.conn?.name ?? 'the PC'}…',
            Link.denied => bridge.problem,
            Link.lost =>
              'Cannot reach ${bridge.conn?.name ?? 'the PC'} — retrying',
            _ => 'Not connected',
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          if (waiting > 0) ...[
            // What is written but not sent yet, so it is never a surprise.
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: C.busy.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule, size: 13, color: C.busy),
                  const SizedBox(width: 6),
                  Text(
                    waiting == 1 ? '1 waiting' : '$waiting waiting',
                    style: const TextStyle(
                      fontSize: 12,
                      color: C.busy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const _Workspace(),
          Material(
            color: bad ? C.danger.withValues(alpha: 0.16) : C.raised,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => showLoopSheet(
                context: context,
                builder: (_) => const _PcSheet(),
              ),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: bad ? C.danger : C.idle,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width - 110,
                      ),
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: C.text2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.unfold_more, size: 14, color: C.text3),
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

class _PcSheet extends StatelessWidget {
  const _PcSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text(
              'Machines',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          for (final c in bridge.saved)
            ListTile(
              leading: Icon(
                Icons.computer,
                color: bridge.conn?.where == c.where ? C.accent : C.text3,
              ),
              title: Text(c.name),
              subtitle: Text(c.where, style: const TextStyle(color: C.text3)),
              trailing: bridge.conn?.where == c.where
                  ? const Icon(Icons.check, color: C.accent)
                  : null,
              onTap: () {
                bridge.connect(c);
                Navigator.pop(context);
              },
            ),
          if (bridge.servers.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                'Servers it reaches',
                style: TextStyle(color: C.text2, fontSize: 12),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('All machines'),
              trailing: bridge.scope == 'all'
                  ? const Icon(Icons.check, color: C.accent)
                  : null,
              onTap: () {
                bridge.setScope('all');
                Navigator.pop(context);
              },
            ),
            for (final s in bridge.servers)
              ListTile(
                leading: const Icon(Icons.dns_outlined, color: C.shell),
                title: Text(s['name'] as String? ?? ''),
                subtitle: Text(
                  '${s['sessions'] ?? 0} sessions',
                  style: const TextStyle(color: C.text3),
                ),
                trailing: bridge.scope == 'srv:${s['id']}'
                    ? const Icon(Icons.check, color: C.accent)
                    : null,
                onTap: () {
                  bridge.setScope('srv:${s['id']}');
                  Navigator.pop(context);
                  say(
                    context,
                    'Showing ${s['name']}. Its sessions run on the server.',
                  );
                },
              ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
