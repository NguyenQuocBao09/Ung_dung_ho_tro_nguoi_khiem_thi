import 'dart:math' as math;
import 'dart:typed_data';

import '../../../core/camera/frame_converter.dart';
import 'obstacle_detection.dart';

/// Giải mã đầu ra YOLOv8 (Ultralytics, export TFLite) dạng [1, 4 + numClasses, numAnchors].
///
/// - 4 hàng đầu: cx, cy, w, h. Ultralytics TFLite xuất toạ độ **chuẩn hoá 0..1 theo kích
///   thước đầu vào model** (đã kiểm chứng bằng Python trên model của dự án); nếu
///   [coordsNormalized] = false thì coi là pixel trong không gian model.
/// - Các hàng còn lại: điểm lớp (đã sigmoid), KHÔNG có objectness riêng.
class YoloDecoder {
  final int numClasses;
  final int numAnchors;
  final double scoreThreshold;
  final double iouThreshold;
  final int maxDetections;
  final bool coordsNormalized;

  /// Chỉ giữ các lớp có chỉ số trong tập này (null = giữ tất cả).
  final Set<int>? allowedClasses;

  const YoloDecoder({
    required this.numClasses,
    required this.numAnchors,
    this.scoreThreshold = 0.4,
    this.iouThreshold = 0.5,
    this.maxDetections = 20,
    this.coordsNormalized = true,
    this.allowedClasses,
  });

  /// [output] là mảng phẳng theo thứ tự [channel][anchor] (độ dài (4+numClasses)*numAnchors).
  /// [labels] dùng để gắn tên nhãn. [lb] dùng để bỏ letterbox, đưa toạ độ về ảnh đứng 0..1.
  List<ObstacleDetection> decode(
    Float32List output,
    List<String> labels,
    LetterboxInfo lb,
  ) {
    final channels = 4 + numClasses;
    if (output.length != channels * numAnchors) {
      throw ArgumentError(
        'Kích thước đầu ra ${output.length} khác ${channels * numAnchors}',
      );
    }
    final coordScale = coordsNormalized ? lb.dstSize.toDouble() : 1.0;
    final candidates = <ObstacleDetection>[];

    for (var a = 0; a < numAnchors; a++) {
      // Chọn nhãn cao nhất trên TOÀN BỘ lớp trước, rồi mới lọc theo allowedClasses.
      // Nếu lọc trước khi chọn, vật như laptop (không phải vật cản) sẽ bị gán nhầm
      // sang lớp vật cản có điểm cao thứ hai (vd. "tv").
      var best = -1;
      var bestScore = scoreThreshold;
      for (var c = 0; c < numClasses; c++) {
        final s = output[(4 + c) * numAnchors + a];
        if (s > bestScore) {
          bestScore = s;
          best = c;
        }
      }
      if (best < 0) continue;
      if (allowedClasses != null && !allowedClasses!.contains(best)) continue;

      // Toạ độ trong không gian model (pixel)
      final cx = output[a] * coordScale;
      final cy = output[numAnchors + a] * coordScale;
      final bw = output[2 * numAnchors + a] * coordScale;
      final bh = output[3 * numAnchors + a] * coordScale;

      // Bỏ letterbox -> pixel ảnh đứng -> chuẩn hoá 0..1
      double toX(double v) =>
          (((v - lb.padX) / lb.scale) / lb.srcWidth).clamp(0.0, 1.0);
      double toY(double v) =>
          (((v - lb.padY) / lb.scale) / lb.srcHeight).clamp(0.0, 1.0);

      final l = toX(cx - bw / 2);
      final r = toX(cx + bw / 2);
      final t = toY(cy - bh / 2);
      final b = toY(cy + bh / 2);
      if (r - l <= 0 || b - t <= 0) continue;

      candidates.add(ObstacleDetection(
        classIndex: best,
        label: best < labels.length ? labels[best] : 'class_$best',
        score: bestScore,
        left: l,
        top: t,
        right: r,
        bottom: b,
      ));
    }
    return nonMaxSuppression(candidates, iouThreshold, maxDetections);
  }

  /// NMS theo từng lớp (class-aware), sắp xếp giảm dần theo điểm.
  static List<ObstacleDetection> nonMaxSuppression(
    List<ObstacleDetection> dets,
    double iouThreshold,
    int maxDetections,
  ) {
    final sorted = [...dets]..sort((a, b) => b.score.compareTo(a.score));
    final kept = <ObstacleDetection>[];
    for (final d in sorted) {
      var suppressed = false;
      for (final k in kept) {
        if (k.classIndex == d.classIndex && iou(k, d) > iouThreshold) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) {
        kept.add(d);
        if (kept.length >= maxDetections) break;
      }
    }
    return kept;
  }

  static double iou(ObstacleDetection a, ObstacleDetection b) {
    final ix = math.max(0.0, math.min(a.right, b.right) - math.max(a.left, b.left));
    final iy = math.max(0.0, math.min(a.bottom, b.bottom) - math.max(a.top, b.top));
    final inter = ix * iy;
    final union = a.area + b.area - inter;
    return union <= 0 ? 0 : inter / union;
  }
}
