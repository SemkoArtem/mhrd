import 'dart:io';

/// Розбір адреси ПК так, як її вводить людина:
///   `MyDesktop`, `10.0.0.1:3390`, `srv.local:3389`, `[fd00::5]:3389`, `fd00::5`.
class ParsedAddress {
  const ParsedAddress(this.host, this.port);
  final String host;
  final int port;

  @override
  bool operator ==(Object other) => other is ParsedAddress && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => 'ParsedAddress($host, $port)';
}

/// Повертає null, якщо адреса некоректна (порожня, пробіли, порт поза 1–65535).
ParsedAddress? parseAddress(String input, {int defaultPort = 3389}) {
  final s = input.trim();
  if (s.isEmpty || s.contains(RegExp(r'\s'))) return null;

  // [IPv6]:port або [IPv6]
  final bracket = RegExp(r'^\[([0-9a-fA-F:.%]+)\](?::(\d+))?$').firstMatch(s);
  if (bracket != null) {
    final port = bracket.group(2) == null ? defaultPort : int.tryParse(bracket.group(2)!);
    return _valid(bracket.group(1)!, port);
  }

  // Голий IPv6 (кілька двокрапок) — порт так не вказати.
  if (':'.allMatches(s).length > 1) {
    return RegExp(r'^[0-9a-fA-F:.%]+$').hasMatch(s) ? _valid(s, defaultPort) : null;
  }

  // host або host:port
  final i = s.lastIndexOf(':');
  if (i < 0) return _valid(s, defaultPort);
  return _valid(s.substring(0, i), int.tryParse(s.substring(i + 1)));
}

ParsedAddress? _valid(String host, int? port) {
  if (host.isEmpty || port == null || port < 1 || port > 65535) return null;
  if (!RegExp(r'^[A-Za-z0-9._\-:%]+$').hasMatch(host)) return null;
  return ParsedAddress(host, port);
}

/// Приватні адреси (для «Обходити шлюз для локальних адрес»).
bool isPrivateHost(String host) {
  final h = host.toLowerCase();
  // Зону IPv6 (fe80::1%eth0) InternetAddress не розбирає — відкидаємо її.
  final ip = InternetAddress.tryParse(h.split('%').first);
  if (ip == null) {
    // Ім'я: локальне, якщо без домену (MyDesktop) або в локальній зоні.
    return h == 'localhost' || h.endsWith('.local') || h.endsWith('.lan') || !h.contains('.');
  }
  final b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv4) {
    return b[0] == 10 || b[0] == 127 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) ||
        (b[0] == 169 && b[1] == 254) || (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
  }
  // IPv6: ::1, унікальні локальні fc00::/7, локальні для каналу fe80::/10.
  return ip.isLoopback || (b[0] & 0xFE) == 0xFC || (b[0] == 0xFE && (b[1] & 0xC0) == 0x80);
}
