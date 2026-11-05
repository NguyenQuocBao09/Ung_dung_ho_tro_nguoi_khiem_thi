import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../core/camera/frame_converter.dart';
import '../../../core/ml/inference_engine.dart';
import '../domain/denomination.dart';
import '../domain/note_window_search.dart';
import '../domain/vote_aggregator.dart';

/// Kết quả dự đoán đa vùng cắt (Multi-Crop Prediction)
class MultiCropPredictionResult {
  final String label;
  final Denomination denomination;
  final double confidence;
  final String spokenVi;
  final String winningCrop; // 'full', 'center_70', 'center_50'
  final int winningCropIndex;
  final int inferenceTimeMs;
  final Map<String, double> cropProbabilities;

  /// Vùng ước lượng chứa tờ tiền (chuẩn hoá 0..1 trong ảnh đứng); null nếu không có tiền.
  final NormRect? box;

  /// Kích thước ảnh camera sau khi xoay đứng (để vẽ khung đúng tỉ lệ preview).
  final int imageWidth;
  final int imageHeight;

  /// Độ sáng trung bình kênh Y (0..255); -1 nếu không đo.
  final double luminance;

  /// Số vùng quét cùng đồng ý (cùng mệnh giá, xác suất cao, chồng lấn nhau).
  final int support;

  /// Cờ tin cậy do nguồn kết quả đặt (vd. YOLO theo ngưỡng điểm); null = dùng luật đồng thuận vùng.
  final bool? reliableFlag;

  /// Đủ tin cậy để đưa vào bỏ phiếu.
  /// - YOLO: điểm khung >= ngưỡng đã chọn từ bảng ngưỡng trên tập test.
  /// - Model phân loại cũ: nhiều vùng cùng đồng ý, không chỉ một mẩu cắt.
  bool get isReliable =>
      isMoney &&
      (reliableFlag ??
          (confidence >= CurrencyClassifier.reliableMinProb &&
              support >= CurrencyClassifier.reliableMinSupport));

  const MultiCropPredictionResult({
    required this.label,
    required this.denomination,
    required this.confidence,
    required this.spokenVi,
    required this.winningCrop,
    required this.winningCropIndex,
    required this.inferenceTimeMs,
    this.cropProbabilities = const {},
    this.box,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.luminance = -1,
    this.support = 0,
    this.reliableFlag,
  });

  bool get isMoney => denomination.isMoney && label != 'none';

  @override
  String toString() =>
      'MultiCropPredictionResult($label, ${(confidence * 100).toStringAsFixed(1)}%, crop: $winningCrop, time: ${inferenceTimeMs}ms)';
}

/// Dịch vụ phân loại tiền polymer VND bằng MobileNetV3 TensorFlow Lite
class CurrencyClassifier
    implements InferenceEngine<Uint8List, CurrencyRecognitionResult?> {
  static const String modelPath = 'assets/models/currency_mobilenetv3.tflite';
  static const String labelsPath = 'assets/models/currency_labels.txt';
  static const String labelDisplayViPath = 'assets/models/label_display_vi.json';

  static const int inputWidth = 224;
  static const int inputHeight = 224;
  static const int inputChannels = 3;

  Interpreter? _interpreter;
  List<String> _labels = [];
  Map<String, String> _labelDisplayVi = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  List<String> get labels => List.unmodifiable(_labels);
  Map<String, String> get labelDisplayVi => Map.unmodifiable(_labelDisplayVi);

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Đọc danh sách nhãn (100k, 10k, 1k, 200k, 20k, 2k, 500k, 50k, 5k, none)
      final labelsData = await rootBundle.loadString(labelsPath);
      _labels = LineSplitter.split(labelsData)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      // 2. Đọc chuỗi tiếng Việt để đọc âm thanh (TTS)
      final displayData = await rootBundle.loadString(labelDisplayViPath);
      final Map<String, dynamic> decoded = jsonDecode(displayData);
      _labelDisplayVi = decoded.map((key, value) => MapEntry(key, value.toString()));

      // 3. Khởi tạo Interpreter TFLite
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(modelPath, options: options);

      _isInitialized = true;
      debugPrint('CurrencyClassifier: Khởi tạo mô hình thành công với ${_labels.length} lớp.');
    } catch (e) {
      debugPrint('CurrencyClassifier: Không thể khởi tạo mô hình TFLite: $e');
      _isInitialized = false;
    }
  }

  // -------------------------------------------------------------------------
  // Luồng camera: định vị + phân loại trong isolate nền
  // -------------------------------------------------------------------------

  Interpreter? _streamInterpreter;
  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _receivePort;
  final Map<int, Completer<_StreamResponse>> _pending = {};
  int _nextId = 0;
  Future<void>? _streamInitFuture;

  /// Ngưỡng xác suất tối thiểu để coi là có tiền (dưới mức này trả 'none').
  static const double moneyMinProb = 0.5;

  /// Luật đồng thuận để một khung được tính phiếu. Chọn theo thử nghiệm mô phỏng trên máy tính
  /// (ảnh test dán lên nền thật): giảm tỉ lệ đọc nhầm mệnh giá từ ~8,5% xuống ~4%,
  /// đổi lại tỉ lệ nhận đúng giảm ~80% -> ~74%. CHƯA hiệu chỉnh trên thiết bị thật.
  static const double reliableMinProb = 0.9;
  static const int reliableMinSupport = 3;

  Future<void> _ensureStreamWorker() =>
      _streamInitFuture ??= _initStreamWorker().catchError((Object e) {
        _streamInitFuture = null;
        throw e;
      });

  Future<void> _initStreamWorker() async {
    await initialize();
    if (_labels.isEmpty) throw StateError('Chưa đọc được nhãn mô hình tiền');
    final noneIndex = _labels.indexOf('none');

    // Interpreter riêng cho isolate nền (không dùng chung với predictMulti trên UI isolate).
    final interpreter = await Interpreter.fromAsset(
      modelPath,
      // XNNPACK đã được TFLite bật mặc định; thêm XNNPackDelegate thủ công gây crash native
      // (TfLiteXNNPackDelegateCreateWithThreadpool) trên S25 FE nên không dùng.
      options: InterpreterOptions()..threads = 4,
    );
    interpreter.allocateTensors();
    final inShape = interpreter.getInputTensor(0).shape;
    final outShape = interpreter.getOutputTensor(0).shape;
    if (inShape.length != 4 ||
        inShape[1] != inputHeight ||
        inShape[2] != inputWidth ||
        inShape[3] != inputChannels ||
        outShape.last != _labels.length) {
      interpreter.close();
      throw StateError('Model tiền không khớp: input $inShape, output $outShape, '
          '${_labels.length} nhãn');
    }
    _streamInterpreter = interpreter;

    final receivePort = ReceivePort();
    _receivePort = receivePort;
    final portCompleter = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        portCompleter.complete(message);
      } else if (message is _StreamResponse) {
        _pending.remove(message.id)?.complete(message);
      }
    });
    _isolate = await Isolate.spawn(
      _currencyWorkerMain,
      _StreamWorkerConfig(
        replyPort: receivePort.sendPort,
        interpreterAddress: interpreter.address,
        numClasses: _labels.length,
        noneIndex: noneIndex,
      ),
      debugName: 'CurrencyWorker',
    );
    _workerPort = await portCompleter.future;
    debugPrint('CurrencyClassifier: worker sẵn sàng (input $inShape, output $outShape).');
  }

  /// Phân tích một khung hình camera (NV21 1 plane hoặc YUV420 3 plane):
  /// định vị vùng có tiền và phân loại mệnh giá. Không chặn UI isolate.
  ///
  /// [trackFrom]: vùng tiền ở khung trước (nếu có) để chỉ quét quanh đó, nhanh hơn quét toàn bộ.
  Future<MultiCropPredictionResult> analyzeFrame(
    CameraImage image,
    int rotationDegrees, {
    NormRect? trackFrom,
  }) async {
    await _ensureStreamWorker();
    final port = _workerPort;
    if (port == null) throw StateError('CurrencyClassifier worker chưa sẵn sàng');

    final id = _nextId++;
    final completer = Completer<_StreamResponse>();
    _pending[id] = completer;
    port.send(_StreamRequest(
      id: id,
      width: image.width,
      height: image.height,
      rotationDegrees: rotationDegrees,
      planes: [
        for (final p in image.planes) TransferableTypedData.fromList([p.bytes]),
      ],
      rowStrides: [for (final p in image.planes) p.bytesPerRow],
      pixelStrides: [for (final p in image.planes) p.bytesPerPixel ?? 1],
      trackBox: trackFrom,
    ));
    final r = await completer.future;
    if (r.error != null) throw StateError(r.error!);

    final isMoney = r.classIndex >= 0 && r.moneyProb >= moneyMinProb;
    final label = isMoney ? _labels[r.classIndex] : 'none';
    return MultiCropPredictionResult(
      label: label,
      denomination: Denomination.fromCode(label),
      confidence: r.moneyProb,
      spokenVi: isMoney ? (_labelDisplayVi[label] ?? '') : '',
      winningCrop: 'quét ${r.windows} vùng',
      winningCropIndex: 0,
      inferenceTimeMs: r.totalMs,
      box: isMoney ? r.box : null,
      imageWidth: r.imageWidth,
      imageHeight: r.imageHeight,
      luminance: r.luminance,
      support: r.support,
    );
  }

  /// Dự đoán đa vùng cắt (3 vùng cắt: toàn khung, giữa 70%, giữa 50%)
  /// Lấy vùng có xác suất mệnh giá (không tính none) cao nhất; nếu < 0.5 thì trả nhãn 'none'.
  /// Mỗi vùng co giãn thẳng về 224x224 (KHÔNG letterbox), RGB, pixel float32 [0..255] không chia 255.
  Future<MultiCropPredictionResult?> predictMulti(img.Image image) async {
    if (!_isInitialized || _interpreter == null) {
      await initialize();
    }
    if (_interpreter == null) {
      debugPrint('CurrencyClassifier: Interpreter chưa sẵn sàng.');
      return null;
    }

    final stopwatch = Stopwatch()..start();

    // 1. Tạo 3 vùng cắt (toàn khung, giữa 70%, giữa 50%)
    // Vùng 1: Toàn khung (full)
    final cropFull = img.copyResize(
      image,
      width: inputWidth,
      height: inputHeight,
      interpolation: img.Interpolation.linear,
    );

    // Vùng 2: Giữa 70% (center 70%)
    final w70 = (image.width * 0.7).round();
    final h70 = (image.height * 0.7).round();
    final x70 = (image.width - w70) ~/ 2;
    final y70 = (image.height - h70) ~/ 2;
    final sub70 = img.copyCrop(image, x: x70, y: y70, width: w70, height: h70);
    final crop70 = img.copyResize(
      sub70,
      width: inputWidth,
      height: inputHeight,
      interpolation: img.Interpolation.linear,
    );

    // Vùng 3: Giữa 50% (center 50%)
    final w50 = (image.width * 0.5).round();
    final h50 = (image.height * 0.5).round();
    final x50 = (image.width - w50) ~/ 2;
    final y50 = (image.height - h50) ~/ 2;
    final sub50 = img.copyCrop(image, x: x50, y: y50, width: w50, height: h50);
    final crop50 = img.copyResize(
      sub50,
      width: inputWidth,
      height: inputHeight,
      interpolation: img.Interpolation.linear,
    );

    final crops = [cropFull, crop70, crop50];
    final cropNames = ['toàn khung', 'giữa 70%', 'giữa 50%'];

    int winningIndex = 0;
    double highestMoneyProb = -1.0;
    String highestMoneyLabel = 'none';
    final cropProbabilities = <String, double>{};

    // 2. Chạy suy luận trên từng vùng cắt
    for (int i = 0; i < crops.length; i++) {
      final scores = _runInferenceOnResizedImage(crops[i]);

      // Tìm mệnh giá tiền có xác suất cao nhất (không tính none)
      double bestCropMoneyProb = -1.0;
      String bestCropMoneyLabel = 'none';

      for (int c = 0; c < scores.length; c++) {
        final label = c < _labels.length ? _labels[c] : 'class_$c';
        if (label == 'none') continue; // Không tính none

        if (scores[c] > bestCropMoneyProb) {
          bestCropMoneyProb = scores[c];
          bestCropMoneyLabel = label;
        }
      }

      cropProbabilities[cropNames[i]] = bestCropMoneyProb;

      if (bestCropMoneyProb > highestMoneyProb) {
        highestMoneyProb = bestCropMoneyProb;
        highestMoneyLabel = bestCropMoneyLabel;
        winningIndex = i;
      }
    }

    // 3. Quy tắc: nếu xác suất mệnh giá cao nhất < 0.5 thì trả về nhãn 'none'
    String finalLabel;
    double finalConf;
    String finalSpokenVi;

    if (highestMoneyProb < 0.5) {
      finalLabel = 'none';
      finalConf = highestMoneyProb;
      finalSpokenVi = '';
    } else {
      finalLabel = highestMoneyLabel;
      finalConf = highestMoneyProb;
      finalSpokenVi = _labelDisplayVi[finalLabel] ?? '';
    }

    stopwatch.stop();
    final inferenceTimeMs = stopwatch.elapsedMilliseconds;
    final winningCropName = cropNames[winningIndex];

    // 4. Log debug (chỉ khi kDebugMode)
    if (kDebugMode) {
      debugPrint(
        'CurrencyClassifier [debug]: Nhãn=$finalLabel, '
        'Xác suất=${(finalConf * 100).toStringAsFixed(1)}%, '
        'Vùng thắng=$winningCropName, Thời gian=${inferenceTimeMs}ms, '
        'Chi tiết vùng: $cropProbabilities',
      );
    }

    return MultiCropPredictionResult(
      label: finalLabel,
      denomination: Denomination.fromCode(finalLabel),
      confidence: finalConf,
      spokenVi: finalSpokenVi,
      winningCrop: winningCropName,
      winningCropIndex: winningIndex,
      inferenceTimeMs: inferenceTimeMs,
      cropProbabilities: cropProbabilities,
    );
  }

  /// Chạy suy luận trên một ảnh đã resize chuẩn 224x224
  List<double> _runInferenceOnResizedImage(img.Image resizedImage) {
    final inputBuffer = Float32List(1 * inputHeight * inputWidth * inputChannels);
    int bufferIndex = 0;

    for (int y = 0; y < inputHeight; y++) {
      for (int x = 0; x < inputWidth; x++) {
        final pixel = resizedImage.getPixel(x, y);
        inputBuffer[bufferIndex++] = pixel.r.toDouble();
        inputBuffer[bufferIndex++] = pixel.g.toDouble();
        inputBuffer[bufferIndex++] = pixel.b.toDouble();
      }
    }

    final inputTensor = inputBuffer.reshape([1, inputHeight, inputWidth, inputChannels]);
    final numClasses = _labels.isNotEmpty ? _labels.length : 10;
    final outputBuffer = List.generate(1, (_) => List<double>.filled(numClasses, 0.0));

    _interpreter!.run(inputTensor, outputBuffer);
    return outputBuffer[0];
  }

  /// Phân loại ảnh từ mảng byte (JPEG/PNG từ CameraImage/XFile)
  @override
  Future<CurrencyRecognitionResult?> runInference(Uint8List input) async {
    if (!_isInitialized || _interpreter == null) {
      await initialize();
    }
    if (_interpreter == null) {
      debugPrint('CurrencyClassifier: Interpreter chưa sẵn sàng.');
      return null;
    }

    final stopwatch = Stopwatch()..start();

    final decodedImage = img.decodeImage(input);
    if (decodedImage == null) {
      debugPrint('CurrencyClassifier: Không thể giải mã ảnh.');
      return null;
    }

    final orientedImage = img.bakeOrientation(decodedImage);
    final resizedImage = img.copyResize(
      orientedImage,
      width: inputWidth,
      height: inputHeight,
      interpolation: img.Interpolation.linear,
    );

    final scores = _runInferenceOnResizedImage(resizedImage);

    int maxIndex = 0;
    double maxScore = -1.0;
    final probabilities = <String, double>{};

    for (int i = 0; i < scores.length; i++) {
      final label = i < _labels.length ? _labels[i] : 'class_$i';
      final score = scores[i];
      probabilities[label] = score;

      if (score > maxScore) {
        maxScore = score;
        maxIndex = i;
      }
    }

    final bestLabel = maxIndex < _labels.length ? _labels[maxIndex] : 'unknown';
    final denomination = Denomination.fromCode(bestLabel);
    final spokenVi = _labelDisplayVi[bestLabel] ?? '';

    stopwatch.stop();

    return CurrencyRecognitionResult(
      label: bestLabel,
      denomination: denomination,
      confidence: maxScore,
      spokenVi: spokenVi,
      inferenceTimeMs: stopwatch.elapsedMilliseconds,
      probabilities: probabilities,
    );
  }

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    _receivePort?.close();
    _receivePort = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.complete(const _StreamResponse(-1, error: 'CurrencyClassifier đã đóng'));
      }
    }
    _pending.clear();
    _streamInterpreter?.close();
    _streamInterpreter = null;
    _streamInitFuture = null;

    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}

// ---------------------------------------------------------------------------
// Isolate nền nhận diện tiền
// ---------------------------------------------------------------------------

class _StreamWorkerConfig {
  final SendPort replyPort;
  final int interpreterAddress;
  final int numClasses;
  final int noneIndex;

  const _StreamWorkerConfig({
    required this.replyPort,
    required this.interpreterAddress,
    required this.numClasses,
    required this.noneIndex,
  });
}

class _StreamRequest {
  final int id;
  final int width;
  final int height;
  final int rotationDegrees;
  final List<TransferableTypedData> planes;
  final List<int> rowStrides;
  final List<int> pixelStrides;
  final NormRect? trackBox;

  const _StreamRequest({
    required this.id,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.planes,
    required this.rowStrides,
    required this.pixelStrides,
    this.trackBox,
  });
}

class _StreamResponse {
  final int id;
  final int classIndex;
  final double moneyProb;
  final NormRect? box;
  final int imageWidth;
  final int imageHeight;
  final double luminance;
  final int windows;
  final int support;
  final int totalMs;
  final String? error;

  const _StreamResponse(
    this.id, {
    this.classIndex = -1,
    this.moneyProb = 0,
    this.box,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.luminance = 0,
    this.windows = 0,
    this.support = 0,
    this.totalMs = 0,
    this.error,
  });
}

Future<void> _currencyWorkerMain(_StreamWorkerConfig cfg) async {
  final port = ReceivePort();
  cfg.replyPort.send(port.sendPort);

  final interpreter = Interpreter.fromAddress(cfg.interpreterAddress, allocated: true);
  final inputTensor = interpreter.getInputTensor(0);
  final outputTensor = interpreter.getOutputTensor(0);
  const size = CurrencyClassifier.inputWidth;
  final input = Float32List(size * size * 3);
  final inputBytes = input.buffer.asUint8List();
  final output = Float32List(cfg.numClasses);
  final outputBytes = output.buffer.asUint8List();
  const search = NoteWindowSearch();

  final timer = Stopwatch();
  var cropUs = 0;
  var inferUs = 0;

  WindowScore score(RgbImage rgb, NormRect r) {
    timer
      ..reset()
      ..start();
    cropResizeToFloat(rgb, r.left, r.top, r.right, r.bottom, size, input);
    cropUs += timer.elapsedMicroseconds;
    timer.reset();
    inputTensor.data = inputBytes;
    interpreter.invoke();
    inferUs += timer.elapsedMicroseconds;
    outputBytes.setAll(0, outputTensor.data);
    var best = -1;
    var bestP = -1.0;
    for (var c = 0; c < cfg.numClasses; c++) {
      if (c == cfg.noneIndex) continue;
      if (output[c] > bestP) {
        bestP = output[c];
        best = c;
      }
    }
    return WindowScore(r, best, bestP);
  }

  await for (final msg in port) {
    if (msg is! _StreamRequest) continue;
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
      final rgb = yuvToUprightRgb(frame);
      final convMs = sw.elapsedMilliseconds;
      cropUs = 0;
      inferUs = 0;

      // 1. Bám theo: nếu khung trước đã thấy tiền, chỉ quét quanh vị trí cũ.
      final scores = <WindowScore>[];
      WindowScore? best;
      final track = msg.trackBox;
      if (track != null) {
        for (final r in search.trackingWindows(track)) {
          scores.add(score(rgb, r));
        }
        best = NoteWindowSearch.best(scores);
      }
      // 2. Chưa có / mất dấu: quét thô toàn khung hình rồi tinh chỉnh quanh vùng tốt nhất.
      if (best == null || best.moneyProb < CurrencyClassifier.moneyMinProb) {
        for (final r in search.coarseWindows(rgb.width, rgb.height)) {
          scores.add(score(rgb, r));
        }
        best = NoteWindowSearch.best(scores)!;
        if (best.moneyProb >= search.refineMinProb) {
          for (final r in search.refineWindows(best.rect)) {
            scores.add(score(rgb, r));
          }
          best = NoteWindowSearch.best(scores)!;
        }
      }
      final box = NoteWindowSearch.fuseBox(scores, best);
      // Chỉ số thời gian (không chứa dữ liệu ảnh) để đo hiệu năng trên thiết bị.
      final support = NoteWindowSearch.support(
        scores,
        best,
        CurrencyClassifier.reliableMinProb,
      );
      debugPrint('CurrencyWorker: ${frame.width}x${frame.height} -> ${rgb.width}x${rgb.height}, '
          'convert ${convMs}ms, crop ${cropUs ~/ 1000}ms, infer ${inferUs ~/ 1000}ms '
          '(${scores.length} vùng, đồng thuận $support), total ${sw.elapsedMilliseconds}ms');

      cfg.replyPort.send(_StreamResponse(
        msg.id,
        classIndex: best.classIndex,
        moneyProb: best.moneyProb,
        box: box,
        imageWidth: frame.uprightWidth,
        imageHeight: frame.uprightHeight,
        luminance: luminance,
        windows: scores.length,
        support: support,
        totalMs: sw.elapsedMilliseconds,
      ));
    } catch (e) {
      cfg.replyPort.send(_StreamResponse(msg.id, error: e.toString()));
    }
  }
}

/// Provider của CurrencyClassifier dùng Riverpod
final currencyClassifierProvider = Provider<CurrencyClassifier>((ref) {
  final classifier = CurrencyClassifier();
  ref.onDispose(() => classifier.dispose());
  return classifier;
});
