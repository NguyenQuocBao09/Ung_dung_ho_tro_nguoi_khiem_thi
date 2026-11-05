import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/features/text_reading/domain/read_session.dart';

void main() {
  group('Levenshtein and Normalization Tests', () {
    test('levenshteinDistance computes correct distance', () {
      expect(levenshteinDistance('kitten', 'sitting'), 3);
      expect(levenshteinDistance('việt nam', 'việt nam'), 0);
      expect(levenshteinDistance('', 'abc'), 3);
      expect(levenshteinDistance('abc', ''), 3);
    });

    test('normalizedLevenshteinSimilarity handles edge cases', () {
      expect(normalizedLevenshteinSimilarity('hello', 'hello'), 1.0);
      expect(normalizedLevenshteinSimilarity('', ''), 1.0);
      expect(normalizedLevenshteinSimilarity('cộng hòa', 'cọng hòa'), greaterThanOrEqualTo(0.85));
      expect(normalizedLevenshteinSimilarity('chào bạn', 'tạm biệt'), lessThan(0.5));
    });

    test('normalizeText lowercases, strips punctuation, collapses whitespace, keeps Unicode', () {
      final session = ReadSession();
      expect(
        session.normalizeText('  Chào Bạn,   Việt Nam 123!???  '),
        'chào bạn việt nam 123',
      );
      expect(
        session.normalizeText('Độc lập - Tự do - Hạnh phúc...'),
        'độc lập tự do hạnh phúc',
      );
    });

    test('isValidLine rejects strings shorter than 3 chars or with < 60% letters', () {
      final session = ReadSession();
      // Length < 3
      expect(session.isValidLine('ab'), isFalse);
      expect(session.isValidLine('a'), isFalse);
      expect(session.isValidLine(''), isFalse);

      // Letter ratio < 60%
      expect(session.isValidLine('123456'), isFalse);
      expect(session.isValidLine('123 456'), isFalse);
      expect(session.isValidLine('a 1 2 3'), isFalse); // 1 letter out of 4 non-space = 25%

      // Valid lines
      expect(session.isValidLine('abc'), isTrue); // 100% letters
      expect(session.isValidLine('chào bạn'), isTrue); // 100% letters
      expect(session.isValidLine('hóa đơn 123'), isTrue); // 6 letters / 9 non-space = 66.7%
    });
  });

  group('ReadSession Workflow Tests', () {
    final t0 = DateTime(2026, 1, 1, 10, 0, 0);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('A line is read only when appearing in at least 3 of last 4 frames', () {
      final session = ReadSession();

      expect(session.onTextFrame(['Cộng hòa xã hội!'], at(0)).paragraphs, isEmpty);
      expect(session.onTextFrame(['Cộng hòa xã hội.'], at(600)).paragraphs, isEmpty);
      // Khung 3 OCR sai dấu, nhưng câu được đọc là biến thể ổn định (medoid),
      // không phải biến thể sai của khung hiện tại.
      final f3 = session.onTextFrame(['Cọng hòa xã hội'], at(1200)).paragraphs;
      expect(f3, hasLength(1));
      expect(f3.single, startsWith('Cộng hòa xã hội'));

      // Đã đọc rồi -> không đọc lại.
      expect(session.onTextFrame(['Cộng hòa xã hội'], at(1800)).paragraphs, isEmpty);
    });

    test('Biến thể OCR sai của dòng đã đọc không bị đọc lại như dòng mới', () {
      final session = ReadSession();
      for (var i = 0; i < 3; i++) {
        session.onTextFrame(['Học sinh đến trường lúc bảy giờ sáng'], at(i * 600));
      }
      expect(session.readLines, hasLength(1));
      // Sai vài ký tự (similarity < 0.85 nhưng >= 0.7) -> vẫn là dòng cũ.
      for (var i = 3; i < 8; i++) {
        final r = session.onTextFrame(['Hoc sinh dên truòng lúc bảy giớ sáng'], at(i * 600));
        expect(r.paragraphs, isEmpty);
      }
      // Dòng bị cắt một phần ở khung sau cũng không bị đọc lại.
      for (var i = 8; i < 12; i++) {
        expect(session.onTextFrame(['đến trường lúc bảy giờ'], at(i * 600)).paragraphs, isEmpty);
      }
    });

    test('Đọc cả đoạn theo thứ tự trên xuống, ghép các dòng cùng khối', () {
      final session = ReadSession();
      // ML Kit trả khối/dòng không theo thứ tự hiển thị.
      const frame = [
        OcrLine(text: 'Đoạn hai dòng một', blockIndex: 0, left: 0.1, top: 0.6, right: 0.9, bottom: 0.65),
        OcrLine(text: 'Đoạn một dòng hai', blockIndex: 1, left: 0.1, top: 0.3, right: 0.9, bottom: 0.35),
        OcrLine(text: 'Đoạn một dòng một', blockIndex: 1, left: 0.1, top: 0.2, right: 0.9, bottom: 0.25),
      ];
      expect(session.onFrame(frame, at(0)).paragraphs, isEmpty);
      expect(session.onFrame(frame, at(600)).paragraphs, isEmpty);
      final r = session.onFrame(frame, at(1200));
      expect(r.paragraphs, ['Đoạn một dòng một Đoạn một dòng hai', 'Đoạn hai dòng một']);
    });

    test('Chờ dòng chưa ổn định để đọc đúng thứ tự, nhưng không chờ mãi', () {
      final session = ReadSession();
      const a = OcrLine(text: 'Dòng đầu tiên của trang', top: 0.2, bottom: 0.25);
      const b = OcrLine(text: 'Dòng thứ hai xuất hiện muộn', top: 0.3, bottom: 0.35);
      session.onFrame([a], at(0));
      session.onFrame([a], at(600));
      // Khung 3: a đã ổn định nhưng b mới xuất hiện -> chờ để đọc cả hai theo thứ tự.
      expect(session.onFrame([a, b], at(1200)).paragraphs, isEmpty);
      session.onFrame([a, b], at(1800));
      final r = session.onFrame([a, b], at(2400));
      expect(r.paragraphs, ['Dòng đầu tiên của trang Dòng thứ hai xuất hiện muộn']);

      // Nhiễu mới liên tục mỗi khung không chặn việc đọc quá maxWaitFrames.
      final s2 = ReadSession();
      const c = OcrLine(text: 'Nội dung chính cần đọc', top: 0.2, bottom: 0.25);
      final noise = ['xqzt wvkp', 'mmbr ttqa', 'plok jjuy', 'zzaw eerx', 'hhgf ddsa'];
      final read = <String>[];
      for (var i = 0; i < 5; i++) {
        read.addAll(s2.onFrame([c, OcrLine(text: noise[i], top: 0.5, bottom: 0.55)], at(i * 600)).paragraphs);
      }
      expect(read, ['Nội dung chính cần đọc']);
    });

    test('Bỏ qua dòng chạm mép khung hình và đếm số dòng bị cắt', () {
      final session = ReadSession();
      const cut = OcrLine(text: 'chữ bị cắt ở mép', left: 0.0, top: 0.4, right: 0.7, bottom: 0.45);
      for (var i = 0; i < 4; i++) {
        final r = session.onFrame([cut], at(i * 600));
        expect(r.paragraphs, isEmpty);
        expect(r.edgeCutLines, 1);
        expect(r.visibleLines, 0);
      }
    });

    test('Session resets when no text is seen for 3 seconds', () {
      final session = ReadSession(silenceResetDuration: const Duration(seconds: 3));

      session.onTextFrame(['Xin chào quý khách'], at(0));
      session.onTextFrame(['Xin chào quý khách'], at(500));
      final read = session.onTextFrame(['Xin chào quý khách'], at(1000));
      expect(read.paragraphs, ['Xin chào quý khách']);
      expect(session.readLines, contains('Xin chào quý khách'));

      session.onTextFrame([], at(2000));
      expect(session.readLines, isNotEmpty);

      session.onTextFrame([], at(5000));
      expect(session.readLines, isEmpty);
      expect(session.recentFrames, isEmpty);

      session.onTextFrame(['Xin chào quý khách'], at(5500));
      session.onTextFrame(['Xin chào quý khách'], at(6000));
      expect(session.onTextFrame(['Xin chào quý khách'], at(6500)).paragraphs, ['Xin chào quý khách']);
    });

    test('reset() clears all session state immediately', () {
      final session = ReadSession();

      session.onTextFrame(['Dòng thứ nhất'], at(0));
      session.onTextFrame(['Dòng thứ nhất'], at(500));
      session.onTextFrame(['Dòng thứ nhất'], at(1000));

      expect(session.readLines, contains('Dòng thứ nhất'));
      session.reset();
      expect(session.readLines, isEmpty);
      expect(session.recentFrames, isEmpty);
      expect(session.lastSeenTextTime, isNull);
    });
  });
}

