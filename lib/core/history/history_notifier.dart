import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'history_entry.dart';

/// Nơi lưu danh sách lịch sử (tách ra để kiểm thử không cần plugin).
abstract class HistoryStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPrefsHistoryStorage implements HistoryStorage {
  static const _key = 'history_v1';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(_key, value);
}

/// Danh sách "Gần đây", mới nhất ở đầu. Lưu cục bộ trên máy, không gửi đi đâu.
class HistoryNotifier extends StateNotifier<List<HistoryEntry>> {
  /// Số mục tối đa giữ lại.
  static const int maxEntries = 50;

  /// Cùng loại + cùng nội dung trong khoảng này coi là một lần đọc lặp.
  static const Duration duplicateWindow = Duration(minutes: 2);

  final HistoryStorage _storage;
  bool _loaded = false;
  final List<HistoryEntry> _pendingBeforeLoad = [];

  HistoryNotifier(this._storage) : super(const []) {
    _load();
  }

  Future<void> _load() async {
    try {
      final stored = HistoryEntry.decodeList(await _storage.read());
      if (!mounted) return;
      state = stored;
    } catch (e) {
      debugPrint('HistoryNotifier: không đọc được lịch sử ($e)');
    }
    _loaded = true;
    // Mục phát sinh trong lúc đang nạp được thêm vào sau, theo đúng thứ tự.
    final pending = List<HistoryEntry>.of(_pendingBeforeLoad);
    _pendingBeforeLoad.clear();
    for (final e in pending) {
      add(e.type, e.text, now: e.time);
    }
  }

  /// Thêm một kết quả vừa đọc. Văn bản rỗng hoặc lặp gần đây bị bỏ qua.
  void add(HistoryType type, String text, {DateTime? now}) {
    if (!mounted) return;
    final clean = text.trim();
    if (clean.isEmpty) return;
    final time = now ?? DateTime.now();
    if (!_loaded) {
      _pendingBeforeLoad.add(HistoryEntry(type: type, text: clean, time: time));
      return;
    }
    final dup = state.any((e) =>
        e.type == type &&
        e.text == clean &&
        time.difference(e.time).abs() < duplicateWindow);
    if (dup) return;
    final next = [HistoryEntry(type: type, text: clean, time: time), ...state];
    state = next.length > maxEntries ? next.sublist(0, maxEntries) : next;
    _persist();
  }

  Future<void> clear() async {
    state = const [];
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await _storage.write(HistoryEntry.encodeList(state));
    } catch (e) {
      debugPrint('HistoryNotifier: không lưu được lịch sử ($e)');
    }
  }
}

final historyStorageProvider = Provider<HistoryStorage>((ref) => SharedPrefsHistoryStorage());

final historyProvider = StateNotifierProvider<HistoryNotifier, List<HistoryEntry>>((ref) {
  return HistoryNotifier(ref.watch(historyStorageProvider));
});
