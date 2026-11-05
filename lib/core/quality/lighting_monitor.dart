import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/camera_service.dart';
import '../constants/strings_vi.dart';
import '../feedback/feedback_manager.dart';
import '../feedback/feedback_message.dart';
import 'lighting_detector.dart';

/// Trạng thái ánh sáng dùng chung cho cả 3 chế độ.
class LightingState {
  /// Đã có đủ mẫu để biết môi trường sáng/tối chưa.
  final bool measured;
  final bool isLowLight;

  /// Đèn flash đang được bật bởi chế độ tự động.
  final bool autoTorchOn;

  /// Độ sáng trung bình gần nhất (0..255), -1 nếu chưa đo.
  final double lastLuma;

  const LightingState({
    this.measured = false,
    this.isLowLight = false,
    this.autoTorchOn = false,
    this.lastLuma = -1,
  });

  LightingState copyWith({bool? measured, bool? isLowLight, bool? autoTorchOn, double? lastLuma}) =>
      LightingState(
        measured: measured ?? this.measured,
        isLowLight: isLowLight ?? this.isLowLight,
        autoTorchOn: autoTorchOn ?? this.autoTorchOn,
        lastLuma: lastLuma ?? this.lastLuma,
      );
}

/// Giám sát ánh sáng từ luồng camera chung và tự bật/tắt đèn flash.
///
/// Mỗi controller chế độ (đọc chữ / tiền / vật cản) gọi [onFrame] với khung hình
/// nó nhận được; lớp này tự điều tiết (mỗi [sampleInterval] lấy 1 mẫu), chỉ đọc
/// một lưới điểm thưa trên mặt phẳng Y nên không tốn CPU và không chuyển RGB.
class LightingMonitor extends StateNotifier<LightingState> {
  final CameraControllerNotifier _camera;
  final FeedbackManager _feedback;
  final LightingDecider _decider;
  final Duration sampleInterval;

  final Duration warmup;

  DateTime? _lastSampleAt;
  DateTime? _warmupUntil;
  bool _busy = false;

  LightingMonitor({
    required CameraControllerNotifier camera,
    required FeedbackManager feedback,
    LightingDecider? decider,
    this.sampleInterval = const Duration(milliseconds: 400),
    this.warmup = const Duration(milliseconds: 1500),
  })  : _camera = camera,
        _feedback = feedback,
        _decider = decider ?? LightingDecider(),
        super(const LightingState());

  void onFrame(CameraImage image) {
    final now = DateTime.now();
    if (_busy) return;
    // Vài khung đầu sau khi camera mở thường gần như đen (chưa cân bằng phơi
    // sáng) -> bỏ qua [warmup] đầu tiên để không bật đèn nhầm.
    final warm = _warmupUntil ??= now.add(warmup);
    if (now.isBefore(warm)) return;
    if (_lastSampleAt != null && now.difference(_lastSampleAt!) < sampleInterval) return;
    if (image.planes.isEmpty) return;
    _lastSampleAt = now;
    final p = image.planes.first;
    final luma = sampleLumaMean(
      p.bytes,
      width: image.width,
      height: image.height,
      rowStride: p.bytesPerRow,
    );
    if (luma == null) return;
    unawaited(onLuma(luma, now));
  }

  /// Xử lý một mẫu độ sáng (tách riêng để kiểm thử).
  @visibleForTesting
  Future<void> onLuma(double luma, DateTime now) async {
    if (!mounted) return;
    _busy = true;
    try {
      final torchOn = _camera.state.isTorchOn;
      final action = _decider.onSample(luma, now, torchOn: torchOn);
      final manual = _camera.manualTorchOverride;
      switch (action) {
        case LightingAction.none:
          break;
        case LightingAction.enterLowLight:
          final ok = !manual && await _camera.setTorch(true);
          debugPrint('LightingMonitor: tối (Y=${luma.toStringAsFixed(0)}), đèn flash: $ok');
          unawaited(_feedback.speak(
            ok ? StringsVi.lowLightTorchOnNotice : StringsVi.hintLowLight,
            priority: FeedbackPriority.info,
          ));
          if (mounted) state = state.copyWith(isLowLight: true, autoTorchOn: ok);
          break;
        case LightingAction.exitLowLight:
          if (mounted) state = state.copyWith(isLowLight: false, autoTorchOn: false);
          break;
        case LightingAction.startProbe:
          if (manual || !state.autoTorchOn) {
            // Đèn do người dùng bật: không tự tắt; coi như đã đủ sáng nhờ đèn.
            break;
          }
          debugPrint('LightingMonitor: ảnh rất sáng (Y=${luma.toStringAsFixed(0)}), tắt đèn để đo thử.');
          await _camera.setTorch(false);
          break;
        case LightingAction.probeStillDark:
          debugPrint('LightingMonitor: đo thử Y=${luma.toStringAsFixed(0)} vẫn tối, bật lại đèn.');
          final ok = !manual && await _camera.setTorch(true);
          if (mounted) state = state.copyWith(isLowLight: true, autoTorchOn: ok);
          break;
        case LightingAction.probeBright:
          debugPrint('LightingMonitor: đủ sáng, tắt đèn flash.');
          if (mounted) state = state.copyWith(isLowLight: false, autoTorchOn: false);
          break;
      }
      if (mounted) state = state.copyWith(measured: true, lastLuma: luma);
    } finally {
      _busy = false;
    }
  }

  /// App vào nền / camera khởi tạo lại: tắt đèn tự động và đo lại từ đầu.
  Future<void> suspend() async {
    final wasAuto = state.autoTorchOn;
    _decider.reset();
    _lastSampleAt = null;
    _warmupUntil = null;
    if (mounted) state = const LightingState();
    if (wasAuto && !_camera.manualTorchOverride) await _camera.setTorch(false);
  }
}

final lightingMonitorProvider = StateNotifierProvider<LightingMonitor, LightingState>((ref) {
  return LightingMonitor(
    camera: ref.watch(cameraStateProvider.notifier),
    feedback: ref.watch(feedbackManagerProvider),
  );
});

/// Dòng gợi ý chất lượng ảnh hiển thị trên màn hình camera (null = không hiện).
final lowLightHintProvider = Provider<String?>((ref) {
  final s = ref.watch(lightingMonitorProvider);
  if (!s.isLowLight) return null;
  return s.autoTorchOn ? StringsVi.hintLowLightTorchOn : StringsVi.hintLowLight;
});
