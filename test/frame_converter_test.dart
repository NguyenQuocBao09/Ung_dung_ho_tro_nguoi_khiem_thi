import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/core/camera/frame_converter.dart';

/// Tạo bộ đệm NV21 đồng màu (Y, U, V cố định).
Uint8List solidNv21(int w, int h, int y, int u, int v) {
  final bytes = Uint8List(w * h + w * (h ~/ 2));
  bytes.fillRange(0, w * h, y);
  for (var i = w * h; i < bytes.length; i += 2) {
    bytes[i] = v; // NV21: V trước
    bytes[i + 1] = u;
  }
  return bytes;
}

void main() {
  group('YuvFrame.fromNv21 + yuvToLetterboxedRgbFloat', () {
    test('Màu đỏ thuần NV21 -> RGB đỏ (không bị chuyển xám)', () {
      // Đỏ BT.601 full range: Y≈76, U≈85, V≈255
      final f = YuvFrame.fromNv21(bytes: solidNv21(8, 8, 76, 85, 255), width: 8, height: 8);
      final out = Float32List(4 * 4 * 3);
      yuvToLetterboxedRgbFloat(f, 4, out: out);
      expect(out[0], greaterThan(0.95)); // R
      expect(out[1], lessThan(0.05)); // G
      expect(out[2], lessThan(0.05)); // B
    });

    test('Màu xanh dương NV21 -> kênh B cao nhất', () {
      // Xanh dương: Y≈29, U≈255, V≈107
      final f = YuvFrame.fromNv21(bytes: solidNv21(8, 8, 29, 255, 107), width: 8, height: 8);
      final out = Float32List(4 * 4 * 3);
      yuvToLetterboxedRgbFloat(f, 4, out: out);
      expect(out[2], greaterThan(0.9));
      expect(out[0], lessThan(0.1));
    });

    test('Xoay 90°: nửa phải ảnh cảm biến thành nửa dưới ảnh đứng, có đệm letterbox', () {
      const w = 4, h = 2;
      final bytes = solidNv21(w, h, 0, 128, 128);
      for (var y = 0; y < h; y++) {
        for (var x = 2; x < w; x++) {
          bytes[y * w + x] = 255;
        }
      }
      final f = YuvFrame.fromNv21(bytes: bytes, width: w, height: h, rotationDegrees: 90);
      expect(f.uprightWidth, 2);
      expect(f.uprightHeight, 4);

      final out = Float32List(4 * 4 * 3);
      final lb = yuvToLetterboxedRgbFloat(f, 4, out: out);
      expect(lb.scale, 1.0);
      expect(lb.padX, 1.0);
      expect(lb.padY, 0.0);

      double r(int ox, int oy) => out[(oy * 4 + ox) * 3];
      expect(r(0, 0), closeTo(114 / 255, 1e-6)); // cột đệm
      expect(r(1, 0), lessThan(0.05)); // trên: tối
      expect(r(1, 3), greaterThan(0.95)); // dưới: sáng
    });

    test('Độ sáng trung bình chỉ tính trên vùng Y', () {
      final f = YuvFrame.fromNv21(bytes: solidNv21(32, 32, 10, 200, 200), width: 32, height: 32);
      expect(f.averageLuminance(step: 4), closeTo(10, 1e-9));
    });

    test('Bộ đệm NV21 quá nhỏ -> ArgumentError', () {
      expect(
        () => YuvFrame.fromNv21(bytes: Uint8List(10), width: 8, height: 8),
        throwsArgumentError,
      );
    });
  });

  group('yuvToUprightRgb + cropResizeToFloat', () {
    test('NV21 đỏ -> RGB đỏ 8-bit, xoay 90° đổi kích thước', () {
      final f = YuvFrame.fromNv21(
        bytes: solidNv21(8, 4, 76, 85, 255),
        width: 8,
        height: 4,
        rotationDegrees: 90,
      );
      final rgb = yuvToUprightRgb(f);
      expect(rgb.width, 4);
      expect(rgb.height, 8);
      expect(rgb.pixels[0], greaterThan(240));
      expect(rgb.pixels[1], lessThan(15));
      expect(rgb.pixels[2], lessThan(15));
    });

    test('Thu nhỏ theo maxSide giữ tỉ lệ', () {
      final f = YuvFrame.fromNv21(bytes: solidNv21(64, 32, 128, 128, 128), width: 64, height: 32);
      final rgb = yuvToUprightRgb(f, maxSide: 16);
      expect(rgb.width, 16);
      expect(rgb.height, 8);
    });

    test('Xoay 90° đúng hướng: nửa phải cảm biến thành nửa dưới ảnh đứng', () {
      const w = 4, h = 2;
      final bytes = solidNv21(w, h, 0, 128, 128);
      for (var y = 0; y < h; y++) {
        for (var x = 2; x < w; x++) {
          bytes[y * w + x] = 255;
        }
      }
      final rgb = yuvToUprightRgb(
        YuvFrame.fromNv21(bytes: bytes, width: w, height: h, rotationDegrees: 90),
      );
      int r(int x, int y) => rgb.pixels[(y * rgb.width + x) * 3];
      expect(r(0, 0), lessThan(10));
      expect(r(0, 3), greaterThan(245));
    });

    test('Cắt nửa phải rồi co giãn: chỉ lấy vùng được chọn, giá trị 0..255', () {
      // Ảnh 4x2: nửa trái đen, nửa phải trắng.
      final px = Uint8List(4 * 2 * 3);
      for (var y = 0; y < 2; y++) {
        for (var x = 2; x < 4; x++) {
          final i = (y * 4 + x) * 3;
          px[i] = px[i + 1] = px[i + 2] = 255;
        }
      }
      final out = Float32List(2 * 2 * 3);
      cropResizeToFloat(RgbImage(4, 2, px), 0.5, 0, 1, 1, 2, out);
      for (final v in out) {
        expect(v, closeTo(255, 1e-6));
      }
      cropResizeToFloat(RgbImage(4, 2, px), 0, 0, 0.5, 1, 2, out);
      for (final v in out) {
        expect(v, closeTo(0, 1e-6));
      }
    });

    test('RgbImage sai kích thước -> ArgumentError', () {
      expect(() => RgbImage(4, 4, Uint8List(10)), throwsArgumentError);
    });
  });
}
