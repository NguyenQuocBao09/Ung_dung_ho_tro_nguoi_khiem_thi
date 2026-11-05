import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../core/camera/frame_converter.dart';
import '../domain/obstacle_classes.dart';
import '../domain/obstacle_detection.dart';
import '../domain/yolo_decoder.dart';

/// Kết quả xử lý một khung hình.
class ObstacleFrameResult {
  final List<ObstacleDetection> detections;

  /// Kích thước ảnh camera sau khi xoay về chiều đứng (để vẽ overlay đúng tỉ lệ).
  final int imageWidth;
  final int imageHeight;

  /// Độ sáng trung bình kênh Y (0..255), dùng phát hiện camera bị che / quá tối.
  final double luminance;

  final int preprocessMs;
  final int inferenceMs;
  final int totalMs;

  const ObstacleFrameResult({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.luminance,
    required this.preprocessMs,
    required this.inferenceMs,
    required this.totalMs,
  });
}

/// Phát hiện vật cản bằng YOLOv8n (COCO, Ultralytics) dạng TFLite.
///
/// Hợp đồng model (đã kiểm chứng bằng Python trên file trong `assets/models/`):
/// - Input: [1, S, S, 3] float32, RGB, 0..1, letterbox đệm 114.
/// - Output: [1, 84, N] float32 (4 toạ độ cx,cy,w,h theo PIXEL không gian model + 80 điểm lớp).
///
/// Toàn bộ tiền xử lý, suy luận và NMS chạy trong MỘT isolate nền, không chặn UI.
class ObstacleDetector {
  static const String modelPath = 'assets/models/obstacle_yolov8n.tflite';
  static const String labelsPath = 'assets/models/coco_labels.txt';

  /// Model xuất qua ONNX -> onnx2tf giữ toạ độ theo pixel không gian model.
  static const bool coordsNormalized = false;

  final double scoreThreshold;
  final double iouThreshold;

  ObstacleDetector({this.scoreThreshold = 0.4, this.iouThreshold = 0.5});

  Interpreter? _interpreter;
  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _receivePort;
  final Map<int, Completer<ObstacleFrameResult>> _pending = {};
  int _nextId = 0;
  Future<void>? _initFuture;

  List<String> _labels = const [];
  int _inputSize = 0;

  bool get isInitialized => _workerPort != null;
  List<String> get labels => _labels;
  int get inputSize => _inputSize;

  /// Khởi tạo một lần; các lần gọi sau trả về cùng Future. Ném lỗi nếu model/nhãn không hợp lệ.
  Future<void> initialize() => _initFuture ??= _initialize().catchError((Object e) {
        _initFuture = null;
        throw e;
      });

  Future<void> _initialize() async {
    final labelsData = await rootBundle.loadString(labelsPath);
    _labels = labelsData
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);

    final options = InterpreterOptions()..threads = 4;
    final interpreter = await Interpreter.fromAsset(modelPath, options: options);
    interpreter.allocateTensors();

    final inShape = interpreter.getInputTensor(0).shape;
    final outShape = interpreter.getOutputTensor(0).shape;
    if (inShape.length != 4 || inShape[1] != inShape[2] || inShape[3] != 3) {
      interpreter.close();
      throw StateError('Input tensor không đúng dạng [1,S,S,3]: $inShape');
    }
    if (outShape.length != 3 || outShape[1] != 4 + _labels.length) {
      interpreter.close();
      throw StateError(
        'Output tensor $outShape không khớp ${_labels.length} nhãn trong $labelsPath',
      );
    }
    _inputSize = inShape[1];
    _interpreter = interpreter;

    final allowed = <int>{
      for (var i = 0; i < _labels.length; i++)
        if (ObstacleClasses.of(_labels[i]) != null) i,
    };

    final receivePort = ReceivePort();
    _receivePort = receivePort;
    final portCompleter = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        portCompleter.complete(message);
      } else if (message is _WorkerResponse) {
        final c = _pending.remove(message.id);
        if (c == null) return;
        if (message.error != null) {
          c.completeError(StateError(message.error!));
        } else {
          c.complete(message.result!);
        }
      }
    });

    _isolate = await Isolate.spawn(
      _workerMain,
      _WorkerConfig(
        replyPort: receivePort.sendPort,
        interpreterAddress: interpreter.address,
        inputSize: _inputSize,
        numClasses: _labels.length,
        numAnchors: outShape[2],
        labels: _labels,
        allowedClasses: allowed,
        coordsNormalized: coordsNormalized,
        scoreThreshold: scoreThreshold,
        iouThreshold: iouThreshold,
      ),
      debugName: 'ObstacleDetectorWorker',
    );
    _workerPort = await portCompleter.future;
    debugPrint(
      'ObstacleDetector: sẵn sàng, input=$inShape output=$outShape, '
      '${allowed.length} lớp vật cản.',
    );
  }

  /// Phát hiện vật cản trên một khung hình camera (NV21 1 plane hoặc YUV420 3 plane).
  Future<ObstacleFrameResult> detect(CameraImage image, int rotationDegrees) async {
    await initialize();
    final port = _workerPort;
    if (port == null) throw StateError('ObstacleDetector chưa khởi tạo');

    final id = _nextId++;
    final completer = Completer<ObstacleFrameResult>();
    _pending[id] = completer;
    port.send(_WorkerRequest(
      id: id,
      width: image.width,
      height: image.height,
      rotationDegrees: rotationDegrees,
      planes: [
        for (final p in image.planes) TransferableTypedData.fromList([p.bytes]),
      ],
      rowStrides: [for (final p in image.planes) p.bytesPerRow],
      pixelStrides: [for (final p in image.planes) p.bytesPerPixel ?? 1],
    ));
    return completer.future;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    _receivePort?.close();
    _receivePort = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('ObstacleDetector đã đóng'));
    }
    _pending.clear();
    _interpreter?.close();
    _interpreter = null;
    _initFuture = null;
  }
}

// ---------------------------------------------------------------------------
// Isolate nền
// ---------------------------------------------------------------------------

class _WorkerConfig {
  final SendPort replyPort;
  final int interpreterAddress;
  final int inputSize;
  final int numClasses;
  final int numAnchors;
  final List<String> labels;
  final Set<int> allowedClasses;
  final bool coordsNormalized;
  final double scoreThreshold;
  final double iouThreshold;

  const _WorkerConfig({
    required this.replyPort,
    required this.interpreterAddress,
    required this.inputSize,
    required this.numClasses,
    required this.numAnchors,
    required this.labels,
    required this.allowedClasses,
    required this.coordsNormalized,
    required this.scoreThreshold,
    required this.iouThreshold,
  });
}

class _WorkerRequest {
  final int id;
  final int width;
  final int height;
  final int rotationDegrees;
  final List<TransferableTypedData> planes;
  final List<int> rowStrides;
  final List<int> pixelStrides;

  const _WorkerRequest({
    required this.id,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.planes,
    required this.rowStrides,
    required this.pixelStrides,
  });
}

class _WorkerResponse {
  final int id;
  final ObstacleFrameResult? result;
  final String? error;
  const _WorkerResponse(this.id, {this.result, this.error});
}

Future<void> _workerMain(_WorkerConfig cfg) async {
  final port = ReceivePort();
  cfg.replyPort.send(port.sendPort);

  final interpreter = Interpreter.fromAddress(cfg.interpreterAddress, allocated: true);
  final inputTensor = interpreter.getInputTensor(0);
  final outputTensor = interpreter.getOutputTensor(0);
  final input = Float32List(cfg.inputSize * cfg.inputSize * 3);
  final output = Float32List((4 + cfg.numClasses) * cfg.numAnchors);
  final outputBytes = output.buffer.asUint8List();
  final decoder = YoloDecoder(
    numClasses: cfg.numClasses,
    numAnchors: cfg.numAnchors,
    scoreThreshold: cfg.scoreThreshold,
    iouThreshold: cfg.iouThreshold,
    coordsNormalized: cfg.coordsNormalized,
    allowedClasses: cfg.allowedClasses,
  );

  await for (final msg in port) {
    if (msg is! _WorkerRequest) continue;
    try {
      final sw = Stopwatch()..start();
      final planes = [for (final p in msg.planes) p.materialize().asUint8List()];
      final YuvFrame frame;
      if (planes.length == 1) {
        frame = YuvFrame.fromNv21(
          bytes: planes[0],
          width: msg.width,
          height: msg.height,
          rowStride: msg.rowStrides[0],
          rotationDegrees: msg.rotationDegrees,
        );
      } else if (planes.length >= 3) {
        frame = YuvFrame(
          width: msg.width,
          height: msg.height,
          yBytes: planes[0],
          yRowStride: msg.rowStrides[0],
          uBytes: planes[1],
          vBytes: planes[2],
          uvRowStride: msg.rowStrides[1],
          uvPixelStride: msg.pixelStrides[1],
          rotationDegrees: msg.rotationDegrees,
        );
      } else {
        throw StateError('Định dạng khung hình không hỗ trợ (${planes.length} plane)');
      }

      final luminance = frame.averageLuminance();
      final lb = yuvToLetterboxedRgbFloat(frame, cfg.inputSize, out: input);
      final preMs = sw.elapsedMilliseconds;

      inputTensor.data = input.buffer.asUint8List();
      interpreter.invoke();
      outputBytes.setAll(0, outputTensor.data);
      final infMs = sw.elapsedMilliseconds - preMs;

      final dets = decoder.decode(output, cfg.labels, lb);
      cfg.replyPort.send(_WorkerResponse(
        msg.id,
        result: ObstacleFrameResult(
          detections: dets,
          imageWidth: frame.uprightWidth,
          imageHeight: frame.uprightHeight,
          luminance: luminance,
          preprocessMs: preMs,
          inferenceMs: infMs,
          totalMs: sw.elapsedMilliseconds,
        ),
      ));
    } catch (e) {
      cfg.replyPort.send(_WorkerResponse(msg.id, error: e.toString()));
    }
  }
}

final obstacleDetectorProvider = Provider<ObstacleDetector>((ref) {
  final detector = ObstacleDetector();
  ref.onDispose(detector.dispose);
  return detector;
});
