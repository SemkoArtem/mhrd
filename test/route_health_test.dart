import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/models/connection.dart';
import 'package:mhrd/models/entities.dart';
import 'package:mhrd/sessions/route_health.dart';
import 'package:mhrd/sessions/session_manager.dart' show RouteError;
import 'package:mhrd/sessions/tunnel.dart';
import 'package:mhrd/storage/database.dart';
import 'package:mhrd/storage/repository.dart';
import 'package:mhrd/storage/secret_store.dart';
import 'package:mhrd/util/wireguard_conf.dart' show tunnelAddress;

/// Фальшивий mhrd-tunnel: на перший запит відповідає подіями зі [script].
class FakeTunnel implements TunnelChannel {
  FakeTunnel(this.script);
  final List<Map<String, Object?>> script;
  final _events = StreamController<Map<String, Object?>>();
  final sent = <Map<String, Object?>>[];
  bool killed = false;

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  void send(Map<String, Object?> message) {
    sent.add(message);
    for (final e in script) {
      scheduleMicrotask(() => _events.add(e));
    }
  }

  @override
  void kill() => killed = true;
}

/// Локальний «проксі»: [handle] отримує сокет і всі байти, що вже прийшли.
Future<ServerSocket> fakeProxy(Future<void> Function(Socket s, Stream<List<int>> input) handle) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((s) => handle(s, s.asBroadcastStream()));
  return server;
}

/// Читає рівно [n] байт із потоку.
Future<List<int>> readN(StreamIterator<List<int>> it, List<int> buf, int n) async {
  while (buf.length < n) {
    if (!await it.moveNext()) throw StateError('closed');
    buf.addAll(it.current);
  }
  final out = buf.sublist(0, n);
  buf.removeRange(0, n);
  return out;
}

ProxyProfile proxy(int port, {ProxyType type = ProxyType.socks5, String user = ''}) =>
    ProxyProfile(id: 'px', name: 'P', type: type, host: '127.0.0.1', port: port, username: user);

void main() {
  group('SOCKS5', () {
    /// Сервер із логіном u/p; на CONNECT відповідає кодом [reply]. Запам'ятовує запит CONNECT.
    Future<(ServerSocket, Completer<List<int>>)> socks({int reply = 0}) async {
      final connect = Completer<List<int>>();
      final server = await fakeProxy((s, input) async {
        final it = StreamIterator(input);
        final buf = <int>[];
        final hello = await readN(it, buf, 3);
        s.add([5, hello[2]]);
        if (hello[2] == 2) {
          final head = await readN(it, buf, 2);
          final user = utf8.decode(await readN(it, buf, head[1]));
          final plen = (await readN(it, buf, 1))[0];
          final pass = utf8.decode(await readN(it, buf, plen));
          final ok = user == 'u' && pass == 'p';
          s.add([1, ok ? 0 : 1]);
          if (!ok) return s.close();
        }
        final head = await readN(it, buf, 5); // 5 1 0 3 len
        final rest = await readN(it, buf, head[4] + 2);
        connect.complete([...head, ...rest]);
        s.add([5, reply, 0, 1, 0, 0, 0, 0, 0, 0]);
      });
      return (server, connect);
    }

    test('логін і CONNECT до ПК за іменем', () async {
      final (server, connect) = await socks();
      addTearDown(server.close);
      await probeProxy(proxy(server.port, user: 'u'), password: 'p', targetHost: 'office.lan', targetPort: 3389);
      expect(await connect.future, [5, 1, 0, 3, 10, ...utf8.encode('office.lan'), 0x0D, 0x3D]);
    });

    test('неправильний пароль → auth', () async {
      final (server, _) = await socks();
      addTearDown(server.close);
      await expectLater(probeProxy(proxy(server.port, user: 'u'), password: 'x', targetHost: 'pc'),
          throwsA(isA<ProxyException>().having((e) => e.error, 'error', ProxyError.auth)));
    });

    test('проксі не пускає до ПК → refused', () async {
      final (server, _) = await socks(reply: 2);
      addTearDown(server.close);
      await expectLater(probeProxy(proxy(server.port), targetHost: 'pc'),
          throwsA(isA<ProxyException>().having((e) => e.error, 'error', ProxyError.refused)));
    });
  });

  group('HTTP', () {
    Future<(ServerSocket, Completer<String>)> http(String status) async {
      final request = Completer<String>();
      final server = await fakeProxy((s, input) async {
        final text = StringBuffer();
        await for (final d in input) {
          text.write(latin1.decode(d));
          if (text.toString().contains('\r\n\r\n')) break;
        }
        request.complete(text.toString());
        s.write('$status\r\n\r\n');
        await s.flush();
        await s.close();
      });
      return (server, request);
    }

    test('CONNECT з логіном (Basic) → 200', () async {
      final (server, request) = await http('HTTP/1.1 200 Connection established');
      addTearDown(server.close);
      await probeProxy(proxy(server.port, type: ProxyType.http, user: 'u'),
          password: 'p', targetHost: '10.0.0.5', targetPort: 3389);
      final r = await request.future;
      expect(r, startsWith('CONNECT 10.0.0.5:3389 HTTP/1.1\r\n'));
      expect(r, contains('Proxy-Authorization: Basic ${base64.encode(utf8.encode('u:p'))}'));
    });

    test('403 на CONNECT → refused, 407 → auth', () async {
      final (s403, _) = await http('HTTP/1.1 403 Forbidden');
      final (s407, _) = await http('HTTP/1.1 407 Proxy Authentication Required');
      addTearDown(s403.close);
      addTearDown(s407.close);
      await expectLater(probeProxy(proxy(s403.port, type: ProxyType.http), targetHost: 'pc'),
          throwsA(isA<ProxyException>().having((e) => e.error, 'error', ProxyError.refused)));
      await expectLater(probeProxy(proxy(s407.port, type: ProxyType.http), targetHost: 'pc'),
          throwsA(isA<ProxyException>().having((e) => e.error, 'error', ProxyError.auth)));
    });

    test('без ПК достатньо будь-якої HTTP-відповіді; не HTTP → protocol', () async {
      final (ok, request) = await http('HTTP/1.1 400 Bad Request');
      final (bad, _) = await http('SSH-2.0-OpenSSH_9.6');
      addTearDown(ok.close);
      addTearDown(bad.close);
      await probeProxy(proxy(ok.port, type: ProxyType.http));
      expect(await request.future, startsWith('OPTIONS * HTTP/1.1'));
      await expectLater(probeProxy(proxy(bad.port, type: ProxyType.http)),
          throwsA(isA<ProxyException>().having((e) => e.error, 'error', ProxyError.protocol)));
    });
  });

  test('нікого не слухає → unreachable', () async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    await expectLater(probeProxy(proxy(port)),
        throwsA(isA<ProxyException>().having((e) => e.error, 'error', ProxyError.unreachable)));
  });

  group('RouteHealth', () {
    late Repository repo;
    setUp(() async {
      repo = Repository(MhrdDatabase.inMemory(), MemorySecretStore());
      await repo.saveTunnel(
          const TunnelProfile(id: 'wg', name: 'WG', type: TunnelType.wireguard, config: {
            'endpoint': 'vpn.example.com:51820',
            'extraPeersIgnored': false,
          }, secretFields: ['privateKey']),
          secretValues: {'privateKey': 'PRIV'});
    });

    test('WireGuard відповів → ok; ключ — лише в stdin, процес прибрано', () async {
      final tun = FakeTunnel([
        {'event': 'ok', 'handshakeMs': 87}
      ]);
      final h = RouteHealth(repo, tunnelPath: 'mhrd-tunnel.exe', tunnelFactory: (_) async => tun);
      addTearDown(h.dispose);
      await h.check('wg');
      expect(h.statusOf('wg').state, HealthState.ok);
      expect(h.statusOf('wg').latencyMs, 87);
      final req = tun.sent.single;
      expect(req['check'], isTrue);
      expect((req['wireguard'] as Map)['privateKey'], 'PRIV');
      expect((req['wireguard'] as Map).containsKey('extraPeersIgnored'), isFalse);
      expect(tun.killed, isTrue);
    });

    test('немає рукостискання → failed з кодом; немає mhrd-tunnel → свій код', () async {
      final h = RouteHealth(repo, tunnelPath: 'mhrd-tunnel.exe', tunnelFactory: (_) async => FakeTunnel([
            {'event': 'error', 'code': 'handshake', 'detail': 'no handshake in 15s'}
          ]));
      addTearDown(h.dispose);
      await h.check('wg');
      expect(h.statusOf('wg').state, HealthState.failed);
      expect(h.statusOf('wg').error, TunnelError.handshake);
      expect(h.statusOf('wg').detail, 'no handshake in 15s');

      final noEngine = RouteHealth(repo);
      addTearDown(noEngine.dispose);
      await noEngine.check('wg');
      expect(noEngine.statusOf('wg').error, RouteError.tunnelEngineMissing);
    });

    test('ще не збережений WireGuard перевіряється з ключами з .conf (перед збереженням)', () async {
      final tun = FakeTunnel([
        {'event': 'ok', 'handshakeMs': 41}
      ]);
      final h = RouteHealth(repo, tunnelPath: 'mhrd-tunnel.exe', tunnelFactory: (_) async => tun);
      addTearDown(h.dispose);
      final ms = await h.checkWireGuard({'endpoint': 'vpn:51820', 'privateKey': 'K', 'extraPeersIgnored': true});
      expect(ms, 41);
      final wg = tun.sent.single['wireguard'] as Map;
      expect(wg['privateKey'], 'K');
      expect(wg.containsKey('extraPeersIgnored'), isFalse);
      expect(tun.sent.single.containsKey('target'), isFalse); // лише рукостискання, без ПК
      expect(tunnelAddress({'addresses': ['10.8.0.2/32', 'fd00::2/128']}), '10.8.0.2');
      expect(tunnelAddress(const {}), isNull);
    });

    test('затримка до ПК: напряму — з\'єднання з портом RDP, через тунель — ПК крізь тунель', () async {
      final now = DateTime.utc(2026);
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((s) => s.destroy());
      final h = RouteHealth(repo, tunnelPath: 'mhrd-tunnel.exe', tunnelFactory: (_) async => FakeTunnel([
            {'event': 'ok', 'handshakeMs': 5, 'targetMs': 33}
          ]));
      addTearDown(h.dispose);
      final direct = Connection(id: 'pc', name: '', host: '127.0.0.1', port: server.port, createdAt: now, updatedAt: now);
      expect(await h.measure(direct), greaterThanOrEqualTo(0));
      await server.close();
      await expectLater(h.measure(direct),
          throwsA(isA<ProbeException>().having((e) => e.error, 'error', ProbeError.pcUnreachable)));
      final viaTunnel = direct.copyWith(route: RouteKind.tunnel, routeRefId: () => 'wg');
      expect(await h.measure(viaTunnel), 33);
    });

    test('проксі перевіряється до ПК, що через нього ходить; видалений профіль зникає', () async {
      final connect = Completer<List<int>>();
      final server = await fakeProxy((s, input) async {
        final it = StreamIterator(input);
        final buf = <int>[];
        await readN(it, buf, 3);
        s.add([5, 0]);
        final head = await readN(it, buf, 4); // 5 1 0 1 (IPv4)
        connect.complete([...head, ...await readN(it, buf, 6)]);
        s.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
      });
      addTearDown(server.close);
      await repo.saveProxy(proxy(server.port));
      final now = DateTime.utc(2026);
      repo.saveConnection(Connection(
          id: 'pc', name: 'Офіс', host: '10.0.0.5', port: 3390, route: RouteKind.proxy, routeRefId: 'px',
          createdAt: now, updatedAt: now));
      final h = RouteHealth(repo, tunnelPath: null);
      addTearDown(h.dispose);
      h.start();
      await h.check('px');
      expect(h.statusOf('px').state, HealthState.ok);
      expect(await connect.future, [5, 1, 0, 1, 10, 0, 0, 5, 0x0D, 0x3E]);

      await repo.deleteProxy('px', force: true);
      expect(h.statusOf('px').state, HealthState.unknown);
    });
  });
}
