import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'voice.dart';

/// What the mic sheet gave back: words to send, or a wish to type instead.
class Said {
  const Said(this.text, {this.typeInstead = false});
  final String text;
  final bool typeInstead;
}

/// The one mic sheet: a goal, a change to a plan, an answer to a question.
/// It listens the moment it opens, and nothing is sent without one tap on
/// Send, because a goal costs tokens.
Future<Said?> askByVoice(BuildContext context, {required String title}) {
  return showModalBottomSheet<Said>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _MicSheet(title: title),
  ).whenComplete(() => Voice.I.stop());
}

class _MicSheet extends StatefulWidget {
  const _MicSheet({required this.title});
  final String title;

  @override
  State<_MicSheet> createState() => _MicSheetState();
}

class _MicSheetState extends State<_MicSheet> {
  final _edit = TextEditingController();
  bool _review = false;
  Timer? _clock;
  int _secs = 0;

  @override
  void initState() {
    super.initState();
    Voice.I.listening.addListener(_onListening);
    _start();
  }

  void _start() {
    setState(() {
      _review = false;
      _secs = 0;
    });
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secs++);
    });
    Voice.I.listen();
  }

  void _onListening() {
    if (Voice.I.listening.value || !mounted) return;
    _clock?.cancel();
    final words = Voice.I.heard.value.trim();
    if (words.isNotEmpty) {
      _edit.text = words;
      setState(() => _review = true);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    Voice.I.listening.removeListener(_onListening);
    _clock?.cancel();
    _edit.dispose();
    super.dispose();
  }

  String get _langShort => switch (Voice.I.lang.value) {
    'hi-IN' => 'हिं',
    'pa-IN' => 'ਪੰ',
    _ => 'EN',
  };

  Future<void> _nextLang() async {
    final codes = Voice.langs.map((l) => l[0]).toList();
    final i = codes.indexOf(Voice.I.lang.value);
    await Voice.I.setLang(codes[(i + 1) % codes.length]);
    if (!mounted) return;
    if (!_review) {
      await Voice.I.stop();
      _start();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + bottom),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<String>(
          valueListenable: Voice.I.problem,
          // In trouble the sheet is only as tall as what it says.
          builder: (context, problem, _) => SizedBox(
          height: problem.isNotEmpty && !_review ? null : 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.text),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _nextLang,
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: C.raised, borderRadius: BorderRadius.circular(14)),
                      child: Text(_langShort, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.text)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (problem.isNotEmpty && !_review) _listenBody() else Expanded(child: _review ? _reviewBody() : _listenBody()),
              SizedBox(height: problem.isNotEmpty && !_review ? 24 : 12),
              _review
                  ? _reviewButtons()
                  : ValueListenableBuilder<String>(
                      valueListenable: Voice.I.problem,
                      builder: (context, problem, _) => problem.isEmpty ? _listenButtons() : _errorButtons(problem),
                    ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _listenBody() {
    return ValueListenableBuilder<String>(
      valueListenable: Voice.I.problem,
      builder: (context, problem, _) {
        if (problem.isNotEmpty) return _problem(problem);
        return ValueListenableBuilder<String>(
          valueListenable: Voice.I.heard,
          builder: (context, heard, _) => SingleChildScrollView(
            reverse: true,
            child: Text(
              heard.isEmpty ? 'Listening…' : heard,
              style: TextStyle(fontSize: 18, height: 1.4, color: heard.isEmpty ? C.text3 : C.text),
            ),
          ),
        );
      },
    );
  }

  Widget _problem(String problem) {
    final noMic = problem.contains('microphone') || problem.contains('cannot listen');
    final noLang = problem.contains('language');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(noMic ? Icons.mic_off : Icons.hearing_disabled, size: 28, color: noMic ? C.danger : C.text3),
        const SizedBox(height: 8),
        Text(problem, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.text2, height: 1.35)),
        const SizedBox(height: 14),
        if (!noLang && !noMic) _Pill('Try again', _start),
      ],
    );
  }

  // In trouble, the big mic and the clock go: they look live. The way out is the main button.
  Widget _errorButtons(String problem) {
    final noLang = problem.contains('language');
    return Row(
      children: [
        _Round(icon: Icons.close, size: 48, bg: C.raised, fg: C.text, onTap: () => Navigator.pop(context)),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: noLang
                  ? () async {
                      await Voice.I.setLang('en-IN');
                      _start();
                    }
                  : () => Navigator.pop(context, const Said('', typeInstead: true)),
              child: Text(noLang ? 'Use English' : 'Type instead', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.accentInk)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _listenButtons() {
    final t = '${_secs ~/ 60}:${(_secs % 60).toString().padLeft(2, '0')}';
    return Row(
      children: [
        _Round(icon: Icons.close, size: 48, bg: C.raised, fg: C.text, onTap: () => Navigator.pop(context)),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: Voice.I.listening,
                builder: (context, on, _) => _Round(
                  icon: on ? Icons.stop : Icons.mic,
                  size: 72,
                  bg: C.accent,
                  fg: C.accentInk,
                  onTap: on ? Voice.I.stop : _start,
                ),
              ),
              const SizedBox(height: 6),
              Text(t, style: const TextStyle(fontSize: 13, color: C.text3, fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _reviewBody() {
    return TextField(
      controller: _edit,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontSize: 17, height: 1.4, color: C.text),
      decoration: const InputDecoration(border: InputBorder.none, filled: false, isCollapsed: true),
    );
  }

  Widget _reviewButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.mic, size: 18),
              label: const Text('Redo'),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () {
                final words = _edit.text.trim();
                if (words.isEmpty) return;
                HapticFeedback.lightImpact();
                Navigator.pop(context, Said(words));
              },
              child: const Text('Send'),
            ),
          ),
        ),
      ],
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.size, required this.bg, required this.fg, required this.onTap});
  final IconData icon;
  final double size;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: bg,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(width: size, height: size, child: Icon(icon, size: size * 0.44, color: fg)),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(onPressed: onTap, child: Text(label));
}

/// A button for something that cannot be undone: press and hold 700 ms while
/// a fill sweeps across, so a pocket tap never goes live, pays or deletes.
class HoldButton extends StatefulWidget {
  const HoldButton({super.key, required this.label, required this.onHeld, this.primary = true, this.height = 48});
  final String label;
  final VoidCallback onHeld;
  final bool primary;
  final double height;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> with SingleTickerProviderStateMixin {
  late final _fill = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  bool _hint = false;
  Timer? _hintOff;

  @override
  void initState() {
    super.initState();
    _fill.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.mediumImpact();
        widget.onHeld();
        _fill.reset();
      }
    });
  }

  @override
  void dispose() {
    _fill.dispose();
    _hintOff?.cancel();
    super.dispose();
  }

  void _showHint() {
    setState(() => _hint = true);
    _hintOff?.cancel();
    _hintOff = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.primary ? C.accentInk : C.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: _showHint,
          onTapDown: (_) => _fill.forward(),
          onTapUp: (_) {
            if (!_fill.isCompleted) _fill.reverse();
          },
          onTapCancel: () {
            if (!_fill.isCompleted) _fill.reverse();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: widget.height,
              child: AnimatedBuilder(
                animation: _fill,
                builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: widget.primary ? C.accent : C.raised),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _fill.value,
                      child: Container(color: (widget.primary ? C.accentInk : C.accent).withValues(alpha: 0.35)),
                    ),
                    Center(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: widget.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
                            TextSpan(text: ' · hold', style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_hint)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Hold to confirm', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.text3)),
          ),
      ],
    );
  }
}
