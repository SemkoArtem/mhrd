import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/connection.dart';
import '../models/entities.dart';
import '../storage/repository.dart';
import 'session_manager.dart' show RouteError, RouteException;
import 'tunnel.dart';

/// Стан тунелю чи проксі в лівій панелі.
enum HealthState { unknown, checking, ok, failed }

class RouteStatus {
  const RouteStatus(this.state, {this.error, this.detail = '', this.latencyMs, this.checkedAt});

  final HealthState state;

  /// Чому не працює: [TunnelError], [ProxyError] або [RouteError]. UI перекладає.
  final Object? error;

  /// Технічні подробиці (без секретів).
  final String detail;

  /// За скільки мс сервер відповів.
  final int? latencyMs;
  final DateTime? checkedAt;
}

/// Чому проксі не пройшов перевірку.
enum ProxyError {
  /// Не вдалося з'єднатися з проксі (немає мережі, неправильна адреса чи порт).
  unreachable,
  /// Відповідає щось, але не проксі вибраного типу.
  protocol,
  /// Проксі відхилив логін або пароль (або вимагає їх).
  auth,
  /// Проксі працює, але не пускає до ПК.
  refused,
}

/// Чому ПК не відповідає при перевірці маршруту «напряму» чи через RD Gateway.
enum ProbeError {
  /// ПК не приймає з'єднання на порт RDP (вимкнений, брандмауер, неправильна адреса).
  pcUnreachable,
  /// RD Gateway не приймає з'єднання.
  gatewayUnreachable,
}

class ProbeException implements Exception {
  const ProbeException(this.error, [this.detail = '']);
  final ProbeError error;
  final String detail;
  @override
  String toString() => 'ProbeException(${error.name}: $detail)';
}

class ProxyException implements Exception {
  const ProxyException(this.error, [this.detail = '']);
  final ProxyError error;
  final String detail;
  @override
  String toString() => 'ProxyException(${error.name}: $detail)';
}

/// Перевіряє тунелі й проксі: при запуску, кожні [interval] і коли профіль змінився.
/// Перевірка WireGuard — рукостискання з сервером (mhrd-tunnel у режимі check); проксі —
/// рукостискання, логін і, якщо через проксі ходить ПК, чи пускає проксі до нього.
class RouteHealth extends ChangeNotifier {
  RouteHealth(
    this.repo, {
    this.tunnelPath,
    TunnelFactory? tunnelFactory,
    this.interval = const Duration(minutes: 5),
    this.liveTunnel,
  }) : _tunnelFactory = tunnelFactory ?? TunnelProcess.start;

  final Repository repo;
  final String? tunnelPath;
  final TunnelFactory _tunnelFactory;
  final Duration interval;

  /// Уже відкритий сеансом тунель з тим самим ключем WireGuard (SessionManager.liveTunnel): перевірки
  /// йдуть крізь нього — окремий процес з тим самим ключем перебив би з'єднання сеансу з сервером.
  final TunnelChannel? Function(Map<String, Object?> wireguard)? liveTunnel;

  final _status = <String, RouteStatus>{};
  final _running = <String, Future<void>>{};
  final _seen = <String, String>{}; // id → профіль у JSON, щоб помітити зміни
  Timer? _timer;
  bool _disposed = false;

  RouteStatus statusOf(String id) => _status[id] ?? const RouteStatus(HealthState.unknown);

  /// Перша перевірка всього й далі — за розкладом.
  void start() {
    if (_timer != null) return;
    _seen.addAll(_profiles());
    repo.addListener(_onRepo);
    checkAll();
    // За розкладом — лише проксі. Перевірка тунелю WireGuard — рукостискання з його ключем: якщо той
    // самий ключ зараз працює на іншому пристрої (той самий .conf на ПК і телефоні), сервер
    // перемкнеться на нас і там обірветься сеанс. Тож тунелі — при запуску, при зміні профілю й за
    // кнопкою оновлення.
    _timer = Timer.periodic(interval, (_) => checkAll(tunnels: false));
  }

  /// Усе по черзі: одночасні перевірки кількох тунелів (часто — з одним ключем WireGuard) заважали б
  /// одна одній і показували робочі тунелі непрацюючими.
  Future<void> checkAll({bool tunnels = true}) async {
    for (final id in [if (tunnels) ...repo.tunnels.keys, ...repo.proxies.keys]) {
      if (_disposed) return;
      await check(id);
    }
  }

  /// Перевірити один профіль (повторний виклик під час перевірки — та сама перевірка).
  Future<void> check(String id) => _running[id] ??= _check(id).whenComplete(() {
        _running.remove(id); // без фігурних дужок whenComplete чекав би сам на себе
      });

  Map<String, String> _profiles() => {
        for (final t in repo.tunnels.values) t.id: jsonEncode(t.toJson()),
        for (final p in repo.proxies.values) p.id: jsonEncode(p.toJson()),
      };

  void _onRepo() {
    final now = _profiles();
    var removed = false;
    for (final id in _seen.keys.toList()) {
      if (!now.containsKey(id)) {
        _seen.remove(id);
        removed |= _status.remove(id) != null;
      }
    }
    for (final e in now.entries) {
      if (_seen[e.key] != e.value) {
        _seen[e.key] = e.value;
        check(e.key);
      }
    }
    if (removed) _notify();
  }

  Future<void> _check(String id) async {
    final tunnel = repo.tunnels[id];
    final proxy = repo.proxies[id];
    if (tunnel == null && proxy == null) return;
    _set(id, RouteStatus(HealthState.checking, checkedAt: _status[id]?.checkedAt));
    RouteStatus result;
    try {
      final ms = tunnel != null ? await _checkTunnel(tunnel) : await _checkProxy(proxy!);
      result = RouteStatus(HealthState.ok, latencyMs: ms, checkedAt: DateTime.now());
    } on TunnelException catch (e) {
      result = RouteStatus(HealthState.failed, error: e.error, detail: e.detail, checkedAt: DateTime.now());
    } on ProxyException catch (e) {
      result = RouteStatus(HealthState.failed, error: e.error, detail: e.detail, checkedAt: DateTime.now());
    } on RouteException catch (e) {
      result = RouteStatus(HealthState.failed, error: e.error, checkedAt: DateTime.now());
    } catch (e) {
      // Будь-що інше (не запустився mhrd-tunnel, збій сокета…) — теж «не працює», а не вічне
      // «Перевіряю…» з вимкненою кнопкою оновлення.
      result = RouteStatus(HealthState.failed, error: TunnelError.failed, detail: '$e', checkedAt: DateTime.now());
    }
    // Профіль могли видалити, поки йшла перевірка.
    if (repo.tunnels.containsKey(id) || repo.proxies.containsKey(id)) _set(id, result);
  }

  Future<int> _checkTunnel(TunnelProfile t) async => checkWireGuard(await repo.wireGuardConfig(t));

  /// Рукостискання з сервером WireGuard за налаштуваннями [wireguard] (з ключами) — і для ще не
  /// збереженого профілю, щоб перевірити його перед збереженням. Повертає мс.
  Future<int> checkWireGuard(Map<String, Object?> wireguard) async {
    // Тунель з цим ключем уже працює (у ньому сеанс) — затримка крізь нього, без нового рукостискання.
    final live = liveTunnel?.call(wireguard);
    if (live != null) return pingTunnel(live);
    final exe = tunnelPath;
    if (exe == null) throw const RouteException(RouteError.tunnelEngineMissing);
    final request = {
      'type': 'wireguard',
      'check': true,
      'wireguard': {...wireguard}..remove('extraPeersIgnored'),
    };
    final ch = await _tunnelFactory(exe);
    try {
      return await checkTunnel(ch, request).timeout(const Duration(seconds: 30),
          onTimeout: () => throw const TunnelException(TunnelError.handshake));
    } finally {
      ch.kill();
    }
  }

  Future<int> _checkProxy(ProxyProfile p) async {
    final users = repo.connections.values.where((c) => c.route == RouteKind.proxy && c.routeRefId == p.id).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final target = users.firstOrNull;
    final password = p.username.isEmpty ? '' : (await repo.secrets.read(p.secretKey) ?? '');
    return probeProxy(p, password: password, targetHost: target?.host, targetPort: target?.port ?? 3389);
  }

  /// Затримка до ПК через увесь його маршрут, мс: напряму — з'єднання з портом RDP; через RD Gateway —
  /// зі шлюзом; через проксі — проксі разом із ПК за ним; через тунель — ПК крізь тунель
  /// ([sessionTunnel] — тунель уже відкритого сеансу, інакше піднімаємо окремий на час заміру).
  /// Кидає [ProbeException], [ProxyException], [TunnelException] або [RouteException].
  Future<int> measure(Connection c, {TunnelChannel? sessionTunnel}) async {
    final target = c.host.contains(':') ? '[${c.host}]:${c.port}' : '${c.host}:${c.port}';
    switch (c.route) {
      case RouteKind.tunnel:
        if (sessionTunnel != null) return pingTunnel(sessionTunnel, target: target);
        final t = repo.tunnels[c.routeRefId];
        if (t == null) throw const RouteException(RouteError.tunnelMissing);
        final wireguard = await repo.wireGuardConfig(t);
        final open = liveTunnel?.call(wireguard);
        if (open != null) return pingTunnel(open, target: target);
        final exe = tunnelPath;
        if (exe == null) throw const RouteException(RouteError.tunnelEngineMissing);
        final ch = await _tunnelFactory(exe);
        try {
          return await checkTunnel(ch, {
            'type': 'wireguard',
            'check': true,
            'target': target,
            'wireguard': wireguard,
          }).timeout(const Duration(seconds: 45), onTimeout: () => throw const TunnelException(TunnelError.handshake));
        } finally {
          ch.kill();
        }
      case RouteKind.proxy:
        final p = repo.proxies[c.routeRefId];
        if (p == null) throw const RouteException(RouteError.proxyMissing);
        final password = p.username.isEmpty ? '' : (await repo.secrets.read(p.secretKey) ?? '');
        return probeProxy(p, password: password, targetHost: c.host, targetPort: c.port);
      case RouteKind.direct:
        final g = c.gatewayId == null ? null : repo.gateways[c.gatewayId];
        if (c.gatewayId != null && g == null) throw const RouteException(RouteError.gatewayMissing);
        return g != null
            ? _tcpTime(g.host, g.port, ProbeError.gatewayUnreachable)
            : _tcpTime(c.host, c.port, ProbeError.pcUnreachable);
    }
  }

  static Future<int> _tcpTime(String host, int port, ProbeError error) async {
    final watch = Stopwatch()..start();
    try {
      final s = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
      final ms = watch.elapsedMilliseconds;
      s.destroy();
      return ms;
    } on SocketException catch (e) {
      throw ProbeException(error, e.osError?.message ?? e.message);
    }
  }

  void _set(String id, RouteStatus s) {
    _status[id] = s;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_timer != null) repo.removeListener(_onRepo);
    super.dispose();
  }
}

/// Перевірка проксі: з'єднання, рукостискання протоколу, логін і — якщо задано [targetHost] —
/// чи пускає проксі до цього ПК (так само, як потім піде FreeRDP). Повертає час у мс.
Future<int> probeProxy(
  ProxyProfile p, {
  String password = '',
  String? targetHost,
  int targetPort = 3389,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final Socket s;
  try {
    s = await Socket.connect(p.host, p.port, timeout: timeout);
  } on SocketException catch (e) {
    throw ProxyException(ProxyError.unreachable, e.osError?.message ?? e.message);
  }
  final r = _Reader(s);
  try {
    final talk = p.type == ProxyType.socks5
        ? _socks5(s, r, p.username, password, targetHost, targetPort)
        : _http(s, r, p, password, targetHost, targetPort);
    return await talk.timeout(timeout, onTimeout: () => throw const ProxyException(ProxyError.protocol, 'timeout'));
  } on SocketException catch (e) {
    throw ProxyException(ProxyError.unreachable, e.osError?.message ?? e.message);
  } finally {
    r.cancel();
    s.destroy();
  }
}

/// Повертає час останнього обміну, мс: запит до ПК крізь проксі (≈ затримка всього шляху, як у сеансі),
/// а без ПК — привітання з проксі. З'єднання й логін не рахуємо — інакше вийшло б утричі більше.
Future<int> _socks5(Socket s, _Reader r, String user, String password, String? host, int port) async {
  final method = user.isEmpty ? 0x00 : 0x02;
  final watch = Stopwatch()..start();
  s.add([5, 1, method]);
  final hello = await r.take(2);
  final helloMs = watch.elapsedMilliseconds;
  if (hello[0] != 5) throw ProxyException(ProxyError.protocol, 'not SOCKS5 (${hello[0]})');
  if (hello[1] == 0xFF) throw const ProxyException(ProxyError.auth, 'no acceptable auth method');
  if (hello[1] != method) throw ProxyException(ProxyError.protocol, 'method ${hello[1]}');
  if (method == 0x02) {
    final u = utf8.encode(user), pw = utf8.encode(password);
    // RFC 1929: довжина — один байт; довше — такий логін SOCKS5 передати не може.
    if (u.length > 255 || pw.length > 255) throw const ProxyException(ProxyError.auth, 'login or password > 255 bytes');
    s.add([1, u.length, ...u, pw.length, ...pw]); // RFC 1929
    final auth = await r.take(2);
    if (auth[1] != 0) throw const ProxyException(ProxyError.auth);
  }
  if (host == null) return helloMs;
  final ip = InternetAddress.tryParse(host);
  final addr = ip == null
      ? [3, utf8.encode(host).length, ...utf8.encode(host)]
      : [ip.type == InternetAddressType.IPv6 ? 4 : 1, ...ip.rawAddress];
  watch.reset();
  s.add([5, 1, 0, ...addr, port >> 8, port & 0xFF]);
  final reply = await r.take(2);
  final ms = watch.elapsedMilliseconds;
  if (reply[0] != 5) throw ProxyException(ProxyError.protocol, 'reply version ${reply[0]}');
  if (reply[1] != 0) throw ProxyException(ProxyError.refused, 'SOCKS5 reply ${reply[1]}');
  return ms;
}

/// Повертає час запиту (CONNECT до ПК або, без ПК, OPTIONS), мс — див. [_socks5].
Future<int> _http(Socket s, _Reader r, ProxyProfile p, String password, String? host, int port) async {
  final auth = p.username.isEmpty
      ? ''
      : 'Proxy-Authorization: Basic ${base64.encode(utf8.encode('${p.username}:$password'))}\r\n';
  final watch = Stopwatch()..start();
  if (host == null) {
    // ПК через цей проксі поки немає — достатньо, що відповідає HTTP-проксі.
    s.add(latin1.encode('OPTIONS * HTTP/1.1\r\nHost: ${p.host}:${p.port}\r\n$auth\r\n'));
  } else {
    final target = host.contains(':') ? '[$host]:$port' : '$host:$port';
    s.add(utf8.encode('CONNECT $target HTTP/1.1\r\nHost: $target\r\n$auth\r\n'));
  }
  final status = await r.line();
  final ms = watch.elapsedMilliseconds;
  final m = RegExp(r'^HTTP/\d\.\d (\d{3})').firstMatch(status);
  if (m == null) throw ProxyException(ProxyError.protocol, status.length > 80 ? status.substring(0, 80) : status);
  final code = int.parse(m.group(1)!);
  if (code == 407) throw ProxyException(ProxyError.auth, status);
  if (host != null && (code < 200 || code > 299)) throw ProxyException(ProxyError.refused, status);
  return ms;
}

/// Читає відповідь проксі порціями потрібної довжини.
class _Reader {
  _Reader(Socket s) {
    _sub = s.listen(
      (d) {
        _buf.addAll(d);
        _poke();
      },
      onError: (Object _) => _close(),
      onDone: _close,
      cancelOnError: true,
    );
  }

  late final StreamSubscription<Uint8List> _sub;
  final _buf = <int>[];
  bool _closed = false;
  Completer<void>? _wait;

  void _poke() {
    final w = _wait;
    _wait = null;
    w?.complete();
  }

  void _close() {
    _closed = true;
    _poke();
  }

  Future<void> _more() {
    if (_closed) throw const ProxyException(ProxyError.protocol, 'connection closed');
    return (_wait ??= Completer<void>()).future;
  }

  Future<List<int>> take(int n) async {
    while (_buf.length < n) {
      await _more();
    }
    final out = _buf.sublist(0, n);
    _buf.removeRange(0, n);
    return out;
  }

  /// Рядок до \r\n (без нього).
  Future<String> line() async {
    while (true) {
      for (var i = 0; i + 1 < _buf.length; i++) {
        if (_buf[i] == 13 && _buf[i + 1] == 10) {
          final out = latin1.decode(_buf.sublist(0, i));
          _buf.removeRange(0, i + 2);
          return out;
        }
      }
      if (_buf.length > 8192) throw const ProxyException(ProxyError.protocol, 'line too long');
      await _more();
    }
  }

  void cancel() => _sub.cancel();
}
