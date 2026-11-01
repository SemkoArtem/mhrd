import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/security/app_lock.dart';
import 'package:mhrd/storage/database.dart';
import 'package:mhrd/storage/repository.dart';
import 'package:mhrd/storage/secret_store.dart';

void main() {
  late Repository repo;
  late MemorySecretStore secrets;
  setUp(() {
    secrets = MemorySecretStore();
    repo = Repository(MhrdDatabase.inMemory(), secrets);
  });

  test('PIN: у сховищі лише сіль і хеш; правильний відкриває, неправильний — ні', () async {
    final lock = AppLock(repo);
    expect(await lock.isRequired(), isFalse);
    await lock.setPin('4821');
    expect(repo.settings.lockEnabled, isTrue);
    expect(await lock.isRequired(), isTrue);
    expect(secrets.data[AppLock.pinKey], isNot(contains('4821')));
    expect(await lock.checkPin('4821'), isTrue);
    expect(await lock.checkPin('4822'), isFalse);
    expect(await lock.checkPin(''), isFalse);
    await lock.disable();
    expect(repo.settings.lockEnabled, isFalse);
    expect(secrets.data.containsKey(AppLock.pinKey), isFalse);
  });

  test('після 3 невдалих PIN — зростаюча пауза; навіть правильний PIN у паузі не відкриває', () async {
    final lock = AppLock(repo);
    await lock.setPin('4821');
    final t0 = DateTime(2026, 11, 1, 12);
    expect(await lock.checkPin('1111', now: t0), isFalse);
    expect(await lock.checkPin('2222', now: t0), isFalse);
    expect(lock.waitLeft(t0), isNull); // дві помилки — ще без паузи
    expect(await lock.checkPin('3333', now: t0), isFalse);
    expect(lock.waitLeft(t0), const Duration(seconds: 5));
    expect(await lock.checkPin('4821', now: t0.add(const Duration(seconds: 2))), isFalse); // у паузі
    final t1 = t0.add(const Duration(seconds: 6));
    expect(await lock.checkPin('4444', now: t1), isFalse);
    expect(lock.waitLeft(t1), const Duration(seconds: 10)); // пауза подвоюється
    final t2 = t1.add(const Duration(seconds: 11));
    expect(await lock.checkPin('4821', now: t2), isTrue);
    expect(lock.waitLeft(t2), isNull); // правильний PIN скидає лічильник
    expect(await lock.checkPin('5555', now: t2), isFalse);
    expect(lock.waitLeft(t2), isNull);
  });

  test('блокування з бекапу іншого пристрою без PIN у сховищі вимикається, а не замикає назавжди', () async {
    repo.updateSettings(repo.settings.copyWith(lockEnabled: true, lockBiometric: true));
    expect(await AppLock(repo).isRequired(), isFalse);
    expect(repo.settings.lockEnabled, isFalse);
    expect(repo.settings.lockBiometric, isFalse);
  });
}
