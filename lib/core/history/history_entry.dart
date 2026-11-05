import 'dart:convert';

/// Loại kết quả được lưu trong màn hình "Gần đây".
enum HistoryType { reading, currency }

/// Một kết quả đã đọc ra cho người dùng (chỉ lưu văn bản, không lưu ảnh).
class HistoryEntry {
  final HistoryType type;
  final String text;
  final DateTime time;

  const HistoryEntry({required this.type, required this.text, required this.time});

  Map<String, dynamic> toJson() => {
        't': type.name,
        'x': text,
        'ms': time.millisecondsSinceEpoch,
      };

  /// Trả về null nếu dữ liệu hỏng / sai định dạng (bỏ qua thay vì làm app lỗi).
  static HistoryEntry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final t = raw['t'];
    final x = raw['x'];
    final ms = raw['ms'];
    if (t is! String || x is! String || ms is! int || x.trim().isEmpty) return null;
    final type = HistoryType.values.where((e) => e.name == t).firstOrNull;
    if (type == null) return null;
    return HistoryEntry(
      type: type,
      text: x,
      time: DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  static String encodeList(List<HistoryEntry> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<HistoryEntry> decodeList(String? source) {
    if (source == null || source.isEmpty) return const [];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return const [];
      return decoded.map(HistoryEntry.tryFromJson).whereType<HistoryEntry>().toList();
    } catch (_) {
      return const [];
    }
  }
}
