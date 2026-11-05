import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings_vi.dart';
import '../../../core/feedback/feedback_manager.dart';
import '../../../core/history/history_entry.dart';
import '../../../core/history/history_notifier.dart';
import '../../../core/feedback/feedback_message.dart';
import '../../../core/quality/lighting_monitor.dart';
import '../data/mlkit_ocr_engine.dart';
import '../domain/read_session.dart';
import '../domain/text_postprocessor.dart';

/// Trạng thái của tính năng đọc chữ tự động
class ReadingState {
  final bool isStreaming;
  final bool isPaused;
  final bool isBusy;
  final List<String> currentLines;
  final List<String> readLines;
  final String? lastSpokenText;
  final bool isLowLight;
  final String? errorMessage;

  /// Khung bao các khối văn bản trên khung hình gần nhất (toạ độ 0..1 ảnh đứng).
  final List<TextBlockBox> blocks;

  /// Kích thước ảnh đứng để ánh xạ khung bao lên preview.
  final int imageWidth;
  final int imageHeight;

  const ReadingState({
    this.isStreaming = false,
    this.isPaused = false,
    this.isBusy = false,
    this.currentLines = const [],
    this.readLines = const [],
    this.lastSpokenText,
    this.isLowLight = false,
    this.errorMessage,
    this.blocks = const [],
    this.imageWidth = 0,
    this.imageHeight = 0,
  });

  ReadingState copyWith({
    bool? isStreaming,
    bool? isPaused,
    bool? isBusy,
    List<String>? currentLines,
    List<String>? readLines,
    String? lastSpokenText,
    bool? isLowLight,
    String? errorMessage,
    bool clearError = false,
    List<TextBlockBox>? blocks,
    int? imageWidth,
    int? imageHeight,
  }) {
    return ReadingState(
      isStreaming: isStreaming ?? this.isStreaming,
      isPaused: isPaused ?? this.isPaused,
      isBusy: isBusy ?? this.isBusy,
      currentLines: currentLines ?? this.currentLines,
      readLines: readLines ?? this.readLines,
      lastSpokenText: lastSpokenText ?? this.lastSpokenText,
      isLowLight: isLowLight ?? this.isLowLight,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      blocks: blocks ?? this.blocks,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
    );
  }
}

/// Controller quản lý luồng đọc chữ tự động (Google Lookout style)
class ReadingController extends StateNotifier<ReadingState> {
  final MlkitOcrEngine _ocrEngine;
  final FeedbackManager _feedbackManager;
  final ReadSession _session;

  CameraController? _cameraController;
  bool _busy = false;
  DateTime? _lastFrameProcessedTime;
  DateTime? _streamStartedTime;
  DateTime? _lastNoTextPromptTime;
  DateTime? _lastEdgePromptTime;
  final LightingMonitor? _lighting;
  final HistoryNotifier? _history;

  /// Hằng số điều chỉnh tần suất xử lý khung hình (bỏ khung nếu < 600 ms)
  static const Duration frameThrottleDuration = Duration(milliseconds: 600);

  ReadingController({
    required MlkitOcrEngine ocrEngine,
    required FeedbackManager feedbackManager,
    ReadSession? session,
    LightingMonitor? lighting,
    HistoryNotifier? history,
  })  : _ocrEngine = ocrEngine,
        _history = history,
        _feedbackManager = feedbackManager,
        _session = session ?? ReadSession(),
        _lighting = lighting,
        super(const ReadingState());

  ReadSession get session => _session;

  /// Bắt đầu nhận luồng ảnh liên tục từ camera
  Future<void> startStream(CameraController controller) async {
    if (state.isStreaming && _cameraController == controller) {
      return;
    }

    _cameraController = controller;

    if (!controller.value.isInitialized) {
      debugPrint('ReadingController: Camera chưa khởi tạo sẵn sàng.');
      return;
    }

    // Nếu camera đang stream rồi thì không gọi startImageStream lần hai
    if (controller.value.isStreamingImages) {
      state = state.copyWith(isStreaming: true, isPaused: false);
      return;
    }

    try {
      _streamStartedTime = DateTime.now();
      _lastFrameProcessedTime = null;
      _lastNoTextPromptTime = null;
      _busy = false;

      await controller.startImageStream(_onCameraFrame);
      state = state.copyWith(isStreaming: true, isPaused: false);
      debugPrint('ReadingController: Đã bắt đầu luồng đọc chữ tự động.');
    } catch (e) {
      debugPrint('ReadingController: Lỗi khi khởi động image stream: $e');
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  /// Dừng luồng ảnh camera
  Future<void> stopStream() async {
    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      try {
        await _cameraController!.stopImageStream();
      } catch (e) {
        debugPrint('ReadingController: Lỗi khi dừng image stream: $e');
      }
    }
    _cameraController = null;
    _busy = false;
    _feedbackManager.clearQueue();
    if (mounted) {
      state = state.copyWith(isStreaming: false);
    }
  }

  /// Tạm dừng hoặc tiếp tục tự đọc
  Future<void> togglePause() async {
    if (state.isPaused) {
      await resume();
    } else {
      await pause();
    }
  }

  /// Tạm dừng tự đọc
  Future<void> pause() async {
    if (state.isPaused) return;
    state = state.copyWith(isPaused: true);
    await _feedbackManager.stop();
    await _feedbackManager.speak(
      StringsVi.readingPausedNotice,
      priority: FeedbackPriority.urgent,
    );
  }

  /// Tiếp tục tự đọc
  Future<void> resume() async {
    if (!state.isPaused) return;
    state = state.copyWith(isPaused: false);
    _lastFrameProcessedTime = null;
    _streamStartedTime = DateTime.now();
    await _feedbackManager.speak(
      StringsVi.readingResumedNotice,
      priority: FeedbackPriority.urgent,
    );
  }

  /// Đọc lại từ đầu (Custom Semantics Action)
  void resetSession() {
    _session.reset();
    _feedbackManager.clearQueue();
    _streamStartedTime = DateTime.now();
    _lastNoTextPromptTime = null;
    state = state.copyWith(
      currentLines: const [],
      readLines: const [],
      lastSpokenText: null,
      blocks: const [],
    );
  }

  /// Callback nhận từng khung hình từ camera
  void _onCameraFrame(CameraImage image) {
    // Đo ánh sáng / bật đèn flash tự động (tự điều tiết, rất nhẹ).
    _lighting?.onFrame(image);
    if (state.isPaused) return;

    final now = DateTime.now();

    // 1. Bỏ khung nếu đang bận xử lý khung trước hoặc cách lần trước < 600 ms
    if (_busy) return;
    if (_lastFrameProcessedTime != null &&
        now.difference(_lastFrameProcessedTime!) < frameThrottleDuration) {
      return;
    }

    _busy = true;
    _lastFrameProcessedTime = now;

    _processFrame(image, now);
  }

  /// Xử lý khung hình nhận diện OCR
  Future<void> _processFrame(CameraImage image, DateTime now) async {
    try {
      final cameraDesc = _cameraController?.description;
      if (cameraDesc == null) {
        return;
      }

      // 1. Ánh sáng yếu: do LightingMonitor dùng chung xử lý (xem _onCameraFrame).

      // 2. Chuyển đổi sang InputImage NV21
      final inputImage = toInputImage(image, cameraDesc);
      if (inputImage == null) {
        return;
      }

      // 3. Nhận dạng ký tự quang học qua ML Kit
      final sw = Stopwatch()..start();
      final recognizedText = await _ocrEngine.processImage(inputImage);
      final ocrMs = sw.elapsedMilliseconds;
      if (!mounted || state.isPaused) return;
      final rawLines = _ocrEngine.extractLines(recognizedText);

      // 4. Đưa vào ReadSession: theo dõi từng dòng qua nhiều khung, chọn biến thể
      // ổn định nhất, đọc theo thứ tự khi các dòng đang thấy đã ổn định.
      final rotated = cameraDesc.sensorOrientation % 180 == 90;
      final uprightW = rotated ? image.height : image.width;
      final uprightH = rotated ? image.width : image.height;
      final result = _session.onFrame(
        _ocrEngine.extractOcrLines(
          recognizedText,
          uprightWidth: uprightW.toDouble(),
          uprightHeight: uprightH.toDouble(),
        ),
        now,
      );
      // Chỉ số đếm/thời gian, không ghi nội dung văn bản.
      debugPrint('ReadingController: ${image.width}x${image.height}, OCR ${ocrMs}ms, '
          '${rawLines.length} dòng, ${result.edgeCutLines} chạm mép, '
          'đọc ${result.paragraphs.length} đoạn');

      state = state.copyWith(
        currentLines: rawLines,
        readLines: _session.readLines,
        blocks: result.blocks,
        imageWidth: uprightW,
        imageHeight: uprightH,
      );

      // Chữ bị cắt ở mép mà không có dòng nào đọc được trọn -> hướng dẫn lùi máy.
      if (result.edgeCutLines > 0 && result.visibleLines == 0) {
        if (_lastEdgePromptTime == null ||
            now.difference(_lastEdgePromptTime!) >= const Duration(seconds: 8)) {
          _lastEdgePromptTime = now;
          unawaited(_feedbackManager.speak(
            StringsVi.hintTextCutAtEdge,
            priority: FeedbackPriority.info,
          ));
        }
      }
      final linesToRead = result.paragraphs;

      // 5. Xóa hàng đợi khi mất chữ > 3 giây
      final lastSeen = _session.lastSeenTextTime;
      if (rawLines.isEmpty) {
        if (lastSeen != null &&
            now.difference(lastSeen) >= const Duration(seconds: 3)) {
          _feedbackManager.clearQueue();
        }
      }

      // 6. Hướng dẫn giọng nói: sau 6 giây chưa thấy chữ
      final referenceTime = lastSeen ?? _streamStartedTime;
      if (referenceTime != null &&
          now.difference(referenceTime) >= const Duration(seconds: 6)) {
        if (_lastNoTextPromptTime == null ||
            now.difference(_lastNoTextPromptTime!) >= const Duration(seconds: 8)) {
          _lastNoTextPromptTime = now;
          await _feedbackManager.speak(
            StringsVi.hintNoTextFound,
            priority: FeedbackPriority.info,
          );
        }
      }

      // 7. Đưa kết quả cho FeedbackManager phát âm thanh (ghép bằng ". ")
      // Đoạn tiếng Anh được tách ra để đọc bằng giọng en-US (nếu máy có).
      if (linesToRead.isNotEmpty) {
        final segments = TextPostprocessor.buildSpeechSegments(linesToRead);
        final spokenJoined = segments.map((s) => s.text).join(' ');
        state = state.copyWith(lastSpokenText: spokenJoined);
        _history?.add(HistoryType.reading, spokenJoined);
        debugPrint('ReadingController: đọc ${segments.length} đoạn ngôn ngữ '
            '(${segments.map((s) => s.language).join(', ')})');
        unawaited(_feedbackManager.speakSegments(
          segments,
          priority: FeedbackPriority.normal,
        ));
      }
    } catch (e) {
      debugPrint('ReadingController: Lỗi trong quá trình xử lý khung hình: $e');
    } finally {
      _busy = false;
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
    _ocrEngine.close();
    super.dispose();
  }
}

final readingControllerProvider =
    StateNotifierProvider<ReadingController, ReadingState>((ref) {
  final ocrEngine = ref.watch(mlkitOcrEngineProvider);
  final feedbackManager = ref.watch(feedbackManagerProvider);

  return ReadingController(
    ocrEngine: ocrEngine,
    feedbackManager: feedbackManager,
    lighting: ref.watch(lightingMonitorProvider.notifier),
    history: ref.watch(historyProvider.notifier),
  );
});
