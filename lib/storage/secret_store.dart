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
      : _s = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
        );

  final FlutterSecureStorage _s;

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
