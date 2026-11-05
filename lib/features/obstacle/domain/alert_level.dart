import 'obstacle_classes.dart';
import 'obstacle_detection.dart';

/// Mức cảnh báo cho một vật thể, xác định theo KÍCH THƯỚC trên ảnh (không ước lượng mét):
/// - `danger`: vật lớn chiếm gần hết khung hình và nằm trên đường đi (rất gần).
/// - `warning`: vật lớn chiếm phần đáng kể khung hình trên đường đi (gần).
/// - `safe`: các trường hợp còn lại — chỉ đọc tên. KHÔNG có nghĩa là an toàn.
enum AlertLevel { safe, warning, danger }

enum ObstacleDirection { left, ahead, right }

/// Một vật thể trong khung hình kèm tên tiếng Việt, hướng và mức cảnh báo.
class ObstacleAssessment {
  final ObstacleDetection detection;
  final String nameVi;
  final ObstacleDirection direction;
  final AlertLevel level;

  const ObstacleAssessment({
    required this.detection,
    required this.nameVi,
    required this.direction,
    required this.level,
  });

  /// Khoá nhận dạng "cùng loại vật ở cùng hướng" giữa các khung hình.
  String get key => '${detection.label}|${direction.name}';
}

class ObstacleAssessor {
  /// Vật có tâm nằm trong [aheadMin, aheadMax] (theo chiều ngang) là "phía trước".
  final double aheadMin;
  final double aheadMax;

  /// Ngưỡng kích thước (tỉ lệ chiều cao bbox / chiều cao ảnh). Do nhóm tự đặt, chưa đo kiểm.
  final double dangerHeight;
  final double warningHeight;

  /// Ngưỡng chạm mép khung hình.
  final double edgeMargin;

  /// Độ tin cậy tối thiểu để đưa một vật vào mô tả.
  final double minScore;

  /// Các lớp COCO hiếm khi gặp trong nhà/đường phố Việt Nam: model hay gán nhầm vật lạ
  /// (vd. quạt trần -> "airplane") với độ tin cậy thấp, nên yêu cầu độ tin cậy cao hơn.
  final double unlikelyMinScore;
  static const Set<String> unlikelyLabels = {
    'airplane', 'train', 'boat', 'elephant', 'bear', 'zebra', 'giraffe', 'horse',
    'sheep', 'cow', 'kite', 'skis', 'snowboard', 'surfboard', 'frisbee',
    'baseball bat', 'baseball glove', 'skateboard', 'tennis racket', 'parking meter',
    'fire hydrant', 'stop sign', 'hot dog', 'pizza', 'donut', 'broccoli',
  };

  const ObstacleAssessor({
    this.aheadMin = 0.33,
    this.aheadMax = 0.67,
    this.dangerHeight = 0.8,
    this.warningHeight = 0.55,
    this.edgeMargin = 0.02,
    this.minScore = 0.45,
    this.unlikelyMinScore = 0.7,
  });

  double minScoreFor(String label) =>
      unlikelyLabels.contains(label) ? unlikelyMinScore : minScore;

  ObstacleDirection directionOf(ObstacleDetection d) {
    if (d.centerX < aheadMin) return ObstacleDirection.left;
    if (d.centerX > aheadMax) return ObstacleDirection.right;
    return ObstacleDirection.ahead;
  }

  /// Bounding box có lấn vào vùng phía trước (đường đi) hay không.
  bool overlapsPath(ObstacleDetection d) => d.right > aheadMin && d.left < aheadMax;

  AlertLevel levelFor(ObstacleDetection d, {bool canObstruct = true}) {
    // Vật nhỏ (cốc, điện thoại...) và vật không chắn đường đi: chỉ đọc tên.
    if (!canObstruct || !overlapsPath(d)) return AlertLevel.safe;
    final spansFrame = d.top <= edgeMargin && d.bottom >= 1 - edgeMargin;
    if (spansFrame || d.height >= dangerHeight) return AlertLevel.danger;
    if (d.height >= warningHeight) return AlertLevel.warning;
    return AlertLevel.safe;
  }

  /// Mọi vật thể nhận diện được, sắp xếp: mức cảnh báo cao trước, rồi vật lớn (gần) trước.
  List<ObstacleAssessment> assessAll(List<ObstacleDetection> detections) {
    final out = <ObstacleAssessment>[];
    for (final d in detections) {
      final info = ObstacleClasses.of(d.label);
      if (info == null) continue;
      if (d.width <= 0 || d.height <= 0) continue;
      if (d.score < minScoreFor(d.label)) continue;
      out.add(ObstacleAssessment(
        detection: d,
        nameVi: info.nameVi,
        direction: directionOf(d),
        level: levelFor(d, canObstruct: info.canObstruct),
      ));
    }
    out.sort((a, b) {
      final byLevel = b.level.index.compareTo(a.level.index);
      if (byLevel != 0) return byLevel;
      return b.detection.area.compareTo(a.detection.area);
    });
    return out;
  }

  ObstacleAssessment? assess(List<ObstacleDetection> detections) {
    final all = assessAll(detections);
    return all.isEmpty ? null : all.first;
  }
}

/// Một mục trong câu mô tả cảnh: loại vật, hướng, số lượng.
class SceneItem {
  final String label;
  final String nameVi;
  final ObstacleDirection direction;
  final int count;
  final bool near;

  const SceneItem({
    required this.label,
    required this.nameVi,
    required this.direction,
    required this.count,
    this.near = false,
  });

  String get key => '$label|${direction.name}';
}

enum SceneDecisionType { danger, scene }

class SceneDecision {
  final SceneDecisionType type;

  /// Với `danger`: vật rất gần cần cảnh báo ngay.
  final ObstacleAssessment? danger;

  /// Với `scene`: toàn bộ vật thể đã xác nhận đang có trước camera.
  final List<SceneItem> items;

  const SceneDecision.danger(ObstacleAssessment a)
      : type = SceneDecisionType.danger,
        danger = a,
        items = const [];

  const SceneDecision.scene(this.items)
      : type = SceneDecisionType.scene,
        danger = null;
}

/// Gom các vật thể qua nhiều khung hình thành "cảnh" và quyết định khi nào đọc:
/// - Cảnh báo `danger` được ưu tiên, phát NGAY nếu độ tin cậy cao (không trì hoãn vì làm mượt),
///   nhắc lại sau [dangerRepeat].
/// - Một vật (loại + hướng) được XÁC NHẬN khi xuất hiện ở ≥ [confirmFrames] trong
///   [windowFrames] khung gần nhất (chống nhận nhầm thoáng qua). Số lượng = số nhiều nhất
///   thấy được trong các khung đó.
/// - Đọc câu mô tả toàn cảnh khi có vật MỚI được xác nhận (chưa đọc, hoặc đã khuất quá
///   [forgetAfter]), cách lần đọc trước ít nhất [minInterval].
/// - Không giới hạn khoảng cách: vật ở xa trong phòng vẫn được đọc nếu model nhận ra.
class SceneAnnouncer {
  final int windowFrames;
  final int confirmFrames;
  final Duration minInterval;
  final Duration forgetAfter;
  final Duration dangerRepeat;
  final double dangerInstantScore;

  SceneAnnouncer({
    this.windowFrames = 3,
    this.confirmFrames = 2,
    this.minInterval = const Duration(seconds: 4),
    this.forgetAfter = const Duration(seconds: 10),
    this.dangerRepeat = const Duration(milliseconds: 2500),
    this.dangerInstantScore = 0.5,
  });

  final List<Map<String, ObstacleAssessmentGroup>> _history = [];
  final Map<String, DateTime> _announcedLastSeen = {};
  DateTime? _lastSceneAt;
  int _dangerStreak = 0;
  DateTime? _lastDangerAt;
  String? _lastDangerLabel;

  void reset() {
    _history.clear();
    _announcedLastSeen.clear();
    _lastSceneAt = null;
    _dangerStreak = 0;
    _lastDangerAt = null;
    _lastDangerLabel = null;
  }

  /// Các vật thể đã xác nhận trong cửa sổ hiện tại (để hiển thị hoặc "đọc lại").
  List<SceneItem> get confirmedItems {
    final presence = <String, int>{};
    final maxCount = <String, int>{};
    final sample = <String, ObstacleAssessmentGroup>{};
    var nearKeys = <String>{};
    for (final frame in _history) {
      for (final e in frame.entries) {
        presence[e.key] = (presence[e.key] ?? 0) + 1;
        if (e.value.count > (maxCount[e.key] ?? 0)) maxCount[e.key] = e.value.count;
        sample[e.key] = e.value;
        if (e.value.near) nearKeys = {...nearKeys, e.key};
      }
    }
    final items = <SceneItem>[];
    for (final e in presence.entries) {
      if (e.value < confirmFrames) continue;
      final g = sample[e.key]!;
      items.add(SceneItem(
        label: g.label,
        nameVi: g.nameVi,
        direction: g.direction,
        count: maxCount[e.key]!,
        near: nearKeys.contains(e.key),
      ));
    }
    // Thứ tự đọc: phía trước, bên trái, bên phải; trong mỗi hướng vật gần trước.
    items.sort((a, b) {
      int dirRank(ObstacleDirection d) => d == ObstacleDirection.ahead
          ? 0
          : (d == ObstacleDirection.left ? 1 : 2);
      final byDir = dirRank(a.direction).compareTo(dirRank(b.direction));
      if (byDir != 0) return byDir;
      if (a.near != b.near) return a.near ? -1 : 1;
      return a.nameVi.compareTo(b.nameVi);
    });
    return items;
  }

  SceneDecision? onFrame(List<ObstacleAssessment> assessments, DateTime now) {
    // 1. Ghi nhận khung hình vào cửa sổ trượt (gom theo loại + hướng, đếm số lượng).
    final frame = <String, ObstacleAssessmentGroup>{};
    for (final a in assessments) {
      final g = frame[a.key];
      if (g == null) {
        frame[a.key] = ObstacleAssessmentGroup(
          label: a.detection.label,
          nameVi: a.nameVi,
          direction: a.direction,
          count: 1,
          near: a.level != AlertLevel.safe,
        );
      } else {
        frame[a.key] = g.copyWith(count: g.count + 1, near: g.near || a.level != AlertLevel.safe);
      }
    }
    _history.add(frame);
    while (_history.length > windowFrames) {
      _history.removeAt(0);
    }

    // 2. Cảnh báo khẩn cấp
    final top = assessments.isEmpty ? null : assessments.first;
    if (top != null && top.level == AlertLevel.danger) {
      _dangerStreak++;
      final confident = top.detection.score >= dangerInstantScore || _dangerStreak >= 2;
      if (confident) {
        final label = top.detection.label;
        final due = _lastDangerAt == null ||
            label != _lastDangerLabel ||
            now.difference(_lastDangerAt!) >= dangerRepeat;
        if (due) {
          _lastDangerAt = now;
          _lastDangerLabel = label;
          return SceneDecision.danger(top);
        }
        return null; // Đang chờ nhắc lại cảnh báo: không chen câu mô tả cảnh.
      }
    } else {
      _dangerStreak = 0;
    }

    // 3. Mô tả cảnh khi có vật mới
    final items = confirmedItems;
    for (final it in items) {
      // Cập nhật thời điểm còn thấy với các vật đã đọc
      if (_announcedLastSeen.containsKey(it.key)) _announcedLastSeen[it.key] = now;
    }
    _announcedLastSeen.removeWhere((_, seen) => now.difference(seen) > forgetAfter);

    final hasNew = items.any((it) => !_announcedLastSeen.containsKey(it.key));
    if (!hasNew) return null;
    if (_lastSceneAt != null && now.difference(_lastSceneAt!) < minInterval) return null;

    _lastSceneAt = now;
    for (final it in items) {
      _announcedLastSeen[it.key] = now;
    }
    return SceneDecision.scene(items);
  }
}

/// Nhóm các vật cùng loại + hướng trong MỘT khung hình.
class ObstacleAssessmentGroup {
  final String label;
  final String nameVi;
  final ObstacleDirection direction;
  final int count;
  final bool near;

  const ObstacleAssessmentGroup({
    required this.label,
    required this.nameVi,
    required this.direction,
    required this.count,
    required this.near,
  });

  ObstacleAssessmentGroup copyWith({int? count, bool? near}) => ObstacleAssessmentGroup(
        label: label,
        nameVi: nameVi,
        direction: direction,
        count: count ?? this.count,
        near: near ?? this.near,
      );
}
