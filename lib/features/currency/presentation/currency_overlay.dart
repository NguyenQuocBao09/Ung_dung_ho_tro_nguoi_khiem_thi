import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/camera/camera_service.dart';
import '../../../core/constants/strings_vi.dart';
import '../../../core/constants/ui_layout.dart';
import '../../../core/quality/lighting_monitor.dart';
import '../domain/denomination.dart';
import 'currency_controller.dart';

/// Lớp phủ giao diện và trợ năng cho chế độ Nhận diện tiền tự động liên tục
class CurrencyOverlay extends ConsumerWidget {
  const CurrencyOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(currencyControllerProvider);
    final cameraState = ref.watch(cameraStateProvider);

    final pauseResumeLabel = state.isPaused
        ? StringsVi.actionResumeCurrency
        : StringsVi.actionPauseCurrency;

    // Custom Semantics Actions cho người dùng TalkBack
    final customSemanticsActions = <CustomSemanticsAction, VoidCallback>{
      const CustomSemanticsAction(label: StringsVi.actionReadAgain): () {
        ref.read(currencyControllerProvider.notifier).readAgain();
      },
      const CustomSemanticsAction(label: StringsVi.actionNewBill): () {
        ref.read(currencyControllerProvider.notifier).newBill();
      },
      CustomSemanticsAction(label: pauseResumeLabel): () {
        ref.read(currencyControllerProvider.notifier).togglePause();
      },
    };

    final result = state.lastResult;
    final isMoney = result != null && result.isMoney;
    // Chỉ coi là chắc chắn khi mệnh giá đã được xác nhận qua bỏ phiếu 3/5 (đã đọc lên).
    final isConfirmed = isMoney && state.announcedDenomination == result.label;
    final headline = result == null
        ? ''
        : (!isMoney || isConfirmed)
            ? result.denomination.displayName
            : StringsVi.currencyProcessing;

    final badgeColor = isConfirmed
        ? const Color(0xFF00E676)
        : (result?.denomination == Denomination.none
            ? const Color(0xFFFF5252)
            : const Color(0xFFFFD600));

    return Semantics(
      container: true,
      customSemanticsActions: customSemanticsActions,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 0. KHUNG BAO QUANH TỜ TIỀN (vùng ước lượng, chỉ hiển thị trực quan)
          if (!state.isPaused &&
              state.box != null &&
              result != null &&
              result.imageWidth > 0 &&
              result.imageHeight > 0)
            ExcludeSemantics(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _NoteBoxPainter(
                    box: state.box!,
                    imageWidth: result.imageWidth,
                    imageHeight: result.imageHeight,
                    // Chỉ ghi mệnh giá khi đã xác nhận (đủ phiếu); trước đó chỉ báo đang nhận diện.
                    label: state.announcedDenomination == result.label
                        ? result.denomination.displayName
                        : StringsVi.currencyDetecting,
                    confirmed: state.announcedDenomination == result.label,
                  ),
                ),
              ),
            ),

          // 1. THẺ HIỂN THỊ KẾT QUẢ NHẬN DIỆN:
          // Bọc trong ExcludeSemantics để TalkBack không tự đọc đè lên giọng nói TTS
          if (result != null)
            Positioned(
              top: 20,
              left: 16,
              right: 16,
              child: ExcludeSemantics(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xDD121212),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: badgeColor, width: 2.0),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black87,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isMoney ? Icons.payments : Icons.warning_amber_rounded,
                              color: badgeColor,
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                headline,
                                style: TextStyle(
                                  color: badgeColor,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (state.isPaused) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade900,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Tạm dừng',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          children: [
                            Text(
                              '${StringsVi.currencyConfidence}: ${(result.confidence * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C3E50),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                result.winningCrop,
                                style: const TextStyle(
                                  color: Color(0xFF80D8FF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (result.inferenceTimeMs > 0)
                              Text(
                                '(${result.inferenceTimeMs} ms)',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 2. NÚT CHÍNH "TẠM DỪNG / TIẾP TỤC": giữa phía dưới, 72dp.
          Positioned(
            left: 0,
            right: 0,
            bottom: UiLayout.mainButtonBottom,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Semantics(
              button: true,
              label: pauseResumeLabel,
              child: SizedBox(
                width: UiLayout.mainButtonSize,
                height: UiLayout.mainButtonSize,
                child: FloatingActionButton(
                  key: const ValueKey('main_pause_button'),
                  shape: const CircleBorder(),
                  heroTag: 'currency_pause_resume_fab',
                  backgroundColor: state.isPaused
                      ? const Color(0xFFFFB74D) // Màu cam khi tạm dừng
                      : const Color(0xFF2C3E50), // Màu xanh xám khi nhận diện
                  foregroundColor: state.isPaused ? Colors.black : Colors.white,
                  onPressed: () {
                    ref.read(currencyControllerProvider.notifier).togglePause();
                  },
                  child: Icon(
                    state.isPaused ? Icons.play_arrow : Icons.pause,
                    size: 36,
                  ),
                ),
              ),
            ),
            ),
          ),

          // 3. NÚT BẬT / TẮT ĐÈN PIN (Góc trên phải khi ánh sáng yếu hoặc cần hỗ trợ)
          Positioned(
            top: 20,
            right: 16,
            child: Semantics(
              button: true,
              label: cameraState.isTorchOn
                  ? StringsVi.torchTurnedOn
                  : StringsVi.actionToggleTorch,
              child: SizedBox(
                width: 48,
                height: 48,
                child: FloatingActionButton.small(
                  heroTag: 'currency_torch_fab',
                  backgroundColor: cameraState.isTorchOn
                      ? const Color(0xFFFFD600)
                      : (ref.watch(lightingMonitorProvider).isLowLight
                          ? const Color(0xFFD32F2F)
                          : const Color(0xAA1E1E1E)),
                  foregroundColor: cameraState.isTorchOn ? Colors.black : Colors.white,
                  onPressed: () {
                    ref.read(cameraStateProvider.notifier).toggleTorch();
                  },
                  child: Icon(
                    cameraState.isTorchOn ? Icons.flash_on : Icons.flash_off,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vẽ khung bo góc quanh tờ tiền theo cách preview hiển thị (lấp đầy, cắt phần thừa = BoxFit.cover).
/// Xanh lá: mệnh giá đã được xác nhận (đủ 3/5 khung). Vàng: đang nhận diện.
class _NoteBoxPainter extends CustomPainter {
  final NormRect box;
  final int imageWidth;
  final int imageHeight;
  final String label;
  final bool confirmed;

  _NoteBoxPainter({
    required this.box,
    required this.imageWidth,
    required this.imageHeight,
    required this.label,
    required this.confirmed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(size.width / imageWidth, size.height / imageHeight);
    final dispW = imageWidth * scale;
    final dispH = imageHeight * scale;
    final dx = (size.width - dispW) / 2;
    final dy = (size.height - dispH) / 2;
    final rect = Rect.fromLTRB(
      dx + box.left * dispW,
      dy + box.top * dispH,
      dx + box.right * dispW,
      dy + box.bottom * dispH,
    );
    final color = confirmed ? const Color(0xFF00E676) : const Color(0xFFFFD600);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Colors.black54,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: ' $label ',
        style: TextStyle(
          color: Colors.black,
          backgroundColor: color,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final ty = rect.top - tp.height - 4 >= 0 ? rect.top - tp.height - 4 : rect.top + 4;
    tp.paint(canvas, Offset(rect.left.clamp(0, math.max(0, size.width - tp.width)), ty));
  }

  @override
  bool shouldRepaint(_NoteBoxPainter old) =>
      old.box != box ||
      old.label != label ||
      old.confirmed != confirmed ||
      old.imageWidth != imageWidth ||
      old.imageHeight != imageHeight;
}
