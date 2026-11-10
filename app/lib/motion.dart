import 'package:flutter/material.dart';

import 'theme.dart';

/// Text with a soft light passing over it, for something that is happening now
/// (a tool running, Claude thinking). Calm enough to sit on screen for minutes.
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.base = C.text2,
    this.glow = C.text,
  });
  final Widget child;
  final Color base;
  final Color glow;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With motion turned off it still takes its colour, it just does not move.
    if (MediaQuery.of(context).disableAnimations) {
      return ColorFiltered(
        colorFilter: ColorFilter.mode(widget.base, BlendMode.srcIn),
        child: widget.child,
      );
    }
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value * 2.4 - 0.7;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [widget.base, widget.glow, widget.base],
            stops: [
              (t - 0.25).clamp(0.0, 1.0),
              t.clamp(0.0, 1.0),
              (t + 0.25).clamp(0.0, 1.0),
            ],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

/// How a new message arrives: a short rise and fade, once. Messages that were
/// already there when the chat opened appear without it.
class Arrive extends StatefulWidget {
  const Arrive({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<Arrive> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void initState() {
    super.initState();
    final k = widget.key;
    if (widget.enabled && _firstTime(k is ValueKey ? k.value : null)) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

/// Text that writes itself in quickly, so a reply that lands in one piece still
/// reads as Claude answering. Fast: a long answer is fully there in about a second.
/// What has already played its entrance. A list builds its rows lazily and
/// throws them away when they scroll off or when rows are added, so the same
/// message is created again; it must not arrive or type itself out twice.
final Set<Object> _played = {};
bool _firstTime(Object? id) => id == null || _played.add(id);

class TypeIn extends StatefulWidget {
  const TypeIn({
    super.key,
    required this.text,
    required this.builder,
    this.enabled = true,
    this.id,
    this.from = 0,
  });
  final String text;

  /// Characters already on screen (written while streaming): it carries on
  /// from there at the same pace rather than starting over.
  final int from;

  /// The message this is, so it types itself out only the first time.
  final Object? id;
  final Widget Function(String shown) builder;
  final bool enabled;

  @override
  State<TypeIn> createState() => _TypeInState();
}

class _TypeInState extends State<TypeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    final from = widget.from.clamp(0, widget.text.length);
    final ms = ((widget.text.length - from) * 1.6).clamp(250, 1100).toInt();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    );
    if (widget.enabled && _firstTime(widget.id)) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_c.isCompleted || MediaQuery.of(context).disableAnimations) {
      return widget.builder(widget.text);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final from = widget.from.clamp(0, widget.text.length);
        // Carrying on keeps a steady pace; starting fresh eases in.
        final t = from > 0 ? _c.value : Curves.easeOut.transform(_c.value);
        final n = (from + (widget.text.length - from) * t).round();
        // Stop at a word boundary so half-words never flash on screen.
        var cut = n;
        while (cut < widget.text.length &&
            cut > 0 &&
            widget.text[cut] != ' ' &&
            widget.text[cut] != '\n') {
          cut++;
          if (cut - n > 12) break;
        }
        return widget.builder(
          widget.text.substring(0, cut.clamp(0, widget.text.length)),
        );
      },
    );
  }
}

/// Grey bars where content is about to be, instead of a spinner.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.lines = 6});
  final int lines;

  @override
  Widget build(BuildContext context) {
    final widths = [0.62, 0.88, 0.75, 0.4, 0.82, 0.55, 0.7, 0.9];
    return Shimmer(
      base: C.raised,
      glow: C.raised2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines; i++)
              Align(
                alignment: i % 3 == 0
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: widths[i % widths.length],
                  child: Container(
                    height: i % 3 == 0 ? 38 : 14,
                    margin: EdgeInsets.only(bottom: i % 3 == 2 ? 22 : 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(i % 3 == 0 ? 16 : 6),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Seconds since a moment, ticking, in figures that do not jump about.
class Elapsed extends StatefulWidget {
  const Elapsed({super.key, required this.since, this.style});
  final DateTime since;
  final TextStyle? style;

  @override
  State<Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<Elapsed> {
  late final _tick = Stream.periodic(const Duration(seconds: 1));

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _tick,
    builder: (context, _) {
      final s = DateTime.now().difference(widget.since).inSeconds;
      final text = s < 60
          ? '${s}s'
          : '${s ~/ 60}m ${(s % 60).toString().padLeft(2, '0')}s';
      return Text(
        text,
        style: (widget.style ?? const TextStyle()).copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    },
  );
}
