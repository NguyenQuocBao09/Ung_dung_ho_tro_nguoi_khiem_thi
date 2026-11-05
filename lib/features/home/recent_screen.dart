import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/strings_vi.dart';
import '../../core/feedback/feedback_manager.dart';
import '../../core/feedback/feedback_message.dart';
import '../../core/history/history_entry.dart';
import '../../core/history/history_notifier.dart';
import '../text_reading/domain/text_postprocessor.dart';

/// Màn hình "Gần đây": các kết quả đọc chữ / nhận diện tiền gần nhất, chạm để nghe lại.
class RecentScreen extends ConsumerWidget {
  const RecentScreen({super.key});

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Giờ:phút, kèm ngày/tháng nếu không phải hôm nay.
  static String formatTime(DateTime t, DateTime now) {
    final hm = '${_two(t.hour)}:${_two(t.minute)}';
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? hm : '$hm ngày ${t.day}/${t.month}';
  }

  static String typeLabel(HistoryType type) =>
      type == HistoryType.reading ? StringsVi.recentTypeReading : StringsVi.recentTypeCurrency;

  void _replay(WidgetRef ref, HistoryEntry e) {
    final feedback = ref.read(feedbackManagerProvider);
    // Ngắt lời đang đọc để nghe ngay mục được chọn.
    feedback.clearQueue();
    final segments = e.type == HistoryType.reading
        ? TextPostprocessor.buildSpeechSegments([e.text])
        : [SpeechSegment(e.text)];
    feedback.speakSegments(segments, priority: FeedbackPriority.normal);
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(StringsVi.recentClearConfirmTitle),
        content: const Text(StringsVi.recentClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(StringsVi.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(StringsVi.recentClearAll),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(historyProvider.notifier).clear();
      ref.read(feedbackManagerProvider).speak(
            StringsVi.recentCleared,
            priority: FeedbackPriority.info,
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(historyProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text(StringsVi.recentScreenTitle),
        leading: IconButton(
          tooltip: StringsVi.backButton,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              tooltip: StringsVi.recentClearAll,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history, size: 72, color: Color(0xFF80D8FF)),
                    const SizedBox(height: 16),
                    Semantics(
                      label: StringsVi.recentEmptyText,
                      child: const Text(
                        StringsVi.recentEmptyText,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    StringsVi.recentPrivacyNote,
                    style: TextStyle(fontSize: 14, color: Colors.white54),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    key: const ValueKey('recent_list'),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final title = '${typeLabel(e.type)} · ${formatTime(e.time, now)}';
                      return Semantics(
                        button: true,
                        label: '$title. ${e.text}',
                        hint: StringsVi.recentItemHint,
                        excludeSemantics: true,
                        onTap: () => _replay(ref, e),
                        child: InkWell(
                          onTap: () => _replay(ref, e),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 72),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    e.type == HistoryType.reading
                                        ? Icons.text_snippet_outlined
                                        : Icons.payments_outlined,
                                    size: 32,
                                    color: const Color(0xFF80D8FF),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                              fontSize: 14, color: Colors.white70),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          e.text,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.volume_up, size: 28),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
