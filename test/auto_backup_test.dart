import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/backup/auto_backup.dart';
import 'package:mhrd/backup/backup_service.dart';
import 'package:mhrd/models/entities.dart';
import 'package:mhrd/storage/database.dart';
import 'package:mhrd/storage/repository.dart';
import 'package:mhrd/storage/secret_store.dart';
import 'package:path/path.dart' as p;

/// Потребує SQLite, як і repository_backup_test.dart.
final Object _skip = () {
  try {
    MhrdDatabase.inMemory().close();
    return false;
  } catch (e) {
    return 'SQLite недоступний: $e';
  }
}();

void main() {
  late Directory tmp;
  late Repository repo;
  late AutoBackup auto;

  setUp(() {
    if (_skip != false) return;
    tmp = Directory.systemTemp.createTempSync('mhrd_auto_');
    repo = Repository(MhrdDatabase.inMemory(), MemorySecretStore());
    // Малі параметри Argon2id, щоб тести йшли швидко.
    auto = AutoBackup(repo, service: BackupService(repo, memKiB: 64, iterations: 1));
  });

  tearDown(() {
    if (_skip != false) return;
    auto.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('увімкнення робить копію, яку можна розшифрувати', () async {
    await repo.saveCredential(const Credential(id: 'c', name: '', username: 'anna'), password: 'p@ss');
    final path = await auto.enable(tmp.path, 'пароль автобекапу');

    expect(path, isNotNull);
    expect(AutoBackup.fileNamePattern.hasMatch(p.basename(path!)), isTrue);
    expect(auto.lastAt, isNotNull);
    expect(auto.lastError, isNull);
    expect(auto.pending, isFalse);
    final data = await BackupService(repo, memKiB: 64, iterations: 1)
        .decrypt(File(path).readAsBytesSync(), 'пароль автобекапу');
    expect((data['credentials'] as List).single['password'], 'p@ss');
  }, skip: _skip);

  test('лишаються 10 найновіших копій, чужі файли не чіпаємо', () async {
    for (var i = 0; i < 12; i++) {
      File(p.join(tmp.path, 'mhrd-auto-2020010${i ~/ 10}-00000${i % 10}.rdpbackup')).writeAsStringSync('старе');
    }
    File(p.join(tmp.path, 'мій-документ.rdpbackup')).writeAsStringSync('не чіпати');
    File(p.join(tmp.path, 'mhrd-auto-нотатки.txt')).writeAsStringSync('не чіпати');

    final fresh = await auto.enable(tmp.path, 'пароль');

    final names = tmp.listSync().map((f) => p.basename(f.path)).toSet();
    final autos = names.where(AutoBackup.fileNamePattern.hasMatch).toList()..sort();
    expect(autos.length, 10);
    expect(autos.last, p.basename(fresh!));
    expect(autos.first, 'mhrd-auto-20200100-000003.rdpbackup'); // найстаріші три видалено
    expect(names, containsAll(['мій-документ.rdpbackup', 'mhrd-auto-нотатки.txt']));
  }, skip: _skip);

  test('зміна в даних позначає, що потрібна нова копія', () async {
    await auto.enable(tmp.path, 'пароль');
    expect(auto.pending, isFalse);
    repo.saveGroup(const Group(id: 'g', name: 'Офіс'));
    expect(auto.pending, isTrue);
  }, skip: _skip);

  test('не частіше разу на годину', () async {
    expect(auto.delayFrom(DateTime.now()), const Duration(seconds: 10)); // копій ще не було
    await auto.enable(tmp.path, 'пароль');
    final d = auto.delayFrom(DateTime.now());
    expect(d, greaterThan(const Duration(minutes: 59)));
    expect(d, lessThanOrEqualTo(const Duration(hours: 1)));
    expect(auto.delayFrom(DateTime.now().add(const Duration(hours: 2))), const Duration(seconds: 10));
  }, skip: _skip);

  test('недоступна тека — зрозуміла помилка, повтор не раніше ніж за годину', () async {
    final missing = p.join(tmp.path, 'немає');
    final path = await auto.enable(missing, 'пароль');
    expect(path, isNull);
    expect(auto.lastError?.kind, AutoBackupFailureKind.writeFailed);
    expect(auto.lastError?.path, isNotEmpty);
    expect(auto.pending, isTrue);
    expect(auto.delayFrom(DateTime.now()), greaterThan(const Duration(minutes: 59)));
  }, skip: _skip);

  test('вимкнення стирає пароль, копії лишаються', () async {
    final path = await auto.enable(tmp.path, 'пароль');
    await auto.disable();
    expect(auto.enabled, isFalse);
    expect(await repo.secrets.read(AutoBackup.passwordKey), isNull);
    expect(File(path!).existsSync(), isTrue);
  }, skip: _skip);

  test('налаштування переживають перезапуск', () async {
    await auto.enable(tmp.path, 'пароль');
    final again = AutoBackup(repo);
    expect(again.dir, tmp.path);
    expect(again.lastAt, auto.lastAt);
    again.dispose();
  }, skip: _skip);
}
