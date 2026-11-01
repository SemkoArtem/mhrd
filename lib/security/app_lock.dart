import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';

import '../storage/repository.dart';

/// Блокування MHRD при запуску: PIN і, за бажанням, відбиток / Windows Hello.
/// PIN ніде не зберігається — лише сіль і хеш PBKDF2 у системному сховищі секретів.
class AppLock {
  AppLock(this.repo, {LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final Repository repo;
  final LocalAuthentication _auth;

  static const pinKey = 'mhrd.appLock.pin';
  static const _iterations = 60000;

  /// Чи питати PIN зараз. Увімкнено, а PIN у сховищі немає (бекап з іншого пристрою) — блокування
  /// вимикається: інакше людина не змогла б відкрити MHRD зовсім.
  Future<bool> isRequired() async {
    if (!repo.settings.lockEnabled) return false;
    if (await repo.secrets.read(pinKey) != null) return true;
    repo.updateSettings(repo.settings.copyWith(lockEnabled: false, lockBiometric: false));
    return false;
  }

  Future<void> setPin(String pin) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hash = await _hash(pin, salt);
    await repo.secrets.write(pinKey, 'v1:${base64.encode(salt)}:${base64.encode(hash)}');
    repo.updateSettings(repo.settings.copyWith(lockEnabled: true));
  }

  Future<bool> checkPin(String pin) async {
    final stored = await repo.secrets.read(pinKey);
    final parts = stored?.split(':');
    if (parts == null || parts.length != 3 || parts[0] != 'v1') return false;
    final expected = base64.decode(parts[2]);
    final actual = await _hash(pin, base64.decode(parts[1]));
    if (actual.length != expected.length) return false;
    var diff = 0; // порівняння за сталий час
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  Future<void> disable() async {
    await repo.secrets.delete(pinKey);
    repo.updateSettings(repo.settings.copyWith(lockEnabled: false, lockBiometric: false));
  }

  /// Чи є на пристрої відбиток / Windows Hello / розпізнавання обличчя.
  Future<bool> biometricAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on Exception {
      return false;
    }
  }

  /// Системний запит відбитка / Windows Hello. false — скасували, не вдалося або недоступно.
  Future<bool> unlockWithBiometric(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } on Exception {
      return false;
    }
  }

  static Future<List<int>> _hash(String pin, List<int> salt) async {
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iterations, bits: 256)
        .deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }
}
