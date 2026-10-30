import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Спільна пам'ять із картинкою сеансу: `mhrd-session` малює туди (BGRA), застосунок читає.
/// Відкривається лише для читання; пам'ять звільняє процес сеансу.
abstract class FrameBuffer {
  Uint8List get bytes;
  void close();

  /// Відкриває буфер за іменем із події SurfaceEvent. null — не вдалося.
  static FrameBuffer? open(String name, int size) =>
      Platform.isWindows ? _WindowsFrameBuffer.open(name, size) : null;
}

// ── Windows: file mapping (kernel32) ────────────────────────────

const _fileMapRead = 0x0004;

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _openFileMapping = _kernel32
    .lookupFunction<IntPtr Function(Uint32, Int32, Pointer<Utf8>), int Function(int, int, Pointer<Utf8>)>(
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
