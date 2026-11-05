import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/core/constants/strings_vi.dart';
import 'package:vision_assist/core/feedback/feedback_manager.dart';
import 'package:vision_assist/core/feedback/feedback_message.dart';
import 'package:vision_assist/core/feedback/tts_service.dart';
import 'package:vision_assist/features/text_reading/domain/read_session.dart';
import 'package:vision_assist/features/text_reading/domain/text_postprocessor.dart';
import 'package:vision_assist/features/text_reading/presentation/reading_controller.dart';
import 'package:vision_assist/features/text_reading/presentation/reading_overlay.dart';

class _FakeTtsService extends TtsService {
  final List<String> spokenTexts = [];
  final List<String> languages = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text, {bool interrupt = true, String language = 'vi-VN'}) async {
    spokenTexts.add(text);
    languages.add(language);
  }

  @override
  Future<void> speakAndWait(String text, {String language = 'vi-VN'}) async {
    spokenTexts.add(text);
    languages.add(language);
  }

  @override
  Future<void> stop() async {}
}

class _FakeReadingController extends StateNotifier<ReadingState>
    implements ReadingController {
  _FakeReadingController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('TextPostprocessor Tests', () {
    test('calculateAverageLuminance computes correct sparse sample mean', () {
      final darkBytes = Uint8List.fromList(List.filled(100, 20));
      final brightBytes = Uint8List.fromList(List.filled(100, 200));

      expect(TextPostprocessor.calculateAverageLuminance(darkBytes, step: 2), 20.0);
      expect(TextPostprocessor.calculateAverageLuminance(brightBytes, step: 4), 200.0);
      expect(TextPostprocessor.calculateAverageLuminance(Uint8List(0)), 255.0);
    });

    test('joinLinesForSpeech formats sentences properly', () {
      final lines = ['Cộng hòa xã hội', 'chủ nghĩa Việt Nam', 'Độc lập tự do'];
      expect(
        TextPostprocessor.joinLinesForSpeech(lines),
        'Cộng hòa xã hội. chủ nghĩa Việt Nam. Độc lập tự do',
      );
      expect(TextPostprocessor.joinLinesForSpeech([]), '');
      // Đoạn đã có dấu câu cuối -> không thêm dấu chấm thừa.
      expect(
        TextPostprocessor.joinLinesForSpeech(['Xin chào.', 'Hôm nay trời đẹp']),
        'Xin chào. Hôm nay trời đẹp',
      );
    });
  });

  group('FeedbackManager Queue Tests', () {
    test('Queues max 3 sentences and drops oldest when exceeded', () async {
      final fakeTts = _FakeTtsService();
      final manager = FeedbackManager(ttsService: fakeTts);

      manager.speak('Câu một');
      manager.speak('Câu hai');
      manager.speak('Câu ba');
      manager.speak('Câu bốn');

      expect(manager.queueLength, lessThanOrEqualTo(FeedbackManager.maxQueueSize));

      manager.clearQueue();
      expect(manager.queueLength, 0);
    });

    test('Urgent priority clears queue and interrupts immediately', () async {
      final fakeTts = _FakeTtsService();
      final manager = FeedbackManager(ttsService: fakeTts);

      await manager.speak('Câu bình thường 1');
      await manager.speak('Câu khẩn cấp', priority: FeedbackPriority.urgent);

      expect(fakeTts.spokenTexts, contains('Câu khẩn cấp'));
    });

    test('Câu nhiều ngôn ngữ được đọc liền, mỗi đoạn đúng giọng', () async {
      final fakeTts = _FakeTtsService();
      final manager = FeedbackManager(ttsService: fakeTts);

      await manager.speakSegments(const [
        SpeechSegment('Xin chào các bạn.'),
        SpeechSegment('Welcome to our school.', language: SpeechSegment.english),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(fakeTts.spokenTexts, ['Xin chào các bạn.', 'Welcome to our school.']);
      expect(fakeTts.languages, ['vi-VN', 'en-US']);
      expect(manager.queueLength, 0);
    });
  });

  group('ReadingOverlay Widget Tests', () {
    testWidgets('Excludes recognized text from Semantics tree for TalkBack', (tester) async {
      const state = ReadingState(
        isStreaming: true,
        currentLines: ['Văn bản dòng 1', 'Văn bản dòng 2'],
        blocks: [
          TextBlockBox(blockIndex: 0, rect: TextRect(0.1, 0.2, 0.9, 0.3), read: false),
        ],
        imageWidth: 720,
        imageHeight: 1280,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readingControllerProvider.overrideWith(
              (ref) => _FakeReadingController(state),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ReadingOverlay(),
            ),
          ),
        ),
      );

      // Widget hiển thị trực quan
      expect(find.text('Văn bản dòng 1'), findsOneWidget);
      expect(find.text('Văn bản dòng 2'), findsOneWidget);

      // Kiểm tra vùng văn bản nhận dạng nằm bên trong ExcludeSemantics
      final textFinder = find.text('Văn bản dòng 1');
      expect(
        find.ancestor(of: textFinder, matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );

      // Có khối văn bản -> vẽ khung bao (nằm trong ExcludeSemantics).
      expect(find.byKey(const ValueKey('reading_block_boxes')), findsOneWidget);

      // Nút Tạm dừng / Tiếp tục có mặt với Semantics rõ ràng
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('Displays play icon and paused badge when state is paused', (tester) async {
      const state = ReadingState(
        isPaused: true,
        currentLines: ['Hóa đơn thanh toán'],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readingControllerProvider.overrideWith(
              (ref) => _FakeReadingController(state),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ReadingOverlay(),
            ),
          ),
        ),
      );

      expect(find.text(StringsVi.readingStatusPaused), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });
  });
}
