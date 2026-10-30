import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/backup/backup_service.dart';
import 'package:mhrd/models/connection.dart';
import 'package:mhrd/models/entities.dart';
import 'package:mhrd/storage/database.dart';
import 'package:mhrd/storage/repository.dart';
import 'package:mhrd/storage/secret_store.dart';
import 'package:mhrd/theme/mhrd_theme.dart';

/// Ці тести потребують бібліотеки SQLite в системі (на CI ставиться через apt).
/// Якщо її немає (наприклад, Windows без sqlite3.dll) — тести пропускаються.
final Object _skip = () {
  try {
    MhrdDatabase.inMemory().close();
    return false;
  } catch (e) {
    return 'SQLite недоступний: $e';
  }
}();

Repository _repo() => Repository(MhrdDatabase.inMemory(), MemorySecretStore());

Connection _pc(String id, {List<String> creds = const [], String? group}) {
  final now = DateTime.utc(2026);
  return Connection(id: id, name: 'ПК $id', host: '10.0.0.$id', credentialIds: creds, groupId: group, createdAt: now, updatedAt: now);
}

void main() {
  test('один акаунт у двох ПК, видалення з перевіркою', () async {
    final r = _repo();
    await r.saveCredential(const Credential(id: 'c', name: '', username: 'anna'), password: 'p@ss');
    r.saveConnection(_pc('1', creds: ['c']));
    r.saveConnection(_pc('2', creds: ['c']));
    await expectLater(r.deleteCredential('c'), throwsA(isA<InUse>()));
    await r.deleteCredential('c', force: true);
    expect(r.connections['1']!.credentialIds, isEmpty);
    expect(await r.secrets.read('mhrd.cred.c'), isNull);
  }, skip: _skip);

  test('групи: цикл заборонено, видалення переносить ПК', () {
    final r = _repo();
    r.saveGroup(const Group(id: 'a', name: 'A'));
    r.saveGroup(const Group(id: 'b', name: 'B', parentId: 'a'));
    expect(() => r.saveGroup(const Group(id: 'a', name: 'A', parentId: 'b')), throwsStateError);
    r.saveConnection(_pc('1', group: 'b'));
    r.deleteGroup('b', moveTo: 'a');
    expect(r.connections['1']!.groupId, 'a');
  }, skip: _skip);

  test('повний бекап: туди й назад з паролями', () async {
    final src = _repo();
    await src.saveCredential(const Credential(id: 'c', name: 'Робочий', username: 'OFFICE\\anna'), password: 'секрет');
    src.saveGroup(const Group(id: 'g', name: 'Офіс'));
    src.saveConnection(_pc('1', creds: ['c'], group: 'g'));
    await src.saveTunnel(
      const TunnelProfile(id: 't', name: 'WG', type: TunnelType.wireguard, secretFields: ['privateKey']),
      secretValues: {'privateKey': 'KEY'},
    );

    // Малі параметри Argon2id, щоб тест ішов швидко.
    final svc = BackupService(src, memKiB: 64, iterations: 1);
    final Uint8List file = await svc.exportEncrypted('правильний пароль');
    expect(String.fromCharCodes(file.sublist(0, 5)), 'RDPB2');

    final dst = _repo();
    final dsvc = BackupService(dst, memKiB: 64, iterations: 1);
    await expectLater(dsvc.decrypt(file, 'неправильний'), throwsFormatException);

    final data = await dsvc.decrypt(file, 'правильний пароль');
    final pv = dsvc.preview(data, replaceAll: false);
    expect(pv.added, 1);
    await dsvc.apply(data, replaceAll: false);

    expect(dst.connections['1']!.groupId, 'g');
    expect(dst.connections['1']!.credentialIds, ['c']);
    expect(await dst.secrets.read('mhrd.cred.c'), 'секрет');
    expect(await dst.secrets.read('mhrd.tunnel.t.privateKey'), 'KEY');
  }, skip: _skip);

  test('видалення проксі й SSH, якими користуються ПК', () async {
    final r = _repo();
    await r.saveProxy(const ProxyProfile(id: 'p', name: 'Офіс', host: 'proxy.lan', port: 1080), password: 'pp');
    await r.saveSsh(const SshProfile(id: 's', name: 'Роутер', host: 'gw.lan', username: 'root'), secret: 'KEY');
    r.saveConnection(_pc('1').copyWith(route: RouteKind.proxy, routeRefId: () => 'p'));
    r.saveConnection(_pc('2').copyWith(route: RouteKind.ssh, routeRefId: () => 's'));

    await expectLater(r.deleteProxy('p'), throwsA(isA<InUse>()));
    await r.deleteProxy('p', force: true);
    await r.deleteSsh('s', force: true);

    expect(r.proxies, isEmpty);
    expect(r.ssh, isEmpty);
    expect(r.connections['1']!.route, RouteKind.direct);
    expect(r.connections['2']!.routeRefId, isNull);
    expect(await r.secrets.read('mhrd.proxy.p'), isNull);
    expect(await r.secrets.read('mhrd.ssh.s'), isNull);
  }, skip: _skip);

  test('«Замінити все» прибирає й проксі, SSH і власні теми', () async {
    final src = _repo();
    await src.saveProxy(const ProxyProfile(id: 'p-new', name: 'Новий', host: 'p.lan', port: 3128), password: 'np');
    final svc = BackupService(src, memKiB: 64, iterations: 1);
    final data = await svc.decrypt(await svc.exportEncrypted('пароль'), 'пароль');

    final dst = _repo();
    await dst.saveProxy(const ProxyProfile(id: 'p-old', name: 'Старий', host: 'old.lan', port: 1080), password: 'op');
    await dst.saveSsh(const SshProfile(id: 's-old', name: 'Старий SSH', host: 'gw.lan', username: 'root'), secret: 'K');
    dst.saveTheme(MhrdTokens.light.copyWith(id: 'custom:old', name: 'Стара тема'));

    await BackupService(dst, memKiB: 64, iterations: 1).apply(data, replaceAll: true);

    expect(dst.proxies.keys, ['p-new']);
    expect(dst.ssh, isEmpty);
    expect(dst.customThemes, isEmpty);
    expect(await dst.secrets.read('mhrd.proxy.p-old'), isNull);
    expect(await dst.secrets.read('mhrd.proxy.p-new'), 'np');
  }, skip: _skip);

  test('експорт для передачі не містить секретів', () async {
    final r = _repo();
    await r.saveCredential(const Credential(id: 'c', name: '', username: 'anna'), password: 'p@ss');
    r.saveConnection(_pc('1', creds: ['c']));
    final share = BackupService(r).exportShare(r.connections.values);
    expect(share.toString(), isNot(contains('p@ss')));
    expect(share['secretIncluded'], isFalse);
  }, skip: _skip);
}
