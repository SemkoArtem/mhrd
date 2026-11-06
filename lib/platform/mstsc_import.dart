import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../util/address.dart';

/// ПК, який пам'ятає стандартний клієнт Windows («Підключення до віддаленого робочого стола», mstsc).
class MstscEntry {
  const MstscEntry({required this.host, required this.port, this.username});

  final String host;
  final int port;

  /// Ім'я користувача, яким підключались востаннє (UsernameHint); пароля Windows не віддає.
  final String? username;

  String get address {
    final h = host.contains(':') ? '[$host]' : host;
    return port == 3389 ? h : '$h:$port';
  }
}

/// Читає з реєстру поточного користувача те, що пам'ятає mstsc:
/// `HKCU\Software\Microsoft\Terminal Server Client\Servers\<адреса>` (UsernameHint) і
/// `...\Default` (MRU0…MRU9 — останні адреси). Без доступу до реєстру чи не на Windows — порожньо.
List<MstscEntry> readMstscHistory() {
  if (!Platform.isWindows) return const [];
  try {
    return _Registry().read();
  } catch (_) {
    return const [];
  }
}

const _root = r'Software\Microsoft\Terminal Server Client';
// HKEY_CURRENT_USER = (HKEY)(ULONG_PTR)(LONG)0x80000001 — на 64 бітах розширюється знаком.
final _hkcu = 0x80000001.toSigned(32);
const _keyRead = 0x20019;
const _rrfRtRegSz = 0x00000002;
const _errorSuccess = 0;

typedef _OpenC = Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>);
typedef _OpenD = int Function(int, Pointer<Utf16>, int, int, Pointer<IntPtr>);
typedef _EnumC = Int32 Function(
    IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Utf16>, Pointer<Uint32>, Pointer<Void>);
typedef _EnumD = int Function(
    int, int, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Utf16>, Pointer<Uint32>, Pointer<Void>);
typedef _GetC = Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>);
typedef _GetD = int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>);
typedef _CloseC = Int32 Function(IntPtr);
typedef _CloseD = int Function(int);

class _Registry {
  _Registry() {
    final lib = DynamicLibrary.open('advapi32.dll');
    _open = lib.lookupFunction<_OpenC, _OpenD>('RegOpenKeyExW');
    _enum = lib.lookupFunction<_EnumC, _EnumD>('RegEnumKeyExW');
    _get = lib.lookupFunction<_GetC, _GetD>('RegGetValueW');
    _close = lib.lookupFunction<_CloseC, _CloseD>('RegCloseKey');
  }

  late final _OpenD _open;
  late final _EnumD _enum;
  late final _GetD _get;
  late final _CloseD _close;

  List<MstscEntry> read() {
    // Servers: підключи названі адресою без порту (mstsc відкидає порт), у кожному UsernameHint.
    final users = <String, String?>{}; // вузол (малими) → ім'я
    final hosts = <String, String>{}; // вузол (малими) → як записано
    for (final name in _subkeys('$_root\\Servers')) {
      final a = parseAddress(name.trim());
      if (a == null) continue;
      final user = _string('$_root\\Servers\\$name', 'UsernameHint')?.trim();
      final key = a.host.toLowerCase();
      hosts[key] = a.host;
      if (user != null && user.isNotEmpty) users[key] = user;
    }
    // Default: MRU0…MRU9 — адреси, як їх вводили (з портом); ім'я — з Servers того ж вузла.
    final byKey = <String, MstscEntry>{};
    final inMru = <String>{};
    for (var i = 0; i < 10; i++) {
      final a = parseAddress(_string('$_root\\Default', 'MRU$i')?.trim() ?? '');
      if (a == null) continue;
      final host = a.host.toLowerCase();
      inMru.add(host);
      byKey.putIfAbsent('$host:${a.port}', () => MstscEntry(host: a.host, port: a.port, username: users[host]));
    }
    // Вузли з Servers, яких немає серед останніх адрес, — на стандартному порту.
    for (final MapEntry(key: host, value: shown) in hosts.entries) {
      if (inMru.contains(host)) continue;
      byKey.putIfAbsent('$host:3389', () => MstscEntry(host: shown, port: 3389, username: users[host]));
    }
    return byKey.values.toList()..sort((a, b) => a.address.toLowerCase().compareTo(b.address.toLowerCase()));
  }

  List<String> _subkeys(String path) {
    final out = <String>[];
    final p = path.toNativeUtf16();
    final h = calloc<IntPtr>();
    final name = calloc<Uint16>(256).cast<Utf16>();
    final len = calloc<Uint32>();
    try {
      if (_open(_hkcu, p, 0, _keyRead, h) != _errorSuccess) return out;
      for (var i = 0;; i++) {
        len.value = 256;
        if (_enum(h.value, i, name, len, nullptr, nullptr, nullptr, nullptr) != _errorSuccess) break;
        out.add(name.toDartString(length: len.value));
      }
      _close(h.value);
    } finally {
      calloc.free(p);
      calloc.free(h);
      calloc.free(name);
      calloc.free(len);
    }
    return out;
  }

  String? _string(String path, String value) {
    final p = path.toNativeUtf16();
    final v = value.toNativeUtf16();
    final size = calloc<Uint32>();
    try {
      if (_get(_hkcu, p, v, _rrfRtRegSz, nullptr, nullptr, size) != _errorSuccess || size.value < 2) return null;
      final buf = calloc<Uint8>(size.value + 2);
      try {
        if (_get(_hkcu, p, v, _rrfRtRegSz, nullptr, buf.cast(), size) != _errorSuccess) return null;
        return buf.cast<Utf16>().toDartString();
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(p);
      calloc.free(v);
      calloc.free(size);
    }
  }
}
