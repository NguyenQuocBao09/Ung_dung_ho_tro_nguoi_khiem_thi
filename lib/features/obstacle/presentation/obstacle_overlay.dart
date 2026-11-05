import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings_vi.dart';
import '../../../core/constants/ui_layout.dart';
import '../domain/alert_level.dart';
import '../domain/obstacle_classes.dart';
import '../domain/obstacle_detection.dart';
import 'obstacle_controller.dart';

Color _levelColor(AlertLevel level) {
  switch (level) {
    case AlertLevel.danger:
      return const Color(0xFFFF1744);
    case AlertLevel.warning:
      return const Color(0xFFFFD600);
    case AlertLevel.safe:
      return const Color(0xFF00E676);
  }
}

String _levelText(AlertLevel level) {
  switch (level) {
    case AlertLevel.danger:
      return StringsVi.obstacleLevelDanger;
    case AlertLevel.warning:
      return StringsVi.obstacleLevelWarning;
    case AlertLevel.safe:
      return StringsVi.obstacleLevelSafe;
  }
}

/// Lớp phủ chế độ Cảnh báo vật cản: khung bao vật thể + thẻ trạng thái + nút tạm dừng.
/// Thông tin được đọc qua TTS nên thẻ hiển thị bọc ExcludeSemantics để TalkBack không đọc chồng.
class ObstacleOverlay extends ConsumerWidget {
  const ObstacleOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(obstacleControllerProvider);
    final level = state.level;
    final color = _levelColor(level);
    final a = state.assessment;
    final pauseLabel =
        state.isPaused ? StringsVi.actionResumeObstacle : StringsVi.actionPauseObstacle;

    String headline;
    if (state.errorMessage != null && !state.isModelLoaded) {
      headline = StringsVi.obstacleModelError;
    } else if (state.isCameraBlocked) {
      headline = StringsVi.obstacleCameraBlocked;
    } else if (a != null && level == AlertLevel.danger) {
      headline = '${_levelText(level)}: ${a.nameVi}, ${directionVi(a.direction)}';
    } else {
      headline = buildSceneMessage(state.sceneItems);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!state.isPaused && state.imageWidth > 0)
          ExcludeSemantics(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _BoxesPainter(
                  detections: state.detections,
                  imageWidth: state.imageWidth,
                  imageHeight: state.imageHeight,
                  highlight: a?.detection,
                  highlightColor: color,
                ),
              ),
            ),
          ),
        Positioned(
          top: 20,
          left: 16,
          right: 16,
          child: ExcludeSemantics(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xDD121212),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.isPaused ? StringsVi.obstaclePausedNotice : headline,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: state.isPaused ? Colors.white : color,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      state.lastTotalMs > 0 ? '${state.lastTotalMs} ms' : '',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Nút chính "Tạm dừng / Tiếp tục": giữa phía dưới, 72dp.
        Positioned(
          left: 0,
          right: 0,
          bottom: UiLayout.mainButtonBottom,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Semantics(
            button: true,
            label: pauseLabel,
            excludeSemantics: true,
            child: SizedBox(
              width: UiLayout.mainButtonSize,
              height: UiLayout.mainButtonSize,
              child: FloatingActionButton(
                key: const ValueKey('main_pause_button'),
                shape: const CircleBorder(),
                heroTag: 'obstacle_pause_resume_fab',
                backgroundColor:
                    state.isPaused ? const Color(0xFFFFB74D) : const Color(0xFF2C3E50),
                foregroundColor: state.isPaused ? Colors.black : Colors.white,
                onPressed: () =>
                    ref.read(obstacleControllerProvider.notifier).togglePause(),
                child: Icon(state.isPaused ? Icons.play_arrow : Icons.pause, size: 36),
              ),
            ),
          ),
          ),
        ),
      ],
    );
  }
}

/// Vẽ khung bao theo cách camera preview được hiển thị (lấp đầy khung, cắt phần thừa = BoxFit.cover).
class _BoxesPainter extends CustomPainter {
  final List<ObstacleDetection> detections;
  final int imageWidth;
  final int imageHeight;
  final ObstacleDetection? highlight;
  final Color highlightColor;

  _BoxesPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.highlight,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(size.width / imageWidth, size.height / imageHeight);
    final dispW = imageWidth * scale;
    final dispH = imageHeight * scale;
    final dx = (size.width - dispW) / 2;
    final dy = (size.height - dispH) / 2;

    for (final d in detections) {
      final isMain = identical(d, highlight);
      final color = isMain ? highlightColor : const Color(0xFF80D8FF);
      final rect = Rect.fromLTRB(
        dx + d.left * dispW,
        dy + d.top * dispH,
        dx + d.right * dispW,
        dy + d.bottom * dispH,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isMain ? 4 : 2
          ..color = color,
      );
      final name = ObstacleClasses.of(d.label)?.nameVi ?? d.label;
      final tp = TextPainter(
        text: TextSpan(
          text: ' $name ${(d.score * 100).round()}% ',
          style: TextStyle(
            color: Colors.black,
            backgroundColor: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left, math.max(0, rect.top - tp.height)));
    }
  }

  @override
  bool shouldRepaint(_BoxesPainter old) =>
      old.detections != detections || old.highlight != highlight;
}
