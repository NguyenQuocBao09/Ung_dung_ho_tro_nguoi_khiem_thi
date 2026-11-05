import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

enum CameraStateStatus {
  initial,
  checkingPermission,
  permissionDenied,
  permissionPermanentlyDenied,
  initializing,
  ready,
  error,
}

class CameraState {
  final CameraStateStatus status;
  final CameraController? controller;
  final String? errorMessage;
  final bool isTorchOn;

  const CameraState({
    required this.status,
    this.controller,
    this.errorMessage,
    this.isTorchOn = false,
  });

  factory CameraState.initial() => const CameraState(status: CameraStateStatus.initial);

  CameraState copyWith({
    CameraStateStatus? status,
    CameraController? controller,
    String? errorMessage,
    bool? isTorchOn,
  }) {
    return CameraState(
      status: status ?? this.status,
      controller: controller ?? this.controller,
      errorMessage: errorMessage ?? this.errorMessage,
      isTorchOn: isTorchOn ?? this.isTorchOn,
    );
  }
}

class CameraControllerNotifier extends StateNotifier<CameraState> {
  CameraControllerNotifier() : super(CameraState.initial());

  CameraController? _controller;
  Future<void>? _initInFlight;

  /// Khởi tạo camera. Nếu đang có một lần khởi tạo chạy dở (vd. vừa gọi từ initState
  /// vừa gọi từ sự kiện lifecycle `resumed` lúc mở app), trả về chính lần đó thay vì
  /// khởi tạo song song — tránh huỷ controller đang khởi tạo và báo "ready" nhầm.
  Future<void> initializeCamera() {
    return _initInFlight ??= _initializeCamera().whenComplete(() {
      _initInFlight = null;
    });
  }

  Future<void> _initializeCamera() async {
    state = state.copyWith(status: CameraStateStatus.checkingPermission);

    try {
      final permissionStatus = await Permission.camera.status;
      if (!mounted) return;

      if (permissionStatus.isPermanentlyDenied) {
        state = state.copyWith(status: CameraStateStatus.permissionPermanentlyDenied);
        return;
      }

      if (!permissionStatus.isGranted) {
        final requestResult = await Permission.camera.request();
        if (!mounted) return;

        if (requestResult.isPermanentlyDenied) {
          state = state.copyWith(status: CameraStateStatus.permissionPermanentlyDenied);
          return;
        }
        if (!requestResult.isGranted) {
          state = state.copyWith(status: CameraStateStatus.permissionDenied);
          return;
        }
      }

      state = state.copyWith(status: CameraStateStatus.initializing);

      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        state = state.copyWith(
          status: CameraStateStatus.error,
          errorMessage: 'Không tìm thấy camera trên thiết bị.',
        );
        return;
      }

      // Ưu tiên camera sau
      final backCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final old = _controller;
      _controller = null;
      await old?.dispose();

      final controller = CameraController(
        backCamera,
        // high (~1280x720): chữ trong đoạn văn ở medium (720x480) chỉ cao vài
        // pixel nên ML Kit đọc sai/nhảy chữ. Model tiền/vật cản tự resize về
        // 640x640 nên không phụ thuộc độ phân giải này.
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      _controller = controller;

      await controller.initialize();
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}

      if (!mounted) {
        await controller.dispose();
        return;
      }

      // Chỉ báo "ready" với đúng controller vừa khởi tạo xong.
      state = CameraState(
        status: CameraStateStatus.ready,
        controller: controller,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        status: CameraStateStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }

  /// Người dùng đã tự bật/tắt đèn bằng nút → chế độ tự động không can thiệp
  /// cho đến khi app vào nền rồi mở lại ([clearManualTorchOverride]).
  bool _manualTorchOverride = false;
  bool get manualTorchOverride => _manualTorchOverride;
  void clearManualTorchOverride() => _manualTorchOverride = false;

  /// Bật / Tắt đèn pin (Torch) bằng tay
  Future<void> toggleTorch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _manualTorchOverride = true;
    await setTorch(!state.isTorchOn);
  }

  /// Bật/tắt đèn flash (chế độ torch). Trả về true nếu thành công; false nếu
  /// camera chưa sẵn sàng hoặc thiết bị không có đèn flash.
  Future<bool> setTorch(bool on) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return false;
    if (state.isTorchOn == on && c.value.flashMode == (on ? FlashMode.torch : FlashMode.off)) {
      return true;
    }
    try {
      await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      if (mounted && identical(c, _controller)) state = state.copyWith(isTorchOn: on);
      return true;
    } catch (e) {
      // Thiết bị không hỗ trợ đèn flash hoặc camera đang đóng.
      return false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

final cameraStateProvider =
    StateNotifierProvider<CameraControllerNotifier, CameraState>((ref) {
  return CameraControllerNotifier();
});
