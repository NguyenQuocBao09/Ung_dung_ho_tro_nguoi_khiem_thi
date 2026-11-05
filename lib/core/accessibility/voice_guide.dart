import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/strings_vi.dart';
import '../feedback/feedback_manager.dart';
import '../feedback/feedback_message.dart';

/// Lưu cờ "đã nghe hướng dẫn lần đầu" (tách ra để kiểm thử không cần plugin).
abstract class GuideFlagStorage {
  Future<bool> isDone();
  Future<void> markDone();
}

class SharedPrefsGuideFlagStorage implements GuideFlagStorage {
  static const _key = 'voice_guide_done_v1';

  @override
  Future<bool> isDone() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> markDone() async =>
      (await SharedPreferences.getInstance()).setBool(_key, true);
}

/// Hướng dẫn sử dụng bằng giọng nói (lần đầu mở app và khi bấm nút Hướng dẫn).
class VoiceGuide {
  final GuideFlagStorage _storage;
  final List<String> steps;

  VoiceGuide(this._storage, {this.steps = StringsVi.voiceGuideSteps});

  /// `true` nếu chưa từng nghe hết / chủ động bỏ qua hướng dẫn.
  /// Không đọc được bộ nhớ -> trả `false` để không làm phiền người dùng mỗi lần mở.
  Future<bool> shouldAutoPlay() async {
    try {
      return !(await _storage.isDone());
    } catch (e) {
      debugPrint('VoiceGuide: không đọc được cờ hướng dẫn ($e)');
      return false;
    }
  }

  Future<void> markDone() async {
    try {
      await _storage.markDone();
    } catch (e) {
      debugPrint('VoiceGuide: không lưu được cờ hướng dẫn ($e)');
    }
  }

  /// Tách từng bước thành các đoạn đọc; tên app tiếng Anh ("Vision Assist") được
  /// đọc bằng giọng en-US (nếu máy có) thay vì giọng Việt.
  static List<SpeechSegment> buildSegments(List<String> steps) {
    const name = StringsVi.appTitle;
    final out = <SpeechSegment>[];
    for (final step in steps) {
      final parts = step.split(name);
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) out.add(const SpeechSegment(name, language: SpeechSegment.english));
        if (parts[i].trim().isNotEmpty) out.add(SpeechSegment(parts[i]));
      }
    }
    return out;
  }

  /// Đọc toàn bộ hướng dẫn qua [FeedbackManager] (một mục hàng đợi duy nhất để
  /// không bị câu khác chen giữa). Ngắt mọi lời đang đọc trước đó.
  /// Trả về `true` nếu đọc hết, `false` nếu bị dừng giữa chừng.
  Future<bool> play(FeedbackManager feedback) async {
    await feedback.stop();
    final sw = Stopwatch()..start();
    final completed = await feedback.speakSegmentsAndWait(
      buildSegments(steps),
      priority: FeedbackPriority.normal,
    );
    debugPrint('VoiceGuide: ${completed ? 'đọc hết' : 'bị dừng'} '
        '${steps.length} đoạn sau ${sw.elapsed.inSeconds}s');
    return completed;
  }
}

final guideFlagStorageProvider =
    Provider<GuideFlagStorage>((ref) => SharedPrefsGuideFlagStorage());

final voiceGuideProvider = Provider<VoiceGuide>((ref) {
  return VoiceGuide(ref.watch(guideFlagStorageProvider));
});
