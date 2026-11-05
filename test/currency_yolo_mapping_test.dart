import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/features/currency/data/currency_detector.dart';
import 'package:vision_assist/features/currency/domain/denomination.dart';
import 'package:vision_assist/features/currency/presentation/currency_controller.dart';
import 'package:vision_assist/features/obstacle/domain/obstacle_detection.dart';

ObstacleDetection det(String label, double score) => ObstacleDetection(
      classIndex: 0,
      label: label,
      score: score,
      left: 0.1,
      top: 0.2,
      right: 0.7,
      bottom: 0.5,
    );

CurrencyDetectionFrame frame(List<ObstacleDetection> d) => CurrencyDetectionFrame(
      detections: d,
      imageWidth: 480,
      imageHeight: 720,
      luminance: 100,
      totalMs: 250,
    );

void main() {
  const spoken = {'50k': 'năm mươi nghìn đồng', '100k': 'một trăm nghìn đồng'};

  test('Không có khung -> none, không tin cậy, không có khung bao', () {
    final r = yoloFrameToResult(frame(const []), spoken, 0.6);
    expect(r.label, 'none');
    expect(r.isMoney, isFalse);
    expect(r.isReliable, isFalse);
    expect(r.box, isNull);
    expect(r.imageWidth, 480);
  });

  test('Lấy khung điểm cao nhất (đầu danh sách), gắn mệnh giá và câu đọc', () {
    final r = yoloFrameToResult(frame([det('50k', 0.82), det('100k', 0.4)]), spoken, 0.6);
    expect(r.label, '50k');
    expect(r.denomination, Denomination.d50k);
    expect(r.spokenVi, 'năm mươi nghìn đồng');
    expect(r.isReliable, isTrue);
    expect(r.box!.left, closeTo(0.1, 1e-9));
    expect(r.box!.bottom, closeTo(0.5, 1e-9));
  });

  test('Điểm dưới ngưỡng bỏ phiếu -> vẫn có khung nhưng không được tính phiếu', () {
    final r = yoloFrameToResult(frame([det('100k', 0.45)]), spoken, 0.6);
    expect(r.isMoney, isTrue);
    expect(r.box, isNotNull);
    expect(r.isReliable, isFalse);
  });
}
