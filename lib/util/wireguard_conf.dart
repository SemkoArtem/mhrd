import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

enum WireGuardConfError { noPrivateKey, noPeer }

/// Помилка розбору .conf; текст для людей складає UI за [error].
class WireGuardConfException extends FormatException {
  WireGuardConfException(this.error) : super('wireguard: ${error.name}');
  final WireGuardConfError error;
}

/// Розбір стандартного файлу конфігурації WireGuard (.conf).
/// Повертає несекретну частину окремо від секретів, щоб секрети пішли в сховище.
class WireGuardConf {
  WireGuardConf({required this.config, required this.secrets});

  /// addresses, dns, mtu, peerPublicKey, endpoint, allowedIps, keepalive
  final Map<String, dynamic> config;

  /// privateKey, presharedKey (якщо є)
  final Map<String, String> secrets;
}

/// Ключ WireGuard: 32 байти в Base64 (44 символи з «=» у кінці).
bool isWireGuardKey(String key) {
  try {
    return base64.decode(key.trim()).length == 32;
  } on FormatException {
    return false;
  }
}

/// Новий приватний ключ — як `wg genkey`: 32 випадкові байти, «затиснуті» для X25519.
String generateWireGuardPrivateKey() {
  final rnd = Random.secure();
  final k = List<int>.generate(32, (_) => rnd.nextInt(256));
  k[0] &= 248;
  k[31] = (k[31] & 127) | 64;
  return base64.encode(k);
}

/// Публічний ключ для приватного — як `wg pubkey`. null — це не ключ WireGuard.
Future<String?> wireGuardPublicKey(String privateKey) async {
  if (!isWireGuardKey(privateKey)) return null;
  final pair = await X25519().newKeyPairFromSeed(base64.decode(privateKey.trim()));
  return base64.encode((await pair.extractPublicKey()).bytes);
}

/// Адреса цього пристрою всередині тунелю (перша з Address, без /маски): «10.8.0.2».
String? tunnelAddress(Map<String, dynamic> config) {
  final a = config['addresses'];
  if (a is! List || a.isEmpty) return null;
  return '${a.first}'.split('/').first;
}

WireGuardConf parseWireGuardConf(String text) {
  String? section;
  final iface = <String, String>{};
  final peer = <String, String>{};
  var peers = 0;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;
    final sec = RegExp(r'^\[(\w+)\]$').firstMatch(line);
    if (sec != null) {
      section = sec.group(1)!.toLowerCase();
      if (section == 'peer') peers++;
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final key = line.substring(0, eq).trim().toLowerCase();
    final value = line.substring(eq + 1).trim();
    if (section == 'interface') {
      iface[key] = value;
    } else if (section == 'peer' && peers == 1) {
      peer[key] = value; // у першій версії підтримуємо один peer
    }
  }

  final privateKey = iface['privatekey'];
  if (privateKey == null || privateKey.isEmpty) {
    throw WireGuardConfException(WireGuardConfError.noPrivateKey);
  }
  if (peer['publickey'] == null || peer['endpoint'] == null) {
    throw WireGuardConfException(WireGuardConfError.noPeer);
  }

  List<String> list(String? v) =>
      v == null ? <String>[] : v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  final secrets = <String, String>{'privateKey': privateKey};
  if (peer['presharedkey'] != null) secrets['presharedKey'] = peer['presharedkey']!;

  return WireGuardConf(
    config: {
      'addresses': list(iface['address']),
      'dns': list(iface['dns']),
      'mtu': int.tryParse(iface['mtu'] ?? '') ?? 1420,
      'peerPublicKey': peer['publickey'],
      'endpoint': peer['endpoint'],
      'allowedIps': list(peer['allowedips']),
      'keepalive': int.tryParse(peer['persistentkeepalive'] ?? '') ?? 0,
      'extraPeersIgnored': peers > 1,
    },
    secrets: secrets,
  );
}
