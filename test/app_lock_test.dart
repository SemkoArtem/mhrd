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

  test('блокування з бекапу іншого пристрою без PIN у сховищі вимикається, а не замикає назавжди', () async {
    repo.updateSettings(repo.settings.copyWith(lockEnabled: true, lockBiometric: true));
    expect(await AppLock(repo).isRequired(), isFalse);
    expect(repo.settings.lockEnabled, isFalse);
    expect(repo.settings.lockBiometric, isFalse);
  });
}
