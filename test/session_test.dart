import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/models/connection.dart';
import 'package:mhrd/models/entities.dart';
import 'package:mhrd/sessions/rdp_session.dart';
import 'package:mhrd/sessions/scancodes.dart';
import 'package:mhrd/sessions/session_manager.dart';
import 'package:mhrd/sessions/session_protocol.dart';
import 'package:mhrd/storage/database.dart';
import 'package:mhrd/storage/repository.dart';
import 'package:mhrd/storage/secret_store.dart';

/// Фальшивий процес mhrd-session: ми «пишемо» за нього події й дивимось, що надіслав застосунок.
class FakeChannel implements SessionChannel {
  final out = StreamController<List<int>>();
  final sent = <Uint8List>[];
  final exit = Completer<int>();
  bool killed = false;

  void emit(int type, [List<int> payload = const []]) => out.add(encodeFrame(type, payload));

  /// Типи надісланих застосунком повідомлень.
  List<int> get sentTypes => [for (final f in sent) f[4]];

  @override
  Stream<List<int>> get output => out.stream;
  @override
  void send(Uint8List frame) => sent.add(frame);
  @override
  Future<int> get exitCode => exit.future;
  @override
  void kill() => killed = true;
}

List<int> u32s(List<int> v) =>
    [for (final x in v) ...(ByteData(4)..setUint32(0, x, Endian.little)).buffer.asUint8List()];

Connection pc({String id = 'pc', String? certPin, bool swap = false, List<String> creds = const []}) {
  final now = DateTime.utc(2026);
  return Connection(
      id: id, name: 'Офіс', host: '10.0.0.5', certPin: certPin, swapMouseButtons: swap,
      credentialIds: creds, createdAt: now, updatedAt: now);
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('протокол', () {
    test('кадр: довжина LE + тип + дані', () {
      expect(encodeFrame(0x07), [1, 0, 0, 0, 0x07]);
      expect(encodeKey(0x11D, true), [4, 0, 0, 0, Msg.key, 0x1D, 0x01, 1]);
      expect(encodeMouseWheel(-120, x: 1, y: 2).sublist(5, 7), [0x88, 0xFF]); // -120 у 16 бітах
    });

    test('події, розірвані на шматки, збираються правильно', () async {
      final bytes = <int>[
        ...encodeFrame(Msg.evtState, [2]),
        ...encodeFrame(Msg.evtSurface, [...u32s([1920, 1080, 7680]), ...ascii.encode(r'Local\mhrd-1-1')]),
        ...encodeFrame(Msg.evtFrame, u32s([10, 20, 30, 40])),
        ...encodeFrame(0x99, [1, 2, 3]), // невідомий тип — пропускається
        ...encodeFrame(Msg.evtDisconnected, [2, ...u32s([0x20009]), ...utf8.encode('auth')]),
      ];
      // по 3 байти за раз — як може прийти з каналу
      final chunks = [for (var i = 0; i < bytes.length; i += 3) bytes.sublist(i, (i + 3).clamp(0, bytes.length))];
      final events = await Stream.fromIterable(chunks).transform(const SessionEventDecoder()).toList();
      expect(events.length, 4);
      expect((events[0] as StateEvent).state, 2);
      final s = events[1] as SurfaceEvent;
      expect([s.width, s.height, s.stride, s.name], [1920, 1080, 7680, r'Local\mhrd-1-1']);
      final f = events[2] as FrameEvent;
      expect([f.x, f.y, f.w, f.h], [10, 20, 30, 40]);
      final d = events[3] as DisconnectedEvent;
      expect([d.reason, d.code, d.details], [DisconnectReason.authFailed, 0x20009, 'auth']);
    });
  });

  group('скан-коди', () {
    test('основні клавіші', () {
      expect(rdpScancode(0x00070004), 0x1E); // A
      expect(rdpScancode(0x00070028), 0x1C); // Enter
      expect(rdpScancode(0x00070052), 0x148); // ↑ — розширена
      expect(rdpScancode(0x000700E4), 0x11D); // правий Ctrl
      expect(rdpScancode(0x000700E6), 0x138); // AltGr
      expect(rdpScancode(0x00070058), 0x11C); // Enter цифрового блоку
      expect(rdpScancode(0xFFFFFFFF), isNull);
    });
  });

  group('RdpSession', () {
    late FakeChannel ch;
    late RdpSession s;

    setUp(() {
      ch = FakeChannel();
      s = RdpSession(id: '1', connection: pc(), channel: ch, openFrameBuffer: (_, __) => null);
      s.start({'host': '10.0.0.5', 'password': 'секрет'});
    });

    test('пароль іде лише в повідомлення connect', () {
      expect(ch.sentTypes, [Msg.connect]);
      final json = jsonDecode(utf8.decode(ch.sent.first.sublist(5))) as Map;
      expect(json['password'], 'секрет');
    });

    test('ввід до підключення не надсилається, після — надсилається', () async {
      s.sendKey(0x1E, true);
      expect(ch.sentTypes, [Msg.connect]);
      ch.emit(Msg.evtState, [2]);
      await settle();
      expect(s.state, SessionState.connected);
      s.sendKey(0x1E, true);
      s.sendMouseButton(RemoteButton.left, true, 5, 5);
      expect(ch.sentTypes, [Msg.connect, Msg.key, Msg.mouseButton]);
    });

    test('сертифікат: питання, відповідь у канал', () async {
      ch.emit(Msg.evtCertificate, utf8.encode(jsonEncode({'host': 'h', 'fingerprint': 'AB:CD', 'changed': true})));
      await settle();
      expect(s.state, SessionState.negotiating);
      expect(s.pendingCertificate?.fingerprint, 'AB:CD');
      expect(s.pendingCertificate?.changed, isTrue);
      s.answerCertificate(true);
      expect(s.pendingCertificate, isNull);
      expect(ch.sent.last, encodeCertAnswer(true));
    });

    test('невірний пароль → failed з причиною', () async {
      ch.emit(Msg.evtDisconnected, [DisconnectReason.authFailed.index, ...u32s([0x20009])]);
      await settle();
      expect(s.state, SessionState.failed);
      expect(s.ended?.reason, DisconnectReason.authFailed);
    });

    test('процес зник без «відключено» → збій, застосунок живий', () async {
      ch.exit.complete(-1073741819); // типовий код падіння Windows
      await settle();
      expect(s.state, SessionState.failed);
      expect(s.ended?.reason, DisconnectReason.crashed);
      await s.done;
    });

    test('відключення: спершу просимо, потім примусово', () {
      fakeAsyncDisconnect(s, ch);
    });
  });

  test('ліва й права кнопки міняються місцями для лівшів', () async {
    final ch = FakeChannel();
    final s = RdpSession(id: '1', connection: pc(swap: true), channel: ch, openFrameBuffer: (_, __) => null, swapMouseButtons: true)
      ..start({});
    ch.emit(Msg.evtState, [2]);
    await settle();
    s.sendMouseButton(RemoteButton.left, true, 0, 0);
    expect(ch.sent.last, encodeMouseButton(RemoteButton.right, true, 0, 0));
  });

  group('SessionManager', () {
    late Repository repo;
    late FakeChannel ch;
    late SessionManager m;

    setUp(() {
      repo = Repository(MhrdDatabase.inMemory(), MemorySecretStore());
      ch = FakeChannel();
      m = SessionManager(repo, enginePath: 'mhrd-session.exe', channelFactory: (_) async => ch);
    });

    test('збережений пароль береться зі сховища, «питати щоразу» — ні', () async {
      await repo.saveCredential(const Credential(id: 'a', name: '', username: 'anna'), password: 'p1');
      await repo.saveCredential(
          const Credential(id: 'b', name: '', username: 'bob', authMode: AuthMode.askPassword));
      final c = pc(creds: ['a', 'b']);
      final first = await m.credentialsFor(c);
      expect([first.username, first.password, first.complete], ['anna', 'p1', true]);
      final second = await m.credentialsFor(c, credentialId: 'b');
      expect([second.username, second.password, second.complete], ['bob', null, false]);
      expect((await m.credentialsFor(pc())).complete, isFalse);
    });

    test('довіра до сертифіката зберігається в ПК', () async {
      repo.saveConnection(pc());
      final s = await m.start(repo.connections['pc']!, username: 'anna', password: 'p', width: 1280, height: 800);
      m.trustCertificate(s, 'AB:CD');
      expect(repo.connections['pc']!.certPin, 'AB:CD');
      expect(repo.connections['pc']!.lastUsed, isNotNull);
    });

    test('certPin ПК передається в mhrd-session', () async {
      await m.start(pc(certPin: 'AB:CD'), username: 'u', password: 'p', width: 800, height: 600);
      final json = jsonDecode(utf8.decode(ch.sent.first.sublist(5))) as Map;
      expect(json['certPin'], 'AB:CD');
      expect(json['width'], 800);
      // Типові пристрої ПК: буфер увімкнено, звук тут, мікрофон вимкнено.
      expect([json['clipboard'], json['sound'], json['microphone']], [true, 'local', false]);
    });
  });
}

void fakeAsyncDisconnect(RdpSession s, FakeChannel ch) {
  s.disconnect();
  expect(ch.sentTypes.last, Msg.disconnect);
  expect(ch.killed, isFalse); // примусово — лише через 5 с, якщо процес сам не завершився
}
