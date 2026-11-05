import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/core/history/history_entry.dart';
import 'package:vision_assist/core/history/history_notifier.dart';
import 'package:vision_assist/features/home/recent_screen.dart';

class _MemStorage implements HistoryStorage {
  String? value;
  int writes = 0;
  _MemStorage([this.value]);

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async {
    value = v;
    writes++;
  }
}

Future<HistoryNotifier> _make(_MemStorage s) async {
  final n = HistoryNotifier(s);
  await Future<void>.delayed(Duration.zero);
  return n;
}

void main() {
  final t0 = DateTime(2026, 11, 4, 10);

  group('HistoryEntry', () {
    test('encode/decode khứ hồi', () {
      final src = [HistoryEntry(type: HistoryType.currency, text: '50.000 đồng', time: t0)];
      final back = HistoryEntry.decodeList(HistoryEntry.encodeList(src));
      expect(back.single.type, HistoryType.currency);
      expect(back.single.text, '50.000 đồng');
      expect(back.single.time, t0);
    });

    test('dữ liệu hỏng -> danh sách rỗng, mục sai bị bỏ qua', () {
      expect(HistoryEntry.decodeList('không phải json'), isEmpty);
      expect(HistoryEntry.decodeList('{"a":1}'), isEmpty);
      expect(HistoryEntry.decodeList(null), isEmpty);
      const mixed = '[{"t":"reading","x":"ok","ms":1},{"t":"lạ","x":"a","ms":1},{"t":"reading","x":"","ms":1},5]';
      expect(HistoryEntry.decodeList(mixed).map((e) => e.text), ['ok']);
    });
  });

  group('HistoryNotifier', () {
    test('mới nhất ở đầu, bỏ qua rỗng, và lưu xuống storage', () async {
      final s = _MemStorage();
      final n = await _make(s);
      n.add(HistoryType.reading, 'một', now: t0);
      n.add(HistoryType.reading, '   ', now: t0);
      n.add(HistoryType.currency, 'hai', now: t0.add(const Duration(seconds: 5)));
      expect(n.state.map((e) => e.text), ['hai', 'một']);
      expect(HistoryEntry.decodeList(s.value).length, 2);
    });

    test('lặp cùng nội dung trong 2 phút bị bỏ; sau đó được thêm lại', () async {
      final n = await _make(_MemStorage());
      n.add(HistoryType.currency, '100.000 đồng', now: t0);
      n.add(HistoryType.currency, '100.000 đồng', now: t0.add(const Duration(seconds: 30)));
      expect(n.state.length, 1);
      n.add(HistoryType.currency, '100.000 đồng', now: t0.add(const Duration(minutes: 5)));
      expect(n.state.length, 2);
      // Khác loại thì không phải trùng.
      n.add(HistoryType.reading, '100.000 đồng', now: t0.add(const Duration(minutes: 5)));
      expect(n.state.length, 3);
    });

    test('giới hạn ${HistoryNotifier.maxEntries} mục, giữ mục mới', () async {
      final n = await _make(_MemStorage());
      for (var i = 0; i < HistoryNotifier.maxEntries + 10; i++) {
        n.add(HistoryType.reading, 'mục $i', now: t0.add(Duration(minutes: 10 * i)));
      }
      expect(n.state.length, HistoryNotifier.maxEntries);
      expect(n.state.first.text, 'mục ${HistoryNotifier.maxEntries + 9}');
    });

    test('nạp lịch sử cũ khi khởi động; mục thêm trong lúc nạp không bị mất', () async {
      final old = HistoryEntry.encodeList(
          [HistoryEntry(type: HistoryType.reading, text: 'cũ', time: t0)]);
      final s = _MemStorage(old);
      final n = HistoryNotifier(s);
      n.add(HistoryType.reading, 'mới', now: t0.add(const Duration(hours: 1)));
      await Future<void>.delayed(Duration.zero);
      expect(n.state.map((e) => e.text), ['mới', 'cũ']);
    });

    test('clear xóa cả trong storage', () async {
      final s = _MemStorage();
      final n = await _make(s);
      n.add(HistoryType.reading, 'a', now: t0);
      await n.clear();
      expect(n.state, isEmpty);
      expect(HistoryEntry.decodeList(s.value), isEmpty);
    });
  });

  group('RecentScreen', () {
    testWidgets('rỗng -> hiện thông báo; có mục -> hiện danh sách có nhãn Semantics', (tester) async {
      final s = _MemStorage();
      final container = ProviderContainer(overrides: [
        historyStorageProvider.overrideWithValue(s),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RecentScreen()),
      ));
      await tester.pump();
      expect(find.text('Chưa có kết quả nào được lưu gần đây.'), findsOneWidget);

      container.read(historyProvider.notifier).add(HistoryType.currency, '20.000 đồng');
      await tester.pump();
      expect(find.byKey(const ValueKey('recent_list')), findsOneWidget);
      expect(find.text('20.000 đồng'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Nhận diện tiền.*20.000 đồng')), findsOneWidget);
    });

    test('formatTime: hôm nay chỉ giờ, ngày khác kèm ngày/tháng', () {
      final now = DateTime(2026, 11, 4, 12);
      expect(RecentScreen.formatTime(DateTime(2026, 11, 4, 9, 5), now), '09:05');
      expect(RecentScreen.formatTime(DateTime(2026, 11, 3, 23, 40), now), '23:40 ngày 3/11');
    });
  });
}
