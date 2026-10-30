import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/models/connection.dart';
import 'package:mhrd/util/wake_on_lan.dart';

void main() {
  const mac = [0xAA, 0xBB, 0xCC, 0x01, 0x02, 0x03];

  test('MAC: три формати запису, однаковий результат', () {
    for (final s in ['AA:BB:CC:01:02:03', 'aa-bb-cc-01-02-03', 'AABBCC010203', ' aa:bb:cc:01:02:03 ']) {
      expect(parseMac(s), mac, reason: s);
    }
    expect(formatMac(mac), 'AA:BB:CC:01:02:03');
  });

  test('MAC: некоректні відкидаються', () {
    for (final s in ['', 'AA:BB:CC:01:02', 'AA:BB:CC:01:02:0G', 'AA:BB-CC:01:02:03', 'AABB:CC01:0203', 'AA:BB:CC:01:02:03:04']) {
      expect(parseMac(s), isNull, reason: s);
    }
  });

  test('магічний пакет: 6×FF і 16 повторів MAC', () {
    final p = magicPacket(mac);
    expect(p.length, 102);
    expect(p.sublist(0, 6), List.filled(6, 0xFF));
    for (var i = 0; i < 16; i++) {
      expect(p.sublist(6 + i * 6, 12 + i * 6), mac, reason: 'повтор $i');
    }
  });

  test('пакет справді йде по UDP', () async {
    final listener = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final got = Completer<List<int>>();
    listener.listen((e) {
      final d = e == RawSocketEvent.read ? listener.receive() : null;
      if (d != null && !got.isCompleted) got.complete(d.data);
    });
    await sendWakeOnLan(WakeOnLan(mac: 'AA:BB:CC:01:02:03', broadcast: '127.0.0.1', port: listener.port));
    final data = await got.future.timeout(const Duration(seconds: 5));
    listener.close();
    expect(data, magicPacket(mac));
  });

  test('некоректні дані — зрозуміла помилка', () async {
    await expectLater(sendWakeOnLan(const WakeOnLan(mac: 'не MAC')), throwsFormatException);
    await expectLater(
        sendWakeOnLan(const WakeOnLan(mac: 'AA:BB:CC:01:02:03', broadcast: 'fd00::1')), throwsFormatException);
  });
}
