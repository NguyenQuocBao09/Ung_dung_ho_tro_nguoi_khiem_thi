import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/core/quality/lighting_detector.dart';

void main() {
  group('sampleLumaMean', () {
    test('Chỉ đọc vùng Y, bỏ qua padding cuối dòng và phần UV phía sau', () {
      const w = 64, h = 32, stride = 80;
      final bytes = Uint8List(stride * h + stride * h ~/ 2);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < stride; x++) {
          bytes[y * stride + x] = x < w ? 30 : 255; // padding sáng
        }
      }
      bytes.fillRange(stride * h, bytes.length, 200); // UV
      expect(sampleLumaMean(bytes, width: w, height: h, rowStride: stride), 30);
    });

    test('Dữ liệu thiếu -> null', () {
      expect(sampleLumaMean(Uint8List(10), width: 64, height: 32, rowStride: 64), isNull);
      expect(sampleLumaMean(Uint8List(100), width: 10, height: 10, rowStride: 5), isNull);
    });
  });

  group('LightingDecider', () {
    final t0 = DateTime(2026, 1, 1);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('Đủ sáng -> không cảnh báo, không bật đèn', () {
      final d = LightingDecider();
      for (var i = 0; i < 10; i++) {
        expect(d.onSample(120, at(i * 400), torchOn: false), LightingAction.none);
      }
      expect(d.isLowLight, isFalse);
    });

    test('Tối liên tiếp 3 mẫu mới báo (không báo vì 1 khung tối lẻ)', () {
      final d = LightingDecider();
      expect(d.onSample(20, at(0), torchOn: false), LightingAction.none);
      expect(d.onSample(120, at(400), torchOn: false), LightingAction.none);
      expect(d.onSample(20, at(800), torchOn: false), LightingAction.none);
      expect(d.onSample(20, at(1200), torchOn: false), LightingAction.none);
      expect(d.onSample(20, at(1600), torchOn: false), LightingAction.enterLowLight);
      expect(d.isLowLight, isTrue);
    });

    test('Đèn bật mà ảnh vẫn tối vừa -> giữ đèn, không nháy', () {
      final d = LightingDecider();
      for (var i = 0; i < 3; i++) {
        d.onSample(20, at(i * 400), torchOn: false);
      }
      for (var i = 3; i < 30; i++) {
        expect(d.onSample(80, at(i * 400), torchOn: true), LightingAction.none);
      }
      expect(d.isLowLight, isTrue);
    });

    test('Đèn bật, ảnh rất sáng -> tắt đèn đo thử; môi trường sáng thật -> thoát', () {
      final d = LightingDecider();
      for (var i = 0; i < 3; i++) {
        d.onSample(20, at(i * 400), torchOn: false);
      }
      d.onSample(150, at(1200), torchOn: true);
      d.onSample(150, at(1600), torchOn: true);
      expect(d.onSample(150, at(2000), torchOn: true), LightingAction.startProbe);
      // Chờ camera cân bằng phơi sáng: mẫu sớm bị bỏ qua.
      expect(d.onSample(10, at(2300), torchOn: false), LightingAction.none);
      expect(d.onSample(130, at(2900), torchOn: false), LightingAction.probeBright);
      expect(d.isLowLight, isFalse);
    });

    test('Đo thử mà vẫn tối -> bật lại đèn và chờ cooldown mới thử lại', () {
      final d = LightingDecider(probeCooldown: const Duration(seconds: 30));
      for (var i = 0; i < 3; i++) {
        d.onSample(20, at(i * 400), torchOn: false);
      }
      for (var i = 3; i < 6; i++) {
        d.onSample(150, at(i * 400), torchOn: true);
      }
      expect(d.onSample(25, at(3200), torchOn: false), LightingAction.probeStillDark);
      expect(d.isLowLight, isTrue);
      // Trong cooldown: ảnh sáng do đèn không kích hoạt đo thử nữa.
      for (var i = 0; i < 20; i++) {
        expect(d.onSample(150, at(3600 + i * 400), torchOn: true), LightingAction.none);
      }
      // Hết cooldown -> được đo thử lại ngay (ảnh vẫn sáng liên tục trong lúc chờ).
      expect(d.onSample(150, at(40000), torchOn: true), LightingAction.startProbe);
    });

    test('Không có đèn flash: sáng trở lại -> thoát cảnh báo (có trễ)', () {
      final d = LightingDecider();
      for (var i = 0; i < 3; i++) {
        d.onSample(20, at(i * 400), torchOn: false);
      }
      // 50 nằm giữa hai ngưỡng (45..60): chưa thoát.
      for (var i = 3; i < 8; i++) {
        expect(d.onSample(50, at(i * 400), torchOn: false), LightingAction.none);
      }
      d.onSample(90, at(4000), torchOn: false);
      d.onSample(90, at(4400), torchOn: false);
      expect(d.onSample(90, at(4800), torchOn: false), LightingAction.exitLowLight);
    });
  });
}
