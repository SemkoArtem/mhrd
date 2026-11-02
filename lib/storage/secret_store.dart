import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Сховище паролів і ключів. Реалізація за замовчуванням — системне сховище ОС
/// (Credential Manager, Keychain, Secret Service/libsecret, Android Keystore).
/// Секрети ніколи не потрапляють у базу, журнали чи звичайний експорт.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SystemSecretStore implements SecretStore {
  SystemSecretStore()
      // Android: типові AndroidOptions — ключ у Keystore, дані шифруються AES-GCM
      // (EncryptedSharedPreferences прибрано з flutter_secure_storage 11).
      : _s = const FlutterSecureStorage(
          mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
        );

  final FlutterSecureStorage _s;

  /// Linux: чи є Secret Service (GNOME Keyring, KWallet). false — лише коли сховище явно відповіло
  /// помилкою (сервісу немає); довга відповідь (система просить розблокувати сховище) — не причина
  /// відмовлятися від нього.
  Future<bool> available({Duration timeout = const Duration(seconds: 20)}) async {
    try {
      await _s.read(key: 'mhrd.probe').timeout(timeout);
      return true;
    } on TimeoutException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// Сховище в пам'яті — для тестів.
class MemorySecretStore implements SecretStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}
