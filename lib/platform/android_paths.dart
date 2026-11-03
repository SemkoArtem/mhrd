import 'dart:io';

import 'package:flutter/services.dart';

import '../sessions/frame_buffer.dart';

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

  /// Служба переднього плану зі сповіщенням [text], поки [count] > 0 (MainActivity → SessionService):
  /// інакше Android заморожує згорнутий застосунок разом із процесами сеансів.
  static Future<void> updateSessions(int count, String text) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('sessions', {'count': count, 'text': text});
    } on PlatformException {
      // служба не запустилась (наприклад, Android заборонив з фону) — сеанс працює й так
    } on MissingPluginException {
      // не Android-раннер MHRD
    }
  }

  /// «Зберегти як» системним вікном Android (Завантаження, Google Drive…). Повертає назву
  /// збереженого файлу або null — скасовано.
  static Future<String?> saveFile(String name, Uint8List bytes) =>
      _channel.invokeMethod<String>('saveFile', {'name': name, 'bytes': bytes});

  /// Вибір файлів системним вікном з одразу видимою пам'яттю телефона (MainActivity → openFiles).
  /// Повертає (назва, вміст); порожньо — скасовано.
  static Future<List<(String, Uint8List)>> openFiles({bool multiple = false, String mime = '*/*'}) async {
    final r = await _channel.invokeListMethod<Map<Object?, Object?>>('openFiles', {'multiple': multiple, 'mime': mime});
    return [
      for (final m in r ?? const <Map<Object?, Object?>>[])
        if (m['name'] case final String name)
          if (m['bytes'] case final Uint8List bytes) (name, bytes),
    ];
  }

  /// Попросити дозвіл на мікрофон (для ПК з увімкненим мікрофоном), якщо його ще немає.
  static Future<void> requestMicrophone() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('microphone');
    } on PlatformException {
      // без дозволу сеанс працює, лише без мікрофона
    } on MissingPluginException {
      // не Android-раннер MHRD
    }
  }

  /// Модуль сеансу; null — його немає в APK.
  String? get engine => _module('libmhrd_session.so');

  /// Вбудований тунель WireGuard (native/tunnels/build-android.sh); null — його немає в APK.
  String? get tunnel => _module('libmhrd_tunnel.so');

  String? _module(String file) {
    final path = '$nativeLibraryDir/$file';
    return File(path).existsSync() ? path : null;
  }

  /// Оточення процесу сеансу: у застосунку Android немає HOME, а FreeRDP тримає там свою теку;
  /// MHRD_FRAME_SOCKET — куди надсилати дескриптор пам'яті кадру (frame_buffer.dart).
  Map<String, String> get environment => {
        'HOME': filesDir,
        'TMPDIR': cacheDir,
        if (FrameSocket.instance case final s?) 'MHRD_FRAME_SOCKET': s.name,
      };
}
