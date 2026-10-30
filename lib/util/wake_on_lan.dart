import 'dart:io';
import 'dart:typed_data';

import '../models/connection.dart';

/// Wake-on-LAN: «магічний пакет» — 6 байтів 0xFF і 16 повторів MAC-адреси (102 байти)
/// по UDP на широкомовну адресу. Працює в тій самій локальній мережі або через роутер,
/// що пропускає спрямований broadcast (наприклад, 192.168.1.255); через тунелі — ні.

enum WakeOnLanError { invalidMac, invalidBroadcast }

/// Некоректні дані Wake-on-LAN; текст для людей складає UI за [error] і [value].
class WakeOnLanException extends FormatException {
  WakeOnLanException(this.error, this.value) : super('wake-on-lan: ${error.name}: $value');
  final WakeOnLanError error;
  final String value;
}

final _macSeparated = RegExp(r'^[0-9a-f]{2}([:-])(?:[0-9a-f]{2}\1){4}[0-9a-f]{2}$', caseSensitive: false);
final _macPlain = RegExp(r'^[0-9a-f]{12}$', caseSensitive: false);

/// `AA:BB:CC:DD:EE:FF`, `AA-BB-CC-DD-EE-FF` або `AABBCCDDEEFF` → 6 байтів; null, якщо некоректно.
List<int>? parseMac(String input) {
  final s = input.trim();
  if (!_macSeparated.hasMatch(s) && !_macPlain.hasMatch(s)) return null;
  final hex = s.replaceAll(RegExp('[:-]'), '');
  return [for (var i = 0; i < 12; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
}

/// Канонічний вигляд для збереження й показу: `AA:BB:CC:DD:EE:FF`.
String formatMac(List<int> mac) =>
    mac.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

Uint8List magicPacket(List<int> mac) {
  final p = Uint8List(102)..fillRange(0, 6, 0xFF);
  for (var i = 0; i < 16; i++) {
    p.setRange(6 + i * 6, 12 + i * 6, mac);
  }
  return p;
}

/// Надсилає магічний пакет кілька разів (UDP може загубитися).
/// Кидає [WakeOnLanException] або [SocketException], якщо мережі немає.
Future<void> sendWakeOnLan(WakeOnLan w, {int repeat = 3}) async {
  final mac = parseMac(w.mac);
  if (mac == null) throw WakeOnLanException(WakeOnLanError.invalidMac, w.mac);
  final target = InternetAddress.tryParse(w.broadcast);
  if (target == null || target.type != InternetAddressType.IPv4) {
    throw WakeOnLanException(WakeOnLanError.invalidBroadcast, w.broadcast);
  }
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  try {
    socket.broadcastEnabled = true;
    final packet = magicPacket(mac);
    for (var i = 0; i < repeat; i++) {
      socket.send(packet, target, w.port);
    }
  } finally {
    socket.close();
  }
}
