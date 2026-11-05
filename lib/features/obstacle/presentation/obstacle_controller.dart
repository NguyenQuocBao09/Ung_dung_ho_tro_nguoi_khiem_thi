import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings_vi.dart';
import '../../../core/feedback/feedback_manager.dart';
import '../../../core/feedback/feedback_message.dart';
import '../../../core/feedback/haptic_service.dart';
import '../../../core/quality/lighting_monitor.dart';
import '../data/obstacle_detector.dart';
import '../domain/alert_level.dart';
import '../domain/obstacle_detection.dart';

class ObstacleState {
  final bool isModelLoaded;
  final bool isStreaming;
  final bool isPaused;
  final bool isCameraBlocked;
  final List<ObstacleDetection> detections;
  final ObstacleAssessment? assessment;
  final int imageWidth;
  final int imageHeight;
  final int lastTotalMs;
  final int lastInferenceMs;
  final String? errorMessage;

  /// Các vật thể đã xác nhận đang có trước camera (dùng cho thẻ hiển thị).
  final List<SceneItem> sceneItems;

  const ObstacleState({
    this.isModelLoaded = false,
    this.isStreaming = false,
    this.isPaused = false,
    this.isCameraBlocked = false,
    this.detections = const [],
    this.assessment,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.lastTotalMs = 0,
    this.lastInferenceMs = 0,
    this.errorMessage,
    this.sceneItems = const [],
  });

  AlertLevel get level => assessment?.level ?? AlertLevel.safe;

  ObstacleState copyWith({
    bool? isModelLoaded,
    bool? isStreaming,
    bool? isPaused,
    bool? isCameraBlocked,
    List<ObstacleDetection>? detections,
    ObstacleAssessment? assessment,
    bool clearAssessment = false,
    int? imageWidth,
    int? imageHeight,
    int? lastTotalMs,
    int? lastInferenceMs,
    String? errorMessage,
    bool clearError = false,
    List<SceneItem>? sceneItems,
  }) {
    return ObstacleState(
      isModelLoaded: isModelLoaded ?? this.isModelLoaded,
      isStreaming: isStreaming ?? this.isStreaming,
      isPaused: isPaused ?? this.isPaused,
      isCameraBlocked: isCameraBlocked ?? this.isCameraBlocked,
      detections: detections ?? this.detections,
      assessment: clearAssessment ? null : (assessment ?? this.assessment),
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      lastTotalMs: lastTotalMs ?? this.lastTotalMs,
      lastInferenceMs: lastInferenceMs ?? this.lastInferenceMs,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      sceneItems: sceneItems ?? this.sceneItems,
    );
  }
}

String directionVi(ObstacleDirection d) {
  switch (d) {
    case ObstacleDirection.left:
      return StringsVi.obstacleDirLeft;
    case ObstacleDirection.ahead:
      return StringsVi.obstacleDirAhead;
    case ObstacleDirection.right:
      return StringsVi.obstacleDirRight;
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Câu cảnh báo khẩn cấp: "Cẩn thận! Người rất gần, phía trước".
String buildDangerMessage(ObstacleAssessment a) =>
    '${StringsVi.obstacleDangerPrefix} ${a.nameVi} ${StringsVi.obstacleVeryClose}, '
    '${directionVi(a.direction)}';

/// Câu mô tả cảnh, gom theo hướng:
/// "Phía trước: người, 2 ghế. Bên trái: chậu cây. Bên phải: ti vi ở gần."
String buildSceneMessage(List<SceneItem> items) {
  if (items.isEmpty) return StringsVi.obstacleNothing;
  final parts = <String>[];
  for (final dir in const [
    ObstacleDirection.ahead,
    ObstacleDirection.left,
    ObstacleDirection.right,
  ]) {
    final inDir = items.where((i) => i.direction == dir).map((i) {
      final name = i.nameVi.toLowerCase();
      final counted = i.count > 1 ? '${i.count} $name' : name;
      return i.near ? '$counted ${StringsVi.obstacleNear}' : counted;
    }).toList();
    if (inDir.isEmpty) continue;
    parts.add('${_capitalize(directionVi(dir))}: ${inDir.join(', ')}');
  }
  return '${parts.join('. ')}.';
}

/// Điều phối luồng camera -> phát hiện vật cản -> đánh giá -> cảnh báo qua FeedbackManager.
class ObstacleController extends StateNotifier<ObstacleState> {
  final ObstacleDetector _detector;
  final FeedbackManager _feedback;
  final HapticService _haptic;

  /// Đo ánh sáng + đèn flash tự động dùng chung cho cả 3 chế độ.
  final LightingMonitor? _lighting;
  final ObstacleAssessor _assessor;
  final SceneAnnouncer _scene;

  /// Khoảng lấy mẫu khung hình (thiết kế 300–500 ms).
  static const Duration frameInterval = Duration(milliseconds: 400);

  /// Độ sáng kênh Y dưới ngưỡng này coi như camera bị che / quá tối.
  static const double blockedLuminance = 22;
  static const Duration blockedRepeat = Duration(seconds: 8);

  /// Thời gian tối đa chờ một khung hình được xử lý.
  static const Duration detectTimeout = Duration(seconds: 3);

  /// Nếu đang ở chế độ vật cản mà quá thời gian này không nhận được khung hình nào
  /// thì tự khởi động lại image stream (tự phục hồi sau khi mở lại app / đổi chế độ).
  static const Duration noFrameRestartAfter = Duration(milliseconds: 2500);
  static const Duration minRestartInterval = Duration(seconds: 3);

  CameraController? _camera;
  bool _busy = false;
  int _generation = 0;
  DateTime? _lastFrameAt;
  DateTime? _lastBlockedPromptAt;
  bool _errorAnnounced = false;

  /// Chế độ vật cản đang hoạt động (đã gọi startStream, chưa gọi stopStream).
  bool _active = false;
  Timer? _watchdog;
  DateTime? _lastFrameSeenAt;
  DateTime? _streamStartedAt;
  DateTime? _lastRestartAt;
  bool _restarting = false;

  ObstacleController({
    required ObstacleDetector detector,
    required FeedbackManager feedbackManager,
    required HapticService hapticService,
    ObstacleAssessor assessor = const ObstacleAssessor(),
    SceneAnnouncer? scene,
    LightingMonitor? lighting,
  })  : _lighting = lighting,
        _detector = detector,
        _feedback = feedbackManager,
        _haptic = hapticService,
        _assessor = assessor,
        _scene = scene ?? SceneAnnouncer(),
        super(const ObstacleState());

  Future<bool> _ensureModel() async {
    try {
      await _detector.initialize();
      if (mounted && !state.isModelLoaded) {
        state = state.copyWith(isModelLoaded: true, clearError: true);
      }
      return true;
    } catch (e) {
      debugPrint('ObstacleController: lỗi khởi tạo model: $e');
      if (mounted) {
        state = state.copyWith(
          isModelLoaded: false,
          errorMessage: StringsVi.obstacleModelError,
        );
      }
      if (!_errorAnnounced) {
        _errorAnnounced = true;
        await _feedback.speak(StringsVi.obstacleModelError,
            priority: FeedbackPriority.normal);
      }
      return false;
    }
  }

  Future<void> startStream(CameraController controller) async {
    if (state.isStreaming && _camera == controller) return;
    if (!controller.value.isInitialized) return;

    _camera = controller;
    final gen = ++_generation;
    _scene.reset();
    _busy = false;
    _lastFrameAt = null;
    _lastBlockedPromptAt = null;

    final ok = await _ensureModel();
    if (!ok || gen != _generation || !mounted) return;

    await _feedback.speak(StringsVi.obstacleIntro, priority: FeedbackPriority.normal);

    // Chế độ trước có thể chưa dừng xong image stream (stopStream không được await
    // ở nơi gọi): chờ tối đa ~1 giây, KHÔNG khởi tạo lại camera.
    for (var i = 0; i < 10 && controller.value.isStreamingImages; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (gen != _generation || !mounted) return;
    }
    // Chỉ một chế độ được hoạt động tại một thời điểm: nếu stream cũ (của chế độ
    // khác hoặc phiên trước) vẫn còn, giành quyền thay vì bỏ cuộc.
    await _takeOverStream(controller, gen);
    if (gen != _generation || !mounted) return;

    _active = true;
    _lastFrameSeenAt = null;
    _streamStartedAt = DateTime.now();
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _checkFrames());
  }

  /// Dừng stream đang chạy (nếu có) rồi bắt đầu stream với callback của chế độ vật cản.
  Future<void> _takeOverStream(CameraController controller, int gen) async {
    if (controller.value.isStreamingImages) {
      debugPrint('ObstacleController: stream cũ vẫn chạy, dừng để giành quyền.');
      try {
        await controller.stopImageStream();
      } catch (e) {
        debugPrint('ObstacleController: lỗi dừng stream cũ: $e');
      }
    }
    if (gen != _generation || !mounted) return;
    try {
      await controller.startImageStream(_onFrame);
      _busy = false;
      if (mounted && gen == _generation) {
        state = state.copyWith(isStreaming: true, isPaused: false, clearError: true);
      }
    } catch (e) {
      // Không bỏ cuộc: watchdog sẽ thử lại.
      debugPrint('ObstacleController: không thể bắt đầu stream: $e');
    }
  }

  /// Watchdog: đang hoạt động mà không có khung hình -> khởi động lại stream.
  void _checkFrames() {
    final cam = _camera;
    if (!_active || cam == null || !mounted || _restarting) return;
    final now = DateTime.now();
    final last = _lastFrameSeenAt ?? _streamStartedAt ?? now;
    if (now.difference(last) < noFrameRestartAfter) return;
    if (_lastRestartAt != null && now.difference(_lastRestartAt!) < minRestartInterval) {
      return;
    }
    _lastRestartAt = now;
    _restarting = true;
    debugPrint('ObstacleController: ${now.difference(last).inMilliseconds} ms không có '
        'khung hình, khởi động lại image stream.');
    final gen = _generation;
    _takeOverStream(cam, gen).whenComplete(() {
      _restarting = false;
      _streamStartedAt = DateTime.now();
    });
  }

  Future<void> stopStream() async {
    _active = false;
    _watchdog?.cancel();
    _watchdog = null;
    _generation++; // Loại bỏ mọi kết quả đang xử lý của phiên cũ.
    final cam = _camera;
    _camera = null;
    if (cam != null && cam.value.isStreamingImages) {
      try {
        await cam.stopImageStream();
      } catch (e) {
        debugPrint('ObstacleController: lỗi dừng stream: $e');
      }
    }
    _busy = false;
    _scene.reset();
    _feedback.clearQueue();
    if (mounted) {
      state = state.copyWith(
        isStreaming: false,
        detections: const [],
        clearAssessment: true,
        isCameraBlocked: false,
        sceneItems: const [],
      );
    }
  }

  /// Đọc lại toàn bộ vật thể đang có trước camera (hành động TalkBack "Đọc lại").
  Future<void> readScene() async {
    await _feedback.speak(
      buildSceneMessage(_scene.confirmedItems),
      priority: FeedbackPriority.urgent,
    );
  }

  Future<void> togglePause() async {
    final paused = !state.isPaused;
    if (mounted) {
      state = state.copyWith(
        isPaused: paused,
        detections: const [],
        clearAssessment: true,
        sceneItems: const [],
      );
    }
    _scene.reset();
    await _feedback.speak(
      paused ? StringsVi.obstaclePausedNotice : StringsVi.obstacleResumedNotice,
      priority: FeedbackPriority.urgent,
    );
  }

  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    _lastFrameSeenAt = now; // Có khung hình đến (kể cả khi bị bỏ qua) -> stream còn sống.
    _lighting?.onFrame(image);
    if (state.isPaused || _busy) return;
    if (_lastFrameAt != null && now.difference(_lastFrameAt!) < frameInterval) return;
    final cam = _camera;
    if (cam == null) return;

    _busy = true;
    _lastFrameAt = now;
    _process(image, cam.description.sensorOrientation, _generation);
  }

  Future<void> _process(CameraImage image, int rotation, int gen) async {
    try {
      // Watchdog: nếu isolate không trả lời, không để cờ _busy kẹt vĩnh viễn.
      final result =
          await _detector.detect(image, rotation).timeout(detectTimeout);
      // Kết quả của phiên/chế độ cũ: bỏ qua, không phát âm thanh.
      if (gen != _generation || !mounted || state.isPaused) return;
      final now = DateTime.now();

      final blocked = result.luminance < blockedLuminance;
      final items = blocked
          ? const <ObstacleAssessment>[]
          : _assessor.assessAll(result.detections);
      final assessment = items.isEmpty ? null : items.first;
      state = state.copyWith(
        detections: blocked ? const [] : result.detections,
        assessment: assessment,
        clearAssessment: assessment == null,
        imageWidth: result.imageWidth,
        imageHeight: result.imageHeight,
        lastTotalMs: result.totalMs,
        lastInferenceMs: result.inferenceMs,
        isCameraBlocked: blocked,
      );

      if (blocked) {
        _scene.reset();
        if (_lastBlockedPromptAt == null ||
            now.difference(_lastBlockedPromptAt!) >= blockedRepeat) {
          _lastBlockedPromptAt = now;
          unawaited(_feedback.speak(StringsVi.obstacleCameraBlocked,
              priority: FeedbackPriority.normal));
        }
        return;
      }

      final decision = _scene.onFrame(items, now);
      state = state.copyWith(sceneItems: _scene.confirmedItems);
      if (decision == null) return;

      // Không await TTS/rung: khung hình kế tiếp không phải chờ đọc xong.
      switch (decision.type) {
        case SceneDecisionType.danger:
          unawaited(_haptic.danger());
          unawaited(_feedback.speak(buildDangerMessage(decision.danger!),
              priority: FeedbackPriority.urgent));
          break;
        case SceneDecisionType.scene:
          unawaited(_haptic.light());
          unawaited(_feedback.speak(buildSceneMessage(decision.items),
              priority: FeedbackPriority.normal));
          break;
      }
    } catch (e) {
      debugPrint('ObstacleController: lỗi xử lý khung hình: $e');
    } finally {
      if (gen == _generation) _busy = false;
    }
  }

  @override
  void dispose() {
    _active = false;
    _watchdog?.cancel();
    _watchdog = null;
    _generation++;
    final cam = _camera;
    if (cam != null && cam.value.isStreamingImages) {
      cam.stopImageStream().catchError((_) {});
    }
    _camera = null;
    super.dispose();
  }
}

final obstacleControllerProvider =
    StateNotifierProvider<ObstacleController, ObstacleState>((ref) {
  return ObstacleController(
    detector: ref.watch(obstacleDetectorProvider),
    feedbackManager: ref.watch(feedbackManagerProvider),
    hapticService: ref.watch(hapticServiceProvider),
    lighting: ref.watch(lightingMonitorProvider.notifier),
  );
});
