import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:xterm/xterm.dart';

import 'main.dart';
import 'sessions.dart';
import 'theme.dart';

/// The session itself: what it is printing, and everything you need to answer
/// it with one thumb.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _tab {
    for (final t in bridge.tabs) {
      if (t['id'] == bridge.watching) return t;
    }
    return null;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final r = await bridge.prompt(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.ok) {
      _input.clear();
    } else {
      say(context, r.text, bad: true);
    }
  }

  Future<void> _picture(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 2200,
      imageQuality: 88,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final r = await bridge.sendImage(file.name, bytes);
    if (!mounted) return;
    say(
      context,
      r.ok ? 'Picture added. Say what to do with it, then send.' : r.text,
      bad: !r.ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = _tab;
    if (bridge.watching == null || tab == null) {
      return const _NoSession();
    }
    final terminal = bridge.terminalFor(bridge.watching!);
    final lamp = tab['lamp'] as String? ?? '';
    return Column(
      children: [
        _TopBar(tab: tab, onSwitch: () => setState(() {})),
        Expanded(
          child: Container(
            color: C.well,
            child: TerminalView(
              terminal,
              theme: loopTerminalTheme,
              textStyle: TerminalStyle(
                fontSize: bridge.fontSize,
                fontFamily: 'monospace',
                height: 1.2,
              ),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              autofocus: false,
              backgroundOpacity: 1,
              hardwareKeyboardOnly: true,
            ),
          ),
        ),
        _Keys(onKey: bridge.keys, onSlash: () => _slashSheet(context)),
        _Composer(
          input: _input,
          focus: _inputFocus,
          sending: _sending,
          busy: lamp == 'busy',
          onSend: _send,
          onImage: _picture,
          onPrompts: bridge.prompts.isEmpty
              ? null
              : () => _promptSheet(context),
        ),
      ],
    );
  }

  void _slashSheet(BuildContext context) {
    const commands = [
      ['/clear', 'Start the conversation again, keeping the session'],
      ['/compact', 'Summarise the conversation so far to free up room'],
      ['/context', 'What is filling the context window'],
      ['/cost', 'What this session has used'],
      ['/model', 'Change the model'],
      ['/agents', 'The agents this project has'],
      ['/mcp', 'The tools this session is connected to'],
      ['/status', 'Version, account and connection'],
      ['/help', 'Everything Claude Code can do'],
    ];
    showLoopSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                'Commands',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final c in commands)
              ListTile(
                dense: true,
                title: Text(
                  c[0],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: C.accent,
                  ),
                ),
                subtitle: Text(
                  c[1],
                  style: const TextStyle(color: C.text3, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  bridge.prompt(c[0]);
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _promptSheet(BuildContext context) {
    showLoopSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                'Your saved prompts',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final p in bridge.prompts)
              ListTile(
                title: Text(p['name'] as String? ?? ''),
                subtitle: Text(
                  p['text'] as String? ?? '',
                  maxLines: 2,
                  style: const TextStyle(color: C.text3, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _input.text = p['text'] as String? ?? '';
                  _inputFocus.requestFocus();
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _NoSession extends StatelessWidget {
  const _NoSession();

  @override
  Widget build(BuildContext context) {
    final tabs = bridge.tabs.where((t) => t['kind'] != 'login').toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
      children: [
        const Icon(Icons.terminal, size: 40, color: C.text3),
        const SizedBox(height: 14),
        const Text(
          'No session open here',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'Open one from Projects, or pick one Loop already has open.',
          textAlign: TextAlign.center,
          style: TextStyle(color: C.text3),
        ),
        const SizedBox(height: 20),
        for (final t in tabs)
          Card(
            color: C.panel,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: C.line),
            ),
            child: ListTile(
              leading: Lamp(t['lamp'] as String? ?? ''),
              title: Text(t['title'] as String? ?? ''),
              onTap: () => bridge.watch(t['id'] as String),
            ),
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.tab, required this.onSwitch});
  final Map<String, dynamic> tab;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final others = bridge.tabs
        .where((t) => t['id'] != tab['id'] && t['kind'] != 'login')
        .toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: const BoxDecoration(
        color: C.chrome,
        border: Border(bottom: BorderSide(color: C.line)),
      ),
      child: Row(
        children: [
          Lamp(tab['lamp'] as String? ?? ''),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tab['title'] as String? ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  (tab['server'] as String? ?? '').isEmpty
                      ? 'On ${bridge.host}'
                      : 'On a server',
                  style: const TextStyle(color: C.text3, fontSize: 11),
                ),
              ],
            ),
          ),
          if (others.isNotEmpty)
            PopupMenuButton<String>(
              color: C.panel,
              icon: const Icon(Icons.swap_horiz, color: C.text2),
              tooltip: 'Another open session',
              onSelected: (id) async {
                await bridge.watch(id);
                onSwitch();
              },
              itemBuilder: (_) => [
                for (final t in others)
                  PopupMenuItem(
                    value: t['id'] as String,
                    child: Row(
                      children: [
                        Lamp(t['lamp'] as String? ?? ''),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            t['title'] as String? ?? '',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          PopupMenuButton<String>(
            color: C.panel,
            icon: const Icon(Icons.more_vert, color: C.text2),
            onSelected: (v) async {
              if (v == 'stop') bridge.keys('\x1b');
              if (v == 'bigger') bridge.setFontSize(bridge.fontSize + 1);
              if (v == 'smaller') bridge.setFontSize(bridge.fontSize - 1);
              if (v == 'hide') bridge.unwatch();
              if (v == 'close') {
                final r = await bridge.act('close', {'tabId': tab['id']});
                bridge.unwatch();
                if (context.mounted) say(context, r.text, bad: !r.ok);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'stop',
                child: Text('Interrupt what it is doing'),
              ),
              PopupMenuItem(value: 'bigger', child: Text('Bigger text')),
              PopupMenuItem(value: 'smaller', child: Text('Smaller text')),
              PopupMenuItem(value: 'hide', child: Text('Stop showing it here')),
              PopupMenuItem(value: 'close', child: Text('Close the terminal')),
            ],
          ),
        ],
      ),
    );
  }
}

/// The keys a phone keyboard does not have, which Claude Code asks for.
class _Keys extends StatelessWidget {
  const _Keys({required this.onKey, required this.onSlash});
  final void Function(String) onKey;
  final VoidCallback onSlash;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, String data, {String? tip, bool wide = false}) =>
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Material(
            color: C.raised,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                HapticFeedback.selectionClick();
                onKey(data);
              },
              child: Container(
                constraints: BoxConstraints(minWidth: wide ? 58 : 40),
                height: 34,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12.5, color: C.text),
                ),
              ),
            ),
          ),
        );
    return Container(
      height: 46,
      color: C.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          key('Enter', '\r', wide: true),
          key('Esc', '\x1b'),
          key('Tab', '\t'),
          key('↑', '\x1b[A'),
          key('↓', '\x1b[B'),
          key('←', '\x1b[D'),
          key('→', '\x1b[C'),
          key('y', 'y'),
          key('n', 'n'),
          key('Ctrl C', '\x03', wide: true),
          key('Shift ⏎', '\x1b\r', wide: true),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Material(
              color: C.raised,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onSlash,
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: const Text(
                    '/',
                    style: TextStyle(
                      fontSize: 14,
                      color: C.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.focus,
    required this.sending,
    required this.busy,
    required this.onSend,
    required this.onImage,
    this.onPrompts,
  });
  final TextEditingController input;
  final FocusNode focus;
  final bool sending;
  final bool busy;
  final VoidCallback onSend;
  final Future<void> Function(ImageSource) onImage;
  final VoidCallback? onPrompts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        8 + MediaQuery.of(context).viewPadding.bottom / 2,
      ),
      decoration: const BoxDecoration(
        color: C.panel,
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(
              Icons.add_photo_alternate_outlined,
              color: C.text2,
            ),
            tooltip: 'Send a picture',
            onPressed: () => showLoopSheet<void>(
              context: context,
              builder: (sheetContext) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('From the gallery'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onImage(ImageSource.gallery);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_camera_outlined),
                      title: const Text('Take a photo'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onImage(ImageSource.camera);
                      },
                    ),
                    if (onPrompts != null)
                      ListTile(
                        leading: const Icon(Icons.bookmark_outline),
                        title: const Text('Your saved prompts'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          onPrompts!();
                        },
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: input,
              focusNode: focus,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: busy
                    ? 'It is working…'
                    : 'Tell this session what to do',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 44,
            width: 44,
            child: IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: C.accentInk,
              ),
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: C.accentInk,
                      ),
                    )
                  : const Icon(Icons.arrow_upward, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
