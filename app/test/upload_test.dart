// A picture's progress, as the PC answers each piece and, for a server
// session, reports the copy on to the server.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/main.dart';
import 'package:loop_app/upload.dart';

void main() {
  // ~200 KB: four pieces of 64K base64 characters, plus a bit
  final photo = Uint8List(200 * 1024);

  testWidgets('to the PC: the ring follows the pieces', (t) async {
    bridge.chatOpen('demo', 'abc', '');
    final up = bridge.upload('photo.jpg', photo);
    await t.pump();
    expect(up.progress.value, 0);
    for (var i = 0; i < 5; i++) {
      bridge.hear({
        't': 'upgot',
        'up': up.id,
        'i': i,
        if (i == 4) 'token': 'phone-abc-123.jpg',
      });
      await t.pump();
      expect(up.progress.value, closeTo((i + 1) / 5, 0.001));
    }
    expect(await up.done.future, 'phone-abc-123.jpg');
    bridge.chatClose();
  });

  testWidgets('to a server: the last part is the copy there', (t) async {
    bridge.chatOpen('srv-x-proj', 'abc', 'x');
    final up = bridge.upload('photo.jpg', photo);
    for (var i = 0; i < 5; i++) {
      bridge.hear({
        't': 'upgot',
        'up': up.id,
        'i': i,
        if (i == 4) ...{'token': 'phone-abc-123.jpg', 'far': true},
      });
      await t.pump();
    }
    expect(up.progress.value, closeTo(0.6, 0.001)); // at the PC, not yet there
    expect(up.done.isCompleted, false);
    bridge.hear({'t': 'upfar', 'up': up.id, 'p': 0.5});
    expect(up.progress.value, closeTo(0.8, 0.001));
    bridge.hear({'t': 'upfar', 'up': up.id, 'p': 1, 'done': true});
    expect(up.progress.value, 1);
    expect(await up.done.future, 'phone-abc-123.jpg');
    bridge.chatClose();
  });

  testWidgets('a failure shows on the ring and stops the message', (t) async {
    bridge.chatOpen('demo', 'abc', '');
    final up = bridge.upload('photo.jpg', photo);
    bridge.hear({'t': 'upgot', 'up': up.id, 'i': 0, 'failed': 'Too big.'});
    await t.pump();
    expect(up.progress.value, lessThan(0));
    expect(await up.done.future, isNull);
    expect(up.error, 'Too big.');
    await t.pumpWidget(
      MaterialApp(
        home: SizedBox(width: 80, height: 80, child: UploadRing(upload: up)),
      ),
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    bridge.chatClose();
  });

  testWidgets('the ring fills, then goes', (t) async {
    final up = Upload('a.jpg', photo);
    await t.pumpWidget(
      MaterialApp(
        home: SizedBox(width: 80, height: 80, child: UploadRing(upload: up)),
      ),
    );
    up.progress.value = 0.5;
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final ring = t.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, closeTo(0.5, 0.01));
    up.finish('x');
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final fade = t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(fade.opacity, 0);
  });
}
