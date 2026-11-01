import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Канал між застосунком і процесом `mhrd-session` (SPEC → «Архітектура»).
/// Кадр: u32 LE довжина (1 байт типу + дані), u8 тип, дані. Те саме — native/session/src/proto.h.
abstract final class Msg {
  static const connect = 0x01;
  static const key = 0x02;
  static const mouseMove = 0x03;
  static const mouseButton = 0x04;
  static const mouseWheel = 0x05;
  static const certAnswer = 0x06;
  static const disconnect = 0x07;
  static const resize = 0x08;
  static const focus = 0x09;
  static const latency = 0x0A;

  static const evtState = 0x81;
  static const evtSurface = 0x82;
  static const evtFrame = 0x83;
  static const evtCertificate = 0x84;
  static const evtDisconnected = 0x85;
  static const evtBar = 0x86;
  static const evtKeyboard = 0x87;
}

/// Кнопки миші в протоколі.
enum RemoteButton { left, right, middle }

/// Чому сеанс закрився. Порядок = номери категорій у proto.h (DISC_*); [crashed] — лише в Dart.
enum DisconnectReason {
  userRequest,
  network,
  authFailed,
  noCredentials,
  accountLocked,
  passwordExpired,
  certRejected,
  tls,
  serverLogoff,
  otherConnection,
  serverDenied,
  other,
  crashed,
}

// ── Повідомлення застосунку ──────────────────────────────────────

Uint8List encodeFrame(int type, [List<int> payload = const []]) {
  final b = BytesBuilder(copy: false)
    ..add((ByteData(4)..setUint32(0, payload.length + 1, Endian.little)).buffer.asUint8List())
    ..addByte(type)
    ..add(payload);
  return b.toBytes();
}

/// Налаштування підключення. Пароль іде лише сюди — ніколи в аргументи процесу.
Uint8List encodeConnect(Map<String, Object?> config) => encodeFrame(Msg.connect, utf8.encode(jsonEncode(config)));

Uint8List encodeKey(int scancode, bool down) =>
    encodeFrame(Msg.key, [scancode & 0xFF, (scancode >> 8) & 0xFF, down ? 1 : 0]);

Uint8List encodeMouseMove(int x, int y) => encodeFrame(Msg.mouseMove, _u16s([x, y]));

Uint8List encodeMouseButton(RemoteButton b, bool down, int x, int y) =>
    encodeFrame(Msg.mouseButton, [b.index + 1, down ? 1 : 0, ..._u16s([x, y])]);

/// [delta] — у «кліках» Windows: +120 = один крок від себе (вгору), −120 — до себе.
Uint8List encodeMouseWheel(int delta, {bool horizontal = false, required int x, required int y}) =>
    encodeFrame(Msg.mouseWheel, [..._u16s([delta & 0xFFFF]), horizontal ? 1 : 0, ..._u16s([x, y])]);

Uint8List encodeCertAnswer(bool accept) => encodeFrame(Msg.certAnswer, [accept ? 1 : 0]);

Uint8List encodeDisconnect() => encodeFrame(Msg.disconnect);

/// Нова роздільність віддаленого екрана (канал Display Control). Сервер відповість SurfaceEvent.
Uint8List encodeResize(int width, int height) => encodeFrame(Msg.resize, _u16s([width, height]));

/// Показати власне вікно сеансу (режим nativeWindow) — розгорнути й вивести наперед.
Uint8List encodeFocus() => encodeFrame(Msg.focus);

/// Затримка до ПК через увесь маршрут для плашки вікна сеансу: мс, −1 — ПК не відповів.
Uint8List encodeLatency(int ms) =>
    encodeFrame(Msg.latency, (ByteData(4)..setInt32(0, ms, Endian.little)).buffer.asUint8List());

List<int> _u16s(List<int> values) => [
      for (final v in values) ...[v.clamp(0, 0xFFFF) & 0xFF, (v.clamp(0, 0xFFFF) >> 8) & 0xFF],
    ];

// ── Події від mhrd-session ───────────────────────────────────────

sealed class SessionEvent {
  const SessionEvent();
}

/// 1 — з'єднання, 2 — підключено, 3 — зв'язок обірвався, йде перепідключення.
class StateEvent extends SessionEvent {
  const StateEvent(this.state);
  final int state;
}

/// Нова спільна пам'ять під картинку (на старті й після зміни роздільності сервером).
class SurfaceEvent extends SessionEvent {
  const SurfaceEvent(this.width, this.height, this.stride, this.name);
  final int width, height, stride;
  final String name;
}

class FrameEvent extends SessionEvent {
  const FrameEvent(this.x, this.y, this.w, this.h);
  final int x, y, w, h;
}

class CertificateEvent extends SessionEvent {
  const CertificateEvent({
    required this.host,
    required this.port,
    required this.commonName,
    required this.subject,
    required this.issuer,
    required this.fingerprint,
    required this.changed,
  });
  final String host, commonName, subject, issuer, fingerprint;
  final int port;

  /// Раніше довіряли іншому сертифікату — червоне попередження.
  final bool changed;
}

class DisconnectedEvent extends SessionEvent {
  const DisconnectedEvent(this.reason, this.code, this.details);
  final DisconnectReason reason;

  /// Код помилки FreeRDP — для «Деталей».
  final int code;
  final String details;
}

/// Плашку у вікні сеансу перетягнули чи змінили її довжину.
class BarEvent extends SessionEvent {
  const BarEvent(this.edge, this.pos, this.length);

  /// 0 — верх, 1 — низ, 2 — ліво, 3 — право.
  final int edge;

  /// Центр уздовж краю, 0..10000.
  final int pos;

  /// Довжина в одиницях інтерфейсу.
  final int length;
}

/// Кнопка «Екранна клавіатура» у вікні сеансу: osk.exe запускає застосунок (сеансу не можна).
class KeyboardEvent extends SessionEvent {
  const KeyboardEvent();
}

/// Перетворює байти з stdout процесу на події. Незнайомі типи пропускає.
class SessionEventDecoder extends StreamTransformerBase<List<int>, SessionEvent> {
  const SessionEventDecoder();

  @override
  Stream<SessionEvent> bind(Stream<List<int>> stream) async* {
    final buf = BytesBuilder(copy: false);
    var pending = Uint8List(0);
    await for (final chunk in stream) {
      buf
        ..add(pending)
        ..add(chunk);
      pending = buf.takeBytes();
      var off = 0;
      while (pending.length - off >= 5) {
        final bd = ByteData.sublistView(pending, off);
        final len = bd.getUint32(0, Endian.little);
        if (len == 0) throw const FormatException('session: zero-length frame');
        if (pending.length - off - 4 < len) break;
        final type = pending[off + 4];
        final data = Uint8List.sublistView(pending, off + 5, off + 4 + len);
        off += 4 + len;
        final e = _decode(type, data);
        if (e != null) yield e;
      }
      pending = Uint8List.fromList(Uint8List.sublistView(pending, off));
    }
  }

  static SessionEvent? _decode(int type, Uint8List d) {
    final bd = ByteData.sublistView(d);
    int u32(int o) => bd.getUint32(o, Endian.little);
    switch (type) {
      case Msg.evtState when d.isNotEmpty:
        return StateEvent(d[0]);
      case Msg.evtSurface when d.length >= 12:
        return SurfaceEvent(u32(0), u32(4), u32(8), utf8.decode(d.sublist(12), allowMalformed: true));
      case Msg.evtFrame when d.length >= 16:
        return FrameEvent(u32(0), u32(4), u32(8), u32(12));
      case Msg.evtCertificate:
        final j = jsonDecode(utf8.decode(d, allowMalformed: true));
        if (j is! Map) return null;
        String s(String k) => j[k] is String ? j[k] as String : '';
        return CertificateEvent(
          host: s('host'),
          port: j['port'] is num ? (j['port'] as num).toInt() : 0,
          commonName: s('commonName'),
          subject: s('subject'),
          issuer: s('issuer'),
          fingerprint: s('fingerprint'),
          changed: j['changed'] == true,
        );
      case Msg.evtDisconnected when d.length >= 5:
        final r = d[0] < DisconnectReason.values.length ? DisconnectReason.values[d[0]] : DisconnectReason.other;
        return DisconnectedEvent(r, u32(1), utf8.decode(d.sublist(5), allowMalformed: true));
      case Msg.evtBar when d.length >= 5:
        return BarEvent(d[0], bd.getUint16(1, Endian.little), bd.getUint16(3, Endian.little));
      case Msg.evtKeyboard:
        return const KeyboardEvent();
      default:
        return null;
    }
  }
}
