// Messages written while the PC is unreachable: kept, saved, and sent in order
// the moment it answers.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/bridge.dart';
import 'package:loop_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bridge.outbox.clear();
    bridge.disconnect(); // no leftover sending from another test
  });

  testWidgets('kept while away, then sent oldest first', (t) async {
    bridge.queue(
      dir: 'd',
      sessionId: 's1',
      server: '',
      title: 'Demo',
      text: 'first',
    );
    bridge.queue(
      dir: 'd',
      sessionId: 's1',
      server: '',
      title: 'Demo',
      text: 'second',
    );
    bridge.queue(
      dir: 'd',
      sessionId: 's2',
      server: '',
      title: 'Other',
      text: 'elsewhere',
    );
    expect(bridge.waitingFor('s1').map((w) => w.text), ['first', 'second']);
    expect(bridge.waitingFor('s2').length, 1);

    // it is written down, so closing the app does not lose it
    await t.pump();
    final kept =
        jsonDecode(
              (await SharedPreferences.getInstance()).getString('outbox') ??
                  '[]',
            )
            as List;
    expect(kept.length, 3);
    expect((kept.first as Map)['text'], 'first');

    // the PC answers: they go by themselves, oldest first
    bridge.hear({'t': 'ready', 'host': 'PC', 'window': true});
    await t.pump();
    expect(bridge.outbox.first.sending, true, reason: 'the first one is going');
    expect(bridge.outbox.first.text, 'first');
    // Each session takes one at a time, so the answers come in rounds; the
    // request's own number is not known here, so the whole range is answered.
    for (var round = 0; round < 4; round++) {
      for (var id = 1; id <= 25; id++) {
        bridge.hear({'t': 'done', 'id': id, 'ok': true});
        await t.pump();
      }
      bridge.hear({
        't': 'state',
        's': {'running': const []},
      });
      await t.pump();
    }
    expect(bridge.outbox, isEmpty);
    expect(
      jsonDecode(
        (await SharedPreferences.getInstance()).getString('outbox') ?? '[]',
      ),
      isEmpty,
    );
  });

  testWidgets('one the PC will not take says why and stays', (t) async {
    bridge.queue(
      dir: 'd',
      sessionId: 's1',
      server: '',
      title: 'Demo',
      text: 'first',
    );
    bridge.queue(
      dir: 'd',
      sessionId: 's1',
      server: '',
      title: 'Demo',
      text: 'second',
    );
    bridge.hear({'t': 'ready', 'host': 'PC', 'window': true});
    await t.pump();
    for (var id = 1; id <= 20; id++) {
      bridge.hear({
        't': 'done',
        'id': id,
        'ok': false,
        'text': 'That project folder is gone.',
      });
      await t.pump();
      await t.pump();
    }
    expect(bridge.outbox.length, 2, reason: 'nothing is thrown away');
    expect(bridge.outbox.first.why, 'That project folder is gone.');
    expect(bridge.outbox.first.sending, false);
    // and you can take it off the list yourself
    bridge.unqueue(bridge.outbox.first.id);
    expect(bridge.outbox.length, 1);
  });

  testWidgets('a message sent while it is working waits its turn', (t) async {
    void live(List<Map<String, String>> running) {
      bridge.hear({
        't': 'state',
        's': {'running': running},
      });
    }

    bridge.hear({'t': 'ready', 'host': 'PC', 'window': true});
    live([
      {'id': 's1', 'lamp': 'busy'},
    ]);
    expect(bridge.busyNow('s1'), true);
    expect(bridge.busyNow('s2'), false);

    bridge.queue(
      dir: 'd',
      sessionId: 's1',
      server: '',
      title: 'Demo',
      text: 'after you',
      afterTurn: true,
    );
    await t.pump();
    // it is working: nothing is sent yet
    expect(bridge.outbox.single.sending, false);
    for (var id = 1; id <= 20; id++) {
      bridge.hear({'t': 'done', 'id': id, 'ok': true});
    }
    await t.pump();
    expect(bridge.outbox.length, 1, reason: 'still waiting its turn');

    // the answer finishes, so it goes
    live([
      {'id': 's1', 'lamp': 'idle'},
    ]);
    await t.pump();
    expect(bridge.outbox.single.sending, true);
    for (var id = 1; id <= 20; id++) {
      bridge.hear({'t': 'done', 'id': id, 'ok': true});
      await t.pump();
    }
    expect(bridge.outbox, isEmpty);
  });

  testWidgets('two for one session go one at a time, in order', (t) async {
    bridge.hear({'t': 'ready', 'host': 'PC', 'window': true});
    bridge.hear({
      't': 'state',
      's': {
        'running': [
          {'id': 's1', 'lamp': 'idle'},
        ],
      },
    });
    for (final word in ['one', 'two']) {
      bridge.queue(
        dir: 'd',
        sessionId: 's1',
        server: '',
        title: 'Demo',
        text: word,
        afterTurn: true,
      );
    }
    await t.pump();
    expect(bridge.outbox.first.text, 'one');
    expect(bridge.outbox.first.sending, true);
    expect(bridge.outbox.last.sending, false, reason: 'the second one waits');
    for (var id = 1; id <= 20; id++) {
      bridge.hear({'t': 'done', 'id': id, 'ok': true});
      await t.pump();
    }
    expect(bridge.outbox.single.text, 'two', reason: 'one at a time');
  });

  test('what was waiting comes back after the app is closed', () async {
    bridge.queue(
      dir: 'd',
      sessionId: 's1',
      server: 'srv',
      title: 'Demo',
      text: 'still here',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final saved = (await SharedPreferences.getInstance()).getString('outbox');
    bridge.outbox.clear();
    SharedPreferences.setMockInitialValues({'outbox': saved!});
    await bridge.load();
    expect(bridge.outbox.length, 1);
    expect(bridge.outbox.first.text, 'still here');
    expect(bridge.outbox.first.server, 'srv');
  });

  test('a message read back keeps its pictures', () {
    final w = Waiting(
      id: '1',
      dir: 'd',
      sessionId: 's',
      server: '',
      title: 'T',
      text: 'look',
      pictures: [
        (name: 'a.png', bytes: Uint8List.fromList([1, 2, 3])),
      ],
    );
    final back = Waiting.fromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    expect(back.text, 'look');
    expect(back.pictures.single.name, 'a.png');
    expect(back.pictures.single.bytes, [1, 2, 3]);
  });
}
