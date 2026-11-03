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
import 'package:mhrd/sessions/tunnel.dart';
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
  @override
  int get pid => 4242;
}

/// Фальшивий mhrd-tunnel: на запит відповідає подіями зі [script]; як і справжній, після
/// hostKey мовчить, доки не прийде trustHostKey.
class FakeTunnel implements TunnelChannel {
  final _events = StreamController<Map<String, Object?>>.broadcast();
  final sent = <Map<String, Object?>>[];
  List<Map<String, Object?>> script = [];
  bool killed = false;

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  /// Відповідь тунелю ([script]) — на перший запит; на заміри затримки — 42 мс.
  @override
  void send(Map<String, Object?> message) {
    sent.add(message);
    if (message['ping'] == true) {
      scheduleMicrotask(() => _events.add({'event': 'pong', 'ms': 42}));
    } else if (sent.length == 1) {
      for (final e in script) {
        scheduleMicrotask(() => _events.add(e));
      }
    }
  }

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
      // Символ з екранної клавіатури телефона: одиниця UTF-16 (кирилиця «Ї» = 0x0407).
      expect(encodeUnicode(0x0407), [3, 0, 0, 0, Msg.unicode, 0x07, 0x04]);
      // Дотик: прапорці (u16), палець, x, y.
      expect(encodeTouch(TouchFlags.down, 1, 300, 2), [8, 0, 0, 0, Msg.touch, 1, 0, 1, 0x2C, 0x01, 2, 0]);
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

    test('вікно просить екранну клавіатуру — застосунок дізнається', () async {
      final events =
          await Stream<List<int>>.value(encodeFrame(Msg.evtKeyboard)).transform(const SessionEventDecoder()).toList();
      expect(events.single, isA<KeyboardEvent>());
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

    test('рух миші зливається: не частіше разу на кадр, остання позиція не губиться', () async {
      ch.emit(Msg.evtState, [2]);
      await settle();
      for (var i = 0; i < 100; i++) {
        s.sendMouseMove(i, i);
      }
      expect(ch.sentTypes.where((t) => t == Msg.mouseMove).length, 1); // лише перший — одразу
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final moves = ch.sent.where((f) => f[4] == Msg.mouseMove).toList();
      expect(moves.length, 2);
      expect(moves.last, encodeMouseMove(99, 99));
    });

    test('перед кліком відкладений рух надсилається одразу', () async {
      ch.emit(Msg.evtState, [2]);
      await settle();
      s.sendMouseMove(1, 1);
      s.sendMouseMove(50, 60);
      s.sendMouseButton(RemoteButton.left, true, 50, 60);
      expect(ch.sentTypes.sublist(1), [Msg.mouseMove, Msg.mouseMove, Msg.mouseButton]);
      expect(ch.sent[2], encodeMouseMove(50, 60));
    });

    test('зміна роздільності: парна ширина, без повторів, лише після підключення', () async {
      s.requestResize(1001, 700);
      expect(ch.sentTypes, [Msg.connect]); // ще не підключено
      ch.emit(Msg.evtState, [2]);
      await settle();
      s.requestResize(1001, 700);
      s.requestResize(1001, 700); // той самий розмір — не повторюємо
      expect(ch.sent.where((f) => f[4] == Msg.resize).toList(), [encodeResize(1000, 700)]);
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

    test('обрив зв\'язку: reconnecting, ввід не йде; відновився — знову connected', () async {
      ch.emit(Msg.evtState, [2]);
      ch.emit(Msg.evtState, [3]);
      await settle();
      expect(s.state, SessionState.reconnecting);
      expect(s.isActive, isTrue); // сеанс живий — не «відключено»
      s.sendKey(0x1E, true);
      expect(ch.sentTypes, [Msg.connect]);
      ch.emit(Msg.evtState, [2]);
      await settle();
      expect(s.state, SessionState.connected);
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

    test('папки передаються з режимом доступу', () async {
      final c = pc().copyWith(
          devices: const DeviceSettings(folders: [
        SharedFolder(name: 'Docs', path: r'C:\Docs'),
        SharedFolder(name: 'Secret', path: r'C:\Secret', access: FolderAccess.readOnly),
        SharedFolder(name: 'Work', path: r'C:\Work', access: FolderAccess.full),
      ]));
      await m.start(c, username: 'u', password: 'p', width: 800, height: 600);
      final json = jsonDecode(utf8.decode(ch.sent.first.sublist(5))) as Map;
      expect(json['folders'], [
        {'name': 'Docs', 'path': r'C:\Docs', 'access': 'addOnly'}, // типовий — найбезпечніший
        {'name': 'Secret', 'path': r'C:\Secret', 'access': 'readOnly'},
        {'name': 'Work', 'path': r'C:\Work', 'access': 'full'},
      ]);
    });

    test('старі записи з прапорцем readOnly читаються правильно', () {
      expect(SharedFolder.fromJson({'name': 'a', 'path': 'b', 'readOnly': true}).access, FolderAccess.readOnly);
      expect(SharedFolder.fromJson({'name': 'a', 'path': 'b', 'readOnly': false}).access, FolderAccess.full);
      expect(SharedFolder.fromJson({'name': 'a', 'path': 'b', 'access': 'addOnly'}).access, FolderAccess.addOnly);
    });

    test('certPin ПК передається в mhrd-session', () async {
      await m.start(pc(certPin: 'AB:CD'), username: 'u', password: 'p', width: 800, height: 600);
      final json = jsonDecode(utf8.decode(ch.sent.first.sublist(5))) as Map;
      expect(json['certPin'], 'AB:CD');
      expect(json['width'], 800);
      // Типові пристрої ПК: буфер увімкнено, звук тут, мікрофон вимкнено.
      expect([json['clipboard'], json['sound'], json['microphone']], [true, 'local', false]);
      expect(json.containsKey('nativeWindow'), isFalse);
    });

    test('маршрут: проксі й шлюз із паролями зі сховища; тунель — відмова, а не тихо напряму', () async {
      await repo.saveProxy(const ProxyProfile(id: 'px', name: '', host: 'proxy.lan', port: 3128, type: ProxyType.http,
          username: 'pu'), password: 'pp');
      await repo.saveCredential(const Credential(id: 'gc', name: '', username: 'CORP\\gw'), password: 'gp');
      repo.saveGateway(const Gateway(id: 'gw', name: '', host: 'rdgw.lan', credentialMode: GatewayCredentialMode.own,
          credentialId: 'gc'));
      final c = pc().copyWith(route: RouteKind.proxy, routeRefId: () => 'px', gatewayId: () => 'gw');
      await m.start(c, username: 'u', password: 'p', width: 800, height: 600);
      final json = jsonDecode(utf8.decode(ch.sent.first.sublist(5))) as Map;
      expect(json['proxy'], {'type': 'http', 'host': 'proxy.lan', 'port': 3128, 'username': 'pu', 'password': 'pp'});
      expect(json['gateway'], {
        'host': 'rdgw.lan', 'port': 443, 'bypassLocal': false, 'sameCredentials': false,
        'username': 'CORP\\gw', 'password': 'gp',
      });
      expect(m.gatewayAccountToAsk(c), isNull); // пароль збережено — не питаємо

      final viaTunnel = pc().copyWith(route: RouteKind.tunnel, routeRefId: () => 't1');
      expect(() => m.tunnelRequest(viaTunnel),
          throwsA(isA<RouteException>().having((e) => e.error, 'error', RouteError.tunnelMissing)));
      final noProxy = pc().copyWith(route: RouteKind.proxy, routeRefId: () => 'gone');
      expect(() => m.routeConfig(noProxy),
          throwsA(isA<RouteException>().having((e) => e.error, 'error', RouteError.proxyMissing)));
      expect(await m.routeConfig(pc()), isEmpty); // напряму — нічого зайвого
    });

    group('тунелі', () {
      late FakeTunnel tun;
      setUp(() {
        tun = FakeTunnel();
        m = SessionManager(repo,
            enginePath: 'mhrd-session.exe',
            channelFactory: (_) async => ch,
            tunnelPath: 'mhrd-tunnel.exe',
            tunnelFactory: (_) async => tun);
      });

      test('WireGuard: ключ зі сховища йде лише в stdin тунелю, сеанс — на 127.0.0.1:порт', () async {
        await repo.saveTunnel(
            const TunnelProfile(id: 'wg', name: 'WG', type: TunnelType.wireguard, config: {
              'addresses': ['10.8.0.2/24'],
              'endpoint': 'vpn.example.com:51820',
              'peerPublicKey': 'PUB',
              'extraPeersIgnored': false,
            }, secretFields: ['privateKey']),
            secretValues: {'privateKey': 'PRIV'});
        tun.script = [
          {'event': 'listening', 'port': 50123}
        ];
        await m.start(pc().copyWith(route: RouteKind.tunnel, routeRefId: () => 'wg'),
            username: 'u', password: 'p', width: 800, height: 600);
        final req = tun.sent.first;
        expect(req['type'], 'wireguard');
        expect(req['target'], '10.0.0.5:3389');
        expect((req['wireguard'] as Map)['privateKey'], 'PRIV');
        expect((req['wireguard'] as Map).containsKey('extraPeersIgnored'), isFalse);
        expect(tun.sent.last, {'watchPid': 4242}); // тунель житиме, поки живе сеанс
        final json = jsonDecode(utf8.decode(ch.sent.first.sublist(5))) as Map;
        expect([json['host'], json['port']], ['127.0.0.1', 50123]);
      });

      test('затримка на плашку — крізь тунель сеансу, поки сеанс підключений', () async {
        m = SessionManager(repo,
            enginePath: 'mhrd-session.exe',
            channelFactory: (_) async => ch,
            tunnelPath: 'mhrd-tunnel.exe',
            tunnelFactory: (_) async => tun,
            latencyInterval: const Duration(milliseconds: 20));
        await repo.saveTunnel(const TunnelProfile(id: 'wg', name: 'WG', type: TunnelType.wireguard));
        tun.script = [
          {'event': 'listening', 'port': 50123}
        ];
        final s = await m.start(pc().copyWith(route: RouteKind.tunnel, routeRefId: () => 'wg'),
            username: 'u', password: 'p', width: 800, height: 600, window: const {});
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(ch.sentTypes, isNot(contains(Msg.latency))); // ще не підключено — не міряємо
        ch.emit(Msg.evtState, [2]);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final frame = ch.sent.lastWhere((f) => f[4] == Msg.latency);
        expect(ByteData.sublistView(frame, 5).getInt32(0, Endian.little), 42);
        expect(tun.sent.where((x) => x['ping'] == true), isNotEmpty);
        s.disconnect();
        ch.exit.complete(0);
        await s.done;
      });

      test('тунель не відкрився — зрозуміла помилка, сеансу немає, процес тунелю прибрано', () async {
        await repo.saveTunnel(const TunnelProfile(id: 'wg', name: 'WG', type: TunnelType.wireguard));
        tun.script = [
          {'event': 'error', 'code': 'unreachable', 'detail': 'i/o timeout'}
        ];
        await expectLater(
            m.start(pc().copyWith(route: RouteKind.tunnel, routeRefId: () => 'wg'),
                username: 'u', password: 'p', width: 800, height: 600),
            throwsA(isA<TunnelException>().having((e) => e.error, 'error', TunnelError.unreachable)));
        expect(tun.killed, isTrue);
        expect(m.sessions, isEmpty);
        expect(ch.sent, isEmpty); // mhrd-session навіть не запускався
      });

      test('тунель разом із RD Gateway — відмова, бо шлюз пішов би в обхід тунелю', () async {
        repo.saveGateway(const Gateway(id: 'gw', name: '', host: 'rdgw.lan'));
        final c = pc().copyWith(route: RouteKind.tunnel, routeRefId: () => 'wg', gatewayId: () => 'gw');
        expect(() => m.routeConfig(c),
            throwsA(isA<RouteException>().having((e) => e.error, 'error', RouteError.gatewayWithTunnel)));
      });
    });

    test('власне вікно: налаштування йдуть у connect, після виходу процесу сеанс зникає', () async {
      final s = await m.start(pc(), username: 'u', password: 'p', width: 800, height: 600, window: {
        'title': 'Офіс — MHRD',
        'labels': {'disconnect': 'Відключитись'},
      });
      final json = jsonDecode(utf8.decode(ch.sent.first.sublist(5))) as Map;
      expect(json['nativeWindow'], isTrue);
      expect(json['title'], 'Офіс — MHRD');
      expect((json['labels'] as Map)['disconnect'], 'Відключитись');
      expect(json['bar'], {'edge': 0, 'pos': 5000, 'length': 0}); // плашка — типово вгорі посередині
      ch.emit(Msg.evtState, [2]);
      // Плашку перетягнули ліворуч і вкоротили — запам'ятовується для наступних сеансів.
      ch.emit(Msg.evtBar, [2, 0x10, 0x27, 200, 0]); // край 2, центр 10000, довжина 200
      await settle();
      expect(repo.settings.bar.edge, BarEdge.left);
      expect(repo.settings.bar.pos, 10000);
      expect(repo.settings.bar.length, 200);
      expect(AppSettings.fromJson(repo.settings.toJson()).bar.edge, BarEdge.left);
      expect(m.forConnection('pc'), same(s));
      s.focusWindow();
      expect(ch.sentTypes.last, Msg.focus);
      ch.emit(Msg.evtDisconnected, [DisconnectReason.userRequest.index, ...u32s([0])]);
      ch.exit.complete(0);
      await s.done;
      await settle();
      expect(m.sessions, isEmpty);
      expect(s.ended?.reason, DisconnectReason.userRequest); // причина лишається для діалогу
    });
  });
}

void fakeAsyncDisconnect(RdpSession s, FakeChannel ch) {
  s.disconnect();
  expect(ch.sentTypes.last, Msg.disconnect);
  expect(ch.killed, isFalse); // примусово — лише через 5 с, якщо процес сам не завершився
}
