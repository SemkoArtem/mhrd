import 'dart:io';
import 'dart:typed_data';

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
    // Саме відмова з'єднання, а не «DNS» (0x20004/0x20005): IP-адресу не треба шукати в DNS.
    // Так виглядала помилка без WSAStartup на Windows.
    expect(ended.code, isNot(anyOf(0x20004, 0x20005)), reason: ended.details);
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

  /// Сирі байти в stdin процесу (зламаний канал), потім чекаємо завершення.
  Future<int> runRaw(List<int> bytes) async {
    final ch = await ProcessChannel.start(File(_exe).absolute.path);
    final sub = ch.output.listen((_) {});
    ch.send(Uint8List.fromList(bytes));
    final code = await ch.exitCode.timeout(const Duration(seconds: 20), onTimeout: () {
      ch.kill();
      return -1;
    });
    await sub.cancel();
    return code;
  }

  test('зламаний канал (кадр нульової довжини чи на 2 ГБ) — процес завершується, а не висить і не падає', () async {
    expect(await runRaw([0, 0, 0, 0, 1]), 0);
    expect(await runRaw([0, 0, 0, 0x80, 1, 1, 2, 3]), 0);
  }, skip: _skip);

  test('зламаний JSON налаштувань — зрозуміла відмова', () async {
    final ch = await ProcessChannel.start(File(_exe).absolute.path);
    final events = <SessionEvent>[];
    final sub = ch.output.transform(const SessionEventDecoder()).listen(events.add);
    ch.send(encodeFrame(Msg.connect, '{"host": "10.0.0.1", "port": '.codeUnits));
    final code = await ch.exitCode.timeout(const Duration(seconds: 20), onTimeout: () {
      ch.kill();
      return -1;
    });
    await sub.cancel();
    expect(code, 2);
    expect(events.whereType<DisconnectedEvent>(), hasLength(1));
  }, skip: _skip);

  test('власне вікно, ПК недоступний — процес закривається сам, а не висить невидимим', () async {
    final (events, code) = await _run({
      'host': '127.0.0.1',
      'port': 1,
      'username': 'u',
      'password': 'p',
      'nativeWindow': true,
      'title': 'test',
      'bar': {'edge': 9, 'pos': -5, 'length': 99999}, // зламані значення плашки не мають шкодити
    });
    expect(events.whereType<DisconnectedEvent>().single.reason, DisconnectReason.network);
    expect(code, isNot(-1), reason: 'процес мав завершитись сам');
  }, skip: _skip);

  test('ввід, затримка й «показати вікно» до підключення — ігноруються, процес живий і далі', () async {
    final ch = await ProcessChannel.start(File(_exe).absolute.path);
    final events = <SessionEvent>[];
    final sub = ch.output.transform(const SessionEventDecoder()).listen(events.add);
    for (final f in [encodeKey(0x1E, true), encodeMouseMove(10, 10), encodeLatency(42), encodeFocus(), encodeFrame(0x7F)]) {
      ch.send(f);
    }
    ch.send(encodeConnect({'host': '127.0.0.1', 'port': 1, 'username': 'u', 'password': 'p'}));
    final code = await ch.exitCode.timeout(const Duration(seconds: 30), onTimeout: () {
      ch.kill();
      return -1;
    });
    await sub.cancel();
    expect(events.whereType<DisconnectedEvent>().single.reason, DisconnectReason.network);
    expect(code, isNot(-1));
  }, skip: _skip);
}
