// Which way the app goes to reach a PC: the short way straight to it, and the
// relay when that cannot be reached.
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/bridge.dart';
import 'package:loop_app/main.dart';

void main() {
  tearDown(() => bridge.disconnect());

  test('a PC with both is tried the short way first', () {
    final c = Conn(
      name: 'Desk',
      host: 'loop.example.com',
      port: 443,
      code: 'abcd-efgh-jkmn',
      secure: true,
      key: 'a-very-long-space-key-aaaaaaaaaaaa',
      direct: 'desk.tail1234.ts.net:8788',
    );
    bridge.connect(c);
    expect(bridge.viaRelay, false, reason: 'the short way is tried first');
  });

  test('with no short way it goes straight to the relay', () {
    bridge.connect(
      Conn(
        name: 'Desk',
        host: 'loop.example.com',
        port: 443,
        code: 'abcd-efgh-jkmn',
        key: 'a-very-long-space-key-aaaaaaaaaaaa',
      ),
    );
    expect(bridge.viaRelay, true);
  });

  test('what a PC is remembered by survives being written down', () {
    final c = Conn(
      name: 'Desk',
      host: 'loop.example.com',
      port: 443,
      code: 'abcd-efgh-jkmn',
      secure: true,
      key: 'space-key',
      direct: 'desk.tail1234.ts.net:8788',
    );
    final back = Conn.fromJson(c.toJson());
    expect(back.key, c.key);
    expect(back.direct, c.direct);
    expect(back.secure, true);
    expect(back.code, c.code);
  });
}
