import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/sessions/tunnel.dart';

/// Справжній mhrd-tunnel.exe без серверів: протокол рядків JSON і коди помилок доходять до
/// застосунку. Повний WireGuard перевіряє native/tunnels/tunnel_test.go (go test).
/// Пропускається, якщо модуль не зібрано (native/tunnels/build.ps1).
const _exe = 'native/tunnels/out/mhrd-tunnel.exe';
final Object _skip = Platform.isWindows && File(_exe).existsSync() ? false : 'mhrd-tunnel.exe не зібрано';

Future<TunnelException> _fail(Map<String, Object?> request) async {
  final ch = await TunnelProcess.start(File(_exe).absolute.path);
  try {
    await openTunnel(ch, request).timeout(const Duration(seconds: 40));
    fail('tunnel unexpectedly opened');
  } on TunnelException catch (e) {
    return e;
  } finally {
    ch.kill();
  }
}

void main() {
  test('зламаний ключ WireGuard → config', () async {
    final e = await _fail({
      'type': 'wireguard',
      'target': '10.0.0.5:3389',
      'wireguard': {'privateKey': 'xx', 'addresses': ['10.8.0.2/24'], 'peerPublicKey': 'yy', 'endpoint': '127.0.0.1:51820'},
    });
    expect(e.error, TunnelError.config);
  }, skip: _skip);

  test('сервер WireGuard не знаходиться за іменем → endpointDns', () async {
    const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    final e = await _fail({
      'type': 'wireguard',
      'target': '10.0.0.5:3389',
      'wireguard': {'privateKey': key, 'addresses': ['10.8.0.2/24'], 'peerPublicKey': key, 'endpoint': 'vpn.invalid:51820'},
    });
    expect(e.error, TunnelError.endpointDns);
  }, skip: _skip);
}
