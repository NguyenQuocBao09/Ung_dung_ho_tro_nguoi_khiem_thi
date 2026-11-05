import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/read_session.dart';

/// Chuyển đổi CameraImage sang InputImage theo định dạng nv21
InputImage? toInputImage(CameraImage image, CameraDescription cameraDescription) {
  // Trả về null nếu định dạng hình ảnh không phải nv21
  if (image.format.group != ImageFormatGroup.nv21) {
    return null;
  }
  if (image.planes.isEmpty) {
    return null;
  }

  final plane = image.planes.first;
  final rotation =
      InputImageRotationValue.fromRawValue(cameraDescription.sensorOrientation) ??
          InputImageRotation.rotation0deg;

  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

/// Dịch vụ nhận dạng ký tự quang học (OCR) dùng Google ML Kit
class MlkitOcrEngine {
  final TextRecognizer _recognizer;
  bool _isClosed = false;

  MlkitOcrEngine({TextRecognizer? recognizer})
      : _recognizer = recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  bool get isClosed => _isClosed;

  /// Xử lý InputImage và trả về RecognizedText
  Future<RecognizedText> processImage(InputImage inputImage) async {
    if (_isClosed) {
      throw StateError('MlkitOcrEngine đã đóng.');
    }
    return _recognizer.processImage(inputImage);
  }

  /// Trích xuất danh sách các dòng văn bản từ RecognizedText
  List<String> extractLines(RecognizedText recognizedText) {
    final lines = <String>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isNotEmpty) {
          lines.add(text);
        }
      }
    }
    return lines;
  }

  /// Trích xuất các dòng kèm vị trí, chuẩn hoá 0..1 theo kích thước ảnh ĐỨNG
  /// ([uprightWidth] x [uprightHeight]). Trên Android, ML Kit trả boundingBox
  /// trong hệ toạ độ ảnh đã xoay theo `InputImageRotation`.
  List<OcrLine> extractOcrLines(
    RecognizedText recognizedText, {
    required double uprightWidth,
    required double uprightHeight,
  }) {
    final out = <OcrLine>[];
    if (uprightWidth <= 0 || uprightHeight <= 0) return out;
    for (var b = 0; b < recognizedText.blocks.length; b++) {
      for (final line in recognizedText.blocks[b].lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;
        final r = line.boundingBox;
        out.add(OcrLine(
          text: text,
          blockIndex: b,
          left: (r.left / uprightWidth).clamp(0.0, 1.0),
          top: (r.top / uprightHeight).clamp(0.0, 1.0),
          right: (r.right / uprightWidth).clamp(0.0, 1.0),
          bottom: (r.bottom / uprightHeight).clamp(0.0, 1.0),
        ));
      }
    }
    return out;
  }

  /// Giải phóng tài nguyên
  Future<void> close() async {
    if (!_isClosed) {
      _isClosed = true;
      await _recognizer.close();
    }
  }
}

final mlkitOcrEngineProvider = Provider<MlkitOcrEngine>((ref) {
  final engine = MlkitOcrEngine();
  ref.onDispose(() => engine.close());
  return engine;
});
