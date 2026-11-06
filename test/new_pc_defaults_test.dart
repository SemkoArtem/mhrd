import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/models/connection.dart';
import 'package:mhrd/models/entities.dart';
import 'package:mhrd/platform/mstsc_import.dart';
import 'package:mhrd/storage/database.dart';
import 'package:mhrd/storage/repository.dart';
import 'package:mhrd/storage/secret_store.dart';

/// Ці тести потребують бібліотеки SQLite в системі (як repository_backup_test).
final Object _skip = () {
  try {
    MhrdDatabase.inMemory().close();
    return false;
  } catch (e) {
    return 'SQLite недоступний: $e';
  }
}();

Repository _repo() => Repository(MhrdDatabase.inMemory(), MemorySecretStore());

void main() {
  test('без налаштувань нових ПК — типовий ПК', () {
    final c = _repo().newConnection(host: '10.0.0.5', port: 3390, groupId: 'g');
    expect(c.address, '10.0.0.5:3390');
    expect(c.groupId, 'g');
    expect(c.credentialIds, isEmpty);
    expect(c.devices.clipboard, isTrue);
  }, skip: _skip);

  test('налаштування нових ПК переносяться; зниклі акаунти й профілі — ні', () async {
    final r = _repo();
    await r.saveCredential(const Credential(id: 'c', name: '', username: 'anna'), password: 'p');
    final now = DateTime.utc(2026);
    r.updateSettings(r.settings.copyWith(
      newPc: () => Connection(
        id: '',
        name: '',
        host: '',
        credentialIds: const ['c', 'gone'],
        route: RouteKind.tunnel,
        routeRefId: 'missing',
        tags: const ['офіс'],
        devices: const DeviceSettings(clipboard: false, sound: SoundMode.off, microphone: true),
        display: const DisplaySettings(hiDpi: false, scalePercent: 150),
        createdAt: now,
        updatedAt: now,
      ),
    ));
    final c = r.newConnection(host: '10.0.0.6');
    expect(c.id, isNotEmpty);
    expect(c.host, '10.0.0.6');
    expect(c.credentialIds, ['c']);
    expect(c.route, RouteKind.direct); // профілю тунелю немає — напряму, а не «тунель без профілю»
    expect(c.routeRefId, isNull);
    expect(c.tags, ['офіс']);
    expect(c.devices.clipboard, isFalse);
    expect(c.devices.sound, SoundMode.off);
    expect(c.display.scalePercent, 150);
    expect(c.createdAt.isAfter(now), isTrue);

    // Збереження й читання налаштувань (як після перезапуску)
    final back = AppSettings.fromJson(r.settings.toJson());
    expect(back.newPc!.devices.microphone, isTrue);
    expect(back.newPc!.display.hiDpi, isFalse);
  }, skip: _skip);

  test('історія mstsc читається без помилок (Windows)', () {
    final list = readMstscHistory();
    for (final e in list) {
      expect(e.host, isNotEmpty);
      expect(e.port, inInclusiveRange(1, 65535));
    }
  });
}
