import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/core/accessibility/talkback_interaction_watcher.dart';
import 'package:vision_assist/core/feedback/feedback_manager.dart';
import 'package:vision_assist/core/feedback/feedback_message.dart';
import 'package:vision_assist/core/feedback/tts_service.dart';

/// TTS giả: câu đang đọc chỉ xong khi test gọi [finishCurrent] hoặc khi bị [stop].
class _GatedTts extends TtsService {
  final List<String> spoken = [];
  Completer<void>? _current;
  int stops = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text, {bool interrupt = true, String language = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String language = 'vi-VN'}) {
    spoken.add(text);
    _current = Completer<void>();
    return _current!.future;
  }

  bool get speaking => _current != null && !_current!.isCompleted;

  void finishCurrent() {
    if (speaking) _current!.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    finishCurrent();
  }
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);
Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const hold = Duration(milliseconds: 80);

  test('TalkBack chuyển tiêu điểm -> dừng hẳn câu đang đọc, KHÔNG đọc lại sau đó', () async {
    final tts = _GatedTts();
    final fm = FeedbackManager(ttsService: tts, userInteractionHold: hold);
    final done = fm.speakSegmentsAndWait(const [SpeechSegment('The quick brown fox')]);
    await _tick();
    expect(tts.spoken, ['The quick brown fox']);

    fm.holdForUserInteraction();
    expect(tts.stops, 1);
    expect(await done, isFalse);
    await _wait(150); // quá thời gian tạm im
    expect(tts.spoken, ['The quick brown fox'], reason: 'không chen lại vào lời TalkBack');
  });

  test('Vuốt liên tục -> các đoạn còn lại của câu dài không được đọc', () async {
    final tts = _GatedTts();
    final fm = FeedbackManager(ttsService: tts, userInteractionHold: hold);
    unawaited(fm.speakSegments(
        const [SpeechSegment('một'), SpeechSegment('hai'), SpeechSegment('ba')]));
    await _tick();
    tts.finishCurrent(); // xong "một"
    await _tick();
    expect(tts.spoken.last, 'hai');
    fm.holdForUserInteraction(); // ngắt khi đang đọc "hai"
    await _wait(40);
    fm.holdForUserInteraction(); // vuốt tiếp
    await _wait(150);
    expect(tts.spoken, ['một', 'hai']);
  });

  test('Gợi ý Info: bị bỏ khi đang tạm im (cả câu đang chờ lẫn câu mới tới)', () async {
    final tts = _GatedTts();
    final fm = FeedbackManager(ttsService: tts, userInteractionHold: hold);
    unawaited(fm.speak('đang đọc', priority: FeedbackPriority.normal));
    await _tick();
    final queuedInfo = fm.speakSegmentsAndWait(const [SpeechSegment('Hãy đưa tờ tiền gần hơn')],
        priority: FeedbackPriority.info);
    fm.holdForUserInteraction();
    expect(await queuedInfo, isFalse);

    final lateInfo = fm.speakSegmentsAndWait(const [SpeechSegment('Chưa thấy chữ')],
        priority: FeedbackPriority.info);
    expect(await lateInfo, isFalse);
    await _wait(130);
    expect(tts.spoken.where((s) => s.contains('tờ tiền') || s.contains('Chưa thấy')), isEmpty);
  });

  test('Cảnh báo Urgent vẫn phát ngay khi đang tạm im và không bị TalkBack ngắt', () async {
    final tts = _GatedTts();
    final fm = FeedbackManager(ttsService: tts, userInteractionHold: hold);
    fm.holdForUserInteraction();
    unawaited(fm.speak('Cẩn thận! Người phía trước', priority: FeedbackPriority.urgent));
    await _tick();
    await _tick();
    expect(tts.spoken, ['Cẩn thận! Người phía trước']);
    final stopsBefore = tts.stops;
    fm.holdForUserInteraction();
    expect(tts.stops, stopsBefore, reason: 'không dừng câu khẩn cấp');
    expect(tts.speaking, isTrue);
  });

  test('Câu Normal mới tới khi đang tạm im -> chờ, rồi được đọc khi hết tạm im', () async {
    final tts = _GatedTts();
    final fm = FeedbackManager(ttsService: tts, userInteractionHold: hold);
    fm.holdForUserInteraction();
    unawaited(fm.speak('100.000 đồng'));
    await _wait(20);
    expect(tts.spoken, isEmpty);
    await _wait(120);
    expect(tts.spoken, ['100.000 đồng']);
  });

  test('releaseHold (người dùng chạm hai lần vào nút) -> đọc ngay, không chờ', () async {
    final tts = _GatedTts();
    final fm = FeedbackManager(
        ttsService: tts, userInteractionHold: const Duration(seconds: 10));
    fm.holdForUserInteraction();
    unawaited(fm.speak('Nghe lại kết quả'));
    await _tick();
    expect(tts.spoken, isEmpty);
    fm.releaseHold();
    await _tick();
    expect(tts.spoken, ['Nghe lại kết quả']);
    expect(fm.isHeld, isFalse);
    fm.dispose();
  });

  test('Watcher: chuyển tiêu điểm/cuộn = tạm im; chạm hai lần = kích hoạt', () {
    expect(TalkBackInteractionWatcher.isTrigger(ui.SemanticsAction.didGainAccessibilityFocus),
        isTrue);
    expect(TalkBackInteractionWatcher.isTrigger(ui.SemanticsAction.scrollDown), isTrue);
    expect(TalkBackInteractionWatcher.isTrigger(ui.SemanticsAction.tap), isFalse);
    expect(TalkBackInteractionWatcher.isTrigger(ui.SemanticsAction.didLoseAccessibilityFocus),
        isFalse);
    expect(TalkBackInteractionWatcher.isActivation(ui.SemanticsAction.tap), isTrue);
    expect(TalkBackInteractionWatcher.isActivation(ui.SemanticsAction.customAction), isTrue);
  });
}
