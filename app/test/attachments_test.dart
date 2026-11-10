// A message with pictures: the words on top, the pictures in one row under it
// that scrolls sideways, each opening whole when tapped.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/chat.dart';
import 'package:loop_app/main.dart';

// a 1x1 png
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('words first, then a row of pictures', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const MaterialApp(
        home: ChatPage(dir: 'demo', sessionId: 'abc', title: 'Demo'),
      ),
    );
    await t.pump();
    bridge.chatLoaded = true;
    bridge.chatLive = {'lamp': 'idle'};
    bridge.chatItems
      ..clear()
      ..add({
        'k': 'user',
        'id': 'u1',
        'text': 'whats inside these',
        'pending': true,
        'images': [
          for (var i = 0; i < 6; i++) {'bytes': Uint8List.fromList(_png)},
        ],
      });
    bridge.chatVersion++;
    bridge.notifyListeners();
    await t.pump(const Duration(milliseconds: 600));

    final words = t.getRect(find.text('whats inside these'));
    final pics = find.byType(Image);
    expect(pics, findsWidgets);
    final first = t.getRect(pics.first);
    expect(
      first.top,
      greaterThan(words.bottom),
      reason: 'pictures sit under the words',
    );
    expect(first.width, 84);
    // one row: every picture shown sits at the same height
    for (final e in pics.evaluate()) {
      expect(t.getRect(find.byWidget(e.widget)).top, first.top);
    }
    // the row scrolls sideways
    final row = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    );
    expect(row, findsOneWidget);

    // a tap opens it whole, a tap closes it
    await t.tap(pics.hitTestable().first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(find.byType(InteractiveViewer), findsOneWidget);
    await t.tap(find.byIcon(Icons.close));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(InteractiveViewer), findsNothing);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
