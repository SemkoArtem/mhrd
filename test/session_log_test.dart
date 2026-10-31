import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/sessions/rdp_session.dart';
import 'package:mhrd/sessions/session_log.dart';
import 'package:mhrd/sessions/session_protocol.dart';

import 'session_test.dart' show FakeChannel, pc, settle, u32s;

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('mhrd-log'));
  tearDown(() => dir.delete(recursive: true));

  test('запис: ПК, причина й код; старші за 7 днів файли видаляються, чужі — ні', () async {
    final now = DateTime(2026, 10, 31, 5, 12, 3);
    File('${dir.path}/session-2026-10-24.log').writeAsStringSync('old'); // 8-й день тому
    File('${dir.path}/session-2026-10-25.log').writeAsStringSync('keep'); // 7-й — лишається
    File('${dir.path}/notes.txt').writeAsStringSync('mine');

    final ch = FakeChannel();
    final s = RdpSession(id: '1', connection: pc(), channel: ch, openFrameBuffer: (_, __) => null)
      ..start({'password': 'секрет'});
    ch.emit(Msg.evtDisconnected, [DisconnectReason.network.index, ...u32s([0x2000d]), ...'timeout'.codeUnits]);
    ch.exit.complete(0);
    await s.done;
    await settle();

    await SessionLog(dir, clock: () => now).write(s);
    final text = File('${dir.path}/session-2026-10-31.log').readAsStringSync();
    expect(text, contains('2026-10-31 05:12:03'));
    expect(text, contains('Офіс (10.0.0.5:3389)'));
    expect(text, contains('network 0x2000d'));
    expect(text, contains('timeout'));
    expect(text, isNot(contains('секрет')));
    expect(File('${dir.path}/session-2026-10-24.log').existsSync(), isFalse);
    expect(File('${dir.path}/session-2026-10-25.log').existsSync(), isTrue);
    expect(File('${dir.path}/notes.txt').existsSync(), isTrue);
  });
}
