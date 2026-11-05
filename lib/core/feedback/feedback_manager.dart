import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feedback_message.dart';
import 'tts_service.dart';

/// Trình quản lý hàng đợi phát âm thanh và phản hồi giọng nói (FeedbackManager)
/// Hỗ trợ ưu tiên (Urgent, Normal, Info), giới hạn tối đa 3 câu trong hàng đợi
/// và đồng bộ phát tuần tự với await completion.
///
/// Khi người dùng đang thao tác bằng TalkBack ([holdForUserInteraction]), app tạm
/// im để không nói đè lên TalkBack: câu đang đọc bị dừng hẳn (không đọc lại), gợi ý
/// phụ (Info) bị bỏ, câu Normal MỚI tới trong lúc đó chờ tới khi người dùng ngừng
/// thao tác; câu Urgent vẫn phát ngay.
class FeedbackManager {
  final TtsService _ttsService;

  /// Mỗi phần tử hàng đợi là một "câu" có thể gồm nhiều đoạn ngôn ngữ khác nhau,
  /// được đọc liền nhau (không bị cắt bởi giới hạn hàng đợi giữa chừng).
  final List<_QueueItem> _queue = [];
  bool _isProcessing = false;

  static const int maxQueueSize = 3;

  /// Thời gian tạm im sau mỗi lần TalkBack chuyển tiêu điểm (đủ để TalkBack đọc nhãn).
  final Duration userInteractionHold;

  FeedbackManager({
    required TtsService ttsService,
    this.userInteractionHold = const Duration(seconds: 3),
  }) : _ttsService = ttsService;

  int get queueLength => _queue.length;
  bool get isProcessing => _isProcessing;

  /// Đang tạm im vì người dùng thao tác bằng TalkBack.
  bool get isHeld => _heldUntil != null && DateTime.now().isBefore(_heldUntil!);

  /// Đưa câu văn (tiếng Việt) vào hàng đợi phát âm thanh.
  /// Nếu [priority] là [FeedbackPriority.urgent], ngắt câu hiện tại và xóa hàng đợi.
  Future<void> speak(
    String text, {
    FeedbackPriority priority = FeedbackPriority.normal,
  }) {
    return speakSegments([SpeechSegment(text)], priority: priority);
  }

  /// Đưa một câu gồm nhiều đoạn (mỗi đoạn một ngôn ngữ) vào hàng đợi.
  Future<void> speakSegments(
    List<SpeechSegment> segments, {
    FeedbackPriority priority = FeedbackPriority.normal,
  }) async {
    await _enqueue(segments, priority);
  }

  /// Như [speakSegments] nhưng chờ tới khi câu được đọc xong.
  /// Trả về `true` nếu đọc hết, `false` nếu bị huỷ (clearQueue/stop/urgent/bị đẩy khỏi hàng đợi).
  Future<bool> speakSegmentsAndWait(
    List<SpeechSegment> segments, {
    FeedbackPriority priority = FeedbackPriority.normal,
  }) async {
    final done = await _enqueue(segments, priority);
    if (done == null) return true;
    return done.future;
  }

  Future<Completer<bool>?> _enqueue(
    List<SpeechSegment> segments,
    FeedbackPriority priority,
  ) async {
    final clean = [
      for (final s in segments)
        if (s.text.trim().isNotEmpty) SpeechSegment(s.text.trim(), language: s.language),
    ];
    if (clean.isEmpty) return null;
    final item = _QueueItem(clean, priority);

    if (priority == FeedbackPriority.urgent) {
      clearQueue();
      await _ttsService.stop();
      _queue.add(item);
    } else {
      // Người dùng đang nghe TalkBack: gợi ý phụ không còn giá trị khi đọc trễ -> bỏ.
      if (priority == FeedbackPriority.info && isHeld) {
        item.finish(false);
        return item.done;
      }
      // Giới hạn hàng đợi tối đa 3 câu: loại bỏ câu cũ nhất nếu đầy
      while (_queue.length >= maxQueueSize) {
        _queue.removeAt(0).finish(false);
      }
      _queue.add(item);
    }

    _processQueue();
    return item.done;
  }

  /// Gọi khi người dùng thao tác bằng TalkBack (chuyển tiêu điểm, cuộn...).
  /// Dừng hẳn câu không khẩn cấp đang đọc để TalkBack nói rõ; gợi ý Info bị bỏ;
  /// câu Normal mới chờ hết [userInteractionHold]. Gọi liên tục sẽ gia hạn.
  void holdForUserInteraction() {
    _heldUntil = DateTime.now().add(userInteractionHold);
    _holdGeneration++;
    _queue.removeWhere((item) {
      final drop = item.priority == FeedbackPriority.info;
      if (drop) item.finish(false);
      return drop;
    });
    final current = _current;
    if (current != null && current.priority != FeedbackPriority.urgent) {
      unawaited(_ttsService.stop());
    }
    _resumeTimer?.cancel();
    _resumeTimer = Timer(userInteractionHold, _processQueue);
  }

  /// Người dùng chủ động kích hoạt một nút (chạm hai lần): bỏ tạm im ngay để lời
  /// phản hồi của nút đó (vd. nghe lại, đọc hướng dẫn) được phát không chậm trễ.
  void releaseHold() {
    if (_heldUntil == null) return;
    _heldUntil = null;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _processQueue();
  }

  /// Xóa toàn bộ hàng đợi khi mất chữ > 3 giây hoặc người dùng dừng đọc
  void clearQueue() {
    for (final item in _queue) {
      item.finish(false);
    }
    _queue.clear();
    // Bỏ cả các đoạn còn lại của câu đang đọc dở (câu nhiều ngôn ngữ).
    _epoch++;
  }

  int _epoch = 0;
  int _holdGeneration = 0;
  DateTime? _heldUntil;
  Timer? _resumeTimer;
  _QueueItem? _current;

  /// Dừng phát âm thanh hiện tại và xóa hàng đợi
  Future<void> stop() async {
    clearQueue();
    await _ttsService.stop();
  }

  /// Vòng lặp xử lý tuần tự từng câu trong hàng đợi
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (_queue.isNotEmpty) {
        // Đang tạm im: chỉ câu khẩn cấp được phát; phần còn lại chờ hẹn giờ gọi lại.
        if (isHeld && _queue.first.priority != FeedbackPriority.urgent) break;

        final item = _queue.removeAt(0);
        final epoch = _epoch;
        final holdGen = _holdGeneration;
        final pausable = item.priority != FeedbackPriority.urgent;
        var interrupted = false;
        _current = item;
        try {
          for (final s in item.segments) {
            if (epoch != _epoch) break;
            if (pausable && holdGen != _holdGeneration) {
              // Người dùng thao tác TalkBack giữa chừng: bỏ phần còn lại, KHÔNG đọc lại
              // (đọc lại sau mỗi lần vuốt sẽ chen vào lời TalkBack liên tục).
              interrupted = true;
              break;
            }
            await _ttsService.speakAndWait(s.text, language: s.language);
          }
          if (pausable && holdGen != _holdGeneration) interrupted = true;
        } finally {
          _current = null;
          item.finish(epoch == _epoch && !interrupted);
        }
      }
    } catch (e) {
      debugPrint('FeedbackManager: Lỗi xử lý phát âm: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void dispose() {
    _resumeTimer?.cancel();
    clearQueue();
    _isProcessing = false;
  }
}

class _QueueItem {
  final List<SpeechSegment> segments;
  final FeedbackPriority priority;
  final Completer<bool> done;

  _QueueItem(this.segments, this.priority) : done = Completer<bool>();

  void finish(bool completed) {
    if (!done.isCompleted) done.complete(completed);
  }
}

final feedbackManagerProvider = Provider<FeedbackManager>((ref) {
  final ttsService = ref.watch(ttsServiceProvider);
  final manager = FeedbackManager(ttsService: ttsService);
  ref.onDispose(() => manager.dispose());
  return manager;
});
