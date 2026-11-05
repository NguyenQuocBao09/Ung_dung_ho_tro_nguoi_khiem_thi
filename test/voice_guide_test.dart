import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/core/accessibility/voice_guide.dart';
import 'package:vision_assist/core/constants/strings_vi.dart';
import 'package:vision_assist/core/feedback/feedback_manager.dart';
import 'package:vision_assist/core/feedback/feedback_message.dart';
import 'package:vision_assist/core/feedback/tts_service.dart';

/// TTS giả: mỗi câu chỉ "đọc xong" khi test gọi [finishCurrent] (hoặc tự xong nếu [autoFinish]).
class _GatedTts extends TtsService {
  final bool autoFinish;
  final List<String> spoken = [];
  Completer<void>? _current;
  int stops = 0;

  _GatedTts({this.autoFinish = false});

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text, {bool interrupt = true, String language = 'vi-VN'}) async {
    spoken.add(text);
  }

  @override
  Future<void> speakAndWait(String text, {String language = 'vi-VN'}) {
    spoken.add(text);
    if (autoFinish) return Future.value();
    _current = Completer<void>();
    return _current!.future;
  }

  void finishCurrent() => _current?.complete();

  @override
  Future<void> stop() async {
    stops++;
    // Dừng TTS thật làm câu đang đọc kết thúc ngay.
    if (_current != null && !_current!.isCompleted) _current!.complete();
  }
}

class _MemFlag implements GuideFlagStorage {
  bool done = false;
  bool throwOnRead;
  _MemFlag({this.throwOnRead = false});

  @override
  Future<bool> isDone() async {
    if (throwOnRead) throw Exception('hỏng');
    return done;
  }

  @override
  Future<void> markDone() async => done = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FeedbackManager.speakSegmentsAndWait', () {
    test('đọc hết -> true, các đoạn đọc đúng thứ tự', () async {
      final tts = _GatedTts(autoFinish: true);
      final fm = FeedbackManager(ttsService: tts);
      final ok = await fm.speakSegmentsAndWait(
          const [SpeechSegment('một'), SpeechSegment('hai'), SpeechSegment('ba')]);
      expect(ok, isTrue);
      expect(tts.spoken, ['một', 'hai', 'ba']);
    });

    test('bị dừng giữa chừng -> false, các đoạn còn lại không được đọc', () async {
      final tts = _GatedTts();
      final fm = FeedbackManager(ttsService: tts);
      final f = fm.speakSegmentsAndWait(
          const [SpeechSegment('một'), SpeechSegment('hai'), SpeechSegment('ba')]);
      await Future<void>.delayed(Duration.zero);
      expect(tts.spoken, ['một']);
      await fm.stop();
      expect(await f, isFalse);
      expect(tts.spoken, ['một']);
    });

    test('câu đang chờ bị đẩy khỏi hàng đợi đầy -> false', () async {
      final tts = _GatedTts();
      final fm = FeedbackManager(ttsService: tts);
      unawaited(fm.speak('đang đọc'));
      await Future<void>.delayed(Duration.zero);
      final waiting = fm.speakSegmentsAndWait(const [SpeechSegment('chờ')]);
      for (var i = 0; i < FeedbackManager.maxQueueSize; i++) {
        unawaited(fm.speak('mới $i'));
      }
      expect(await waiting, isFalse);
    });

    test('câu khẩn cấp ngắt câu đang chờ -> false', () async {
      final tts = _GatedTts();
      final fm = FeedbackManager(ttsService: tts);
      final f = fm.speakSegmentsAndWait(const [SpeechSegment('a'), SpeechSegment('b')]);
      await Future<void>.delayed(Duration.zero);
      unawaited(fm.speak('Cẩn thận', priority: FeedbackPriority.urgent));
      expect(await f, isFalse);
    });

    test('nội dung rỗng -> true ngay, không đọc gì', () async {
      final tts = _GatedTts();
      final fm = FeedbackManager(ttsService: tts);
      expect(await fm.speakSegmentsAndWait(const [SpeechSegment('  ')]), isTrue);
      expect(tts.spoken, isEmpty);
    });
  });

  group('VoiceGuide', () {
    test('lần đầu -> tự đọc; sau khi markDone -> không tự đọc nữa', () async {
      final flag = _MemFlag();
      final g = VoiceGuide(flag);
      expect(await g.shouldAutoPlay(), isTrue);
      await g.markDone();
      expect(await g.shouldAutoPlay(), isFalse);
    });

    test('không đọc được bộ nhớ -> không tự đọc (tránh làm phiền mỗi lần mở)', () async {
      final g = VoiceGuide(_MemFlag(throwOnRead: true));
      expect(await g.shouldAutoPlay(), isFalse);
    });

    test('play đọc toàn bộ các bước theo thứ tự và ngắt lời cũ trước đó', () async {
      final tts = _GatedTts(autoFinish: true);
      final fm = FeedbackManager(ttsService: tts);
      final ok = await VoiceGuide(_MemFlag()).play(fm);
      expect(ok, isTrue);
      expect(tts.stops, greaterThanOrEqualTo(1));
      String norm(String s) =>
          s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r' (?=[,.])'), '');
      expect(norm(tts.spoken.join(' ')), norm(StringsVi.voiceGuideSteps.join(' ')));
    });

    test('tên app "Vision Assist" được đọc bằng giọng tiếng Anh, phần còn lại giọng Việt', () {
      final segs = VoiceGuide.buildSegments(
          const ['Chào mừng bạn đến với Vision Assist, trợ lý thị giác.']);
      expect(segs.map((s) => s.text.trim()), ['Chào mừng bạn đến với', 'Vision Assist', ', trợ lý thị giác.']);
      expect(segs.map((s) => s.language), ['vi-VN', 'en-US', 'vi-VN']);
    });

    test('play bị dừng -> false', () async {
      final tts = _GatedTts();
      final fm = FeedbackManager(ttsService: tts);
      final f = VoiceGuide(_MemFlag()).play(fm);
      await Future<void>.delayed(Duration.zero);
      await fm.stop();
      expect(await f, isFalse);
      expect(tts.spoken.length, lessThan(StringsVi.voiceGuideSteps.length));
    });

    test('nội dung hướng dẫn nhắc đủ 3 chế độ, nút hướng dẫn và giới hạn vật cản', () {
      final all = StringsVi.voiceGuideSteps.join(' ');
      expect(all, contains('Đọc văn bản'));
      expect(all, contains('Nhận diện tiền'));
      expect(all, contains('Cảnh báo vật cản'));
      expect(all, contains('Hướng dẫn sử dụng'));
      expect(all, contains('gậy dò đường'));
    });
  });
}
