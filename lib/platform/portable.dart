import 'dart:io';

import 'package:path/path.dart' as p;

/// Портативна версія: поруч із mhrd.exe лежить `portable.txt`. Тоді все — база, мініатюри,
/// журнали й зашифрований файл паролів — у теці `mhrd-data` поруч із програмою, а не в профілі
/// Windows, тож MHRD можна носити на флешці. Те саме перевіряє раннер (shell_integration.cpp,
/// linux/runner/my_application.cc). AppImage на Linux — `portable.txt` поруч із самим файлом AppImage
/// (програма всередині нього змонтована лише на час роботи).
abstract final class Portable {
  static const marker = 'portable.txt';
  static const dataDirName = 'mhrd-data';
  static const secretsFileName = 'secrets.mhrd';

  static final Directory? _dir = _detect(Platform.isWindows
      ? Platform.resolvedExecutable
      : Platform.isLinux
          ? Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable
          : null);

  /// Тека даних портативної версії; null — звичайна (встановлена) MHRD.
  static Directory? get dataDir => _dir;

  static bool get enabled => _dir != null;

  static Directory? _detect(String? exe) => exe == null ? null : detect(exe);

  /// Для тестів: тека даних для .exe за шляхом [exe] або null.
  static Directory? detect(String exe) {
    final dir = p.dirname(exe);
    return File(p.join(dir, marker)).existsSync() ? Directory(p.join(dir, dataDirName)) : null;
  }
}
