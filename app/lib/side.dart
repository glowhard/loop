import 'package:flutter/material.dart';

import 'main.dart';
import 'tasks.dart';
import 'ticket.dart';
import 'sessions.dart';
import 'theme.dart';

/// The things that sit beside a conversation rather than inside it: what it
/// left running, the project's tickets, the terminals that are open. On a wide
/// screen they live in a panel down the right; on a phone the same sections
/// come up as sheets. One list, two frames, so a new one appears in both.
enum Side {
  tasks(
    Icons.schedule_outlined,
    'Tasks',
    'Background tasks',
    'Commands and agents it left running',
  ),
  board(Icons.checklist_outlined, 'Board', 'Tickets', "This project's board"),
  shells(Icons.terminal, 'Shells', 'Terminals', 'The terminals that are open');

  const Side(this.icon, this.short, this.title, this.about);
  final IconData icon;
  final String short;
  final String title;
  final String about;
}

/// What one section shows for the chat that is open.
Widget sideBody(Side bit, Map<String, String> open) => switch (bit) {
  Side.tasks => TasksBody(
    key: ValueKey('tasks:${open['sessionId']}'),
    dir: open['dir'] ?? '',
    sessionId: open['sessionId'] ?? '',
    server: open['server'] ?? '',
    title: Side.tasks.title,
  ),
  Side.board => TicketsBody(
    key: ValueKey('board:${open['dir']}'),
    dir: open['dir'] ?? '',
  ),
  Side.shells => const ShellsBody(),
};

/// The panel itself: a row of sections at the top, the one you picked below,
/// and a way to fold it out of sight when the conversation needs the room.
class SidePanel extends StatefulWidget {
  const SidePanel({super.key, required this.open, required this.onClose});
  final Map<String, String> open;
  final VoidCallback onClose;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  Side _bit = Side.tasks;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 330,
      decoration: const BoxDecoration(
        color: C.chrome,
        border: Border(left: BorderSide(color: C.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 6, 6),
            child: Row(
              children: [
                // More sections than fit are reached by sliding the row, so
                // adding one never pushes anything off the edge.
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final bit in Side.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: _Tab(
                              bit: bit,
                              on: bit == _bit,
                              onTap: () => setState(() => _bit = bit),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Hide this panel',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.last_page, size: 18),
                  style: IconButton.styleFrom(foregroundColor: C.text3),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: C.line),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: sideBody(_bit, widget.open),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.bit, required this.on, required this.onTap});
  final Side bit;
  final bool on;
  final VoidCallback onTap;

  // The one you are on carries its name; the rest are their icon, so the row
  // stays short however many sections there come to be.
  @override
  Widget build(BuildContext context) => Tooltip(
    message: bit.title,
    waitDuration: const Duration(milliseconds: 400),
    child: Material(
      color: on ? C.raised2 : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(bit.icon, size: 15, color: on ? C.text : C.text3),
              if (on) ...[
                const SizedBox(width: 6),
                Text(
                  bit.short,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: C.text,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// The folded panel: the same sections as a strip of icons, so bringing it
/// back is one click on the one you want.
class SideRail extends StatelessWidget {
  const SideRail({super.key, required this.onOpen});
  final void Function(Side) onOpen;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    decoration: const BoxDecoration(
      color: C.chrome,
      border: Border(left: BorderSide(color: C.line)),
    ),
    child: Column(
      children: [
        const SizedBox(height: 8),
        for (final bit in Side.values)
          IconButton(
            tooltip: bit.title,
            onPressed: () => onOpen(bit),
            icon: Icon(bit.icon, size: 18),
            style: IconButton.styleFrom(foregroundColor: C.text3),
          ),
      ],
    ),
  );
}

/// The project's tickets, the same ones the team page shows.
class TicketsBody extends StatefulWidget {
  const TicketsBody({super.key, required this.dir});
  final String dir;

  @override
  State<TicketsBody> createState() => _TicketsBodyState();
}

class _TicketsBodyState extends State<TicketsBody> {
  List<Map<String, dynamic>> _tickets = [];
  bool _first = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await bridge.act('tasks', {'dir': widget.dir});
    if (!mounted) return;
    setState(() {
      _tickets = ((r.data ?? []) as List).cast<Map<String, dynamic>>();
      _first = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final open = _tickets.where((t) => t['status'] != 'done').toList();
    final done = _tickets.where((t) => t['status'] == 'done').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Head(title: 'Tickets', count: open.length, onRefresh: _load),
        if (_first)
          const _Waiting()
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                if (_tickets.isEmpty)
                  const _Empty(
                    icon: Icons.checklist,
                    what: 'No tickets on this board',
                    more: 'The project manager puts the work here.',
                  ),
                for (final t in [...open, ...done])
                  TicketCard(task: t, dir: widget.dir, onChanged: _load),
              ],
            ),
          ),
      ],
    );
  }
}

/// The terminals that are open on the PC, and the way back into one. This is
/// the list that used to live on its own page.
class ShellsBody extends StatelessWidget {
  const ShellsBody({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: bridge,
    builder: (context, _) {
      final tabs = bridge.tabs
          .where((t) => t['kind'] == 'shell' && t['exited'] != true)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Head(title: 'Terminals', count: tabs.length),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                if (tabs.isEmpty)
                  const _Empty(
                    icon: Icons.terminal,
                    what: 'No terminal open',
                    more: 'Open one from a project to use the shell here.',
                  ),
                for (final t in tabs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: C.well,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          final r = await bridge.watch(t['id'] as String);
                          if (!context.mounted) return;
                          if (r.ok) await pushTerminal(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.terminal,
                                size: 15,
                                color: C.shell,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  t['name'] as String? ?? 'Terminal',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: C.text2,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: C.text3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _Head extends StatelessWidget {
  const _Head({required this.title, this.count, this.onRefresh});
  final String title;
  final int? count;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            count == null || count == 0 ? title : '$title · $count',
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

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(0, 24, 0, 40),
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: C.accent),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.what, required this.more});
  final IconData icon;
  final String what;
  final String more;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 20, 0, 36),
    child: Column(
      children: [
        Icon(icon, size: 28, color: C.text3),
        const SizedBox(height: 10),
        Text(what, style: const TextStyle(fontSize: 14, color: C.text2)),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            more,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: C.text3),
          ),
        ),
      ],
    ),
  );
}

/// The same section, brought up from the bottom on a phone.
Future<void> showSide(
  BuildContext context,
  Side bit,
  Map<String, String> open,
) => showLoopSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      child: sideBody(bit, open),
    ),
  ),
);
