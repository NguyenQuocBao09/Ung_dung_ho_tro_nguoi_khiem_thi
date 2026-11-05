/// Một vật thể phát hiện được, toạ độ chuẩn hoá 0..1 trong ảnh camera đã xoay về chiều đứng.
class ObstacleDetection {
  final int classIndex;
  final String label;
  final double score;

  final double left;
  final double top;
  final double right;
  final double bottom;

  const ObstacleDetection({
    required this.classIndex,
    required this.label,
    required this.score,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get area => width * height;

  @override
  String toString() =>
      'ObstacleDetection($label ${(score * 100).toStringAsFixed(0)}%, '
      'l=${left.toStringAsFixed(2)} t=${top.toStringAsFixed(2)} '
      'r=${right.toStringAsFixed(2)} b=${bottom.toStringAsFixed(2)})';
}
