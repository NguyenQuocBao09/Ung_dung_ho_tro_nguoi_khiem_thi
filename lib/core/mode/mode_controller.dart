import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_mode.dart';

/// Quản lý trạng thái chuyển đổi giữa các chế độ hoạt động
class ModeController extends StateNotifier<AppMode> {
  ModeController([super.initialMode = AppMode.reading]);

  void setMode(AppMode newMode) {
    if (state != newMode) {
      state = newMode;
    }
  }

  void nextMode() {
    state = state.next;
  }
}

final appModeProvider = StateNotifierProvider<ModeController, AppMode>((ref) {
  return ModeController();
});
