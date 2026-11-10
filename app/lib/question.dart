// A question Claude asks with its question tool, answered the way the Claude
// app does it: tap to choose (several, where it allows that), or type your own,
// then Next. Skip leaves the question unanswered and moves on.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'theme.dart';

class QuestionCard extends StatefulWidget {
  const QuestionCard({super.key, required this.ask, required this.onAnswer});
  final Map<String, dynamic> ask;

  /// keys: the options' numbers, comma separated; 'skip'; or '' with words.
  final void Function(String keys, String words) onAnswer;

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  final Set<String> _chosen = {};
  final _words = TextEditingController();
  final _focus = FocusNode();
  bool _typing = false;
  bool _sent = false; // waiting for the next question, or for Claude

  bool get _multi => widget.ask['multi'] == true;
  int get _at => (widget.ask['at'] as num?)?.toInt() ?? 1;
  int get _of => (widget.ask['of'] as num?)?.toInt() ?? 1;
  bool get _ready =>
      _typing ? _words.text.trim().isNotEmpty : _chosen.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _words.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _words.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _choose(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      _typing = false;
      if (_multi) {
        if (!_chosen.remove(key)) _chosen.add(key);
      } else {
        _chosen
          ..clear()
          ..add(key);
      }
    });
    _focus.unfocus();
  }

  void _typeOwn() {
    HapticFeedback.selectionClick();
    setState(() {
      _typing = true;
      _chosen.clear();
    });
    _focus.requestFocus();
  }

  void _send(String keys, String words) {
    if (_sent) return;
    HapticFeedback.lightImpact();
    setState(() => _sent = true);
    _focus.unfocus();
    widget.onAnswer(keys, words);
  }

  void _next() {
    if (!_ready) return;
    if (_typing) {
      _send('', _words.text.trim());
    } else {
      final keys = _chosen.toList()
        ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
      _send(keys.join(','), '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = ((widget.ask['options'] ?? const []) as List).cast<Map>();
    final header = widget.ask['header'] as String? ?? '';
    final last = _at >= _of;
    return Arrive(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        decoration: BoxDecoration(
          color: C.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.lineStrong),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: _sent ? 0.55 : 1,
          child: IgnorePointer(
            ignoring: _sent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (header.isNotEmpty)
                      Text(
                        header,
                        style: const TextStyle(
                          fontSize: 12,
                          color: C.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const Spacer(),
                    if (_of > 1)
                      Text(
                        '$_at of $_of',
                        style: const TextStyle(fontSize: 12, color: C.text3),
                      ),
                  ],
                ),
                if (header.isNotEmpty || _of > 1) const SizedBox(height: 6),
                Text(
                  widget.ask['question'] as String? ?? 'Claude is asking',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                if (_multi)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      'Choose any that apply',
                      style: TextStyle(fontSize: 12, color: C.text2),
                    ),
                  ),
                const SizedBox(height: 4),
                for (final o in options) _option(o),
                _own(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _send('skip', ''),
                      style: TextButton.styleFrom(
                        foregroundColor: C.text2,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: const Text('Skip'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _ready ? _next : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: C.accent,
                        foregroundColor: C.accentInk,
                        disabledBackgroundColor: C.raised,
                        disabledForegroundColor: C.text3,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        last ? 'Submit' : 'Next',
                        style: const TextStyle(fontWeight: FontWeight.w600),
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

  Widget _box({required bool on, required Widget child, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: on ? C.accent.withValues(alpha: 0.14) : C.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: on ? C.accent : C.line, width: on ? 1.4 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }

  Widget _mark(bool on) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: on ? C.accent : Colors.transparent,
        shape: _multi ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: _multi ? BorderRadius.circular(5) : null,
        border: Border.all(color: on ? C.accent : C.text3, width: 1.6),
      ),
      child: on ? const Icon(Icons.check, size: 14, color: C.accentInk) : null,
    );
  }

  Widget _option(Map o) {
    final key = o['key'] as String? ?? '';
    final label = o['label'] as String? ?? '';
    final desc = o['desc'] as String? ?? '';
    final on = _chosen.contains(key);
    return _box(
      on: on,
      onTap: () => _choose(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: _mark(on)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: C.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (desc.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        desc,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: C.text2,
                          height: 1.35,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _own() {
    return _box(
      on: _typing,
      onTap: _typing ? null : _typeOwn,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.edit_outlined,
              size: 18,
              color: _typing ? C.accent : C.text3,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _typing
                  ? TextField(
                      controller: _words,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _next(),
                      style: const TextStyle(fontSize: 14.5, color: C.text),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Type your answer',
                        hintStyle: TextStyle(color: C.text3),
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    )
                  : const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Type your own answer',
                        style: TextStyle(fontSize: 14.5, color: C.text2),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
