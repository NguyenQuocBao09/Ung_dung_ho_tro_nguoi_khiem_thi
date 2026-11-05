/// Phiên quản lý nhận diện tiền liên tục (CurrencySession) - Dart thuần, không phụ thuộc Flutter
class CurrencySession {
  final int windowSize;
  final int requiredConsensus;
  final double confidenceThreshold;
  final int noneStreakThreshold;

  final List<String> _voteWindow = [];
  int _noneStreak = 0;
  String? _currentActiveDenomination;
  String? _lastAnnounced;

  CurrencySession({
    this.windowSize = 5,
    this.requiredConsensus = 3,
    this.confidenceThreshold = 0.85,
    this.noneStreakThreshold = 4,
  }) : assert(requiredConsensus <= windowSize,
            'requiredConsensus must be <= windowSize');

  /// Cửa sổ phiếu bầu hiện tại
  List<String> get voteWindow => List.unmodifiable(_voteWindow);

  /// Số khung 'none' liên tiếp hiện tại
  int get noneStreak => _noneStreak;

  /// Mệnh giá đang được giữ trong khung hình (chưa rời đi)
  String? get currentActiveDenomination => _currentActiveDenomination;

  /// Mệnh giá đọc gần nhất (dùng cho hành động 'Đọc lại')
  String? get lastAnnounced => _lastAnnounced;

  /// Xử lý kết quả dự đoán của từng khung hình.
  /// Trả về chuỗi mệnh giá nếu đủ điều kiện phát âm thanh đọc, ngược lại trả về null.
  String? onFrame(String label, double conf) {
    final normLabel = label.trim().toLowerCase();

    // 1. Khung có nhãn "none":
    // Làm trống cửa sổ phiếu và tăng bộ đếm; sau 4 khung "none" liên tiếp thì cho phép đọc tờ mới.
    if (normLabel == 'none') {
      _voteWindow.clear();
      _noneStreak++;
      if (_noneStreak >= noneStreakThreshold) {
        _currentActiveDenomination = null;
      }
      return null;
    }

    // Gặp khung có tiền -> đặt lại đếm chuỗi "none"
    _noneStreak = 0;

    // 2. Kiểm tra độ tin cậy của khung hình:
    // Mỗi phiếu cần đạt ngưỡng tin cậy >= confidenceThreshold (mặc định 0.85)
    if (conf < confidenceThreshold) {
      return null;
    }

    // 3. Thêm phiếu vào cửa sổ trượt (tối đa windowSize khung gần nhất)
    _voteWindow.add(normLabel);
    if (_voteWindow.length > windowSize) {
      _voteWindow.removeAt(0);
    }

    // 4. Kiểm tra điều kiện đồng thuận bỏ phiếu (>= requiredConsensus phiếu)
    final voteCounts = <String, int>{};
    for (final vote in _voteWindow) {
      voteCounts[vote] = (voteCounts[vote] ?? 0) + 1;
    }

    for (final entry in voteCounts.entries) {
      if (entry.value >= requiredConsensus) {
        final candidate = entry.key;

        // Không đọc lại cùng một mệnh giá khi tờ tiền vẫn ở trong khung
        if (candidate == _currentActiveDenomination) {
          return null;
        }

        // Đổi sang mệnh giá khác (hoặc đọc tờ tiền mới) ngay khi đủ phiếu
        _currentActiveDenomination = candidate;
        _lastAnnounced = candidate;
        return candidate;
      }
    }

    return null;
  }

  /// Cho phép đọc tờ mới ngay lập tức (dùng cho hành động 'Tờ khác')
  void resetActiveBill() {
    _currentActiveDenomination = null;
    _voteWindow.clear();
  }

  /// Đặt lại toàn bộ trạng thái phiên
  void reset() {
    _voteWindow.clear();
    _noneStreak = 0;
    _currentActiveDenomination = null;
    _lastAnnounced = null;
  }
}

