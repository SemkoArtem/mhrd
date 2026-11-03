import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/connection.dart';
import '../models/entities.dart';
import '../storage/repository.dart';
import '../platform/shell_bridge.dart';
import '../util/app_files.dart';
import 'rdp_session.dart';
import 'route_health.dart';
import 'session_log.dart';
import 'tunnel.dart';

export 'rdp_session.dart' show RdpSession, SessionState;
export 'route_health.dart'
    show HealthState, ProbeError, ProbeException, ProxyError, ProxyException, RouteHealth, RouteStatus;
export 'session_log.dart' show SessionLog;
export 'tunnel.dart' show TunnelError, TunnelException;

/// Облікові дані для одного підключення. password == null — UI має спитати.
class ConnectCredentials {
  const ConnectCredentials({this.username, this.password});
  final String? username;
  final String? password;

  bool get complete => (username ?? '').isNotEmpty && (password ?? '').isNotEmpty;
}

typedef ChannelFactory = Future<SessionChannel> Function(String executable);

/// Чому маршрут ПК не можна використати. UI перекладає код (SPEC: логіка повертає коди).
enum RouteError {
  proxyMissing,
  gatewayMissing,
  tunnelMissing,
  /// Тип тунелю, якого ще не вміємо (поки є лише WireGuard).
  tunnelUnsupported,
  /// Немає mhrd-tunnel поруч із програмою.
  tunnelEngineMissing,
  /// RD Gateway разом із тунелем: шлюз пішов би в обхід тунелю.
  gatewayWithTunnel,
}

class RouteException implements Exception {
  const RouteException(this.error);
  final RouteError error;
  @override
  String toString() => 'RouteException(${error.name})';
}

/// Керує активними сеансами. Кожен сеанс — окремий процес `mhrd-session` (SPEC → «Архітектура»).
class SessionManager extends ChangeNotifier {
  SessionManager(
    this.repo, {
    String? enginePath,
    ChannelFactory? channelFactory,
    String? tunnelPath,
    TunnelFactory? tunnelFactory,
    this.log,
    this.latencyInterval = const Duration(seconds: 10),
    this.files,
  })  : enginePath = enginePath ?? _defaultEnginePath(),
        tunnelPath = tunnelPath ?? _besideApp('mhrd-tunnel'),
        _channelFactory = channelFactory ?? ProcessChannel.start,
        _tunnelFactory = tunnelFactory ?? TunnelProcess.start;

  final Repository repo;

  /// Стан тунелів і проксі для лівої панелі (перевірки запускає main).
  late final RouteHealth health = RouteHealth(repo, tunnelPath: tunnelPath, tunnelFactory: _tunnelFactory);

  /// Шлях до `mhrd-tunnel` (WireGuard); null — модуля тунелів немає.
  final String? tunnelPath;
  final TunnelFactory _tunnelFactory;

  /// Куди записати сеанс, коли він завершився (null — не записувати).
  final SessionLog? log;

  /// Як часто міряти затримку до ПК для плашки вікна сеансу.
  final Duration latencyInterval;

  /// Мініатюри й картинки ПК (null — у тестах).
  final AppFiles? files;

  /// Шлях до `mhrd-session`; null — модуля підключення немає (наприклад, ще не зібрано).
  final String? enginePath;
  final ChannelFactory _channelFactory;
  final List<RdpSession> sessions = [];

  bool get engineAvailable => enginePath != null;

  /// На десктопі кожен сеанс — окреме вікно, яке малює сам `mhrd-session` (SDL3);
  /// на мобільних — екран сеансу всередині застосунку.
  bool get nativeWindows => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// `mhrd-session` лежить поруч із головною програмою (його кладе туди збірка Windows чи Linux).
  static String? _defaultEnginePath() => _besideApp('mhrd-session');

  /// Модуль [name] поруч із програмою (на Windows — `name.exe`); null — його немає.
  static String? _besideApp(String name) {
    if (!Platform.isWindows && !Platform.isLinux) return null;
    final file = Platform.isWindows ? '$name.exe' : name;
    final path = p.join(p.dirname(Platform.resolvedExecutable), file);
    return File(path).existsSync() ? path : null;
  }

  /// Акаунт для підключення: вибраний у «Підключитись як…» або перший у ПК.
  /// Пароль читається із системного сховища, якщо акаунт його зберігає.
  Future<ConnectCredentials> credentialsFor(Connection c, {String? credentialId}) async {
    final id = credentialId ?? (c.credentialIds.isEmpty ? null : c.credentialIds.first);
    final cred = id == null ? null : repo.credentials[id];
    if (cred == null) return const ConnectCredentials();
    final pw = cred.authMode == AuthMode.savedPassword ? await repo.secrets.read(cred.secretKey) : null;
    return ConnectCredentials(username: cred.username, password: pw);
  }

  /// Маршрут до ПК для mhrd-session: проксі й RD Gateway (з паролями зі сховища).
  /// Маршрут, якого ще не вміємо, — помилка, а не тихе підключення напряму в обхід тунелю.
  /// [gatewayPassword] — якщо пароль акаунта шлюзу не збережено й UI щойно спитав.
  Future<Map<String, Object?>> routeConfig(Connection c, {String? gatewayPassword}) async {
    final out = <String, Object?>{};
    switch (c.route) {
      case RouteKind.direct:
        break;
      case RouteKind.proxy:
        final p = repo.proxies[c.routeRefId];
        if (p == null) throw const RouteException(RouteError.proxyMissing);
        out['proxy'] = {
          'type': p.type == ProxyType.http ? 'http' : 'socks5',
          'host': p.host,
          'port': p.port,
          'username': p.username,
          'password': p.username.isEmpty ? '' : (await repo.secrets.read(p.secretKey) ?? ''),
        };
      case RouteKind.tunnel:
        break; // тунель відкриває mhrd-tunnel — див. [tunnelRequest]
    }
    if (c.gatewayId != null) {
      final g = repo.gateways[c.gatewayId];
      if (g == null) throw const RouteException(RouteError.gatewayMissing);
      if (c.route == RouteKind.tunnel) {
        throw const RouteException(RouteError.gatewayWithTunnel);
      }
      final own = g.credentialMode == GatewayCredentialMode.own ? repo.credentials[g.credentialId] : null;
      out['gateway'] = {
        'host': g.host,
        'port': g.port,
        'bypassLocal': c.gatewayBypassLocal,
        'sameCredentials': own == null,
        if (own != null) 'username': own.username,
        if (own != null)
          'password': gatewayPassword ??
              (own.authMode == AuthMode.savedPassword ? await repo.secrets.read(own.secretKey) : null) ??
              '',
      };
    }
    return out;
  }

  /// Запит для mhrd-tunnel (з ключами й паролями зі сховища) або null, якщо тунель не потрібен.
  Future<Map<String, Object?>?> tunnelRequest(Connection c) async {
    final target = c.host.contains(':') ? '[${c.host}]:${c.port}' : '${c.host}:${c.port}';
    switch (c.route) {
      case RouteKind.tunnel:
        final t = repo.tunnels[c.routeRefId];
        if (t == null) throw const RouteException(RouteError.tunnelMissing);
        if (t.type != TunnelType.wireguard) throw const RouteException(RouteError.tunnelUnsupported);
        return {'type': 'wireguard', 'target': target, 'wireguard': await repo.wireGuardConfig(t)};
      case RouteKind.direct:
      case RouteKind.proxy:
        return null;
    }
  }

  /// Акаунт шлюзу, для якого треба спитати пароль (свій акаунт без збереженого пароля), або null.
  Credential? gatewayAccountToAsk(Connection c) {
    final g = repo.gateways[c.gatewayId];
    if (g == null || g.credentialMode != GatewayCredentialMode.own) return null;
    final cred = repo.credentials[g.credentialId];
    return cred != null && cred.authMode != AuthMode.savedPassword ? cred : null;
  }

  /// Запускає сеанс. [width]/[height] — бажана роздільність віддаленого екрана.
  /// [window] — налаштування власного вікна процесу (заголовок, шрифт, мітки, кольори…);
  /// із ним сеанс сам зникає зі списку, щойно процес завершився.
  Future<RdpSession> start(
    Connection c, {
    required String username,
    required String password,
    required int width,
    required int height,
    int scale = 100,
    Map<String, Object?>? window,
    String? gatewayPassword,
  }) async {
    final exe = enginePath;
    if (exe == null) throw StateError('mhrd-session not found');
    // Маршрут — до запуску процесу: помилка тут не має лишити напівживий сеанс.
    final route = await routeConfig(c, gatewayPassword: gatewayPassword);
    final tunnelReq = await tunnelRequest(c);
    var host = c.host;
    var port = c.port;
    TunnelChannel? tunnel;
    if (tunnelReq != null) {
      final texe = tunnelPath;
      if (texe == null) throw const RouteException(RouteError.tunnelEngineMissing);
      tunnel = await _tunnelFactory(texe);
      try {
        // mhrd-tunnel сам обмежує DNS (10 с) і перевірку ПК (20 с); це — запобіжник від зависання.
        port = await openTunnel(tunnel, tunnelReq).timeout(const Duration(seconds: 60),
            onTimeout: () => throw const TunnelException(TunnelError.unreachable, 'timeout'));
      } catch (_) {
        tunnel.kill();
        rethrow;
      }
      host = '127.0.0.1'; // тунель слухає лише локально
    }
    if (repo.connections.containsKey(c.id)) repo.markUsed(c.id);
    final SessionChannel channel;
    try {
      channel = await _channelFactory(exe);
    } catch (_) {
      tunnel?.kill();
      rethrow;
    }
    // Тунель живе, поки живий процес сеансу (і переживає перепідключення FreeRDP).
    tunnel?.send({'watchPid': channel.pid});
    final s = RdpSession(
      id: '${c.id}#${DateTime.now().microsecondsSinceEpoch}',
      connection: c,
      channel: channel,
      swapMouseButtons: c.swapMouseButtons,
    );
    sessions.add(s);
    s.onBarMoved = (e) => repo.updateSettings(repo.settings.copyWith(
        bar: BarPlacement(edge: BarEdge.values[e.edge.clamp(0, 3)], pos: e.pos, length: e.length)));
    s.onKeyboard = () => ShellBridge.instance.openKeyboard();
    s.start({
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'width': width,
      'height': height,
      // Масштаб інтерфейсу на ПК: явний з налаштувань ПК, інакше — як у цієї ОС.
      'scale': c.display.scalePercent != 100 ? c.display.scalePercent : scale,
      'colorDepth': c.display.colorDepth,
      'adminSession': c.adminSession,
      'reconnect': c.reconnectOnDrop,
      'certPin': c.certPin,
      // Пристрої (SPEC → «Перенаправлення пристроїв»)
      'clipboard': c.devices.clipboard,
      'sound': c.devices.sound.name, // local | remote | off
      'microphone': c.devices.microphone,
      // Режим доступу виконує наш канал дисків (native/session/vcpkg-overlay/freerdp/mhrd).
      'folders': [
        for (final f in c.devices.folders) {'name': f.name, 'path': f.path, 'access': f.access.name},
      ],
      ...route,
      if (window != null) ...{
        'nativeWindow': true,
        'bar': repo.settings.bar.toJson(),
        // Мініатюра для плитки ПК — лише для збережених ПК і якщо мініатюри не вимкнено.
        if (files != null && repo.settings.showPreviews && repo.connections.containsKey(c.id))
          'thumbnailPath': _thumbnailPath(c.id),
        ...window,
      },
    });
    final log = this.log;
    if (log != null) s.done.then((_) => log.write(s));
    // Сеанс у застосунку завершився, а екран ще відкритий — лічильник активних (служба Android) оновлюється.
    if (window == null) s.done.then((_) => notifyListeners());
    if (window != null) {
      final timer = _watchLatency(s, tunnel);
      s.done.then((_) {
        timer.cancel();
        if (sessions.remove(s)) notifyListeners();
        s.dispose();
      });
    }
    notifyListeners();
    return s;
  }

  String _thumbnailPath(String connectionId) {
    final f = files!.thumbnail(connectionId);
    f.parent.createSync(recursive: true);
    return f.path;
  }

  /// Поки сеанс підключений — затримка до ПК через увесь маршрут на плашку, кожні [latencyInterval].
  Timer _watchLatency(RdpSession s, TunnelChannel? tunnel) {
    var busy = false;
    return Timer.periodic(latencyInterval, (_) async {
      if (busy || s.state != SessionState.connected) return;
      busy = true;
      try {
        s.sendLatency(await health.measure(s.connection, sessionTunnel: tunnel));
      } on Exception {
        s.sendLatency(-1);
      } finally {
        busy = false;
      }
    });
  }

  /// Користувач довіряє сертифікату: запам'ятовуємо відбиток у ПК (для швидкого
  /// підключення, якого немає в списку, просто продовжуємо).
  void trustCertificate(RdpSession s, String fingerprint) {
    final c = repo.connections[s.connection.id];
    if (c != null) repo.saveConnection(c.copyWith(certPin: () => fingerprint));
  }

  RdpSession? forConnection(String connectionId) {
    for (final s in sessions) {
      if (s.connection.id == connectionId && s.isActive) return s;
    }
    return null;
  }

  /// Прибирає сеанс зі списку (після відключення чи закриття екрана). Звільняє його,
  /// лише коли процес справді завершився — інакше не спрацює примусове закриття за 5 с.
  void close(RdpSession s) {
    if (!sessions.remove(s)) return;
    s.disconnect();
    s.done.then((_) => s.dispose());
    notifyListeners();
  }
}
