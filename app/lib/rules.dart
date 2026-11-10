import 'package:flutter/material.dart';

import 'main.dart';
import 'theme.dart';

/// The rules the teams work by, and where they come from.
///
/// One company, one set of rules: the user writes them here, the CEO may
/// rewrite them with its own tool, and nobody else may touch them. A project
/// adds its own on top, a single member can be given extra, and the clock says
/// how long the CEO leaves a quiet team alone before asking for an update.
/// While the company box is empty the teams work by the rules Loop ships with,
/// which are shown underneath so nothing is a mystery.
Future<void> showRules(BuildContext context, String dir) async {
  final r = await bridge.act('rules', {'dir': dir});
  if (!context.mounted) return;
  final d = r.data ?? const {};
  final wide = MediaQuery.of(context).size.width >= 760;
  final body = _RulesView(
    dir: dir,
    house: d['house'] as String? ?? '',
    company: d['rules'] as String? ?? '',
    project: d['policy'] as String? ?? '',
    mins: (d['mins'] as num?)?.toInt() ?? 30,
    inForce: (d['inForce'] as num?)?.toInt() ?? 30,
  );
  if (wide) {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: C.panel,
        insetPadding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
          child: body,
        ),
      ),
    );
    return;
  }
  await showLoopSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
      child: FractionallySizedBox(heightFactor: 0.92, child: body),
    ),
  );
}

/// Rules for one member alone, on top of the company's and the project's.
Future<void> showMemberRules(
  BuildContext context,
  String dir,
  Map<String, dynamic> session,
) async {
  final r = await bridge.act('rules', {'dir': dir});
  if (!context.mounted) return;
  final id = session['id'] as String? ?? '';
  final name = session['title'] as String? ?? 'this member';
  final had = ((r.data?['memberRules'] ?? const {}) as Map)[id] as String? ?? '';
  final box = TextEditingController(text: had);
  final save = await showLoopSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Rules for $name',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Only this member reads them, on top of the company rules and '
                'the project rules.',
                style: TextStyle(fontSize: 12.5, color: C.text3),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: box,
                minLines: 3,
                maxLines: 8,
                autofocus: true,
                style: const TextStyle(fontSize: 13.5, height: 1.45),
                decoration: const InputDecoration(
                  hintText:
                      'For example: ask the CTO before adding a dependency.',
                  hintStyle: TextStyle(fontSize: 13, color: C.text3),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(sheet, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheet, true),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (save != true || !context.mounted) return;
  final out = await bridge.act('policy', {
    'dir': dir,
    'scope': 'member',
    'session': name,
    'text': box.text,
  });
  if (!context.mounted) return;
  say(context, out.text ?? 'Saved.', bad: !out.ok);
}

class _RulesView extends StatefulWidget {
  const _RulesView({
    required this.dir,
    required this.house,
    required this.company,
    required this.project,
    required this.mins,
    required this.inForce,
  });
  final String dir;
  final String house;
  final String company;
  final String project;
  final int mins;
  final int inForce;

  @override
  State<_RulesView> createState() => _RulesViewState();
}

class _RulesViewState extends State<_RulesView> {
  late final _company = TextEditingController(text: widget.company);
  late final _project = TextEditingController(text: widget.project);
  late int _mins = widget.mins;
  bool _showHouse = false;
  bool _saving = false;

  @override
  void dispose() {
    _company.dispose();
    _project.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final notes = <String>[];
    if (_company.text.trim() != widget.company.trim() || _mins != widget.mins) {
      final r = await bridge.act('policy', {
        'dir': widget.dir,
        'scope': 'company',
        'text': _company.text,
        'mins': _mins,
      });
      notes.add(r.text ?? '');
    }
    if (_project.text.trim() != widget.project.trim()) {
      final r = await bridge.act('policy', {
        'dir': widget.dir,
        'scope': 'project',
        'text': _project.text,
      });
      notes.add(r.text ?? '');
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final said = notes.where((x) => x.isNotEmpty).join(' ').trim();
    Navigator.pop(context);
    say(context, said.isEmpty ? 'Nothing changed.' : said);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Rules',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                  color: C.text3,
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              children: [
                const _Head(
                  'The company',
                  'Every team on this machine works by these. You and the CEO '
                      'set them; no other member may.',
                ),
                TextField(
                  controller: _company,
                  minLines: 4,
                  maxLines: 12,
                  style: const TextStyle(fontSize: 13.5, height: 1.45),
                  decoration: const InputDecoration(
                    hintText:
                        'Leave this empty to use the rules Loop ships with.',
                    hintStyle: TextStyle(fontSize: 13, color: C.text3),
                  ),
                ),
                const SizedBox(height: 10),
                _Clock(
                  mins: _mins,
                  onChanged: (n) => setState(() => _mins = n),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _showHouse = !_showHouse),
                    style: TextButton.styleFrom(
                      foregroundColor: C.text3,
                      textStyle: const TextStyle(fontSize: 12),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(
                      _showHouse
                          ? 'Hide the rules Loop ships with'
                          : 'Read the rules Loop ships with',
                    ),
                  ),
                ),
                if (_showHouse)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: C.well,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: C.line),
                    ),
                    child: Text(
                      widget.house,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: C.text2,
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                const _Head(
                  'This project',
                  'Added on top of the company rules, for this project only.',
                ),
                TextField(
                  controller: _project,
                  minLines: 3,
                  maxLines: 10,
                  style: const TextStyle(fontSize: 13.5, height: 1.45),
                  decoration: const InputDecoration(
                    hintText:
                        'For example: never deploy on a Friday. Ask before '
                        'touching the database.',
                    hintStyle: TextStyle(fontSize: 13, color: C.text3),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.title, this.about);
  final String title;
  final String about;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          about,
          style: const TextStyle(fontSize: 12, height: 1.4, color: C.text3),
        ),
      ],
    ),
  );
}

/// How long the CEO leaves a quiet team alone before asking the project manager
/// for an update. Off means nobody is chased.
class _Clock extends StatelessWidget {
  const _Clock({required this.mins, required this.onChanged});
  final int mins;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const steps = [0, 15, 30, 45, 60, 120];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          mins == 0
              ? 'The CEO is not asked to chase updates.'
              : 'The CEO asks for an update after $mins minutes of quiet.',
          style: const TextStyle(fontSize: 12.5, color: C.text2),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in steps)
              ChoiceChip(
                label: Text(n == 0 ? 'Off' : '$n min'),
                selected: n == mins,
                onSelected: (_) => onChanged(n),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: n == mins ? C.accentInk : C.text2,
                ),
                selectedColor: C.accent,
                backgroundColor: C.raised,
                side: BorderSide(color: n == mins ? C.accent : C.line),
                showCheckmark: false,
              ),
          ],
        ),
      ],
    );
  }
}
