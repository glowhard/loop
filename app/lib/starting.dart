// Something to read while a session starts, and a way out of it the moment the
// session is up.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'facts.dart';
import 'theme.dart';

class StartingCard extends StatefulWidget {
  const StartingCard({super.key, required this.ready, required this.onClose});

  /// The session is up: the card offers to go away.
  final bool ready;
  final VoidCallback onClose;

  @override
  State<StartingCard> createState() => _StartingCardState();
}

class _StartingCardState extends State<StartingCard> {
  static final _rand = Random();
  static int _at = _rand.nextInt(kFacts.length); // carries on between sessions
  Timer? _turn;
  bool _forwards = true;

  @override
  void initState() {
    super.initState();
    _turn = Timer.periodic(const Duration(seconds: 9), (_) => _next());
  }

  @override
  void dispose() {
    _turn?.cancel();
    super.dispose();
  }

  void _next({bool byHand = false}) {
    if (!mounted) return;
    if (byHand) {
      HapticFeedback.selectionClick();
      _turn?.cancel();
      _turn = Timer.periodic(const Duration(seconds: 9), (_) => _next());
    }
    setState(() {
      _forwards = true;
      _at = (_at + 1) % kFacts.length;
    });
  }

  void _back() {
    HapticFeedback.selectionClick();
    setState(() {
      _forwards = false;
      _at = (_at - 1 + kFacts.length) % kFacts.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fact = kFacts[_at];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        color: C.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.ready ? C.idle : C.line),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (!widget.ready) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: C.busy,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Starting the session — something to read',
                    style: TextStyle(fontSize: 12, color: C.text3),
                  ),
                ),
              ] else
                const Expanded(
                  child: Text(
                    'Ready',
                    style: TextStyle(
                      fontSize: 12,
                      color: C.idle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Text(
                fact.tag,
                style: const TextStyle(
                  fontSize: 11,
                  color: C.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(_forwards ? 0.06 : -0.06, 0),
                    end: Offset.zero,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey(_at),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fact.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    fact.body,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: C.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _Flip(icon: Icons.chevron_left, onTap: _back),
              _Flip(
                icon: Icons.chevron_right,
                onTap: () => _next(byHand: true),
              ),
              const Spacer(),
              if (widget.ready)
                FilledButton(
                  onPressed: widget.onClose,
                  style: FilledButton.styleFrom(
                    backgroundColor: C.idle,
                    foregroundColor: C.accentInk,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 34),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: const Text(
                    'Session ready',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                )
              else
                TextButton(
                  onPressed: widget.onClose,
                  style: TextButton.styleFrom(
                    foregroundColor: C.text3,
                    minimumSize: const Size(0, 34),
                    textStyle: const TextStyle(fontSize: 12.5),
                  ),
                  child: const Text('Hide'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Flip extends StatelessWidget {
  const _Flip({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 20, color: C.text3),
      ),
    ),
  );
}
