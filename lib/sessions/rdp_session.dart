import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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

  /// PID процесу сеансу — за ним стежить тунель, щоб жити рівно стільки ж.
  int get pid;
}

/// Справжній процес `mhrd-session`: stdin/stdout — канал, stderr — журнал FreeRDP.
class ProcessChannel implements SessionChannel {
  ProcessChannel._(this._p) {
    // stderr треба читати, інакше процес зупиниться, коли буфер заповниться.
    _p.stderr.listen((d) => stderrTail.add(d), onError: (_) {});
    // Запис у вже завершений процес дає помилку асинхронно — без цього вона б вилетіла необробленою.
    _p.stdin.done.catchError((Object _) {});
  }

  final Process _p;

  /// Останні рядки журналу — для «Деталей» при збої процесу і для журналу сеансів.
  final stderrTail = _Tail(16384);

  static Future<ProcessChannel> start(String executable, {Map<String, String>? environment}) async =>
      ProcessChannel._(await Process.start(executable, const [], runInShell: false, environment: environment));

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

  @override
  int get pid => _p.pid;

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
  String toString() => utf8.decode(_bytes, allowMalformed: true);
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

  /// Плашку у власному вікні сеансу перемістили — щоб запам'ятати для наступних сеансів.
  void Function(BarEvent e)? onBarMoved;

  /// Вікно сеансу просить екранну клавіатуру ОС.
  void Function()? onKeyboard;

  /// Текст, скопійований на віддаленому ПК (Android: екран сеансу кладе його в буфер телефона).
  void Function(String text)? onClipText;

  /// Поточна картинка віддаленого екрана.
  ui.Image? image;
  int width = 0, height = 0;

  FrameBuffer? _frame;
  int _stride = 0;
  bool _decoding = false, _disposed = false;

  /// Наступну картинку зібрати цілком (новий розмір кадру, ще немає попередньої).
  bool _full = true;

  /// Ділянки, що змінились після останньої картинки: (ліво, верх, право, низ).
  final _rects = <(int, int, int, int)>[];
  Timer? _killTimer;
  StreamSubscription<SessionEvent>? _sub;
  final _done = Completer<void>();

  bool get isActive => state != SessionState.disconnected && state != SessionState.failed;

  /// Завершується, коли процес сеансу закрився (сам, на прохання чи примусово).
  Future<void> get done => _done.future;

  /// Журнал FreeRDP (stderr процесу) — для журналу сеансів.
  String get engineLog {
    final ch = _channel;
    return ch is ProcessChannel ? '${ch.stderrTail}' : '';
  }

  /// Запускає підключення. [config] містить пароль — він іде лише в канал.
  void start(Map<String, Object?> config) {
    _sub = _channel.output.transform(const SessionEventDecoder()).listen(_onEvent, onError: (_) {});
    _channel.exitCode.then(_onExit);
    _channel.send(encodeConnect(config));
  }

  void _onEvent(SessionEvent e) {
    switch (e) {
      case StateEvent(:final state):
        this.state = switch (state) {
          2 => SessionState.connected,
          3 => SessionState.reconnecting, // зв'язок обірвався, mhrd-session відновлює сам
          _ => SessionState.connecting,
        };
      case SurfaceEvent():
        _frame?.close();
        width = e.width;
        height = e.height;
        _requestedSize = null; // новий розмір від сервера — можна просити знову
        _stride = e.stride;
        _frame = _openFrameBuffer(e.name, e.stride * e.height);
        _full = true;
        _rects.clear();
        _pump();
      case FrameEvent():
        _markDirty(e.x, e.y, e.w, e.h);
        _pump();
        return; // перемалюємо, коли буде готова нова картинка
      case CertificateEvent():
        pendingCertificate = e;
        state = SessionState.negotiating;
      case DisconnectedEvent():
        ended = e;
        state = e.reason == DisconnectReason.userRequest ? SessionState.disconnected : SessionState.failed;
      case BarEvent():
        onBarMoved?.call(e);
        return;
      case ClipTextEvent(:final text):
        onClipText?.call(text);
      case KeyboardEvent():
        onKeyboard?.call();
        return;
    }
    _notify();
  }

  void _onExit(int code) {
    _killTimer?.cancel();
    _frame?.close();
    _frame = null;
    if (ended == null) {
      // Процес зник без події «відключено» — збій. Застосунок працює далі (SPEC → стабільність).
      ended = DisconnectedEvent(DisconnectReason.crashed, code, engineLog.trim());
      state = SessionState.failed;
    }
    _notify();
    if (!_done.isCompleted) _done.complete();
  }

  /// Ділянка кадру змінилась: додаємо до списку, зливаючи з сусідніми (далеко розкидані — окремо,
  /// щоб годинник у куті й курсор в іншому не перетворились на весь екран).
  void _markDirty(int x, int y, int w, int h) {
    var r = (x.clamp(0, width), y.clamp(0, height), (x + w).clamp(0, width), (y + h).clamp(0, height));
    if (r.$1 >= r.$3 || r.$2 >= r.$4) return;
    const slack = 32;
    for (var i = 0; i < _rects.length;) {
      final o = _rects[i];
      if (r.$1 <= o.$3 + slack && o.$1 <= r.$3 + slack && r.$2 <= o.$4 + slack && o.$2 <= r.$4 + slack) {
        r = (math.min(r.$1, o.$1), math.min(r.$2, o.$2), math.max(r.$3, o.$3), math.max(r.$4, o.$4));
        _rects.removeAt(i);
        i = 0; // збільшена ділянка може тепер зачепити й ті, що вже переглянули
      } else {
        i++;
      }
    }
    _rects.add(r);
    if (_rects.length > 8) {
      final all = _rects.reduce((a, b) =>
          (math.min(a.$1, b.$1), math.min(a.$2, b.$2), math.max(a.$3, b.$3), math.max(a.$4, b.$4)));
      _rects
        ..clear()
        ..add(all);
    }
  }

  /// Збирає ui.Image зі спільної пам'яті. Поки попередня ще декодується, нові ділянки лише
  /// позначаються — так частота кадрів сама підлаштовується під швидкість пристрою.
  /// Змінилась невелика частина — копіюються лише змінені ділянки, а нова картинка складається з
  /// попередньої й цих ділянок на відеокарті (без копіювання всього кадру процесором).
  void _pump() {
    final f = _frame;
    if (_decoding || f == null || width == 0 || height == 0 || _disposed) return;
    if (!_full && _rects.isEmpty) return;
    final old = image;
    final area = _rects.fold(0, (a, r) => a + (r.$3 - r.$1) * (r.$4 - r.$2));
    if (_full || old == null || old.width != width || old.height != height || area * 2 > width * height) {
      _full = false;
      _rects.clear();
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
      return;
    }
    final rects = List.of(_rects);
    _rects.clear();
    _decoding = true;
    final parts = <(int, int, ui.Image)>[];
    var left = rects.length;
    final src = f.bytes;
    for (final (l, t, r, b) in rects) {
      final w = r - l, h = b - t, row = w * 4;
      final buf = Uint8List(row * h);
      for (var y = 0; y < h; y++) {
        final from = (t + y) * _stride + l * 4;
        buf.setRange(y * row, y * row + row, src, from);
      }
      ui.decodeImageFromPixels(buf, w, h, ui.PixelFormat.bgra8888, (img) {
        parts.add((l, t, img));
        if (--left == 0) _compose(parts);
      });
    }
  }

  /// Попередня картинка + змінені ділянки → нова картинка (на відеокарті).
  void _compose(List<(int, int, ui.Image)> parts) {
    _decoding = false;
    final old = image;
    if (_disposed || old == null || old.width != width || old.height != height) {
      for (final p in parts) {
        p.$3.dispose();
      }
      _full = !_disposed; // розмір змінився, поки складали — наступна цілком
      _pump();
      return;
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..blendMode = ui.BlendMode.src;
    canvas.drawImage(old, ui.Offset.zero, paint);
    for (final (x, y, img) in parts) {
      canvas.drawImage(img, ui.Offset(x.toDouble(), y.toDouble()), paint);
      img.dispose();
    }
    final picture = recorder.endRecording();
    final next = picture.toImageSync(width, height);
    picture.dispose();
    old.dispose();
    image = next;
    _notify();
    _pump();
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

  /// Дотик сенсора телефона — справжнім дотиком у Windows (режим «Дотик», як у клієнта Microsoft).
  void sendTouch(int flags, int finger, int x, int y) {
    if (_canInput) _channel.send(encodeTouch(flags, finger, x, y));
  }

  /// Текст буфера телефона — щоб на віддаленому ПК його можна було вставити (Android).
  void sendClipText(String text) {
    if (_canInput) _channel.send(encodeClipText(text));
  }

  /// Текст з екранної клавіатури телефона — символами, без клавіш (кирилиця, емодзі тощо).
  void sendText(String text) {
    if (!_canInput) return;
    for (final unit in text.codeUnits) {
      _channel.send(encodeUnicode(unit));
    }
  }

  /// Рух миші — не частіше разу на кадр: миша дає до 1000 подій/с, і через інтернет
  /// кожна окремим пакетом забиває канал. Перший рух іде одразу, решта в межах 16 мс —
  /// одним повідомленням з останньою позицією.
  static const moveInterval = Duration(milliseconds: 16);
  (int, int)? _pendingMove;
  Timer? _moveTimer;

  void sendMouseMove(int x, int y) {
    if (!_canInput) return;
    if (_moveTimer != null) {
      _pendingMove = (x, y);
      return;
    }
    _channel.send(encodeMouseMove(x, y));
    _moveTimer = Timer(moveInterval, _flushMove);
  }

  void _flushMove() {
    _moveTimer = null;
    final p = _pendingMove;
    _pendingMove = null;
    if (p != null && _canInput) {
      _channel.send(encodeMouseMove(p.$1, p.$2));
      _moveTimer = Timer(moveInterval, _flushMove);
    }
  }

  /// Перед кліком чи прокруткою — відкладений рух, щоб подія влучила в правильне місце.
  void _sendPendingMove() {
    _moveTimer?.cancel();
    _moveTimer = null;
    final p = _pendingMove;
    _pendingMove = null;
    if (p != null) _channel.send(encodeMouseMove(p.$1, p.$2));
  }

  void sendMouseButton(RemoteButton b, bool down, int x, int y) {
    if (!_canInput) return;
    _sendPendingMove();
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
    if (!_canInput || delta == 0) return;
    _sendPendingMove();
    _channel.send(encodeMouseWheel(delta, horizontal: horizontal, x: x, y: y));
  }

  (int, int)? _requestedSize;

  /// Просить сервер змінити роздільність під вікно. Ширину округлюємо до парної (MS-RDPEDISP).
  /// Якщо сервер не вміє (немає Display Control), картинка просто масштабується далі.
  void requestResize(int width, int height) {
    if (!_canInput) return;
    final w = width.clamp(200, 8192) & ~1, h = height.clamp(200, 8192);
    if ((w, h) == (this.width, this.height) || (w, h) == _requestedSize) return;
    _requestedSize = (w, h);
    _channel.send(encodeResize(w, h));
  }

  /// Виводить наперед вікно сеансу, яке малює сам процес (десктоп).
  void focusWindow() {
    if (isActive) _channel.send(encodeFocus());
  }

  /// Затримка до ПК через маршрут — показати на плашці (−1 — ПК не відповів).
  void sendLatency(int ms) {
    if (isActive) _channel.send(encodeLatency(ms));
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
    if (_disposed) return;
    _disposed = true;
    _killTimer?.cancel();
    _moveTimer?.cancel();
    _sub?.cancel();
    _frame?.close();
    image?.dispose();
    super.dispose();
  }
}
