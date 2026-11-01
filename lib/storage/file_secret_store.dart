import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'secret_store.dart';

/// Сховище секретів портативної версії: зашифрований файл поруч із програмою замість системного
/// сховища (там секрети прив'язані до користувача Windows і на іншому ПК не відкриються).
///
/// Формат: "MHRDS1" | memKiB (u32 BE) | iterations (u8) | parallelism (u8) | salt (16) | nonce (12) |
/// tag (16) | шифротекст. Ключ — Argon2id(майстер-пароль, salt), шифр — AES-256-GCM, AAD — усі байти
/// до tag. Усередині — JSON-об'єкт «ключ → секрет». Ключ живе лише в пам'яті, поки MHRD відкритий.
///
/// Поки сховище не розблоковане, читання й запис чекають розблокування (так фонові перевірки
/// тунелів і автобекап просто почнуться після введення пароля).
class FileSecretStore implements SecretStore {
  FileSecretStore(this.file, {this.memKiB = 65536, this.iterations = 3, this.parallelism = 1});

  final File file;

  /// Параметри Argon2id нового файлу. Тести можуть зменшити.
  final int memKiB, iterations, parallelism;

  static final _magic = ascii.encode('MHRDS1');
  static const _saltLen = 16, _nonceLen = 12, _tagLen = 16;
  static const minPasswordLength = 8;

  SecretKey? _key;
  List<int>? _salt;
  int _mem = 0, _it = 0, _par = 0;
  Map<String, String> _data = {};
  Completer<void> _ready = Completer<void>();
  Future<void> _writes = Future.value();

  bool get exists => file.existsSync();
  bool get unlocked => _key != null;

  /// Створює новий файл з паролем (старого файлу не має бути).
  Future<void> create(String password) async {
    if (password.length < minPasswordLength) throw ArgumentError('password too short');
    if (exists) throw StateError('secrets file already exists');
    await _setPassword(password, {});
    await _persist();
    _open();
  }

  /// Розблоковує наявний файл. false — пароль не підійшов. Пошкоджений файл — [FormatException].
  Future<bool> unlock(String password) async {
    final f = await _read(file);
    final key = await _derive(password, f.salt, f.mem, f.it, f.par);
    final Map<String, String> data;
    try {
      data = await _decrypt(f, key);
    } on SecretBoxAuthenticationError {
      return false;
    }
    _key = key;
    _salt = f.salt;
    _mem = f.mem;
    _it = f.it;
    _par = f.par;
    _data = data;
    _open();
    return true;
  }

  /// Чи це майстер-пароль (для чутливих дій, коли сховище вже відкрите).
  Future<bool> checkPassword(String password) async {
    final salt = _salt;
    final key = _key;
    if (salt == null || key == null) return false;
    final a = await (await _derive(password, salt, _mem, _it, _par)).extractBytes();
    final b = await key.extractBytes();
    if (a.length != b.length) return false;
    var diff = 0; // порівняння за сталий час
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Новий майстер-пароль (сховище має бути відкрите): нова сіль, файл перешифровується.
  Future<void> changePassword(String password) async {
    if (password.length < minPasswordLength) throw ArgumentError('password too short');
    await _ready.future;
    await _queue(() async {
      await _setPassword(password, _data);
      await _persist();
    });
  }

  /// Забуває ключ і секрети з пам'яті; нові читання знову чекатимуть [unlock].
  void lock() {
    _key = null;
    _data = {};
    if (_ready.isCompleted) _ready = Completer<void>();
  }

  @override
  Future<String?> read(String key) async {
    await _ready.future;
    return _data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    await _ready.future;
    await _queue(() async {
      _data[key] = value;
      await _persist();
    });
  }

  @override
  Future<void> delete(String key) async {
    await _ready.future;
    await _queue(() async {
      if (_data.remove(key) != null) await _persist();
    });
  }

  void _open() {
    if (!_ready.isCompleted) _ready.complete();
  }

  /// Записи — по черзі: інакше два одночасні записали б файл кожен зі своїм станом.
  Future<void> _queue(Future<void> Function() job) {
    final next = _writes.then((_) => job());
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _setPassword(String password, Map<String, String> data) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(_saltLen, (_) => rnd.nextInt(256));
    _key = await _derive(password, salt, memKiB, iterations, parallelism);
    _salt = salt;
    _mem = memKiB;
    _it = iterations;
    _par = parallelism;
    _data = Map.of(data);
  }

  /// Шифрує все наново (свіжий nonce) і замінює файл атомарно: обрив посеред запису не псує його.
  Future<void> _persist() async {
    final rnd = Random.secure();
    final nonce = List<int>.generate(_nonceLen, (_) => rnd.nextInt(256));
    final header = (BytesBuilder()
          ..add(_magic)
          ..add((ByteData(4)..setUint32(0, _mem)).buffer.asUint8List())
          ..addByte(_it)
          ..addByte(_par)
          ..add(_salt!)
          ..add(nonce))
        .toBytes();
    final box = await AesGcm.with256bits()
        .encrypt(utf8.encode(jsonEncode(_data)), secretKey: _key!, nonce: nonce, aad: header);
    final bytes = (BytesBuilder()
          ..add(header)
          ..add(box.mac.bytes)
          ..add(box.cipherText))
        .toBytes();
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  static Future<_Parsed> _read(File file) async {
    final f = await file.readAsBytes();
    final headerLen = _magic.length + 4 + 1 + 1 + _saltLen + _nonceLen;
    if (f.length < headerLen + _tagLen) throw const FormatException('secrets: truncated');
    for (var i = 0; i < _magic.length; i++) {
      if (f[i] != _magic[i]) throw const FormatException('secrets: not a secrets file');
    }
    var o = _magic.length;
    final mem = ByteData.sublistView(f, o, o + 4).getUint32(0);
    o += 4;
    final it = f[o++];
    final par = f[o++];
    // Ті самі межі, що й для бекапу: підроблений файл не має «вішати» запуск.
    if (mem < 8 || mem > 262144 || it < 1 || it > 10 || par < 1 || par > 16 || mem * it > 1048576) {
      throw const FormatException('secrets: bad parameters');
    }
    final salt = f.sublist(o, o + _saltLen);
    o += _saltLen;
    final nonce = f.sublist(o, o + _nonceLen);
    return _Parsed(mem, it, par, salt, nonce, f.sublist(0, headerLen), f.sublist(headerLen, headerLen + _tagLen),
        f.sublist(headerLen + _tagLen));
  }

  static Future<Map<String, String>> _decrypt(_Parsed f, SecretKey key) async {
    final plain = await AesGcm.with256bits()
        .decrypt(SecretBox(f.cipher, nonce: f.nonce, mac: Mac(f.tag)), secretKey: key, aad: f.aad);
    final obj = jsonDecode(utf8.decode(plain));
    if (obj is! Map) throw const FormatException('secrets: corrupted');
    return {
      for (final e in obj.entries)
        if (e.value is String) '${e.key}': e.value as String,
    };
  }

  // Виведення ключа — секунда-дві, тож в окремому ізоляті: інтерфейс не замерзає.
  static Future<SecretKey> _derive(String pw, List<int> salt, int mem, int it, int par) async =>
      SecretKey(await Isolate.run(() async {
        final k = await Argon2id(parallelism: par, memory: mem, iterations: it, hashLength: 32)
            .deriveKey(secretKey: SecretKey(utf8.encode(pw)), nonce: salt);
        return k.extractBytes();
      }));
}

class _Parsed {
  const _Parsed(this.mem, this.it, this.par, this.salt, this.nonce, this.aad, this.tag, this.cipher);
  final int mem, it, par;
  final List<int> salt, nonce, aad, tag, cipher;
}
