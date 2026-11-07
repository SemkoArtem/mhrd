import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/models/connection.dart';
import 'package:mhrd/sessions/frame_buffer.dart';
import 'package:mhrd/sessions/rdp_session.dart';
import 'package:mhrd/sessions/session_protocol.dart';

import 'session_test.dart' show FakeChannel;

/// Буфер кадру в пам'яті замість спільної пам'яті процесу сеансу.
class MemFrame implements FrameBuffer {
  MemFrame(int size) : bytes = Uint8List(size);
  @override
  final Uint8List bytes;
  @override
  void close() {}
}

List<int> u32(List<int> v) => [for (final x in v) ...[x & 255, x >> 8 & 255, x >> 16 & 255, x >> 24 & 255]];

void fill(MemFrame f, int stride, int l, int t, int r, int b, List<int> bgra) {
  for (var y = t; y < b; y++) {
    for (var x = l; x < r; x++) {
      f.bytes.setRange(y * stride + x * 4, y * stride + x * 4 + 4, bgra);
    }
  }
}

Future<List<int>> pixel(ui.Image img, int x, int y) async {
  final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final o = (y * img.width + x) * 4;
  return [d!.getUint8(o), d.getUint8(o + 1), d.getUint8(o + 2)];
}

void main() {
  testWidgets('змінена ділянка оновлюється, решта кадру лишається', (tester) async {
    await tester.runAsync(() async {
      const w = 64, h = 48, stride = w * 4;
      final frame = MemFrame(stride * h);
      final ch = FakeChannel();
      final now = DateTime.utc(2026);
      final s = RdpSession(
        id: '1',
        connection: Connection(id: 'c', name: '', host: '10.0.0.5', createdAt: now, updatedAt: now),
        channel: ch,
        openFrameBuffer: (_, __) => frame,
      );
      s.start(const {});
      Future<void> settle(bool Function() done) async {
        for (var i = 0; i < 200 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      fill(frame, stride, 0, 0, w, h, const [0, 0, 255, 255]); // BGRA: червоний
      ch.emit(Msg.evtSurface, [...u32([w, h, stride]), ...'mem'.codeUnits]);
      await settle(() => s.image != null);
      final first = s.image!;
      expect(await pixel(first, 5, 5), [255, 0, 0]);

      fill(frame, stride, 40, 30, 50, 40, const [255, 0, 0, 255]); // синя ділянка
      fill(frame, stride, 2, 2, 4, 4, const [0, 255, 0, 255]); // і маленька зелена в іншому куті
      ch.emit(Msg.evtFrame, u32([40, 30, 10, 10]));
      ch.emit(Msg.evtFrame, u32([2, 2, 2, 2]));
      // Дві ділянки можуть скластися по черзі — чекаємо, доки картинка перестане мінятись.
      await settle(() => s.image != first);
      for (var stable = 0; stable < 5;) {
        final cur = s.image;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        stable = identical(cur, s.image) ? stable + 1 : 0;
      }
      final img = s.image!;
      expect(img.width, w);
      expect(await pixel(img, 45, 35), [0, 0, 255]); // оновлено
      expect(await pixel(img, 3, 3), [0, 255, 0]); // оновлено
      expect(await pixel(img, 20, 20), [255, 0, 0]); // не чіпали — як було
      expect(await pixel(img, 63, 47), [255, 0, 0]);
    });
  });
}
