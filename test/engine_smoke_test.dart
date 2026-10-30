import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/sessions/rdp_session.dart';
import 'package:mhrd/sessions/session_protocol.dart';

/// Справжній mhrd-session.exe без сервера RDP: перевіряє канал, журнали (не в stdout!)
/// і поведінку при помилках. Пропускається, якщо модуль не зібрано (native/session/build.ps1).
const _exe = 'native/session/out/mhrd-session.exe';
final Object _skip = Platform.isWindows && File(_exe).existsSync() ? false : 'mhrd-session.exe не зібрано';

Future<(List<SessionEvent>, int)> _run(Map<String, Object?>? config, {bool closeInput = false}) async {
  final ch = await ProcessChannel.start(File(_exe).absolute.path);
  final events = <SessionEvent>[];
  final sub = ch.output.transform(const SessionEventDecoder()).listen(events.add);
  if (config != null) ch.send(encodeConnect(config));
  if (closeInput) ch.closeInput();
  final code = await ch.exitCode.timeout(const Duration(seconds: 30), onTimeout: () {
    ch.kill();
    return -1;
  });
  await sub.cancel();
  return (events, code);
}

void main() {
  test('порт без RDP → «мережа», процес завершується сам', () async {
    final (events, code) = await _run({'host': '127.0.0.1', 'port': 1, 'username': 'u', 'password': 'p'}, closeInput: false);
    final ended = events.whereType<DisconnectedEvent>().single;
    expect(ended.reason, DisconnectReason.network, reason: '${ended.code}: ${ended.details}');
    expect(code, isNot(-1), reason: 'процес мав завершитись сам');
  }, skip: _skip);

  test('без адреси — зрозуміла відмова, не падіння', () async {
    final (events, code) = await _run({'port': 3389});
    expect(events.whereType<DisconnectedEvent>(), hasLength(1));
    expect(code, 2);
  }, skip: _skip);

  test('застосунок закрився до підключення — процес не висить', () async {
    final (events, code) = await _run(null, closeInput: true);
    expect(events, isEmpty);
    expect(code, 0);
  }, skip: _skip);
}
