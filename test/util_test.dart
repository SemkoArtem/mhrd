import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/models/connection.dart';
import 'package:mhrd/util/address.dart';
import 'package:mhrd/util/rdp_file.dart';
import 'package:mhrd/util/wireguard_conf.dart';

void main() {
  group('parseAddress', () {
    test('ім\'я без порту → 3389', () {
      expect(parseAddress('MyDesktop'), const ParsedAddress('MyDesktop', 3389));
    });
    test('IPv4 з портом', () {
      expect(parseAddress(' 10.0.0.1:3390 '), const ParsedAddress('10.0.0.1', 3390));
    });
    test('IPv6 у дужках з портом і без', () {
      expect(parseAddress('[fd00::5]:3389'), const ParsedAddress('fd00::5', 3389));
      expect(parseAddress('[fd00::5]'), const ParsedAddress('fd00::5', 3389));
    });
    test('голий IPv6', () {
      expect(parseAddress('fd00::5'), const ParsedAddress('fd00::5', 3389));
    });
    test('некоректні', () {
      for (final s in ['', '   ', 'a b', 'host:0', 'host:70000', 'host:abc', ':3389', 'хост!']) {
        expect(parseAddress(s), isNull, reason: s);
      }
    });
    test('приватні адреси', () {
      expect(isPrivateHost('192.168.1.20'), isTrue);
      expect(isPrivateHost('172.20.0.1'), isTrue);
      expect(isPrivateHost('srv.local'), isTrue);
      expect(isPrivateHost('8.8.8.8'), isFalse);
      expect(isPrivateHost('example.com'), isFalse);
    });
    test('приватні адреси: IPv6 та імена, схожі на них', () {
      expect(isPrivateHost('fd00::5'), isTrue);
      expect(isPrivateHost('fe80::1%eth0'), isTrue);
      expect(isPrivateHost('::1'), isTrue);
      expect(isPrivateHost('MyDesktop'), isTrue);
      expect(isPrivateHost('2001:db8::1'), isFalse);
      // Раніше ці імена помилково вважалися локальними через префікс fd/fc/fe80.
      expect(isPrivateHost('fdsite.com'), isFalse);
      expect(isPrivateHost('fcbarcelona.com'), isFalse);
      expect(isPrivateHost('fe80.example.com'), isFalse);
      expect(isPrivateHost('10.0.0.300'), isFalse);
    });
  });

  group('WireGuard .conf', () {
    const conf = '''
[Interface]
PrivateKey = cHJpdmF0ZWtleQ==
Address = 10.8.0.2/32, fd00:8::2/128
DNS = 10.8.0.1
MTU = 1380

[Peer]
PublicKey = cHVibGlja2V5
PresharedKey = cHNr
Endpoint = vpn.example.com:51820
AllowedIPs = 10.20.0.0/16
PersistentKeepalive = 25
''';

    test('розбирає поля й відокремлює секрети', () {
      final r = parseWireGuardConf(conf);
      expect(r.secrets, {'privateKey': 'cHJpdmF0ZWtleQ==', 'presharedKey': 'cHNr'});
      expect(r.config['addresses'], ['10.8.0.2/32', 'fd00:8::2/128']);
      expect(r.config['endpoint'], 'vpn.example.com:51820');
      expect(r.config['mtu'], 1380);
      expect(r.config['keepalive'], 25);
      expect(r.config.toString(), isNot(contains('cHJpdmF0ZWtleQ')));
    });

    test('без PrivateKey — помилка', () {
      expect(() => parseWireGuardConf('[Peer]\nPublicKey = x\nEndpoint = a:1'), throwsFormatException);
    });
  });

  group('.rdp', () {
    test('експорт → імпорт зберігає основні поля', () {
      final now = DateTime(2026);
      final c = Connection(
        id: 'a',
        name: 'Офіс',
        host: '10.20.0.15',
        port: 3390,
        adminSession: true,
        display: const DisplaySettings(useAllMonitors: true, startFullscreen: true, colorDepth: 16),
        devices: const DeviceSettings(clipboard: false, sound: SoundMode.remote, microphone: true),
        createdAt: now,
        updatedAt: now,
      );
      final text = buildRdpFile(c, username: 'OFFICE\\anna', gatewayHost: 'gw.example.com');
      final bytes = encodeUtf16Le(text);
      final r = parseRdpFile(decodeRdpBytes(bytes), id: 'b', fallbackName: 'Офіс');
      expect(r.connection.host, '10.20.0.15');
      expect(r.connection.port, 3390);
      expect(r.connection.adminSession, isTrue);
      expect(r.connection.display.useAllMonitors, isTrue);
      expect(r.connection.display.startFullscreen, isTrue);
      expect(r.connection.display.colorDepth, 16);
      expect(r.connection.devices.clipboard, isFalse);
      expect(r.connection.devices.sound, SoundMode.remote);
      expect(r.connection.devices.microphone, isTrue);
      expect(r.username, 'OFFICE\\anna');
      expect(r.gatewayHost, 'gw.example.com');
      expect(text, isNot(contains('password')));
    });

    test('файл без адреси — помилка', () {
      expect(() => parseRdpFile('username:s:x', id: 'z'), throwsFormatException);
    });
  });

  group('Connection JSON', () {
    test('туди й назад без втрат', () {
      final now = DateTime.utc(2026, 10, 30);
      final c = Connection(
        id: 'x',
        name: '',
        host: 'fd00::5',
        credentialIds: const ['c1', 'c2'],
        route: RouteKind.tunnel,
        routeRefId: 't1',
        devices: const DeviceSettings(folders: [SharedFolder(name: 'Docs', path: '/home/u/Docs', access: FolderAccess.readOnly)]),
        wakeOnLan: const WakeOnLan(mac: 'AA:BB:CC:DD:EE:FF'),
        createdAt: now,
        updatedAt: now,
      );
      final back = Connection.fromJson(c.toJson());
      expect(back.toJson(), c.toJson());
      expect(back.address, '[fd00::5]');
      expect(back.displayName, '[fd00::5]');
    });
  });
}
