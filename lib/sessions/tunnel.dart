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
    _p.stderr.drain<void>(); // журнал Go не потрібен, але буфер має спорожнятись
  }

  final Process _p;

  static Future<TunnelProcess> start(String executable) async =>
      TunnelProcess._(await Process.start(executable, const [], runInShell: false));

  @override
  Stream<Map<String, Object?>> get events => _p.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map((l) => jsonDecode(l))
      .where((e) => e is Map)
      .map((e) => (e as Map).cast<String, Object?>());

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
Future<int> openTunnel(TunnelChannel channel, Map<String, Object?> request) {
  final done = Completer<int>();
  late final StreamSubscription<Map<String, Object?>> sub;
  sub = channel.events.listen(
    (e) {
      switch (e['event']) {
        case 'listening':
          final port = e['port'];
          if (port is int && !done.isCompleted) done.complete(port);
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
