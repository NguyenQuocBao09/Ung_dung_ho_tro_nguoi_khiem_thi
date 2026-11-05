import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings_vi.dart';
import '../../../core/constants/ui_layout.dart';
import '../../../core/quality/lighting_monitor.dart';
import '../domain/read_session.dart';
import 'reading_controller.dart';

/// Lớp phủ giao diện và trợ năng cho chế độ Đọc chữ tự động
class ReadingOverlay extends ConsumerWidget {
  const ReadingOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(readingControllerProvider);
    final hasHint = ref.watch(lowLightHintProvider) != null;

    final pauseResumeLabel = state.isPaused
        ? StringsVi.actionResumeReading
        : StringsVi.actionPauseReading;

    // Custom Semantics Actions cho người dùng TalkBack
    final customSemanticsActions = <CustomSemanticsAction, VoidCallback>{
      const CustomSemanticsAction(label: StringsVi.actionRestartReading): () {
        ref.read(readingControllerProvider.notifier).resetSession();
      },
      CustomSemanticsAction(label: pauseResumeLabel): () {
        ref.read(readingControllerProvider.notifier).togglePause();
      },
    };

    return Semantics(
      container: true,
      customSemanticsActions: customSemanticsActions,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 0. KHUNG BAO QUANH CÁC ĐOẠN VĂN BẢN (chỉ hiển thị trực quan).
          // Vàng: đang nhận diện; xanh lá: đã đọc.
          if (!state.isPaused &&
              state.blocks.isNotEmpty &&
              state.imageWidth > 0 &&
              state.imageHeight > 0)
            ExcludeSemantics(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('reading_block_boxes'),
                  painter: TextBlockBoxPainter(
                    blocks: state.blocks,
                    imageWidth: state.imageWidth,
                    imageHeight: state.imageHeight,
                  ),
                ),
              ),
            ),

          // 1. VĂN BẢN NHẬN DẠNG:
          // Bọc trong ExcludeSemantics để TalkBack không tự đọc đè lên giọng nói TTS
          if (state.currentLines.isNotEmpty)
            // Đặt ở phía dưới (trên nút Tạm dừng) để không che khung bao văn bản;
            // đẩy lên khi có dòng gợi ý "Ánh sáng yếu".
            Positioned(
              bottom: hasHint ? UiLayout.cardBottomWithHint : UiLayout.cardBottom,
              left: 16,
              right: 16,
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xDD121212),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF80D8FF), width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.text_snippet_outlined,
                              color: Color(0xFF80D8FF),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              StringsVi.readingOverlayTitle,
                              style: TextStyle(
                                color: Color(0xFF80D8FF),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            if (state.isPaused)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade900,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  StringsVi.readingStatusPaused,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...state.currentLines.map(
                          (line) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(
                              line,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 2. NÚT CHÍNH "TẠM DỪNG / TIẾP TỤC TỰ ĐỌC": giữa phía dưới, 72dp.
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
                  heroTag: 'reading_pause_resume_fab',
                  backgroundColor: state.isPaused
                      ? const Color(0xFFFFB74D) // Màu cam khi đang tạm dừng
                      : const Color(0xFF2C3E50), // Màu xanh xám khi đang tự đọc
                  foregroundColor: state.isPaused ? Colors.black : Colors.white,
                  onPressed: () {
                    ref.read(readingControllerProvider.notifier).togglePause();
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
        ],
      ),
    );
  }
}

/// Vẽ khung bo góc quanh từng khối văn bản theo cách preview hiển thị
/// (lấp đầy, cắt phần thừa = BoxFit.cover), giống khung tiền ở chế độ tiền.
class TextBlockBoxPainter extends CustomPainter {
  final List<TextBlockBox> blocks;
  final int imageWidth;
  final int imageHeight;

  static const Color readColor = Color(0xFF00E676);
  static const Color pendingColor = Color(0xFFFFD600);

  TextBlockBoxPainter({
    required this.blocks,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(size.width / imageWidth, size.height / imageHeight);
    final dispW = imageWidth * scale;
    final dispH = imageHeight * scale;
    final dx = (size.width - dispW) / 2;
    final dy = (size.height - dispH) / 2;
    const pad = 6.0;

    for (final b in blocks) {
      final rect = Rect.fromLTRB(
        dx + b.rect.left * dispW - pad,
        dy + b.rect.top * dispH - pad,
        dx + b.rect.right * dispW + pad,
        dy + b.rect.bottom * dispH + pad,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = Colors.black54,
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..color = b.read ? readColor : pendingColor,
      );
    }
  }

  @override
  bool shouldRepaint(TextBlockBoxPainter old) =>
      old.blocks != blocks || old.imageWidth != imageWidth || old.imageHeight != imageHeight;
}
