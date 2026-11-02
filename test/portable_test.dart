import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/platform/portable.dart';
import 'package:mhrd/storage/file_secret_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mhrd-portable-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // Малі параметри Argon2id — щоб тести йшли швидко.
  FileSecretStore store() => FileSecretStore(File(p.join(tmp.path, 'secrets.mhrd')), memKiB: 64, iterations: 1);

  group('Portable', () {
    test('є portable.txt поруч із .exe — дані в mhrd-data поруч', () {
      final exe = p.join(tmp.path, 'mhrd.exe');
      expect(Portable.detect(exe), isNull);
      File(p.join(tmp.path, Portable.marker)).writeAsStringSync('');
      expect(Portable.detect(exe)!.path, p.join(tmp.path, 'mhrd-data'));
    });
  });

  group('FileSecretStore', () {
    test('створити, записати, відкрити знову тим самим паролем', () async {
      final a = store();
      expect(a.exists, isFalse);
      await a.create('correct horse');
      await a.write('k', 'секрет');
      expect(await a.read('k'), 'секрет');

      final b = store();
      expect(b.unlocked, isFalse);
      expect(await b.unlock('wrong password'), isFalse);
      expect(b.unlocked, isFalse);
      expect(await b.unlock('correct horse'), isTrue);
      expect(await b.read('k'), 'секрет');
      await b.delete('k');
      expect(await b.read('k'), isNull);
    });

    test('у файлі немає відкритого тексту', () async {
      final a = store();
      await a.create('correct horse');
      await a.write('mhrd.tunnel.key', 'PRIVATE-KEY-123');
      // latin1 приймає будь-які байти (системне кодування Linux — UTF-8, на шифротексті падає).
      final raw = latin1.decode(File(p.join(tmp.path, 'secrets.mhrd')).readAsBytesSync());
      expect(raw.contains('PRIVATE-KEY-123'), isFalse);
      expect(raw.contains('mhrd.tunnel.key'), isFalse);
    });

    test('короткий пароль — відмова', () async {
      expect(() => store().create('short'), throwsArgumentError);
    });

    test('читання до розблокування чекає на нього', () async {
      await store().create('correct horse').then((_) {});
      final s = store();
      String? got;
      final pending = s.read('x').then((v) => got = v);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(got, isNull);
      expect(await s.unlock('correct horse'), isTrue);
      await pending;
      expect(got, isNull); // ключа немає, але читання завершилось
    });

    test('зміна майстер-пароля: старий більше не підходить', () async {
      final a = store();
      await a.create('correct horse');
      await a.write('k', 'v');
      expect(await a.checkPassword('correct horse'), isTrue);
      expect(await a.checkPassword('nope nope'), isFalse);
      await a.changePassword('battery staple');
      expect(await a.checkPassword('battery staple'), isTrue);

      final b = store();
      expect(await b.unlock('correct horse'), isFalse);
      expect(await b.unlock('battery staple'), isTrue);
      expect(await b.read('k'), 'v');
    });

    test('чужий чи пошкоджений файл — FormatException, а не «неправильний пароль»', () async {
      File(p.join(tmp.path, 'secrets.mhrd')).writeAsBytesSync([1, 2, 3, 4]);
      expect(() => store().unlock('whatever!'), throwsFormatException);
    });

    test('паралельні записи не губляться', () async {
      final a = store();
      await a.create('correct horse');
      await Future.wait([for (var i = 0; i < 10; i++) a.write('k$i', '$i')]);
      final b = store();
      expect(await b.unlock('correct horse'), isTrue);
      for (var i = 0; i < 10; i++) {
        expect(await b.read('k$i'), '$i');
      }
    });
  });
}
