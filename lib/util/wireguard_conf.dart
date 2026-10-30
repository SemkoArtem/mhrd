/// Розбір стандартного файлу конфігурації WireGuard (.conf).
/// Повертає несекретну частину окремо від секретів, щоб секрети пішли в сховище.
class WireGuardConf {
  WireGuardConf({required this.config, required this.secrets});

  /// addresses, dns, mtu, peerPublicKey, endpoint, allowedIps, keepalive
  final Map<String, dynamic> config;

  /// privateKey, presharedKey (якщо є)
  final Map<String, String> secrets;
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
    throw const FormatException('У файлі немає PrivateKey у секції [Interface].');
  }
  if (peer['publickey'] == null || peer['endpoint'] == null) {
    throw const FormatException('У файлі немає секції [Peer] з PublicKey і Endpoint.');
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
