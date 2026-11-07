import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Канал до процесу `mhrd-tunnel` (native/tunnels): рядки JSON у stdin і з stdout.
/// Окремий інтерфейс — щоб тести обходились без справжнього процесу.
abstract class TunnelChannel {
  Stream<Map<String, Object?>> get events;
  void send(Map<String, Object?> message);
  void kill();
}

typedef TunnelFactory = Future<TunnelChannel> Function(String executable);

class TunnelProcess implements TunnelChannel {
  TunnelProcess._(this._p) {
    _p.stderr.drain<void>().catchError((Object _) {}); // журнал Go не потрібен, але буфер має спорожнятись
    _p.stdin.done.catchError((Object _) {}); // запис у вже завершений процес — не необроблена помилка
  }

  final Process _p;

  static Future<TunnelProcess> start(String executable) async =>
      TunnelProcess._(await Process.start(executable, const [], runInShell: false));

  /// Спільний для всіх слухачів: спершу чекаємо відкриття тунелю, потім — заміри затримки.
  @override
  late final Stream<Map<String, Object?>> events = _p.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map((l) => jsonDecode(l))
      .where((e) => e is Map)
      .map((e) => (e as Map).cast<String, Object?>())
      .asBroadcastStream();

  @override
  void send(Map<String, Object?> message) {
    try {
      _p.stdin.writeln(jsonEncode(message));
    } on StateError {
      // процес уже завершився
    }
  }

  @override
  void kill() => _p.kill();
}

/// Чому тунель не відкрився. Коди — як у native/tunnels (поле "code"); UI перекладає.
enum TunnelError {
  config,
  endpointDns,
  start,
  unreachable,
  connect,
  listen,
  /// Перевірка: сервер WireGuard не відповів на рукостискання.
  handshake,
  failed,
}

class TunnelException implements Exception {
  const TunnelException(this.error, [this.detail = '']);
  final TunnelError error;

  /// Технічні подробиці (без секретів) — для «Деталей».
  final String detail;

  @override
  String toString() => 'TunnelException(${error.name}: $detail)';
}

/// Надсилає [request] і чекає, доки тунель відкриє локальний порт. Повертає порт на 127.0.0.1.
Future<int> openTunnel(TunnelChannel channel, Map<String, Object?> request) =>
    _request(channel, request, 'listening', 'port');

/// Перевірка, чи тунель живий ([request] з `"check": true`). Повертає, за скільки мс сервер
/// відповів на рукостискання, а якщо в [request] є `target` — за скільки відповів ПК крізь тунель.
Future<int> checkTunnel(TunnelChannel channel, Map<String, Object?> request) =>
    _request(channel, request, 'ok', request['target'] != null ? 'targetMs' : 'handshakeMs');

/// Номер запиту до тунелю: кілька сеансів ділять один процес, і відповіді (pong, listening)
/// розрізняються за ним.
int _nextRequestId = 1;

/// Затримка до ПК крізь уже відкритий тунель, мс. [target] — «host:port» ПК (тунель може вести до
/// кількох); null — до першого ПК тунелю.
Future<int> pingTunnel(TunnelChannel channel, {String? target}) {
  final id = _nextRequestId++;
  final done = Completer<int>();
  late final StreamSubscription<Map<String, Object?>> sub;
  sub = channel.events.listen(
    (e) {
      if (e['event'] != 'pong' || e['id'] != id || done.isCompleted) return;
      final ms = e['ms'];
      ms is int
          ? done.complete(ms)
          : done.completeError(TunnelException(TunnelError.unreachable, '${e['error'] ?? ''}'));
    },
    onDone: () {
      if (!done.isCompleted) done.completeError(const TunnelException(TunnelError.failed));
    },
  );
  channel.send({'ping': true, 'id': id, if (target != null) 'target': target});
  return done.future
      .timeout(const Duration(seconds: 25), onTimeout: () => throw const TunnelException(TunnelError.unreachable))
      .whenComplete(sub.cancel);
}

/// Ще один ПК ([target], «host:port») крізь уже відкритий тунель — для наступного сеансу з тим самим
/// профілем. Повертає порт на 127.0.0.1.
Future<int> forwardTunnel(TunnelChannel channel, String target) {
  final id = _nextRequestId++;
  final done = Completer<int>();
  late final StreamSubscription<Map<String, Object?>> sub;
  sub = channel.events.listen(
    (e) {
      if (e['id'] != id || done.isCompleted) return;
      switch (e['event']) {
        case 'listening':
          final port = e['port'];
          port is int ? done.complete(port) : done.completeError(const TunnelException(TunnelError.failed));
        case 'forwardError':
          final code = e['code'] is String ? e['code'] as String : '';
          final err = TunnelError.values.where((x) => x.name == code).firstOrNull ?? TunnelError.failed;
          done.completeError(TunnelException(err, '${e['detail'] ?? ''}'));
      }
    },
    onDone: () {
      if (!done.isCompleted) done.completeError(const TunnelException(TunnelError.failed));
    },
  );
  channel.send({'forward': target, 'id': id});
  return done.future
      .timeout(const Duration(seconds: 30), onTimeout: () => throw const TunnelException(TunnelError.unreachable))
      .whenComplete(sub.cancel);
}

Future<int> _request(TunnelChannel channel, Map<String, Object?> request, String okEvent, String field) {
  final done = Completer<int>();
  late final StreamSubscription<Map<String, Object?>> sub;
  sub = channel.events.listen(
    (e) {
      switch (e['event']) {
        case final String ev when ev == okEvent:
          final v = e[field];
          if (v is int && !done.isCompleted) done.complete(v);
        case 'error':
          final code = e['code'] is String ? e['code'] as String : '';
          final err = TunnelError.values.where((x) => x.name == code).firstOrNull ?? TunnelError.failed;
          if (!done.isCompleted) done.completeError(TunnelException(err, '${e['detail'] ?? ''}'));
      }
    },
    onError: (Object _) {
      if (!done.isCompleted) done.completeError(const TunnelException(TunnelError.failed));
    },
    onDone: () {
      if (!done.isCompleted) done.completeError(const TunnelException(TunnelError.failed));
    },
  );
  channel.send(request);
  return done.future.whenComplete(sub.cancel);
}
