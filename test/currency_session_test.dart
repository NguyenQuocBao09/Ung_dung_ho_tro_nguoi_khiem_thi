import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/features/currency/domain/currency_session.dart';

void main() {
  group('CurrencySession Tests', () {
    test('1. Giữ nguyên tờ tiền chỉ đọc 1 lần', () {
      final session = CurrencySession();

      // Khung 1: 1 phiếu -> null
      expect(session.onFrame('100k', 0.90), isNull);
      // Khung 2: 2 phiếu -> null
      expect(session.onFrame('100k', 0.92), isNull);
      // Khung 3: 3 phiếu -> đọc '100k'
      expect(session.onFrame('100k', 0.88), '100k');
      expect(session.lastAnnounced, '100k');

      // Khung 4, 5, 6, 7: tờ tiền vẫn ở trong khung -> không đọc lại!
      expect(session.onFrame('100k', 0.95), isNull);
      expect(session.onFrame('100k', 0.91), isNull);
      expect(session.onFrame('100k', 0.89), isNull);
      expect(session.onFrame('100k', 0.93), isNull);
    });

    test('2. Bỏ tiền ra rồi đưa lại thì đọc lại', () {
      final session = CurrencySession(noneStreakThreshold: 4);

      // Đưa tờ 50k vào -> đọc sau 3 khung
      session.onFrame('50k', 0.90);
      session.onFrame('50k', 0.90);
      expect(session.onFrame('50k', 0.90), '50k');

      // Bỏ tiền ra: 1, 2, 3 khung "none" (chưa đủ 4 khung liên tiếp)
      expect(session.onFrame('none', 0.99), isNull);
      expect(session.onFrame('none', 0.99), isNull);
      expect(session.onFrame('none', 0.99), isNull);
      expect(session.currentActiveDenomination, '50k'); // Vẫn nhớ tờ 50k

      // Khung "none" thứ 4 liên tiếp -> giải phóng tờ tiền
      expect(session.onFrame('none', 0.99), isNull);
      expect(session.currentActiveDenomination, isNull);

      // Đưa lại tờ 50k: sau 3 khung thì đọc lại thành công!
      expect(session.onFrame('50k', 0.92), isNull);
      expect(session.onFrame('50k', 0.95), isNull);
      expect(session.onFrame('50k', 0.91), '50k');
    });

    test('3. Đổi mệnh giá thì đọc mệnh giá mới', () {
      final session = CurrencySession();

      // Đang cầm tờ 20k
      session.onFrame('20k', 0.90);
      session.onFrame('20k', 0.90);
      expect(session.onFrame('20k', 0.90), '20k');

      // Đổi sang tờ 500k: nhận 3 phiếu 500k
      expect(session.onFrame('500k', 0.91), isNull);
      expect(session.onFrame('500k', 0.92), isNull);
      // Đủ 3 phiếu 500k -> đọc ngay mệnh giá mới!
      expect(session.onFrame('500k', 0.95), '500k');
      expect(session.lastAnnounced, '500k');
    });

    test('4. Nhiễu thấp conf không kích hoạt đọc', () {
      final session = CurrencySession(confidenceThreshold: 0.85);

      // Đưa các khung có độ tin cậy thấp (< 0.85)
      expect(session.onFrame('10k', 0.80), isNull);
      expect(session.onFrame('10k', 0.75), isNull);
      expect(session.onFrame('10k', 0.84), isNull);
      expect(session.onFrame('10k', 0.70), isNull);
      expect(session.onFrame('10k', 0.82), isNull);

      // Cửa sổ phiếu vẫn trống do bị loại bỏ bởi ngưỡng tin cậy
      expect(session.voteWindow, isEmpty);
      expect(session.lastAnnounced, isNull);
    });

    test('5. Chuỗi toàn "none" không đọc gì', () {
      final session = CurrencySession();

      for (int i = 0; i < 10; i++) {
        expect(session.onFrame('none', 0.99), isNull);
      }
      expect(session.lastAnnounced, isNull);
      expect(session.voteWindow, isEmpty);
      expect(session.noneStreak, 10);
    });

    test('reset() và resetActiveBill() hoạt động chuẩn xác', () {
      final session = CurrencySession();

      session.onFrame('200k', 0.95);
      session.onFrame('200k', 0.95);
      expect(session.onFrame('200k', 0.95), '200k');

      // Hành động 'Tờ khác' (resetActiveBill)
      session.resetActiveBill();
      expect(session.currentActiveDenomination, isNull);
      expect(session.lastAnnounced, '200k'); // Vẫn giữ để có thể đọc lại

      // Cho phép nhận diện lại 200k ngay lập tức sau 3 khung
      session.onFrame('200k', 0.95);
      session.onFrame('200k', 0.95);
      expect(session.onFrame('200k', 0.95), '200k');

      // reset() xóa sạch toàn bộ
      session.reset();
      expect(session.lastAnnounced, isNull);
      expect(session.currentActiveDenomination, isNull);
      expect(session.voteWindow, isEmpty);
      expect(session.noneStreak, 0);
    });
  });
}

