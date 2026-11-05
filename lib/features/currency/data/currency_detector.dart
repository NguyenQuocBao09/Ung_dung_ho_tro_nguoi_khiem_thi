import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../core/camera/frame_converter.dart';
// Dùng chung bộ giải mã YOLO và kiểu kết quả với chế độ vật cản (cùng định dạng YOLOv8).
import '../../obstacle/domain/obstacle_detection.dart';
import '../../obstacle/domain/yolo_decoder.dart';

/// Kết quả phát hiện tiền trên một khung hình.
class CurrencyDetectionFrame {
  /// Các khung tiền, sắp xếp giảm dần theo điểm (toạ độ chuẩn hoá 0..1 trong ảnh đứng).
  final List<ObstacleDetection> detections;
  final int imageWidth;
  final int imageHeight;
  final double luminance;
  final int totalMs;

  const CurrencyDetectionFrame({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.luminance,
    required this.totalMs,
  });
}

/// Phát hiện + phân loại mệnh giá tiền VND bằng YOLOv8n (huấn luyện trong
/// `ml_training/notebooks/train_currency_yolo.ipynb`).
///
/// Hợp đồng model (đã kiểm chứng bằng Python, TFLite khớp PyTorch 128/130 ảnh test):
/// - Input: [1, 640, 640, 3] float32, RGB 0..1, letterbox đệm 114.
/// - Output: [1, 4 + 9, 8400]; toạ độ cx,cy,w,h theo PIXEL không gian model; 9 điểm lớp.
/// - Nhãn theo chỉ số: `assets/models/currency_yolo_labels.txt` (1k, 10k, 100k, 2k, ...).
class CurrencyDetector {
  static const String modelPath = 'assets/models/currency_yolov8n.tflite';
  static const String labelsPath = 'assets/models/currency_yolo_labels.txt';
  static const bool coordsNormalized = false;

  /// Ngưỡng giữ khung để hiển thị (khung vàng "đang nhận diện").
  final double scoreThreshold;
  final double iouThreshold;

  CurrencyDetector({this.scoreThreshold = 0.35, this.iouThreshold = 0.5});

  Interpreter? _interpreter;
  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _receivePort;
  final Map<int, Completer<_Response>> _pending = {};
  int _nextId = 0;
  Future<void>? _initFuture;
  List<String> _labels = const [];

  List<String> get labels => _labels;
  bool get isInitialized => _workerPort != null;

  /// Khởi tạo một lần; ném lỗi nếu thiếu model hoặc model không khớp nhãn.
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

    final interpreter = await Interpreter.fromAsset(
      modelPath,
      options: InterpreterOptions()..threads = 4,
    );
    interpreter.allocateTensors();
    final inShape = interpreter.getInputTensor(0).shape;
    final outShape = interpreter.getOutputTensor(0).shape;
    if (inShape.length != 4 || inShape[1] != inShape[2] || inShape[3] != 3) {
      interpreter.close();
      throw StateError('Input tensor không đúng dạng [1,S,S,3]: $inShape');
    }
    if (outShape.length != 3 || outShape[1] != 4 + _labels.length) {
      interpreter.close();
      throw StateError('Output $outShape không khớp ${_labels.length} nhãn trong $labelsPath');
    }
    _interpreter = interpreter;

    final receivePort = ReceivePort();
    _receivePort = receivePort;
    final portCompleter = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        portCompleter.complete(message);
      } else if (message is _Response) {
        _pending.remove(message.id)?.complete(message);
      }
    });
    _isolate = await Isolate.spawn(
      _workerMain,
      _Config(
        replyPort: receivePort.sendPort,
        interpreterAddress: interpreter.address,
        inputSize: inShape[1],
        numClasses: _labels.length,
        numAnchors: outShape[2],
        labels: _labels,
        scoreThreshold: scoreThreshold,
        iouThreshold: iouThreshold,
      ),
      debugName: 'CurrencyDetectorWorker',
    );
    _workerPort = await portCompleter.future;
    debugPrint('CurrencyDetector: sẵn sàng, input=$inShape output=$outShape.');
  }

  Future<CurrencyDetectionFrame> detect(CameraImage image, int rotationDegrees) async {
    await initialize();
    final port = _workerPort;
    if (port == null) throw StateError('CurrencyDetector chưa khởi tạo');
    final id = _nextId++;
    final completer = Completer<_Response>();
    _pending[id] = completer;
    port.send(_Request(
      id: id,
      width: image.width,
      height: image.height,
      rotationDegrees: rotationDegrees,
      planes: [for (final p in image.planes) TransferableTypedData.fromList([p.bytes])],
      rowStrides: [for (final p in image.planes) p.bytesPerRow],
      pixelStrides: [for (final p in image.planes) p.bytesPerPixel ?? 1],
    ));
    final r = await completer.future;
    if (r.error != null) throw StateError(r.error!);
    return r.frame!;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    _receivePort?.close();
    _receivePort = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(const _Response(-1, error: 'CurrencyDetector đã đóng'));
    }
    _pending.clear();
    _interpreter?.close();
    _interpreter = null;
    _initFuture = null;
  }
}

class _Config {
  final SendPort replyPort;
  final int interpreterAddress;
  final int inputSize;
  final int numClasses;
  final int numAnchors;
  final List<String> labels;
  final double scoreThreshold;
  final double iouThreshold;

  const _Config({
    required this.replyPort,
    required this.interpreterAddress,
    required this.inputSize,
    required this.numClasses,
    required this.numAnchors,
    required this.labels,
    required this.scoreThreshold,
    required this.iouThreshold,
  });
}

class _Request {
  final int id;
  final int width;
  final int height;
  final int rotationDegrees;
  final List<TransferableTypedData> planes;
  final List<int> rowStrides;
  final List<int> pixelStrides;

  const _Request({
    required this.id,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.planes,
    required this.rowStrides,
    required this.pixelStrides,
  });
}

class _Response {
  final int id;
  final CurrencyDetectionFrame? frame;
  final String? error;
  const _Response(this.id, {this.frame, this.error});
}

Future<void> _workerMain(_Config cfg) async {
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
    coordsNormalized: CurrencyDetector.coordsNormalized,
    maxDetections: 5,
  );

  await for (final msg in port) {
    if (msg is! _Request) continue;
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
      inputTensor.data = input.buffer.asUint8List();
      interpreter.invoke();
      outputBytes.setAll(0, outputTensor.data);
      final dets = decoder.decode(output, cfg.labels, lb);
      // Chỉ số thời gian (không chứa dữ liệu ảnh) để đo hiệu năng trên thiết bị.
      debugPrint('CurrencyDetector: ${dets.length} khung, '
          '${dets.isEmpty ? '-' : '${dets.first.label}@${dets.first.score.toStringAsFixed(2)}'}, '
          '${sw.elapsedMilliseconds}ms');
      cfg.replyPort.send(_Response(
        msg.id,
        frame: CurrencyDetectionFrame(
          detections: dets,
          imageWidth: frame.uprightWidth,
          imageHeight: frame.uprightHeight,
          luminance: luminance,
          totalMs: sw.elapsedMilliseconds,
        ),
      ));
    } catch (e) {
      cfg.replyPort.send(_Response(msg.id, error: e.toString()));
    }
  }
}

final currencyDetectorProvider = Provider<CurrencyDetector>((ref) {
  final detector = CurrencyDetector();
  ref.onDispose(detector.dispose);
  return detector;
});
