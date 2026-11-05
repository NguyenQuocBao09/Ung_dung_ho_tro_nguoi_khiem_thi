import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dịch vụ phản hồi xúc giác (Haptic Feedback) cho người khiếm thị
class HapticService {
  const HapticService();

  /// Phản hồi khi nhận diện thành công mệnh giá tiền
  Future<void> success() async {
    await HapticFeedback.mediumImpact();
  }

  /// Phản hồi khi thao tác xác nhận hoặc chọn
  Future<void> selection() async {
    await HapticFeedback.selectionClick();
  }

  /// Phản hồi khi cảnh báo hoặc chưa nhận diện rõ
  Future<void> warning() async {
    await HapticFeedback.heavyImpact();
  }

  /// Rung nhẹ khi bắt đầu chụp/xử lý
  Future<void> light() async {
    await HapticFeedback.lightImpact();
  }

  /// Rung báo lỗi
  Future<void> error() async {
    await HapticFeedback.vibrate();
  }

  /// Rung dồn dập khi vật cản rất gần (3 nhịp mạnh)
  Future<void> danger() async {
    for (var i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
  }
}

final hapticServiceProvider = Provider<HapticService>((ref) {
  return const HapticService();
});
