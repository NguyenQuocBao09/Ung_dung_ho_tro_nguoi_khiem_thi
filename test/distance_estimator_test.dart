import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/features/obstacle/domain/distance_estimator.dart';
import 'package:vision_assist/features/obstacle/domain/obstacle_detection.dart';

ObstacleDetection det(String label, double l, double t, double r, double b, [double s = 0.8]) =>
    ObstacleDetection(classIndex: 0, label: label, score: s, left: l, top: t, right: r, bottom: b);

void main() {
  const est = DistanceEstimator();

  test('Vật càng lớn trên ảnh thì càng gần', () {
    final far = est.estimate(det('person', 0.45, 0.4, 0.55, 0.6))!;
    final near = est.estimate(det('person', 0.3, 0.1, 0.7, 0.9))!;
    expect(near.meters, lessThan(far.meters));
  });

  test('Người cao ~1,65 m chiếm 50% chiều cao ảnh -> khoảng 2–3 m (xấp xỉ)', () {
    final e = est.estimate(det('person', 0.45, 0.25, 0.55, 0.75))!;
    expect(e.meters, inInclusiveRange(2.0, 3.0));
  });

  test('Lấy ước lượng nhỏ hơn giữa chiều cao và chiều rộng (thận trọng)', () {
    // Bàn rộng chiếm gần hết bề ngang nhưng thấp trên ảnh -> theo chiều rộng sẽ gần hơn
    final e = est.estimate(det('dining table', 0.05, 0.6, 0.95, 0.8))!;
    final byHeight = est.estimateFromBox(
      heightFrac: 0.2, widthFrac: 1.0, top: 0.6, bottom: 0.8, realHeightM: 0.75, realWidthM: 1000,
    )!;
    expect(e.meters, lessThan(byHeight.meters));
    // Kích thước thật không hợp lệ -> null
    expect(
      est.estimateFromBox(
        heightFrac: 0.2, widthFrac: 0.5, top: 0.6, bottom: 0.8, realHeightM: 0.75, realWidthM: 0,
      ),
      isNull,
    );
  });

  test('Chạm cả mép trên và dưới -> đánh dấu truncated', () {
    expect(est.estimate(det('person', 0.2, 0.0, 0.8, 1.0))!.truncated, isTrue);
    expect(est.estimate(det('person', 0.2, 0.2, 0.8, 0.8))!.truncated, isFalse);
  });

  test('Nhãn không có trong bảng hoặc bbox không hợp lệ -> null', () {
    expect(est.estimate(det('unknown_label', 0.4, 0.4, 0.6, 0.6)), isNull);
    expect(est.estimate(det('cell phone', 0.4, 0.4, 0.6, 0.6)), isNotNull);
    expect(est.estimate(det('person', 0.5, 0.5, 0.5, 0.9)), isNull); // rộng = 0
    expect(est.estimate(det('person', 0.5, 0.9, 0.6, 0.5)), isNull); // cao âm
    expect(
      est.estimateFromBox(
        heightFrac: double.nan, widthFrac: 0.2, top: 0, bottom: 1, realHeightM: 1, realWidthM: 1,
      ),
      isNull,
    );
  });
}
