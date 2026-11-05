import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/core/feedback/feedback_message.dart';
import 'package:vision_assist/features/text_reading/domain/language_segmenter.dart';
import 'package:vision_assist/features/text_reading/domain/read_session.dart';
import 'package:vision_assist/features/text_reading/domain/text_postprocessor.dart';

void main() {
  const seg = LanguageSegmenter();
  const vi = SpeechSegment.vietnamese;
  const en = SpeechSegment.english;

  group('LanguageSegmenter', () {
    test('Phân loại từ', () {
      expect(LanguageSegmenter.classifyWord('Việt'), 'vi');
      expect(LanguageSegmenter.classifyWord('đường'), 'vi');
      expect(LanguageSegmenter.classifyWord('reading'), 'en');
      expect(LanguageSegmenter.classifyWord('with'), 'en');
      expect(LanguageSegmenter.classifyWord('school,'), 'en');
      expect(LanguageSegmenter.classifyWord('the'), 'en?');
      expect(LanguageSegmenter.classifyWord('con'), isNull); // hợp lệ cả hai, mơ hồ
      expect(LanguageSegmenter.classifyWord('2026'), isNull);
    });

    test('Đoạn tiếng Việt thuần -> một đoạn giọng Việt', () {
      expect(seg.segment('Hôm nay trời đẹp, chúng tôi đi học.'),
          [const SpeechSegment('Hôm nay trời đẹp, chúng tôi đi học.', language: vi)]);
    });

    test('Đoạn tiếng Anh thuần -> giọng Anh', () {
      final r = seg.segment('The quick brown fox jumps over the lazy dog.');
      expect(r, hasLength(1));
      expect(r.single.language, en);
    });

    test('Câu tiếng Anh ngắn chỉ có từ thông dụng mơ hồ vẫn là tiếng Anh', () {
      expect(seg.segment('Go to the page').single.language, en);
    });

    test('Câu Việt có tên riêng tiếng Anh ngắn -> giữ giọng Việt', () {
      final r = seg.segment('Ứng dụng Google Lookout giúp người khiếm thị đọc chữ.');
      expect(r, hasLength(1));
      expect(r.single.language, vi);
    });

    test('Đoạn trộn: phần tiếng Anh đủ dài được tách sang giọng Anh', () {
      final r = seg.segment('Khẩu hiệu của trường là: Learning never stops for anyone. Hãy cố gắng mỗi ngày.');
      expect(r.map((s) => s.language).toList(), [vi, en, vi]);
      expect(r[1].text, contains('Learning never stops'));
    });
  });

  test('buildSpeechSegments thêm dấu chấm cuối đoạn và gộp đoạn cùng ngôn ngữ', () {
    final r = TextPostprocessor.buildSpeechSegments([
      'Chương một',
      'Mở đầu câu chuyện.',
      'Chapter one begins here with something',
    ]);
    expect(r, [
      const SpeechSegment('Chương một. Mở đầu câu chuyện.', language: vi),
      const SpeechSegment('Chapter one begins here with something.', language: en),
    ]);
  });

  group('readingOrder (trên xuống, trái sang phải)', () {
    test('Các dòng xếp chồng -> trên xuống', () {
      final order = readingOrder(const [
        TextRect(0.1, 0.5, 0.9, 0.55),
        TextRect(0.1, 0.1, 0.9, 0.15),
        TextRect(0.1, 0.3, 0.9, 0.35),
      ]);
      expect(order, [1, 2, 0]);
    });

    test('Hai mảnh trên cùng một hàng -> trái sang phải', () {
      final order = readingOrder(const [
        TextRect(0.55, 0.2, 0.9, 0.25),
        TextRect(0.1, 0.21, 0.5, 0.26),
      ]);
      expect(order, [1, 0]);
    });

    test('Tiêu đề + hai cột (cột phải nhiều khối) -> tiêu đề, cột trái, cột phải từ trên xuống', () {
      final order = readingOrder(const [
        TextRect(0.55, 0.5, 0.9, 0.8), // 0: cột phải, khối dưới
        TextRect(0.1, 0.2, 0.45, 0.9), // 1: cột trái
        TextRect(0.1, 0.05, 0.9, 0.12), // 2: tiêu đề
        TextRect(0.55, 0.2, 0.9, 0.45), // 3: cột phải, khối trên
      ]);
      expect(order, [2, 1, 3, 0]);
    });
  });

  test('ReadSession trả khung bao theo khối và đánh dấu đã đọc', () {
    final s = ReadSession();
    final t0 = DateTime(2026, 1, 1);
    const frame = [
      OcrLine(text: 'Dòng một của đoạn', blockIndex: 0, left: 0.1, top: 0.2, right: 0.8, bottom: 0.25),
      OcrLine(text: 'Dòng hai của đoạn', blockIndex: 0, left: 0.1, top: 0.26, right: 0.9, bottom: 0.31),
    ];
    final r1 = s.onFrame(frame, t0);
    expect(r1.blocks, hasLength(1));
    expect(r1.blocks.single.read, isFalse);
    expect(r1.blocks.single.rect, const TextRect(0.1, 0.2, 0.9, 0.31));
    s.onFrame(frame, t0.add(const Duration(milliseconds: 600)));
    final r3 = s.onFrame(frame, t0.add(const Duration(milliseconds: 1200)));
    expect(r3.paragraphs, ['Dòng một của đoạn Dòng hai của đoạn']);
    expect(r3.blocks.single.read, isTrue);
  });
}
