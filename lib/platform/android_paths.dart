import 'dart:io';

import 'package:flutter/services.dart';

/// Android: теки застосунку з MainActivity (канал «mhrd/android»). Модуль сеансу лежить у теці
/// бібліотек застосунку як libmhrd_session.so — лише звідти Android дозволяє його запускати.
class AndroidPaths {
  const AndroidPaths({required this.nativeLibraryDir, required this.filesDir, required this.cacheDir});

  final String nativeLibraryDir, filesDir, cacheDir;

  static const _channel = MethodChannel('mhrd/android');

  /// null — не Android або канал не відповів.
  static Future<AndroidPaths?> load() async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await _channel.invokeMapMethod<String, String>('paths');
      if (m == null) return null;
      return AndroidPaths(nativeLibraryDir: m['nativeLibraryDir']!, filesDir: m['filesDir']!, cacheDir: m['cacheDir']!);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Модуль сеансу; null — його немає в APK.
  String? get engine {
    final path = '$nativeLibraryDir/libmhrd_session.so';
    return File(path).existsSync() ? path : null;
  }

  /// Оточення процесу сеансу: у застосунку Android немає HOME, а FreeRDP тримає там свою теку.
  Map<String, String> get environment => {'HOME': filesDir, 'TMPDIR': cacheDir};
}
