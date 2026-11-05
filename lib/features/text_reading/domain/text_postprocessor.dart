import 'dart:typed_data';

import '../../../core/feedback/feedback_message.dart';
import 'language_segmenter.dart';

/// Tiện ích hậu xử lý hình ảnh và văn bản cho tính năng đọc chữ
class TextPostprocessor {
  const TextPostprocessor._();

  /// Tính độ sáng trung bình của mặt phẳng Y (NV21 / YUV) bằng cách lấy mẫu thưa.
  /// [step]: bước nhảy lấy mẫu (mặc định 32 pixel) để tối ưu hiệu năng CPU trên mobile.
  static double calculateAverageLuminance(Uint8List yPlaneBytes, {int step = 32}) {
    if (yPlaneBytes.isEmpty) return 255.0;
    int total = 0;
    int count = 0;
    final length = yPlaneBytes.length;

    for (int i = 0; i < length; i += step) {
      total += yPlaneBytes[i];
      count++;
    }

    return count == 0 ? 0.0 : total / count;
  }

  static final RegExp _endsWithPunctuation = RegExp(r'[.!?;:…,]$');

  /// Ghép các đoạn thành câu đọc, ngăn cách bằng dấu chấm (để TTS ngắt nghỉ).
  /// Đoạn đã kết thúc bằng dấu câu thì chỉ thêm dấu cách, tránh "..".
  static String joinLinesForSpeech(List<String> lines) {
    final parts = lines.map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final sb = StringBuffer(parts.first);
    for (var i = 1; i < parts.length; i++) {
      sb.write(_endsWithPunctuation.hasMatch(parts[i - 1]) ? ' ' : '. ');
      sb.write(parts[i]);
    }
    return sb.toString();
  }

  /// Tạo danh sách đoạn đọc theo ngôn ngữ từ các đoạn văn (đã theo thứ tự đọc).
  /// Mỗi đoạn văn kết thúc bằng dấu câu để TTS ngắt nghỉ; các đoạn liền kề cùng
  /// ngôn ngữ được gộp để hạn chế đổi giọng.
  static List<SpeechSegment> buildSpeechSegments(
    List<String> paragraphs, {
    LanguageSegmenter segmenter = const LanguageSegmenter(),
  }) {
    final out = <SpeechSegment>[];
    for (final p in paragraphs) {
      final text = p.trim();
      if (text.isEmpty) continue;
      final withStop = _endsWithPunctuation.hasMatch(text) ? text : '$text.';
      for (final s in segmenter.segment(withStop)) {
        if (out.isNotEmpty && out.last.language == s.language) {
          out[out.length - 1] = SpeechSegment('${out.last.text} ${s.text}', language: s.language);
        } else {
          out.add(s);
        }
      }
    }
    return out;
  }
}
