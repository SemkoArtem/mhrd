import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/connection.dart';
import 'frame_buffer.dart';
import 'session_protocol.dart';

/// Стани сеансу (SPEC.md → «Підключення й сеанс» → «Стани сесії»).
enum SessionState {
  resolving,
  tunneling,
  connecting,
  negotiating,
  authenticating,
  connected,
  reconnecting,
  disconnected,
  failed,
}

/// Канал до процесу сеансу. Окремий інтерфейс — щоб тести обходились без справжнього процесу.
abstract class SessionChannel {
  Stream<List<int>> get output;
  void send(Uint8List frame);
  Future<int> get exitCode;
  void kill();
}

/// Справжній процес `mhrd-session`: stdin/stdout — канал, stderr — журнал FreeRDP.
class ProcessChannel implements SessionChannel {
  ProcessChannel._(this._p) {
    // stderr треба читати, інакше процес зупиниться, коли буфер заповниться.
    _p.stderr.listen((d) => stderrTail.add(d), onError: (_) {});
  }

  final Process _p;

  /// Останні рядки журналу — для «Деталей» при збої процесу.
  final stderrTail = _Tail(4096);

  static Future<ProcessChannel> start(String executable) async =>
      ProcessChannel._(await Process.start(executable, const [], runInShell: false));

  @override
  Stream<List<int>> get output => _p.stdout;

  @override
  void send(Uint8List frame) {
    try {
      _p.stdin.add(frame);
    } on StateError {
      // процес уже завершився — повідомлення нікому
    }
  }

  @override
  Future<int> get exitCode => _p.exitCode;

  @override
  void kill() => _p.kill();

  /// Закриває stdin — так процес сеансу дізнається, що застосунок пішов.
  void closeInput() => _p.stdin.close();
}

class _Tail {
  _Tail(this.max);
  final int max;
  final _bytes = <int>[];
  void add(List<int> d) {
    _bytes.addAll(d);
    if (_bytes.length > max) _bytes.removeRange(0, _bytes.length - max);
  }

  @override
  String toString() => String.fromCharCodes(_bytes);
}

typedef FrameBufferOpener = FrameBuffer? Function(String name, int size);

/// Один сеанс RDP. Стан сеансу ніколи не змінює збережених налаштувань ПК (SPEC);
/// довіру до сертифіката зберігає SessionManager.
class RdpSession extends ChangeNotifier {
  RdpSession({
    required this.id,
    required this.connection,
    required SessionChannel channel,
    FrameBufferOpener openFrameBuffer = FrameBuffer.open,
    this.swapMouseButtons = false,
  })  : _channel = channel,
        _openFrameBuffer = openFrameBuffer;

  final String id;
  final Connection connection;
  final bool swapMouseButtons;
  final SessionChannel _channel;
  final FrameBufferOpener _openFrameBuffer;

  SessionState state = SessionState.connecting;

  /// Сертифікат, про який треба спитати користувача (поки не відповіли).
  CertificateEvent? pendingCertificate;

  /// Чому сеанс закрився (для стану failed/disconnected).
  DisconnectedEvent? ended;

  /// Поточна картинка віддаленого екрана.
  ui.Image? image;
  int width = 0, height = 0;

  FrameBuffer? _frame;
  int _stride = 0;
  bool _dirty = false, _decoding = false, _disposed = false;
  Timer? _killTimer;
  StreamSubscription<SessionEvent>? _sub;
  final _done = Completer<void>();

  bool get isActive => state != SessionState.disconnected && state != SessionState.failed;

  /// Завершується, коли процес сеансу закрився (сам, на прохання чи примусово).
  Future<void> get done => _done.future;

  /// Запускає підключення. [config] містить пароль — він іде лише в канал.
  void start(Map<String, Object?> config) {
    _sub = _channel.output.transform(const SessionEventDecoder()).listen(_onEvent, onError: (_) {});
    _channel.exitCode.then(_onExit);
    _channel.send(encodeConnect(config));
  }

  void _onEvent(SessionEvent e) {
    switch (e) {
      case StateEvent(:final state):
        this.state = state == 2 ? SessionState.connected : SessionState.connecting;
      case SurfaceEvent():
        _frame?.close();
        width = e.width;
        height = e.height;
        _stride = e.stride;
        _frame = _openFrameBuffer(e.name, e.stride * e.height);
        _dirty = true;
        _pump();
      case FrameEvent():
        _dirty = true;
        _pump();
        return; // перемалюємо, коли буде готова нова картинка
      case CertificateEvent():
        pendingCertificate = e;
        state = SessionState.negotiating;
      case DisconnectedEvent():
        ended = e;
        state = e.reason == DisconnectReason.userRequest ? SessionState.disconnected : SessionState.failed;
    }
    _notify();
  }

  void _onExit(int code) {
    _killTimer?.cancel();
    _frame?.close();
    _frame = null;
    if (ended == null) {
      // Процес зник без події «відключено» — збій. Застосунок працює далі (SPEC → стабільність).
      final ch = _channel;
      final log = ch is ProcessChannel ? '${ch.stderrTail}' : '';
      ended = DisconnectedEvent(DisconnectReason.crashed, code, log.trim());
      state = SessionState.failed;
    }
    _notify();
    if (!_done.isCompleted) _done.complete();
  }

  /// Збирає ui.Image зі спільної пам'яті. Поки попередня ще декодується, нові ділянки лише
  /// позначаються — так частота кадрів сама підлаштовується під швидкість пристрою.
  void _pump() {
    final f = _frame;
    if (_decoding || !_dirty || f == null || width == 0 || height == 0 || _disposed) return;
    _dirty = false;
    _decoding = true;
    ui.decodeImageFromPixels(f.bytes, width, height, ui.PixelFormat.bgra8888, (img) {
      _decoding = false;
      if (_disposed) {
        img.dispose();
        return;
      }
      image?.dispose();
      image = img;
      _notify();
      _pump();
    }, rowBytes: _stride);
  }

  void answerCertificate(bool accept) {
    if (pendingCertificate == null) return;
    pendingCertificate = null;
    state = SessionState.connecting;
    _channel.send(encodeCertAnswer(accept));
    _notify();
  }

  // ── Ввід ──────────────────────────────────────────────────────

  bool get _canInput => state == SessionState.connected;

  void sendKey(int scancode, bool down) {
    if (_canInput) _channel.send(encodeKey(scancode, down));
  }

  void sendMouseMove(int x, int y) {
    if (_canInput) _channel.send(encodeMouseMove(x, y));
  }

  void sendMouseButton(RemoteButton b, bool down, int x, int y) {
    if (!_canInput) return;
    final swapped = !swapMouseButtons
        ? b
        : switch (b) {
            RemoteButton.left => RemoteButton.right,
            RemoteButton.right => RemoteButton.left,
            RemoteButton.middle => RemoteButton.middle,
          };
    _channel.send(encodeMouseButton(swapped, down, x, y));
  }

  void sendWheel(int delta, {bool horizontal = false, required int x, required int y}) {
    if (_canInput && delta != 0) _channel.send(encodeMouseWheel(delta, horizontal: horizontal, x: x, y: y));
  }

  /// Просить процес відключитись сам; за 5 с — закриває примусово (SPEC → «Архітектура»).
  void disconnect() {
    if (!isActive && _killTimer == null) {
      _channel.kill();
      return;
    }
    _channel.send(encodeDisconnect());
    _killTimer ??= Timer(const Duration(seconds: 5), _channel.kill);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _killTimer?.cancel();
    _sub?.cancel();
    _frame?.close();
    image?.dispose();
    super.dispose();
  }
}
