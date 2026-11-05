import 'dart:math' as math;

import 'obstacle_classes.dart';
import 'obstacle_detection.dart';

/// Kết quả ước lượng khoảng cách (XẤP XỈ).
class DistanceEstimate {
  final double meters;

  /// Bounding box chạm mép trên/dưới khung hình: vật có thể lớn hơn phần nhìn thấy,
  /// nên khoảng cách thật có thể còn GẦN hơn giá trị ước lượng.
  final bool truncated;

  const DistanceEstimate(this.meters, {this.truncated = false});
}

/// Ước lượng khoảng cách bằng mô hình camera lỗ kim:
///   khoảng_cách ≈ kích_thước_thật × tiêu_cự / kích_thước_trên_ảnh
///
/// Đây CHỈ là phép xấp xỉ: phụ thuộc kích thước điển hình của lớp vật thể
/// (xem [ObstacleClasses]), góc nhìn camera (FOV giả định, chưa hiệu chuẩn trên
/// Samsung S25 FE), tư thế cầm máy và việc vật bị che khuất. Không dùng như phép đo.
class DistanceEstimator {
  /// Góc nhìn dọc của ảnh ĐỨNG (cạnh dài cảm biến 4:3). Giá trị điển hình cho camera
  /// chính tương đương ~26 mm; cần hiệu chuẩn trên thiết bị thật.
  final double verticalFovDeg;

  /// Góc nhìn ngang của ảnh đứng (cạnh ngắn).
  final double horizontalFovDeg;

  /// Ngưỡng coi là chạm mép khung hình.
  final double edgeMargin;

  const DistanceEstimator({
    this.verticalFovDeg = 67.0,
    this.horizontalFovDeg = 53.0,
    this.edgeMargin = 0.02,
  });

  double get _focalY => 0.5 / math.tan(verticalFovDeg * math.pi / 360);
  double get _focalX => 0.5 / math.tan(horizontalFovDeg * math.pi / 360);

  /// Trả về null nếu lớp không được hỗ trợ hoặc bounding box không hợp lệ.
  DistanceEstimate? estimate(ObstacleDetection d) {
    final info = ObstacleClasses.of(d.label);
    if (info == null) return null;
    return estimateFromBox(
      heightFrac: d.height,
      widthFrac: d.width,
      top: d.top,
      bottom: d.bottom,
      realHeightM: info.typicalHeightM,
      realWidthM: info.typicalWidthM,
    );
  }

  DistanceEstimate? estimateFromBox({
    required double heightFrac,
    required double widthFrac,
    required double top,
    required double bottom,
    required double realHeightM,
    required double realWidthM,
  }) {
    if (!heightFrac.isFinite || !widthFrac.isFinite) return null;
    if (heightFrac <= 0 || widthFrac <= 0) return null;
    if (realHeightM <= 0 || realWidthM <= 0) return null;

    final h = heightFrac.clamp(1e-3, 1.0);
    final w = widthFrac.clamp(1e-3, 1.0);
    final byHeight = realHeightM * _focalY / h;
    final byWidth = realWidthM * _focalX / w;

    // Lấy giá trị nhỏ hơn: thận trọng (ưu tiên báo gần hơn là xa hơn).
    final meters = math.min(byHeight, byWidth);
    final truncated = top <= edgeMargin && bottom >= 1 - edgeMargin;
    return DistanceEstimate(meters, truncated: truncated);
  }
}
