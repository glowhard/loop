// A picture on its way to the PC (and, for a server session, on to the
// server), with how far along it is for the ring drawn over it.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class Upload {
  Upload(this.name, this.bytes)
    : id = List.generate(
        12,
        (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_rand.nextInt(36)],
      ).join();
  static final _rand = Random();

  final String id;
  final String name;
  final Uint8List bytes;

  /// 0 to 1 while on its way, 1 once there, below 0 if it failed.
  final progress = ValueNotifier<double>(0);
  String? error;
  final done = Completer<String?>(); // the PC's name for it, or null

  void fail(String why) {
    if (done.isCompleted) return;
    error = why;
    progress.value = -1;
    done.complete(null);
  }

  void finish(String token) {
    if (done.isCompleted) return;
    progress.value = 1;
    done.complete(token);
  }
}

/// Drawn over a picture: a ring filling up while it goes, gone once it is there.
class UploadRing extends StatelessWidget {
  const UploadRing({super.key, required this.upload, this.size = 30});
  final Upload upload;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: upload.progress,
      builder: (context, p, _) {
        final there = p >= 1;
        return IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: there ? 0 : 1,
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
              alignment: Alignment.center,
              child: p < 0
                  ? const Icon(
                      Icons.error_outline,
                      color: Color(0xFFEE7B6C),
                      size: 24,
                    )
                  : SizedBox(
                      width: size,
                      height: size,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: p.clamp(0.03, 1.0)),
                        duration: const Duration(milliseconds: 200),
                        builder: (context, v, _) => CircularProgressIndicator(
                          value: v,
                          strokeWidth: 3,
                          strokeCap: StrokeCap.round,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}
