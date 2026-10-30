import 'dart:convert';

import '../models/connection.dart';
import 'address.dart';

/// Імпорт і експорт підключень у формат `.rdp` (публічно задокументований Microsoft).
/// Паролі в .rdp не пишемо ніколи.

class RdpImport {
  RdpImport({required this.connection, this.username, this.gatewayHost});
  final Connection connection;
  final String? username;
  final String? gatewayHost;
}

Map<String, String> _parseLines(String text) {
  final out = <String, String>{};
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim().replaceAll('\u0000', '');
    // формат рядка: ключ:тип:значення
    final m = RegExp(r'^([^:]+):([isb]):(.*)$').firstMatch(line);
    if (m != null) out[m.group(1)!.trim().toLowerCase()] = m.group(3)!.trim();
  }
  return out;
}

/// [text] — уже декодований вміст (.rdp буває в UTF-16 LE з BOM, див. [decodeRdpBytes]).
RdpImport parseRdpFile(String text, {required String id, String fallbackName = ''}) {
  final kv = _parseLines(text);
  final addr = parseAddress(kv['full address'] ?? '');
  if (addr == null) {
    throw const FormatException('У файлі .rdp немає коректної адреси (full address).');
  }
  final now = DateTime.now();
  int i(String k, int fb) => int.tryParse(kv[k] ?? '') ?? fb;

  final conn = Connection(
    id: id,
    name: fallbackName,
    host: addr.host,
    port: kv['server port'] != null ? i('server port', addr.port) : addr.port,
    adminSession: i('administrative session', 0) == 1,
    display: DisplaySettings(
      useAllMonitors: i('use multimon', 0) == 1,
      startFullscreen: kv['screen mode id'] == null ? null : i('screen mode id', 1) == 2,
      resizeMode: i('dynamic resolution', 1) == 1
          ? ResizeMode.changeResolution
          : (i('smart sizing', 0) == 1 ? ResizeMode.scale : ResizeMode.none),
      colorDepth: i('session bpp', 32),
      width: kv['desktopwidth'] != null ? i('desktopwidth', 0) : null,
      height: kv['desktopheight'] != null ? i('desktopheight', 0) : null,
    ),
    devices: DeviceSettings(
      clipboard: i('redirectclipboard', 1) == 1,
      sound: switch (i('audiomode', 0)) {
        1 => SoundMode.remote,
        2 => SoundMode.off,
        _ => SoundMode.local,
      },
      microphone: i('audiocapturemode', 0) == 1,
    ),
    createdAt: now,
    updatedAt: now,
  );
  final gw = kv['gatewayhostname'];
  return RdpImport(
    connection: conn,
    username: (kv['username'] ?? '').isEmpty ? null : kv['username'],
    gatewayHost: (gw == null || gw.isEmpty || i('gatewayusagemethod', 0) == 0) ? null : gw,
  );
}

/// Декодує байти .rdp: UTF-16 LE з BOM (так зберігає Windows) або UTF-8.
String decodeRdpBytes(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final units = <int>[];
    for (var k = 2; k + 1 < bytes.length; k += 2) {
      units.add(bytes[k] | (bytes[k + 1] << 8));
    }
    return String.fromCharCodes(units);
  }
  final start = (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) ? 3 : 0;
  return utf8.decode(bytes.sublist(start), allowMalformed: true);
}

/// Експорт одного ПК у текст .rdp (записувати у файл як UTF-16 LE з BOM для сумісності з mstsc).
String buildRdpFile(Connection c, {String? username, String? gatewayHost}) {
  final b = StringBuffer();
  void s(String k, String v) => b.writeln('$k:s:$v');
  void n(String k, int v) => b.writeln('$k:i:$v');
  final host = c.host.contains(':') ? '[${c.host}]' : c.host;
  s('full address', c.port == 3389 ? host : '$host:${c.port}');
  if (username != null && username.isNotEmpty) s('username', username);
  n('screen mode id', (c.display.startFullscreen ?? false) ? 2 : 1);
  n('use multimon', c.display.useAllMonitors ? 1 : 0);
  n('session bpp', c.display.colorDepth);
  if (c.display.width != null && c.display.height != null) {
    n('desktopwidth', c.display.width!);
    n('desktopheight', c.display.height!);
  }
  n('dynamic resolution', c.display.resizeMode == ResizeMode.changeResolution ? 1 : 0);
  n('smart sizing', c.display.resizeMode == ResizeMode.scale ? 1 : 0);
  n('redirectclipboard', c.devices.clipboard ? 1 : 0);
  n('audiomode', switch (c.devices.sound) { SoundMode.local => 0, SoundMode.remote => 1, SoundMode.off => 2 });
  n('audiocapturemode', c.devices.microphone ? 1 : 0);
  n('administrative session', c.adminSession ? 1 : 0);
  n('autoreconnection enabled', c.reconnectOnDrop ? 1 : 0);
  if (gatewayHost != null && gatewayHost.isNotEmpty) {
    s('gatewayhostname', gatewayHost);
    n('gatewayusagemethod', c.gatewayBypassLocal ? 2 : 1);
    n('promptcredentialonce', 1);
  }
  return b.toString();
}

/// Кодує текст у UTF-16 LE з BOM.
List<int> encodeUtf16Le(String text) {
  final out = <int>[0xFF, 0xFE];
  for (final u in text.codeUnits) {
    out
      ..add(u & 0xFF)
      ..add(u >> 8);
  }
  return out;
}
