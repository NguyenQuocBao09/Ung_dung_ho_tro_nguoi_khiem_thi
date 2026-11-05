import '../constants/strings_vi.dart';

/// Ba chế độ hoạt động cốt lõi của ứng dụng Vision Assist (100% On-Device)
enum AppMode {
  reading,
  currency,
  obstacle,
}

extension AppModeExtension on AppMode {
  /// Tên tiếng Việt hiển thị trên thanh AppBar và đọc qua TalkBack
  String get title {
    switch (this) {
      case AppMode.reading:
        return StringsVi.modeReading;
      case AppMode.currency:
        return StringsVi.modeCurrency;
      case AppMode.obstacle:
        return StringsVi.modeObstacle;
    }
  }

  /// Chế độ tiếp theo khi xoay vòng
  AppMode get next {
    switch (this) {
      case AppMode.reading:
        return AppMode.currency;
      case AppMode.currency:
        return AppMode.obstacle;
      case AppMode.obstacle:
        return AppMode.reading;
    }
  }

  /// Mô tả hành động Semantics để chuyển sang chế độ này
  String get switchActionLabel {
    switch (this) {
      case AppMode.reading:
        return StringsVi.actionSwitchToReading;
      case AppMode.currency:
        return StringsVi.actionSwitchToCurrency;
      case AppMode.obstacle:
        return StringsVi.actionSwitchToObstacle;
    }
  }
}
