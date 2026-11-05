import 'denomination.dart';

/// Kết quả nhận diện tiền tệ từ CurrencyClassifier
class CurrencyRecognitionResult {
  final String label;
  final Denomination denomination;
  final double confidence;
  final String spokenVi;
  final int inferenceTimeMs;
  final Map<String, double> probabilities;

  const CurrencyRecognitionResult({
    required this.label,
    required this.denomination,
    required this.confidence,
    required this.spokenVi,
    this.inferenceTimeMs = 0,
    this.probabilities = const {},
  });

  bool get isConfident => confidence >= 0.85;
  bool get isMoney => denomination.isMoney;

  @override
  String toString() =>
      'CurrencyRecognitionResult($label, ${(confidence * 100).toStringAsFixed(1)}%, spoken: "$spokenVi")';
}

/// Thuật toán bỏ phiếu 3/5 khung hình (Vote Aggregator):
/// - Lưu trữ kết quả của tối đa 5 khung hình gần nhất.
/// - Chỉ xác nhận khi có ít nhất 3 kết quả đồng thuận cùng một nhãn và đạt điều kiện độ tin cậy.
/// - Không yêu cầu toàn bộ 5 khung hình phải giống nhau.
/// - Hỗ trợ reset trạng thái khi đổi chế độ hoặc khi kết quả không còn phù hợp.
class VoteAggregator {
  final int windowSize;
  final int requiredConsensus;
  final double confidenceThreshold;

  final List<CurrencyRecognitionResult> _history = [];

  VoteAggregator({
    this.windowSize = 5,
    this.requiredConsensus = 3,
    this.confidenceThreshold = 0.85,
  }) : assert(requiredConsensus <= windowSize,
            'requiredConsensus must be <= windowSize');

  /// Danh sách lịch sử các dự đoán trong cửa sổ trượt (tối đa [windowSize])
  List<CurrencyRecognitionResult> get history => List.unmodifiable(_history);

  /// Thêm một kết quả dự đoán mới vào cửa sổ trượt.
  /// Nếu có ít nhất [requiredConsensus] khung hình đồng thuận cùng một nhãn
  /// và đạt ngưỡng tin cậy [confidenceThreshold], trả về kết quả được xác nhận.
  /// Ngược lại, trả về null (chưa đủ điều kiện xác nhận).
  CurrencyRecognitionResult? addPrediction(CurrencyRecognitionResult prediction) {
    _history.add(prediction);
    if (_history.length > windowSize) {
      _history.removeAt(0);
    }

    // Đếm số phiếu của từng nhãn đạt ngưỡng tin cậy
    final votesByLabel = <String, int>{};
    final latestByLabel = <String, CurrencyRecognitionResult>{};

    for (final item in _history) {
      if (item.confidence >= confidenceThreshold) {
        votesByLabel[item.label] = (votesByLabel[item.label] ?? 0) + 1;
        latestByLabel[item.label] = item;
      }
    }

    for (final entry in votesByLabel.entries) {
      if (entry.value >= requiredConsensus) {
        return latestByLabel[entry.key];
      }
    }

    return null;
  }

  /// Đặt lại trạng thái bỏ phiếu (xóa toàn bộ lịch sử)
  void reset() {
    _history.clear();
  }
}
