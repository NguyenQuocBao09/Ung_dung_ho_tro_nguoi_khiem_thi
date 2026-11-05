import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'feedback_message.dart';

/// Dịch vụ tổng hợp giọng nói (Text-to-Speech). Mặc định tiếng Việt; có thể đổi
/// sang ngôn ngữ khác (vd. `en-US`) cho từng câu nếu máy có giọng đó.
class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  String _currentLanguage = SpeechSegment.vietnamese;
  final Map<String, bool> _availability = {};

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setLanguage(SpeechSegment.vietnamese);
      _currentLanguage = SpeechSegment.vietnamese;
      await _flutterTts.setSpeechRate(0.5); // Tốc độ vừa phải cho người khiếm thị
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.awaitSpeakCompletion(true);
      _isInitialized = true;
    } catch (_) {
      // Bỏ qua lỗi khởi tạo nếu môi trường không hỗ trợ TTS (vd: giả lập không có TTS tiếng Việt)
    }
  }

  /// Chuyển ngôn ngữ TTS. Nếu máy không có giọng [language] thì giữ tiếng Việt
  /// (vẫn đọc được, chỉ là phát âm không chuẩn).
  Future<void> _useLanguage(String language) async {
    if (language == _currentLanguage) return;
    var target = language;
    if (language != SpeechSegment.vietnamese) {
      final ok = _availability[language] ??= await _isAvailable(language);
      if (!ok) target = SpeechSegment.vietnamese;
    }
    if (target == _currentLanguage) return;
    try {
      await _flutterTts.setLanguage(target);
      _currentLanguage = target;
    } catch (_) {}
  }

  Future<bool> _isAvailable(String language) async {
    try {
      final r = await _flutterTts.isLanguageAvailable(language);
      final ok = r == true || r == 1;
      if (!ok) debugPrint('TtsService: máy không có giọng $language, dùng giọng Việt.');
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Đọc câu. Nếu [interrupt] là true thì ngắt câu đang đọc trước đó.
  Future<void> speak(
    String text, {
    bool interrupt = true,
    String language = SpeechSegment.vietnamese,
  }) async {
    if (text.trim().isEmpty) return;
    if (!_isInitialized) {
      await init();
    }
    try {
      if (interrupt) {
        await _flutterTts.stop();
      }
      await _useLanguage(language);
      await _flutterTts.speak(text);
    } catch (_) {}
  }

  /// Đọc câu và đợi hoàn tất (await completion)
  Future<void> speakAndWait(String text, {String language = SpeechSegment.vietnamese}) async {
    if (text.trim().isEmpty) return;
    if (!_isInitialized) {
      await init();
    }
    try {
      await _useLanguage(language);
      await _flutterTts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
  }

  void dispose() {
    _flutterTts.stop();
  }
}

final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService();
  ref.onDispose(() => service.dispose());
  return service;
});
