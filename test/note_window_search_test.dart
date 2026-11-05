import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/features/currency/domain/note_window_search.dart';

void main() {
  const search = NoteWindowSearch();

  group('NoteWindowSearch.coarseWindows', () {
    test('Có toàn khung và mọi vùng nằm trong ảnh', () {
      final ws = search.coarseWindows(480, 640);
      expect(ws.first.isFull, isTrue);
      expect(ws.length, 25);
      for (final w in ws) {
        expect(w.left, greaterThanOrEqualTo(-1e-9));
        expect(w.top, greaterThanOrEqualTo(-1e-9));
        expect(w.right, lessThanOrEqualTo(1 + 1e-9));
        expect(w.bottom, lessThanOrEqualTo(1 + 1e-9));
      }
    });

    test('Vùng có tỉ lệ tờ tiền ~2.2:1 (ngang hoặc dọc) theo pixel', () {
      final ws = search.coarseWindows(480, 640).skip(1);
      for (final w in ws) {
        final pw = w.width * 480;
        final ph = w.height * 640;
        final ratio = pw > ph ? pw / ph : ph / pw;
        expect(ratio, closeTo(2.2, 0.01));
      }
    });

    test('Ảnh ngang (landscape) vẫn sinh vùng hợp lệ', () {
      final ws = search.coarseWindows(640, 480);
      expect(ws.length, greaterThan(1));
      for (final w in ws) {
        expect(w.right, lessThanOrEqualTo(1 + 1e-9));
        expect(w.bottom, lessThanOrEqualTo(1 + 1e-9));
      }
    });
  });

  group('NoteWindowSearch.refineWindows', () {
    test('Toàn khung thì không tinh chỉnh', () {
      expect(search.refineWindows(NormRect.full), isEmpty);
    });

    test('6 vùng tinh chỉnh, đều nằm trong ảnh', () {
      const best = NormRect(0.0, 0.0, 0.6, 0.2);
      final ws = search.refineWindows(best);
      expect(ws.length, 6);
      for (final w in ws) {
        expect(w.left, greaterThanOrEqualTo(0));
        expect(w.top, greaterThanOrEqualTo(0));
        expect(w.right, lessThanOrEqualTo(1 + 1e-9));
        expect(w.bottom, lessThanOrEqualTo(1 + 1e-9));
      }
    });
  });

  group('NoteWindowSearch.trackingWindows', () {
    test('Vùng cũ + 6 vùng tinh chỉnh, vùng cũ lệch ra ngoài được kéo vào trong', () {
      final ws = search.trackingWindows(const NormRect(0.7, 0.1, 1.1, 0.3));
      expect(ws.length, 7);
      expect(ws.first.right, closeTo(1, 1e-9));
      expect(ws.first.width, closeTo(0.4, 1e-9));
    });

    test('Bám theo toàn khung -> chỉ một vùng', () {
      expect(search.trackingWindows(NormRect.full).length, 1);
    });
  });

  group('NoteWindowSearch.fuseBox', () {
    test('Gộp vùng cùng lớp, chồng lấn; bỏ vùng khác lớp, điểm thấp và toàn khung', () {
      const a = NormRect(0.1, 0.1, 0.5, 0.3);
      const b = NormRect(0.2, 0.1, 0.6, 0.3);
      final scores = [
        const WindowScore(a, 3, 0.9),
        const WindowScore(b, 3, 0.9),
        const WindowScore(NormRect(0.5, 0.6, 0.9, 0.8), 1, 0.95), // khác lớp
        const WindowScore(NormRect(0.12, 0.1, 0.52, 0.3), 3, 0.3), // điểm thấp
        const WindowScore(NormRect.full, 3, 0.9), // toàn khung
      ];
      final box = NoteWindowSearch.fuseBox(scores, scores[0]);
      expect(box.left, closeTo(0.15, 1e-9));
      expect(box.right, closeTo(0.55, 1e-9));
      expect(box.top, closeTo(0.1, 1e-9));
      expect(box.bottom, closeTo(0.3, 1e-9));
    });

    test('Vùng tốt nhất là toàn khung -> khung bao là toàn khung', () {
      final scores = [const WindowScore(NormRect.full, 0, 0.99)];
      expect(NoteWindowSearch.fuseBox(scores, scores[0]).isFull, isTrue);
    });

    test('support() chỉ đếm vùng cùng lớp, đủ xác suất và chồng lấn', () {
      const best = WindowScore(NormRect(0.1, 0.1, 0.5, 0.3), 3, 0.95);
      final scores = [
        best,
        const WindowScore(NormRect(0.15, 0.1, 0.55, 0.3), 3, 0.92),
        const WindowScore(NormRect(0.1, 0.12, 0.5, 0.32), 3, 0.80), // xác suất thấp
        const WindowScore(NormRect(0.12, 0.1, 0.52, 0.3), 5, 0.99), // khác lớp
        const WindowScore(NormRect(0.6, 0.6, 1.0, 0.8), 3, 0.97), // không chồng lấn
      ];
      expect(NoteWindowSearch.support(scores, best, 0.9), 2);
    });

    test('best() chọn xác suất cao nhất; rỗng -> null', () {
      expect(NoteWindowSearch.best(const []), isNull);
      final s = [
        const WindowScore(NormRect.full, 0, 0.2),
        const WindowScore(NormRect(0, 0, 0.5, 0.5), 2, 0.7),
      ];
      expect(NoteWindowSearch.best(s)!.classIndex, 2);
    });
  });

  group('NormRect', () {
    test('IoU', () {
      const a = NormRect(0, 0, 0.5, 0.5);
      expect(a.iou(a), closeTo(1, 1e-9));
      expect(a.iou(const NormRect(0.5, 0.5, 1, 1)), 0);
      expect(a.iou(const NormRect(0.25, 0, 0.75, 0.5)), closeTo(1 / 3, 1e-9));
    });

    test('clampInside giữ kích thước, đẩy vào trong ảnh', () {
      final r = const NormRect(-0.1, 0.8, 0.3, 1.2).clampInside();
      expect(r.left, 0);
      expect(r.width, closeTo(0.4, 1e-9));
      expect(r.bottom, closeTo(1, 1e-9));
    });
  });

  group('BoxSmoother', () {
    test('Làm mượt khi cùng nhãn, nhảy ngay khi đổi nhãn hoặc reset', () {
      final s = BoxSmoother(alpha: 0.5);
      s.update(const NormRect(0, 0, 0.4, 0.4), '50k');
      final m = s.update(const NormRect(0.2, 0, 0.6, 0.4), '50k');
      expect(m.left, closeTo(0.1, 1e-9));

      final j = s.update(const NormRect(0.5, 0.5, 0.9, 0.9), '100k');
      expect(j.left, closeTo(0.5, 1e-9));

      s.reset();
      expect(s.box, isNull);
    });

    test('Vùng mới không chồng lấn (cùng nhãn) -> nhảy ngay', () {
      final s = BoxSmoother(alpha: 0.5);
      s.update(const NormRect(0, 0, 0.2, 0.2), '10k');
      final j = s.update(const NormRect(0.7, 0.7, 0.9, 0.9), '10k');
      expect(j.left, closeTo(0.7, 1e-9));
    });
  });
}
