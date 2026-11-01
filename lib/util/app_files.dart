import 'dart:io';

import 'package:path/path.dart' as p;

/// Файли MHRD поза базою: мініатюри останнього сеансу й свої картинки ПК. Лежать у теці даних
/// застосунку й не йдуть у бекап (мініатюри — вміст екрана, картинку легко вибрати знову).
class AppFiles {
  AppFiles(this.root);

  final Directory root;

  /// Мініатюра останнього сеансу ПК (BMP, її пише вікно сеансу).
  File thumbnail(String connectionId) => File(p.join(root.path, 'thumbs', '$connectionId.bmp'));

  /// Своя картинка ПК — ім'я файлу з [Connection.image].
  File image(String name) => File(p.join(root.path, 'images', name));

  /// Копіює вибрану картинку до себе й повертає ім'я файлу для [Connection.image].
  Future<String> saveImage(String connectionId, List<int> bytes, String extension) async {
    final name = '$connectionId-${DateTime.now().millisecondsSinceEpoch}.$extension';
    final f = image(name);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    return name;
  }

  /// Прибирає картинку й мініатюру видаленого ПК.
  Future<void> forget(String connectionId, {String? image}) async {
    for (final f in [thumbnail(connectionId), if (image != null) this.image(image)]) {
      try {
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // зайнятий чи вже видалений — не страшно
      }
    }
  }
}
