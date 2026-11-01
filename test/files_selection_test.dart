import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/models/connection.dart';
import 'package:mhrd/models/entities.dart';
import 'package:mhrd/sessions/session_manager.dart';
import 'package:mhrd/storage/database.dart';
import 'package:mhrd/storage/repository.dart';
import 'package:mhrd/storage/secret_store.dart';
import 'package:mhrd/util/app_files.dart';

import 'session_test.dart' show FakeChannel;

Connection pc(String id, {String? group, String? image}) {
  final now = DateTime.utc(2026);
  return Connection(id: id, name: id, host: '10.0.0.5', groupId: group, image: image, createdAt: now, updatedAt: now);
}

void main() {
  late Repository repo;
  setUp(() => repo = Repository(MhrdDatabase.inMemory(), MemorySecretStore()));

  test('кілька ПК переносяться в групу одним разом; null — «Без групи»', () {
    repo.saveGroup(const Group(id: 'g', name: 'Офіс'));
    repo.saveConnection(pc('a'));
    repo.saveConnection(pc('b', group: 'g'));
    repo.saveConnection(pc('c'));
    repo.moveConnections(['a', 'b'], 'g');
    expect([for (final id in ['a', 'b', 'c']) repo.connections[id]!.groupId], ['g', 'g', null]);
    repo.moveConnections(['a', 'b', 'gone'], null);
    expect(repo.countInGroup(null), 3);
  });

  test('своя картинка ПК: копіюється до себе, у JSON — лише ім\'я файлу; forget прибирає файли', () async {
    final dir = await Directory.systemTemp.createTemp('mhrd-files');
    addTearDown(() => dir.delete(recursive: true));
    final files = AppFiles(dir);
    final name = await files.saveImage('pc1', [1, 2, 3], 'png');
    expect(files.image(name).readAsBytesSync(), [1, 2, 3]);
    final c = pc('pc1', image: name);
    expect(Connection.fromJson(c.toJson()).image, name);
    files.thumbnail('pc1')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([9]);
    await files.forget('pc1', image: name);
    expect(files.image(name).existsSync(), isFalse);
    expect(files.thumbnail('pc1').existsSync(), isFalse);
  });

  test('вікно сеансу отримує шлях мініатюри — лише для збереженого ПК і якщо мініатюри ввімкнено', () async {
    final dir = await Directory.systemTemp.createTemp('mhrd-thumbs');
    addTearDown(() => dir.delete(recursive: true));
    Future<Map<String, dynamic>> connectConfig(Connection c) async {
      final ch = FakeChannel();
      final m = SessionManager(repo, enginePath: 'x.exe', channelFactory: (_) async => ch, files: AppFiles(dir));
      await m.start(c, username: 'u', password: 'p', width: 800, height: 600, window: const {});
      return jsonDecode(utf8.decode(ch.sent.first.sublist(5))) as Map<String, dynamic>;
    }

    repo.saveConnection(pc('saved'));
    expect((await connectConfig(pc('saved')))['thumbnailPath'], AppFiles(dir).thumbnail('saved').path);
    expect((await connectConfig(pc('quick'))).containsKey('thumbnailPath'), isFalse); // швидке підключення
    repo.updateSettings(repo.settings.copyWith(showPreviews: false));
    expect((await connectConfig(pc('saved'))).containsKey('thumbnailPath'), isFalse);
  });
}
