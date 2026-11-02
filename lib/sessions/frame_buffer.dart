import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Спільна пам'ять із картинкою сеансу: `mhrd-session` малює туди (BGRA), застосунок читає.
/// Відкривається лише для читання; пам'ять звільняє процес сеансу.
abstract class FrameBuffer {
  Uint8List get bytes;
  void close();

  /// Відкриває буфер за іменем із події SurfaceEvent. null — не вдалося.
  static FrameBuffer? open(String name, int size) => Platform.isWindows
      ? _WindowsFrameBuffer.open(name, size)
      : Platform.isAndroid && name.startsWith('fd:')
          ? _PosixFrameBuffer.open(FrameSocket.instance?.take(name.substring(3)), size)
          : null;
}

// ── Android: memfd процесу сеансу, переданий дескриптором (native/session/src/shm.c) ─────────
// Відкрити чужий memfd за шляхом /proc/<pid>/fd SELinux не дає, а відобразити переданий
// дескриптор — так. Процес сеансу надсилає його дейтаграмою з SCM_RIGHTS на абстрактний сокет
// застосунку (ім'я — у змінній MHRD_FRAME_SOCKET) ще до події SurfaceEvent, тож вона вже чекає.

const _afUnix = 1, _sockDgram = 2, _sockNonblock = 0x800, _sockCloexec = 0x80000;
const _solSocket = 1, _soPasscred = 16, _scmRights = 1, _scmCredentials = 2;
const _msgDontwait = 0x40, _msgCmsgCloexec = 0x40000000;
const _protRead = 1, _mapShared = 1;

final _libc = DynamicLibrary.process();
final _socket = _libc.lookupFunction<Int32 Function(Int32, Int32, Int32), int Function(int, int, int)>('socket');
final _bind =
    _libc.lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Uint32), int Function(int, Pointer<Uint8>, int)>('bind');
final _setsockopt = _libc.lookupFunction<Int32 Function(Int32, Int32, Int32, Pointer<Int32>, Uint32),
    int Function(int, int, int, Pointer<Int32>, int)>('setsockopt');
final _recvmsg = _libc
    .lookupFunction<IntPtr Function(Int32, Pointer<Uint8>, Int32), int Function(int, Pointer<Uint8>, int)>('recvmsg');
final _getuid = _libc.lookupFunction<Uint32 Function(), int Function()>('getuid');
final _close = _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
final _mmap = _libc.lookupFunction<Pointer<Uint8> Function(Pointer<Void>, IntPtr, Int32, Int32, Int32, IntPtr),
    Pointer<Uint8> Function(Pointer<Void>, int, int, int, int, int)>('mmap');
final _munmap =
    _libc.lookupFunction<Int32 Function(Pointer<Uint8>, IntPtr), int Function(Pointer<Uint8>, int)>('munmap');

/// Сокет застосунку, на який процеси сеансу надсилають дескриптори пам'яті кадру. Приймає лише
/// від процесів того самого користувача Android (SCM_CREDENTIALS), тобто від самого MHRD.
class FrameSocket {
  FrameSocket._(this._fd, this.name);

  final int _fd;

  /// Абстрактне ім'я (без початкового нуля) — для MHRD_FRAME_SOCKET процесу сеансу.
  final String name;

  final _received = <String, int>{};

  static FrameSocket? _instance;
  static bool _tried = false;

  /// Один на застосунок; null — не Android або сокет не створився.
  static FrameSocket? get instance {
    if (!_tried) {
      _tried = true;
      _instance = Platform.isAndroid ? _open() : null;
    }
    return _instance;
  }

  static FrameSocket? _open() {
    final fd = _socket(_afUnix, _sockDgram | _sockNonblock | _sockCloexec, 0);
    if (fd < 0) return null;
    final rnd = Random.secure();
    final name = 'mhrd-frames-$pid-${List.generate(8, (_) => rnd.nextInt(16).toRadixString(16)).join()}';
    final bytes = name.codeUnits;
    final addr = calloc<Uint8>(110);
    final one = calloc<Int32>()..value = 1;
    try {
      addr[0] = _afUnix; // sun_family (u16 LE), далі sun_path: 0 + ім'я — абстрактний простір
      for (var i = 0; i < bytes.length; i++) {
        addr[3 + i] = bytes[i];
      }
      if (_bind(fd, addr, 3 + bytes.length) != 0 || _setsockopt(fd, _solSocket, _soPasscred, one, 4) != 0) {
        _close(fd);
        return null;
      }
      return FrameSocket._(fd, name);
    } finally {
      calloc.free(addr);
      calloc.free(one);
    }
  }

  /// Дескриптор, надісланий із міткою [tag]; null — не надходив. Дескриптор переходить до викликача.
  int? take(String tag) {
    _drain();
    return _received.remove(tag);
  }

  /// Забирає з сокета все, що надійшло (не чекаючи).
  void _drain() {
    final msg = calloc<Uint8>(56), iov = calloc<Uint8>(16), data = calloc<Uint8>(64), control = calloc<Uint8>(128);
    try {
      for (;;) {
        msg.asTypedList(56).fillRange(0, 56, 0);
        final m = msg.cast<Uint64>(), io = iov.cast<Uint64>();
        io[0] = data.address;
        io[1] = 64;
        m[2] = iov.address; // msg_iov
        m[3] = 1; // msg_iovlen
        m[4] = control.address; // msg_control
        m[5] = 128; // msg_controllen
        final n = _recvmsg(_fd, msg, _msgDontwait | _msgCmsgCloexec);
        if (n < 0) return; // більше нічого немає
        final controlLen = m[5];
        int? fd, uid;
        for (var off = 0; off + 16 <= controlLen;) {
          final len = (control + off).cast<Uint64>().value;
          if (len < 16) break;
          final level = (control + off + 8).cast<Int32>().value;
          final type = (control + off + 12).cast<Int32>().value;
          if (level == _solSocket && type == _scmRights && len >= 20) {
            fd = (control + off + 16).cast<Int32>().value;
          } else if (level == _solSocket && type == _scmCredentials && len >= 28) {
            uid = (control + off + 20).cast<Uint32>().value; // struct ucred: pid, uid, gid
          }
          off += (len + 7) & ~7;
        }
        if (fd == null) continue;
        if (uid != _getuid() || n <= 0) {
          _close(fd); // не від нашого процесу — не беремо
          continue;
        }
        final tag = String.fromCharCodes(data.asTypedList(n));
        final old = _received.remove(tag);
        if (old != null) _close(old);
        _received[tag] = fd;
        // Запобіжник: необраних дескрипторів не накопичуємо.
        while (_received.length > 8) {
          _close(_received.remove(_received.keys.first)!);
        }
      }
    } finally {
      calloc.free(msg);
      calloc.free(iov);
      calloc.free(data);
      calloc.free(control);
    }
  }
}

class _PosixFrameBuffer implements FrameBuffer {
  _PosixFrameBuffer(this._view, this._size) : bytes = _view.asTypedList(_size);

  final Pointer<Uint8> _view;
  final int _size;
  bool _closed = false;

  @override
  final Uint8List bytes;

  /// Відображає переданий дескриптор [fd] і закриває його (відображення живе й без нього).
  static _PosixFrameBuffer? open(int? fd, int size) {
    if (fd == null) return null;
    final view = _mmap(nullptr, size, _protRead, _mapShared, fd, 0);
    _close(fd);
    if (view.address == -1 || view == nullptr) return null;
    return _PosixFrameBuffer(view, size);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _munmap(_view, _size);
  }
}

// ── Windows: file mapping (kernel32) ────────────────────────────

const _fileMapRead = 0x0004;

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _openFileMapping =
    _kernel32.lookupFunction<IntPtr Function(Uint32, Int32, Pointer<Utf8>), int Function(int, int, Pointer<Utf8>)>(
        'OpenFileMappingA');
final _mapViewOfFile = _kernel32.lookupFunction<Pointer<Uint8> Function(IntPtr, Uint32, Uint32, Uint32, IntPtr),
    Pointer<Uint8> Function(int, int, int, int, int)>('MapViewOfFile');
final _unmapViewOfFile =
    _kernel32.lookupFunction<Int32 Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>('UnmapViewOfFile');
final _closeHandle = _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

class _WindowsFrameBuffer implements FrameBuffer {
  _WindowsFrameBuffer(this._handle, this._view, int size) : bytes = _view.asTypedList(size);

  final int _handle;
  final Pointer<Uint8> _view;
  bool _closed = false;

  @override
  final Uint8List bytes;

  static _WindowsFrameBuffer? open(String name, int size) {
    final cName = name.toNativeUtf8();
    try {
      final h = _openFileMapping(_fileMapRead, 0, cName);
      if (h == 0) return null;
      final view = _mapViewOfFile(h, _fileMapRead, 0, 0, size);
      if (view == nullptr) {
        _closeHandle(h);
        return null;
      }
      return _WindowsFrameBuffer(h, view, size);
    } finally {
      malloc.free(cName);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _unmapViewOfFile(_view);
    _closeHandle(_handle);
  }
}
