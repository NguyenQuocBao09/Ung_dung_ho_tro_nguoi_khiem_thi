import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/core/camera/frame_converter.dart';
import 'package:vision_assist/features/obstacle/domain/alert_level.dart';
import 'package:vision_assist/features/obstacle/domain/obstacle_detection.dart';
import 'package:vision_assist/features/obstacle/domain/yolo_decoder.dart';
import 'package:vision_assist/features/obstacle/presentation/obstacle_controller.dart';

ObstacleDetection det(String label, double l, double t, double r, double b,
        {double s = 0.8, int c = 0}) =>
    ObstacleDetection(classIndex: c, label: label, score: s, left: l, top: t, right: r, bottom: b);

const _vi = {'person': 'Người', 'chair': 'Ghế', 'tv': 'Ti vi', 'potted plant': 'Chậu cây'};

ObstacleAssessment assessment(AlertLevel level,
        {String label = 'person', double score = 0.8,
        ObstacleDirection dir = ObstacleDirection.ahead}) =>
    ObstacleAssessment(
      detection: det(label, 0.4, 0.1, 0.6, 0.9, s: score),
      nameVi: _vi[label] ?? label,
      direction: dir,
      level: level,
    );

void main() {
  group('YoloDecoder', () {
    const labels = ['person', 'chair', 'cat'];
    // Ảnh đứng 480x640 -> model 320: scale 0.5, padX 40, padY 0
    final lb = LetterboxInfo.compute(480, 640, 320);

    Float32List buildOutput(List<List<double>> anchors) {
      // mỗi anchor: [cx, cy, w, h, s0, s1, s2]
      final n = anchors.length;
      final out = Float32List(7 * n);
      for (var a = 0; a < n; a++) {
        for (var ch = 0; ch < 7; ch++) {
          out[ch * n + a] = anchors[a][ch];
        }
      }
      return out;
    }

    test('Bỏ letterbox đúng, NMS loại box trùng, lọc ngưỡng điểm', () {
      final out = buildOutput([
        [160, 160, 100, 200, 0.9, 0.0, 0.0], // người
        [162, 158, 100, 200, 0.8, 0.0, 0.0], // người trùng -> bị NMS loại
        [100, 100, 40, 40, 0.0, 0.3, 0.0], // ghế điểm thấp -> loại
      ]);
      const dec = YoloDecoder(numClasses: 3, numAnchors: 3, coordsNormalized: false);
      final dets = dec.decode(out, labels, lb);
      expect(dets, hasLength(1));
      final d = dets.single;
      expect(d.label, 'person');
      expect(d.score, closeTo(0.9, 1e-6));
      expect(d.left, closeTo(140 / 480, 1e-6));
      expect(d.right, closeTo(340 / 480, 1e-6));
      expect(d.top, closeTo(120 / 640, 1e-6));
      expect(d.bottom, closeTo(520 / 640, 1e-6));
    });

    test('Toạ độ chuẩn hoá 0..1 cho kết quả giống toạ độ pixel', () {
      final px = buildOutput([[160, 160, 100, 200, 0.9, 0, 0]]);
      final norm = buildOutput([[0.5, 0.5, 100 / 320, 200 / 320, 0.9, 0, 0]]);
      final a = const YoloDecoder(numClasses: 3, numAnchors: 1, coordsNormalized: false)
          .decode(px, labels, lb)
          .single;
      final b = const YoloDecoder(numClasses: 3, numAnchors: 1, coordsNormalized: true)
          .decode(norm, labels, lb)
          .single;
      expect(b.left, closeTo(a.left, 1e-5));
      expect(b.bottom, closeTo(a.bottom, 1e-5));
    });

    test('allowedClasses loại lớp không phải vật cản', () {
      final out = buildOutput([[160, 160, 50, 50, 0.0, 0.0, 0.95]]);
      final dets = const YoloDecoder(
        numClasses: 3,
        numAnchors: 1,
        coordsNormalized: false,
        allowedClasses: {0, 1},
      ).decode(out, labels, lb);
      expect(dets, isEmpty);
    });

    test('Lớp cao nhất không phải vật cản -> bỏ, KHÔNG gán sang lớp vật cản điểm thấp hơn', () {
      // "cat" (chỉ số 2) không được phép, điểm 0.8; "person" được phép nhưng chỉ 0.45
      final out = buildOutput([[160, 160, 50, 50, 0.45, 0.0, 0.8]]);
      final dets = const YoloDecoder(
        numClasses: 3,
        numAnchors: 1,
        coordsNormalized: false,
        allowedClasses: {0, 1},
      ).decode(out, labels, lb);
      expect(dets, isEmpty);
    });

    test('Sai kích thước đầu ra -> ArgumentError', () {
      expect(
        () => const YoloDecoder(numClasses: 3, numAnchors: 2).decode(Float32List(5), labels, lb),
        throwsArgumentError,
      );
    });

    test('NMS theo lớp: khác lớp không loại nhau', () {
      final kept = YoloDecoder.nonMaxSuppression([
        det('person', 0.1, 0.1, 0.5, 0.5, s: 0.9, c: 0),
        det('chair', 0.1, 0.1, 0.5, 0.5, s: 0.8, c: 1),
      ], 0.5, 10);
      expect(kept, hasLength(2));
    });
  });

  group('ObstacleAssessor (theo kích thước trên ảnh, không ước lượng mét)', () {
    const assessor = ObstacleAssessor();

    test('Người chiếm trọn chiều cao ở giữa -> danger, phía trước', () {
      final a = assessor.assess([det('person', 0.25, 0.0, 0.75, 1.0)])!;
      expect(a.level, AlertLevel.danger);
      expect(a.direction, ObstacleDirection.ahead);
    });

    test('Vật lớn chiếm ~60% chiều cao trên đường đi -> warning', () {
      expect(assessor.assess([det('chair', 0.35, 0.3, 0.65, 0.9)])!.level, AlertLevel.warning);
    });

    test('Vật lớn ở hẳn bên trái (không lấn đường đi) -> chỉ đọc tên', () {
      final a = assessor.assess([det('person', 0.0, 0.0, 0.3, 1.0)])!;
      expect(a.direction, ObstacleDirection.left);
      expect(a.level, AlertLevel.safe);
    });

    test('Vật nhỏ không bao giờ cảnh báo khẩn cấp dù chiếm trọn khung', () {
      final a = assessor.assess([det('cell phone', 0.1, 0.0, 0.9, 1.0)])!;
      expect(a.nameVi, 'Điện thoại');
      expect(a.level, AlertLevel.safe);
    });

    test('Vật nhỏ ở xa vẫn được nhận diện (không giới hạn khoảng cách)', () {
      final a = assessor.assess([det('chair', 0.48, 0.48, 0.5, 0.51)])!;
      expect(a.nameVi, 'Ghế');
      expect(a.level, AlertLevel.safe);
    });

    test('Lớp hiếm gặp (máy bay) cần độ tin cậy ≥ 70%; lớp thường cần ≥ 45%', () {
      expect(assessor.assess([det('airplane', 0.3, 0.2, 0.9, 0.5, s: 0.47)]), isNull);
      expect(assessor.assess([det('airplane', 0.3, 0.2, 0.9, 0.5, s: 0.75)]), isNotNull);
      expect(assessor.assess([det('chair', 0.3, 0.2, 0.6, 0.5, s: 0.42)]), isNull);
      expect(assessor.assess([det('chair', 0.3, 0.2, 0.6, 0.5, s: 0.5)]), isNotNull);
    });

    test('Không nhận ra vật nào -> null; bbox lỗi bị bỏ', () {
      expect(assessor.assess(const []), isNull);
      expect(assessor.assess([det('unknown_label', 0.4, 0.4, 0.6, 0.6)]), isNull);
      expect(assessor.assess([det('chair', 0.5, 0.5, 0.5, 0.9)]), isNull);
    });
  });

  group('SceneAnnouncer', () {
    final t0 = DateTime(2026, 11, 3, 10);
    Duration ms(int v) => Duration(milliseconds: v);

    test('Vật phải xuất hiện ≥2/3 khung mới được đọc, gom thành một câu mô tả', () {
      final s = SceneAnnouncer();
      final frame = [
        assessment(AlertLevel.safe, label: 'person'),
        assessment(AlertLevel.safe, label: 'chair'),
        assessment(AlertLevel.safe, label: 'chair'),
        assessment(AlertLevel.safe, label: 'tv', dir: ObstacleDirection.right),
      ];
      expect(s.onFrame(frame, t0), isNull);
      final d = s.onFrame(frame, t0.add(ms(400)))!;
      expect(d.type, SceneDecisionType.scene);
      expect(buildSceneMessage(d.items), 'Phía trước: 2 ghế, người. Bên phải: ti vi.');
    });

    test('Cảnh không đổi thì không đọc lại; có vật mới thì đọc lại toàn cảnh', () {
      final s = SceneAnnouncer();
      final a = [assessment(AlertLevel.safe, label: 'chair')];
      s.onFrame(a, t0);
      expect(s.onFrame(a, t0.add(ms(400))), isNotNull);
      expect(s.onFrame(a, t0.add(ms(5000))), isNull);

      final b = [...a, assessment(AlertLevel.safe, label: 'potted plant', dir: ObstacleDirection.left)];
      s.onFrame(b, t0.add(ms(5400)));
      final d = s.onFrame(b, t0.add(ms(5800)))!;
      expect(buildSceneMessage(d.items), 'Phía trước: ghế. Bên trái: chậu cây.');
    });

    test('Có vật mới nhưng chưa đủ 4 giây kể từ lần đọc trước -> chờ', () {
      final s = SceneAnnouncer();
      final a = [assessment(AlertLevel.safe, label: 'chair')];
      s.onFrame(a, t0);
      s.onFrame(a, t0.add(ms(400)));
      final b = [...a, assessment(AlertLevel.safe, label: 'tv')];
      s.onFrame(b, t0.add(ms(800)));
      expect(s.onFrame(b, t0.add(ms(1200))), isNull);
      expect(s.onFrame(b, t0.add(ms(4500))), isNotNull);
    });

    test('Vật khuất hơn 10 giây rồi quay lại thì được đọc lại', () {
      final s = SceneAnnouncer();
      final a = [assessment(AlertLevel.safe, label: 'chair')];
      s.onFrame(a, t0);
      expect(s.onFrame(a, t0.add(ms(400))), isNotNull);
      for (var i = 1; i <= 3; i++) {
        s.onFrame(const [], t0.add(Duration(seconds: i)));
      }
      s.onFrame(a, t0.add(const Duration(seconds: 12)));
      expect(s.onFrame(a, t0.add(const Duration(seconds: 13))), isNotNull);
    });

    test('Danger tin cậy cao phát ngay khung đầu, có cooldown, rồi nhắc lại', () {
      final s = SceneAnnouncer();
      final d = [assessment(AlertLevel.danger)];
      expect(s.onFrame(d, t0)!.type, SceneDecisionType.danger);
      expect(s.onFrame(d, t0.add(ms(1000))), isNull);
      expect(s.onFrame(d, t0.add(ms(3000)))!.type, SceneDecisionType.danger);
    });

    test('Danger tin cậy thấp cần 2 khung liên tiếp', () {
      final s = SceneAnnouncer();
      final d = [assessment(AlertLevel.danger, score: 0.42)];
      expect(s.onFrame(d, t0), isNull);
      expect(s.onFrame(d, t0.add(ms(400)))!.type, SceneDecisionType.danger);
    });
  });

  group('Câu thông báo', () {
    test('Câu cảnh báo khẩn cấp', () {
      expect(buildDangerMessage(assessment(AlertLevel.danger)),
          'Cẩn thận! Người rất gần, phía trước');
    });

    test('Câu mô tả cảnh: gom theo hướng, đếm số lượng, đánh dấu vật ở gần', () {
      final msg = buildSceneMessage(const [
        SceneItem(label: 'chair', nameVi: 'Ghế', direction: ObstacleDirection.ahead, count: 3, near: true),
        SceneItem(label: 'person', nameVi: 'Người', direction: ObstacleDirection.left, count: 1),
      ]);
      expect(msg, 'Phía trước: 3 ghế ở gần. Bên trái: người.');
    });

    test('Không có vật nào', () {
      expect(buildSceneMessage(const []), 'Chưa nhận ra vật thể nào phía trước');
    });
  });
}
