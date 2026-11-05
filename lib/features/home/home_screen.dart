import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accessibility/talkback_interaction_watcher.dart';
import '../../core/accessibility/voice_guide.dart';
import '../../core/camera/camera_service.dart';
import '../../core/constants/strings_vi.dart';
import '../../core/constants/ui_layout.dart';
import '../../core/feedback/feedback_manager.dart';
import '../../core/feedback/tts_service.dart';
import '../../core/mode/app_mode.dart';
import '../../core/mode/mode_controller.dart';
import '../../core/quality/lighting_monitor.dart';
import '../currency/presentation/currency_controller.dart';
import '../currency/presentation/currency_overlay.dart';
import '../obstacle/presentation/obstacle_controller.dart';
import '../obstacle/presentation/obstacle_overlay.dart';
import '../text_reading/presentation/reading_controller.dart';
import '../text_reading/presentation/reading_overlay.dart';
import 'quality_hint_provider.dart';
import 'recent_screen.dart';
import 'widgets/app_drawer.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  TalkBackInteractionWatcher? _talkBackWatcher;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // TalkBack chuyển tiêu điểm -> app tạm im để không nói đè lên TalkBack.
    _talkBackWatcher = TalkBackInteractionWatcher(
      onInteraction: () => ref.read(feedbackManagerProvider).holdForUserInteraction(),
      onActivate: () => ref.read(feedbackManagerProvider).releaseHold(),
    )..attach();

    // Khởi tạo camera khi màn hình sẵn sàng; lần đầu mở app thì đọc hướng dẫn
    // sau khi xong bước xin quyền camera (để không chồng với hộp thoại hệ thống).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(cameraStateProvider.notifier).initializeCamera();
      if (!mounted) return;
      if (await ref.read(voiceGuideProvider).shouldAutoPlay() && mounted) {
        _openGuide(firstRun: true);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Hướng dẫn bằng giọng nói
  //
  // Trong lúc đọc hướng dẫn, luồng camera của chế độ hiện tại được dừng để các
  // thông báo nhận diện không chen vào; đóng hướng dẫn thì bật lại.
  // ---------------------------------------------------------------------------
  bool _guideOpen = false;
  bool _guideInterrupted = false;
  BuildContext? _guideDialogContext;

  Future<void> _openGuide({bool firstRun = false}) async {
    if (_guideOpen) return;
    _guideOpen = true;
    _guideInterrupted = false;
    // Phải đợi dừng stream XONG rồi mới đọc: stopStream() của các chế độ gọi
    // clearQueue(), nếu chạy sau khi hướng dẫn đã vào hàng đợi sẽ huỷ các đoạn còn lại.
    final streamsStopped = Completer<void>();
    _queueStreamOp(() async {
      try {
        await _stopAllStreams();
      } finally {
        if (!streamsStopped.isCompleted) streamsStopped.complete();
      }
    });

    final feedback = ref.read(feedbackManagerProvider);
    final guide = ref.read(voiceGuideProvider);

    var dialogIsClosed = false;
    final dialogClosed = showDialog<void>(
      context: context,
      builder: (ctx) {
        _guideDialogContext = ctx;
        return _buildGuideDialog(ctx);
      },
    ).whenComplete(() => dialogIsClosed = true);
    // _queueStreamOp bỏ qua thao tác khi màn hình đã huỷ -> có giới hạn thời gian chờ.
    final played = streamsStopped.future
        .timeout(const Duration(seconds: 3), onTimeout: () {})
        .then<bool>((_) async => dialogIsClosed ? false : await guide.play(feedback))
        .then<bool>((completed) {
      // Đọc xong -> tự đóng hộp thoại.
      final ctx = _guideDialogContext;
      if (completed && ctx != null && ctx.mounted) Navigator.of(ctx).pop();
      return completed;
    });

    await dialogClosed;
    _guideDialogContext = null;
    // Người dùng đóng giữa chừng -> dừng đọc ngay.
    await feedback.stop();
    final completed = await played;

    // Nghe hết hoặc chủ động đóng thì không tự đọc lại ở lần mở sau;
    // bị gián đoạn do app vào nền thì lần sau vẫn đọc.
    if (firstRun && (completed || !_guideInterrupted)) {
      await guide.markDone();
    }
    _guideOpen = false;
    if (!mounted) return;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _restartStreamFor(ref.read(appModeProvider));
    }
  }

  void _closeGuide({bool interrupted = false}) {
    final ctx = _guideDialogContext;
    if (!_guideOpen || ctx == null || !ctx.mounted) return;
    if (interrupted) _guideInterrupted = true;
    Navigator.of(ctx).pop();
  }

  Widget _buildGuideDialog(BuildContext ctx) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text(
        StringsVi.infoDialogTitle,
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Text(
          StringsVi.voiceGuideSteps.join('\n\n'),
          style: const TextStyle(fontSize: 16, height: 1.4, color: Colors.white),
        ),
      ),
      actions: [
        Semantics(
          button: true,
          label: StringsVi.guideStopButton,
          hint: StringsVi.guideStopHint,
          excludeSemantics: true,
          child: TextButton(
            key: const ValueKey('guide_stop_button'),
            style: TextButton.styleFrom(minimumSize: const Size(160, 52)),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              StringsVi.guideStopButton,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF80D8FF)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _talkBackWatcher?.detach();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Mở lại app: chế độ đèn tự động hoạt động lại từ đầu.
      ref.read(cameraStateProvider.notifier).clearManualTorchOverride();
      // Khi quay lại từ Cài đặt hoặc đa nhiệm, thử khởi tạo lại máy ảnh
      final cameraStatus = ref.read(cameraStateProvider).status;
      if (cameraStatus != CameraStateStatus.ready) {
        ref.read(cameraStateProvider.notifier).initializeCamera();
      } else {
        _restartStreamFor(ref.read(appModeProvider));
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // Không đọc hướng dẫn khi app ở nền; lần mở sau (nếu là lần đầu) đọc lại.
      if (state != AppLifecycleState.inactive) _closeGuide(interrupted: true);
      _queueStreamOp(() async {
        await _stopAllStreams();
        // Không để đèn flash sáng khi app ở nền / khoá màn hình.
        if (mounted) await ref.read(lightingMonitorProvider.notifier).suspend();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Điều phối camera stream dùng chung (Single Camera Shell)
  //
  // camera_android chỉ dọn dẹp xong stream cũ SAU KHI lệnh dừng hoàn tất; nếu bật
  // stream mới trước lúc đó, phần dọn dẹp muộn sẽ xoá luôn bộ điều phối của stream
  // mới -> chế độ mới không nhận được khung hình nào. Vì vậy mọi thao tác dừng/bật
  // được xếp hàng tuần tự: dừng xong hẳn rồi mới bật.
  // ---------------------------------------------------------------------------
  Future<void> _streamQueue = Future<void>.value();

  void _queueStreamOp(Future<void> Function() op) {
    _streamQueue = _streamQueue.then((_) async {
      if (!mounted) return;
      await op();
    }).catchError((Object e) {
      debugPrint('HomeScreen: lỗi khi chuyển camera stream: $e');
    });
  }

  Future<void> _stopAllStreams() async {
    if (!mounted) return;
    await ref.read(readingControllerProvider.notifier).stopStream();
    await ref.read(currencyControllerProvider.notifier).stopStream();
    await ref.read(obstacleControllerProvider.notifier).stopStream();
  }

  /// Dừng hẳn mọi stream rồi bật stream cho [mode] (nếu camera sẵn sàng và mode vẫn đang chọn).
  void _restartStreamFor(AppMode mode) {
    _queueStreamOp(() async {
      await _stopAllStreams();
      if (!mounted) return;
      final cam = ref.read(cameraStateProvider);
      final controller = cam.controller;
      if (cam.status != CameraStateStatus.ready || controller == null) return;
      if (ref.read(appModeProvider) != mode) return; // người dùng đã đổi chế độ khác
      if (_guideOpen) return; // đang đọc hướng dẫn; đóng hướng dẫn sẽ bật lại
      switch (mode) {
        case AppMode.reading:
          await ref.read(readingControllerProvider.notifier).startStream(controller);
          break;
        case AppMode.currency:
          await ref.read(currencyControllerProvider.notifier).startStream(controller);
          break;
        case AppMode.obstacle:
          await ref.read(obstacleControllerProvider.notifier).startStream(controller);
          break;
      }
    });
  }

  void _handleCapture() {
    final currentMode = ref.read(appModeProvider);
    final isTalkBackOn = MediaQuery.accessibleNavigationOf(context);

    if (currentMode == AppMode.reading) {
      ref.read(readingControllerProvider.notifier).togglePause();
      return;
    }

    if (currentMode == AppMode.currency) {
      ref.read(currencyControllerProvider.notifier).togglePause();
      return;
    }

    if (currentMode == AppMode.obstacle) {
      ref.read(obstacleControllerProvider.notifier).togglePause();
      return;
    }

    if (isTalkBackOn) {
      // Khi bật TalkBack, thông báo trực tiếp qua SemanticsService của hệ thống
      SemanticsService.sendAnnouncement(
        View.of(context),
        StringsVi.capturingText,
        TextDirection.ltr,
      );
    } else {
      // Khi tắt TalkBack, phát âm thanh TTS
      ref.read(ttsServiceProvider).speak(StringsVi.capturingText);
    }
  }

  void _announceFeedback(String message) {
    final isTalkBackOn = MediaQuery.accessibleNavigationOf(context);
    if (isTalkBackOn) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        TextDirection.ltr,
      );
    } else {
      ref.read(ttsServiceProvider).speak(message);
    }
  }

  void _repeatFeedback() {
    final currentHint = ref.read(qualityHintProvider);
    final currentMode = ref.read(appModeProvider);
    final message = currentHint != null && currentHint.isNotEmpty
        ? '${currentMode.title}. $currentHint'
        : currentMode.title;
    _announceFeedback(message);
  }

  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(appModeProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final qualityHint = ref.watch(qualityHintProvider);
    final isTalkBackOn = MediaQuery.accessibleNavigationOf(context);

    // Lắng nghe thay đổi chế độ hoạt động để làm mới nhận diện
    ref.listen<AppMode>(appModeProvider, (previous, next) {
      if (previous != next) {
        // Cắt ngay lời đang đọc của chế độ cũ (vd. đoạn văn bản dài) để không phát
        // sang chế độ mới. Chạy đồng bộ khi đổi chế độ, trước lời thông báo tên chế độ.
        ref.read(feedbackManagerProvider).stop();
        ref.read(currencyControllerProvider.notifier).reset();
        _restartStreamFor(next);
      }
    });

    // Thông báo "Ánh sáng yếu" được LightingMonitor đọc qua FeedbackManager
    // (một lần khi chuyển sang tối), nên ở đây chỉ hiển thị.

    // Lắng nghe trạng thái từ chối quyền camera để đọc TTS hướng dẫn khi TalkBack tắt
    ref.listen<CameraState>(cameraStateProvider, (previous, next) {
      // Chỉ (re)start stream khi camera VỪA sẵn sàng hoặc đổi controller,
      // không phải mỗi lần state thay đổi (vd. bật/tắt đèn pin).
      final becameReady = next.status == CameraStateStatus.ready &&
          next.controller != null &&
          (previous?.status != CameraStateStatus.ready ||
              previous?.controller != next.controller);
      if (becameReady) {
        // Controller camera mới (đèn đang tắt) -> đo ánh sáng lại từ đầu.
        ref.read(lightingMonitorProvider.notifier).suspend();
        _restartStreamFor(ref.read(appModeProvider));
      }

      if (!isTalkBackOn) {
        if (next.status == CameraStateStatus.permissionDenied ||
            next.status == CameraStateStatus.permissionPermanentlyDenied) {
          ref.read(ttsServiceProvider).speak(StringsVi.cameraPermissionDeniedMessage);
        }
      }
    });

    return Scaffold(
      drawer: const AppDrawer(),
      // 1. THANH TRÊN (AppBar nền tối, tiêu đề là tên chế độ hiện tại)
      appBar: AppBar(
        leading: Builder(
          builder: (scaffoldContext) {
            return Semantics(
              label: StringsVi.menuButton,
              button: true,
              sortKey: const OrdinalSortKey(1.0),
              child: IconButton(
                icon: const Icon(Icons.menu),
                tooltip: StringsVi.menuButton,
                onPressed: () {
                  Scaffold.of(scaffoldContext).openDrawer();
                },
              ),
            );
          },
        ),
        title: Semantics(
          header: true,
          sortKey: const OrdinalSortKey(1.1),
          child: Text(
            currentMode.title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        actions: [
          Semantics(
            label: StringsVi.infoButton,
            button: true,
            sortKey: const OrdinalSortKey(1.2),
            child: IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: StringsVi.infoButton,
              onPressed: () => _openGuide(),
            ),
          ),
        ],
      ),

      // 2. VÙNG GIỮA: Camera Preview đúng tỉ lệ + 3. Quality Pill + 4. Nút chụp tròn
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Vùng hiển thị camera chiếm toàn bộ khoảng trống
          _buildCameraView(context, cameraState, currentMode),

          // Lớp phủ thông tin nhận diện tiền tệ khi ở chế độ Tiền tệ
          if (currentMode == AppMode.currency)
            const CurrencyOverlay(),

          // Lớp phủ thông tin nhận diện đọc chữ khi ở chế độ Đọc chữ
          if (currentMode == AppMode.reading)
            const ReadingOverlay(),

          // Lớp phủ cảnh báo vật cản
          if (currentMode == AppMode.obstacle)
            const ObstacleOverlay(),

          // 3. THÔNG BÁO DẠNG VIÊN THUỐC (Pill) ngay trên nút Tạm dừng/Tiếp tục
          // (nút chính nằm giữa phía dưới, do lớp phủ của từng chế độ vẽ).
          if (qualityHint != null && qualityHint.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: UiLayout.hintPillBottom,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _buildQualityPill(qualityHint),
              ),
            ),
        ],
      ),

      // 5. THANH ĐIỀU HƯỚNG DƯỚI (NavigationBar có 2 mục: Xem & Gần đây)
      bottomNavigationBar: Semantics(
        sortKey: const OrdinalSortKey(2.0),
        child: NavigationBar(
          selectedIndex: 0,
          onDestinationSelected: (index) {
            if (index == 1) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const RecentScreen(),
                ),
              );
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.visibility),
              label: StringsVi.navView,
            ),
            NavigationDestination(
              icon: Icon(Icons.history),
              label: StringsVi.navRecent,
            ),
          ],
        ),
      ),
    );
  }

  /// Xây dựng vùng Kính ngắm máy ảnh với Semantics và Custom Actions cho TalkBack
  Widget _buildCameraView(
    BuildContext context,
    CameraState cameraState,
    AppMode currentMode,
  ) {
    // Custom Actions cho TalkBack để chuyển chế độ và đọc lại
    final customSemanticsActions = <CustomSemanticsAction, VoidCallback>{
      for (final mode in AppMode.values.where((m) => m != currentMode))
        CustomSemanticsAction(label: mode.switchActionLabel): () {
          ref.read(appModeProvider.notifier).setMode(mode);
          _announceFeedback(mode.title);
        },
      if (currentMode == AppMode.reading)
        const CustomSemanticsAction(label: StringsVi.actionRestartReading): () {
          ref.read(readingControllerProvider.notifier).resetSession();
          _announceFeedback(StringsVi.actionRestartReading);
        },
      if (currentMode == AppMode.currency) ...{
        const CustomSemanticsAction(label: StringsVi.actionReadAgain): () {
          ref.read(currencyControllerProvider.notifier).readAgain();
        },
        const CustomSemanticsAction(label: StringsVi.actionNewBill): () {
          ref.read(currencyControllerProvider.notifier).newBill();
          _announceFeedback(StringsVi.actionNewBill);
        },
      },
      if (currentMode == AppMode.obstacle)
        const CustomSemanticsAction(label: StringsVi.actionReadScene): () {
          ref.read(obstacleControllerProvider.notifier).readScene();
        },
      const CustomSemanticsAction(label: StringsVi.actionRepeatFeedback): () {
        _repeatFeedback();
      },
    };

    Widget content;

    switch (cameraState.status) {
      case CameraStateStatus.initial:
      case CameraStateStatus.checkingPermission:
      case CameraStateStatus.initializing:
        content = Container(
          color: Colors.black,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF80D8FF)),
                SizedBox(height: 16),
                Text(
                  StringsVi.cameraLoading,
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
        break;

      case CameraStateStatus.permissionDenied:
      case CameraStateStatus.permissionPermanentlyDenied:
        content = Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.no_photography,
                  size: 64,
                  color: Color(0xFFFF5252),
                ),
                const SizedBox(height: 16),
                const Text(
                  StringsVi.cameraPermissionRequiredTitle,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  StringsVi.cameraPermissionDeniedMessage,
                  style: TextStyle(fontSize: 16, color: Colors.white70, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF80D8FF),
                    foregroundColor: const Color(0xFF00364A),
                    minimumSize: const Size(200, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.settings),
                  label: const Text(
                    StringsVi.openSettingsButton,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    ref.read(cameraStateProvider.notifier).openSettings();
                  },
                ),
                const SizedBox(height: 12),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(160, 48),
                    foregroundColor: Colors.white70,
                  ),
                  onPressed: () {
                    ref.read(cameraStateProvider.notifier).initializeCamera();
                  },
                  child: const Text(
                    StringsVi.retryPermissionButton,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        );
        break;

      case CameraStateStatus.error:
        content = Container(
          color: Colors.black,
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 60, color: Color(0xFFFF5252)),
                const SizedBox(height: 16),
                const Text(
                  StringsVi.cameraError,
                  style: TextStyle(fontSize: 16, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(160, 48),
                    backgroundColor: const Color(0xFF80D8FF),
                    foregroundColor: const Color(0xFF00364A),
                  ),
                  onPressed: () {
                    ref.read(cameraStateProvider.notifier).initializeCamera();
                  },
                  child: const Text(StringsVi.retryPermissionButton),
                ),
              ],
            ),
          ),
        );
        break;

      case CameraStateStatus.ready:
        final controller = cameraState.controller!;
        content = LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            // Tính toán hệ số co giãn để camera hiển thị đúng tỉ lệ và lấp đầy khung hình không méo
            var scale = size.aspectRatio * controller.value.aspectRatio;
            if (scale < 1) scale = 1 / scale;

            return ClipRect(
              child: Transform.scale(
                scale: scale,
                child: Center(
                  child: CameraPreview(controller),
                ),
              ),
            );
          },
        );
        break;
    }

    // Bọc toàn bộ vùng camera bằng Semantics nút lớn "Chụp ảnh"
    // Được focus đầu tiên khi mở màn hình với sortKey: 0.0
    return Semantics(
      label: StringsVi.cameraViewfinderLabel,
      hint: StringsVi.cameraViewfinderHint,
      button: true,
      sortKey: const OrdinalSortKey(0.0),
      customSemanticsActions: customSemanticsActions,
      onTap: _handleCapture,
      child: content,
    );
  }

  /// Thông báo dạng viên thuốc (Pill) dưới giữa vùng camera
  Widget _buildQualityPill(String hintText) {
    return Semantics(
      // Không dùng liveRegion: LightingMonitor đã đọc thông báo qua FeedbackManager,
      // tránh TalkBack đọc trùng.
      label: '${StringsVi.qualityPillLabel} $hintText',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xDD1C1C1E), // Nền tối sẫm bán trong suốt
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: const Color(0xFF48484A),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFF2C3E50),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.visibility,
                size: 18,
                color: Color(0xFF80D8FF),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                hintText,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
