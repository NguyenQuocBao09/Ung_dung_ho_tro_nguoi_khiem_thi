import 'dart:ui' as ui;

import 'package:flutter/semantics.dart';

/// Theo dõi thao tác của trình đọc màn hình (TalkBack/VoiceOver) trên app.
///
/// Chỉ phản ứng với việc *chuyển tiêu điểm* và *cuộn* — đó là lúc TalkBack tự đọc
/// nhãn phần tử. Không phản ứng với chạm hai lần (kích hoạt nút), vì khi đó chính
/// nút đó thường phát lời phản hồi của app (vd. nghe lại, đọc hướng dẫn).
class TalkBackInteractionWatcher {
  /// Người dùng đang duyệt (TalkBack sắp đọc nhãn) -> app nên tạm im.
  final void Function() onInteraction;

  /// Người dùng kích hoạt nút (chạm hai lần / hành động tuỳ chỉnh) -> bỏ tạm im.
  /// Gọi TRƯỚC khi nút xử lý, nên lời phản hồi của nút được phát ngay.
  final void Function()? onActivate;
  bool _attached = false;

  TalkBackInteractionWatcher({required this.onInteraction, this.onActivate});

  static const Set<ui.SemanticsAction> triggers = {
    ui.SemanticsAction.didGainAccessibilityFocus,
    ui.SemanticsAction.scrollUp,
    ui.SemanticsAction.scrollDown,
    ui.SemanticsAction.scrollLeft,
    ui.SemanticsAction.scrollRight,
  };

  static const Set<ui.SemanticsAction> activations = {
    ui.SemanticsAction.tap,
    ui.SemanticsAction.longPress,
    ui.SemanticsAction.customAction,
  };

  static bool isTrigger(ui.SemanticsAction action) => triggers.contains(action);
  static bool isActivation(ui.SemanticsAction action) => activations.contains(action);

  void _listener(ui.SemanticsActionEvent event) {
    if (isTrigger(event.type)) {
      onInteraction();
    } else if (isActivation(event.type)) {
      onActivate?.call();
    }
  }

  void attach() {
    if (_attached) return;
    SemanticsBinding.instance.addSemanticsActionListener(_listener);
    _attached = true;
  }

  void detach() {
    if (!_attached) return;
    SemanticsBinding.instance.removeSemanticsActionListener(_listener);
    _attached = false;
  }
}
