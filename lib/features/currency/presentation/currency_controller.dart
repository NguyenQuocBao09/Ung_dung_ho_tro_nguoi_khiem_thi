import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../core/constants/strings_vi.dart';
import '../../../core/feedback/feedback_manager.dart';
import '../../../core/history/history_entry.dart';
import '../../../core/history/history_notifier.dart';
import '../../../core/feedback/feedback_message.dart';
import '../../../core/feedback/haptic_service.dart';
import '../../../core/quality/lighting_monitor.dart';
import '../data/currency_classifier.dart';
import '../data/currency_detector.dart';
import '../domain/currency_session.dart';
import '../domain/denomination.dart';
import '../domain/note_window_search.dart';

export '../domain/note_window_search.dart' show NormRect;

/// Trạng thái của chức năng nhận diện tiền tệ liên tục
class CurrencyState {
  final bool isModelLoaded;
  final bool isStreaming;
  final bool isPaused;
  final bool isProcessing;
  final MultiCropPredictionResult? lastResult;
  final String? announcedDenomination;
  final bool isLowLight;
  final String? errorMessage;
  final double confidenceThreshold;

  /// Khung bao đã làm mượt quanh tờ tiền (chuẩn hoá trong ảnh đứng); null khi không thấy tiền.
  final NormRect? box;

  const CurrencyState({
    this.isModelLoaded = false,
    this.isStreaming = false,
    this.isPaused = false,
    this.isProcessing = false,
    this.lastResult,
    this.announcedDenomination,
    this.isLowLight = false,
    this.errorMessage,
    this.confidenceThreshold = 0.85,
    this.box,
  });

  CurrencyState copyWith({
    bool? isModelLoaded,
    bool? isStreaming,
    bool? isPaused,
    bool? isProcessing,
    MultiCropPredictionResult? lastResult,
    String? announcedDenomination,
    bool? isLowLight,
    String? errorMessage,
    double? confidenceThreshold,
    NormRect? box,
    bool clearBox = false,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return CurrencyState(
      box: (clearResult || clearBox) ? null : (box ?? this.box),
      isModelLoaded: isModelLoaded ?? this.isModelLoaded,
      isStreaming: isStreaming ?? this.isStreaming,
      isPaused: isPaused ?? this.isPaused,
      isProcessing: isProcessing ?? this.isProcessing,
      lastResult: clearResult ? null : (lastResult ?? this.lastResult),
      announcedDenomination: clearResult ? null : (announcedDenomination ?? this.announcedDenomination),
      isLowLight: isLowLight ?? this.isLowLight,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
    );
  }
}

/// Controller quản lý luồng nhận diện tiền tệ tự động liên tục (Google Lookout style)
class CurrencyController extends StateNotifier<CurrencyState> {
  final CurrencyClassifier _classifier;
  final FeedbackManager _feedbackManager;
  final HapticService _hapticService;
  final CurrencySession _session;

  CameraController? _cameraController;
  bool _busy = false;

  /// Tăng mỗi khi dừng/đặt lại luồng; kết quả của thế hệ cũ bị bỏ (không đọc, không vẽ).
  int _generation = 0;
  final BoxSmoother _boxSmoother = BoxSmoother();

  /// Vùng tiền của khung trước, để worker chỉ quét quanh đó (bám theo).
  NormRect? _trackBox;
  int _framesSinceFullScan = 0;
  static const int fullScanEvery = 4;

  /// Quá thời gian này mà worker chưa trả kết quả thì bỏ khung để luồng không bị kẹt.
  static const Duration analyzeTimeout = Duration(seconds: 3);
  DateTime? _lastFrameProcessedTime;
  DateTime? _lastAnnouncementTime;
  DateTime? _lastCloserPromptTime;
  /// Đo ánh sáng + đèn flash tự động dùng chung cho cả 3 chế độ.
  final LightingMonitor? _lighting;
  final HistoryNotifier? _history;

  /// Hằng số điều chỉnh tần suất xử lý khung hình (bỏ khung nếu < 500 ms)
  static const Duration frameThrottleDuration = Duration(milliseconds: 500);

  /// Model chính: YOLOv8n phát hiện + phân loại tiền trong 1 lần chạy. Null hoặc nạp lỗi thì
  /// dùng lại model phân loại cũ với cách quét nhiều vùng (phương án dự phòng).
  final CurrencyDetector? _detector;
  bool _useYolo = false;

  /// Điểm khung YOLO tối thiểu để một khung hình được tính phiếu (bỏ phiếu 3/5).
  /// Chọn từ bảng ngưỡng trên tập test của notebook (0,6: đọc sai 1,45%, bỏ sót 1,45%,
  /// báo nhầm 1,64% trên 130 ảnh). Tập test còn ảnh gần giống train nên số liệu lạc quan;
  /// CHƯA hiệu chỉnh trên thiết bị.
  static const double yoloVoteMinScore = 0.6;

  CurrencyController({
    required CurrencyClassifier classifier,
    required FeedbackManager feedbackManager,
    required HapticService hapticService,
    CurrencyDetector? detector,
    CurrencySession? session,
    double confidenceThreshold = 0.85,
    LightingMonitor? lighting,
    HistoryNotifier? history,
  })  : _classifier = classifier,
        _history = history,
        _lighting = lighting,
        _detector = detector,
        _feedbackManager = feedbackManager,
        _hapticService = hapticService,
        _session = session ?? CurrencySession(confidenceThreshold: confidenceThreshold),
        super(CurrencyState(confidenceThreshold: confidenceThreshold)) {
    _initModel();
  }

  CurrencySession get session => _session;

  Future<void> _initModel() async {
    try {
      await _classifier.initialize();
      final detector = _detector;
      if (detector != null) {
        try {
          await detector.initialize();
          _useYolo = true;
        } catch (e) {
          debugPrint('CurrencyController: không nạp được YOLO, dùng model phân loại dự phòng: $e');
          _useYolo = false;
        }
      }
      if (mounted) {
        state = state.copyWith(isModelLoaded: true, clearError: true);
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isModelLoaded: false,
          errorMessage: StringsVi.currencyModelError,
        );
      }
    }
  }

  /// Bắt đầu nhận luồng ảnh liên tục từ camera
  Future<void> startStream(CameraController controller) async {
    if (state.isStreaming && _cameraController == controller) {
      return;
    }

    _cameraController = controller;

    if (!controller.value.isInitialized) {
      debugPrint('CurrencyController: Camera chưa khởi tạo sẵn sàng.');
      return;
    }

    if (controller.value.isStreamingImages) {
      if (mounted) {
        state = state.copyWith(isStreaming: true, isPaused: false);
      }
      return;
    }

    try {
      _lastFrameProcessedTime = null;
      _lastAnnouncementTime = DateTime.now();
      _lastCloserPromptTime = null;
      _busy = false;

      await controller.startImageStream(_onCameraFrame);
      if (mounted) {
        state = state.copyWith(isStreaming: true, isPaused: false);
      }
      debugPrint('CurrencyController: Đã bắt đầu luồng nhận diện tiền tự động.');
    } catch (e) {
      debugPrint('CurrencyController: Lỗi khi bắt đầu image stream: $e');
      if (mounted) {
        state = state.copyWith(errorMessage: e.toString());
      }
    }
  }

  /// Dừng luồng ảnh camera
  Future<void> stopStream() async {
    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      try {
        await _cameraController!.stopImageStream();
      } catch (e) {
        debugPrint('CurrencyController: Lỗi khi dừng image stream: $e');
      }
    }
    _cameraController = null;
    _busy = false;
    _generation++;
    _boxSmoother.reset();
    _trackBox = null;
    _feedbackManager.clearQueue();
    if (mounted) {
      state = state.copyWith(isStreaming: false, clearBox: true);
    }
  }

  /// Bật / Tắt trạng thái tạm dừng tự nhận diện
  Future<void> togglePause() async {
    if (state.isPaused) {
      await resume();
    } else {
      await pause();
    }
  }

  /// Tạm dừng tự nhận diện
  Future<void> pause() async {
    if (state.isPaused) return;
    if (mounted) {
      state = state.copyWith(isPaused: true);
    }
    await _feedbackManager.stop();
    await _feedbackManager.speak(
      StringsVi.currencyPausedNotice,
      priority: FeedbackPriority.urgent,
    );
  }

  /// Tiếp tục tự nhận diện
  Future<void> resume() async {
    if (!state.isPaused) return;
    if (mounted) {
      state = state.copyWith(isPaused: false);
    }
    _lastFrameProcessedTime = null;
    _lastAnnouncementTime = DateTime.now();
    await _feedbackManager.speak(
      StringsVi.currencyResumedNotice,
      priority: FeedbackPriority.urgent,
    );
  }

  /// Đọc lại mệnh giá gần nhất (Custom Semantics Action)
  Future<void> readAgain() async {
    final last = _session.lastAnnounced;
    if (last != null && last != 'none') {
      final spoken = _classifier.labelDisplayVi[last] ?? Denomination.fromCode(last).displayName;
      await _hapticService.success();
      await _feedbackManager.speak(spoken, priority: FeedbackPriority.urgent);
    } else {
      await _hapticService.warning();
      await _feedbackManager.speak(
        StringsVi.currencyNoLastBill,
        priority: FeedbackPriority.info,
      );
    }
  }

  /// Cho phép đọc tờ tiền mới ngay cả khi cùng mệnh giá cũ (Custom Semantics Action 'Tờ khác')
  Future<void> newBill() async {
    _session.resetActiveBill();
    _lastAnnouncementTime = DateTime.now();
    await _hapticService.selection();
    if (mounted) {
      state = state.copyWith(clearResult: true);
    }
  }

  /// Đặt lại toàn bộ trạng thái phiên
  void reset() {
    _generation++;
    _boxSmoother.reset();
    _trackBox = null;
    _session.reset();
    _feedbackManager.clearQueue();
    _lastAnnouncementTime = DateTime.now();
    _lastCloserPromptTime = null;
    if (mounted) {
      state = state.copyWith(
        isProcessing: false,
        clearResult: true,
        clearError: true,
      );
    }
  }

  /// Callback nhận từng khung hình từ camera
  void _onCameraFrame(CameraImage image) {
    _lighting?.onFrame(image);
    if (state.isPaused) return;

    final now = DateTime.now();

    // Bỏ khung nếu đang bận hoặc cách lần trước < 500 ms
    if (_busy) return;
    if (_lastFrameProcessedTime != null &&
        now.difference(_lastFrameProcessedTime!) < frameThrottleDuration) {
      return;
    }

    _busy = true;
    _lastFrameProcessedTime = now;

    _processStreamFrame(image, now, _generation);
  }

  Future<MultiCropPredictionResult> _detectWithYolo(CameraImage image, int rotation) async {
    final frame = await _detector!.detect(image, rotation).timeout(analyzeTimeout);
    return yoloFrameToResult(frame, _classifier.labelDisplayVi, yoloVoteMinScore);
  }

  /// Xử lý khung hình nhận diện tiền: định vị + phân loại chạy trong isolate nền.
  Future<void> _processStreamFrame(CameraImage image, DateTime now, int generation) async {
    try {
      final cameraDesc = _cameraController?.description;
      if (cameraDesc == null) return;

      // 1. Quét các vùng hình tờ tiền để tìm vị trí và mệnh giá (đúng màu NV21/YUV420).
      final MultiCropPredictionResult result;
      if (_useYolo) {
        result = await _detectWithYolo(image, cameraDesc.sensorOrientation);
      } else {
        // Dự phòng: model phân loại + quét nhiều vùng.
        // Cứ [fullScanEvery] khung thì quét lại toàn bộ, để không bị khoá vào một vùng sai.
        _framesSinceFullScan++;
        final track = _framesSinceFullScan >= fullScanEvery ? null : _trackBox;
        if (track == null) _framesSinceFullScan = 0;
        result = await _classifier
            .analyzeFrame(image, cameraDesc.sensorOrientation, trackFrom: track)
            .timeout(analyzeTimeout);
      }

      // Kết quả của luồng cũ (đã dừng/đổi chế độ/đặt lại) thì bỏ qua.
      if (!mounted || generation != _generation || state.isPaused) return;
      _trackBox = result.isMoney ? result.box : null;

      // 2. Ánh sáng yếu: LightingMonitor dùng chung xử lý (cảnh báo + đèn flash).

      // 3. Khung bao quanh tờ tiền (làm mượt giữa các khung hình)
      final rawBox = result.box;
      if (result.isMoney && rawBox != null) {
        final smoothed = _boxSmoother.update(rawBox, result.label);
        state = state.copyWith(lastResult: result, box: smoothed);
      } else {
        _boxSmoother.reset();
        state = state.copyWith(lastResult: result, clearBox: true);
      }

      // 4. Bỏ phiếu 3/5 khung hình trước khi đọc mệnh giá. Khung không đủ đồng thuận
      // giữa các vùng quét thì không được tính phiếu (đưa độ tin cậy 0 nhưng không xoá phiếu cũ).
      // Khung đủ tin cậy được tính phiếu với độ tin cậy 1.0 (vượt ngưỡng phiên), còn lại 0.
      final announcedDenom = _session.onFrame(
        result.label,
        result.isMoney ? (result.isReliable ? 1.0 : 0.0) : result.confidence,
      );

      if (announcedDenom != null) {
        _lastAnnouncementTime = now;
        _lastCloserPromptTime = null;
        state = state.copyWith(announcedDenomination: announcedDenom);

        final spokenText = result.spokenVi.isNotEmpty
            ? result.spokenVi
            : Denomination.fromCode(announcedDenom).displayName;

        _history?.add(HistoryType.currency, spokenText);
        unawaited(_hapticService.success());
        unawaited(_feedbackManager.speak(spokenText, priority: FeedbackPriority.normal));
      } else {
        // 5. Sau 6 giây chưa đọc được gì thì nhắc đưa tờ tiền gần camera hơn
        if (_lastAnnouncementTime != null &&
            now.difference(_lastAnnouncementTime!) >= const Duration(seconds: 6)) {
          if (_lastCloserPromptTime == null ||
              now.difference(_lastCloserPromptTime!) >= const Duration(seconds: 6)) {
            _lastCloserPromptTime = now;
            unawaited(_feedbackManager.speak(
              StringsVi.hintBringCloser,
              priority: FeedbackPriority.info,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('CurrencyController: Lỗi khi xử lý khung hình nhận diện tiền: $e');
    } finally {
      _busy = false;
    }
  }

  /// Chụp ảnh tĩnh thủ công (dành cho chế độ chụp thủ công nếu cần)
  Future<MultiCropPredictionResult?> captureAndClassify(
    CameraController cameraController,
  ) async {
    if (state.isProcessing) return null;

    if (mounted) {
      state = state.copyWith(isProcessing: true, clearError: true);
    }
    await _hapticService.light();

    try {
      final xFile = await cameraController.takePicture();
      final bytes = await xFile.readAsBytes();

      try {
        final tempFile = File(xFile.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}

      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        if (mounted) {
          state = state.copyWith(isProcessing: false);
        }
        return null;
      }

      final oriented = img.bakeOrientation(decoded);
      final result = await _classifier.predictMulti(oriented);

      if (result == null) {
        if (mounted) {
          state = state.copyWith(isProcessing: false);
        }
        return null;
      }

      if (mounted) {
        state = state.copyWith(
          isProcessing: false,
          lastResult: result,
          announcedDenomination: result.isMoney ? result.label : null,
        );
      }

      if (result.isMoney && result.confidence >= state.confidenceThreshold) {
        final spoken = result.spokenVi.isNotEmpty
            ? result.spokenVi
            : result.denomination.displayName;
        _history?.add(HistoryType.currency, spoken);
        await _hapticService.success();
        await _feedbackManager.speak(spoken, priority: FeedbackPriority.normal);
      } else {
        await _hapticService.warning();
        await _feedbackManager.speak(
          StringsVi.currencyNotRecognized,
          priority: FeedbackPriority.info,
        );
      }

      return result;
    } catch (e) {
      debugPrint('CurrencyController: Lỗi chụp ảnh thủ công: $e');
      if (mounted) {
        state = state.copyWith(isProcessing: false, errorMessage: e.toString());
      }
      await _hapticService.error();
      return null;
    }
  }

  @override
  void dispose() {
    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      try {
        _cameraController!.stopImageStream();
      } catch (_) {}
    }
    _cameraController = null;
    _busy = false;
    _feedbackManager.clearQueue();
    _classifier.dispose();
    super.dispose();
  }
}

/// Chuyển kết quả YOLO của một khung hình thành kết quả nhận diện tiền:
/// lấy khung điểm cao nhất (app đọc một tờ mỗi lần); không có khung = không có tiền.
MultiCropPredictionResult yoloFrameToResult(
  CurrencyDetectionFrame frame,
  Map<String, String> spokenVi,
  double voteMinScore,
) {
  if (frame.detections.isEmpty) {
    return MultiCropPredictionResult(
      label: 'none',
      denomination: Denomination.none,
      confidence: 0,
      spokenVi: '',
      winningCrop: 'YOLO',
      winningCropIndex: 0,
      inferenceTimeMs: frame.totalMs,
      imageWidth: frame.imageWidth,
      imageHeight: frame.imageHeight,
      luminance: frame.luminance,
      reliableFlag: false,
    );
  }
  final top = frame.detections.first;
  return MultiCropPredictionResult(
    label: top.label,
    denomination: Denomination.fromCode(top.label),
    confidence: top.score,
    spokenVi: spokenVi[top.label] ?? '',
    winningCrop: 'YOLO',
    winningCropIndex: 0,
    inferenceTimeMs: frame.totalMs,
    box: NormRect(top.left, top.top, top.right, top.bottom),
    imageWidth: frame.imageWidth,
    imageHeight: frame.imageHeight,
    luminance: frame.luminance,
    reliableFlag: top.score >= voteMinScore,
  );
}

/// Provider của CurrencyController dùng Riverpod
final currencyControllerProvider =
    StateNotifierProvider<CurrencyController, CurrencyState>((ref) {
  final classifier = ref.watch(currencyClassifierProvider);
  final feedbackManager = ref.watch(feedbackManagerProvider);
  final hapticService = ref.watch(hapticServiceProvider);

  return CurrencyController(
    classifier: classifier,
    detector: ref.watch(currencyDetectorProvider),
    lighting: ref.watch(lightingMonitorProvider.notifier),
    history: ref.watch(historyProvider.notifier),
    feedbackManager: feedbackManager,
    hapticService: hapticService,
  );
});
