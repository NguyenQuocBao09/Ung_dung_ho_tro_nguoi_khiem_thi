import '../../../core/feedback/feedback_message.dart';

/// Tách văn bản thành các đoạn tiếng Việt / tiếng Anh để đọc bằng giọng phù hợp.
///
/// Chạy hoàn toàn offline, không dùng model: dựa trên đặc trưng chữ viết.
/// - Từ có dấu tiếng Việt (ă, â, đ, ê, ô, ơ, ư, dấu thanh) → tiếng Việt.
/// - Từ có f/j/w/z hoặc không khớp cấu trúc âm tiết tiếng Việt
///   (phụ âm đầu + nguyên âm + phụ âm cuối c/ch/m/n/ng/nh/p/t) → tiếng Anh.
/// - Từ mơ hồ (vd. "to", "in", "the") hoặc số → trung tính, theo từ bên cạnh.
/// Đoạn tiếng Anh ngắn hơn [minRunWords] từ nằm giữa câu tiếng Việt (vd. tên
/// riêng "Google") được giữ giọng Việt để tránh đổi giọng liên tục.
///
/// Đây là heuristic: văn bản tiếng Việt không dấu hoặc từ mượn có thể bị phân
/// loại sai.
class LanguageSegmenter {
  final int minRunWords;

  const LanguageSegmenter({this.minRunWords = 3});

  static final RegExp _viChars = RegExp(
      r'[àáảãạăằắẳẵặâầấẩẫậđèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵ]');
  static final RegExp _nonLetter = RegExp(r'[^a-zàáảãạăằắẳẵặâầấẩẫậđèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵ]');
  static final RegExp _viSyllable =
      RegExp(r'^(ngh|ng|nh|ch|gh|gi|kh|ph|qu|th|tr|[bcdghklmnprstvx])?[aeiouy]{1,3}(ng|nh|ch|[cmnpt])?$');
  static final RegExp _enOnlyLetters = RegExp(r'[fjwz]');

  /// Từ tiếng Anh thông dụng nhưng vẫn khớp cấu trúc âm tiết Việt.
  static const Set<String> _ambiguousEnglish = {
    'the', 'to', 'in', 'on', 'a', 'i', 'be', 'he', 'she', 'we', 'me', 'my', 'by',
    'do', 'go', 'so', 'no', 'or', 'it', 'at', 'an', 'up', 'you', 'are', 'can',
    'not', 'but', 'one', 'time', 'see', 'use', 'make', 'more', 'some', 'take',
    'like', 'come', 'game', 'name', 'home', 'page', 'type',
  };

  /// Phân loại một từ: 'vi', 'en', 'en?' (mơ hồ nghiêng tiếng Anh) hoặc null (trung tính).
  static String? classifyWord(String token) {
    final w = token.toLowerCase().replaceAll(_nonLetter, '');
    if (w.isEmpty) return null;
    if (_viChars.hasMatch(w)) return 'vi';
    if (_enOnlyLetters.hasMatch(w)) return 'en';
    if (!_viSyllable.hasMatch(w)) return 'en';
    if (_ambiguousEnglish.contains(w)) return 'en?';
    return null;
  }

  List<SpeechSegment> segment(String text) {
    final tokens = text.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const [];
    final classes = [for (final t in tokens) classifyWord(t)];

    final strongCount = classes.where((c) => c == 'vi' || c == 'en').length;
    if (strongCount == 0) {
      // Không có từ nào chắc chắn: tiếng Anh chỉ khi đa số là từ tiếng Anh thông dụng.
      final weak = classes.where((c) => c == 'en?').length;
      final words = classes.where((c) => c != null).length;
      final lang = weak >= 2 && weak * 2 >= words ? SpeechSegment.english : SpeechSegment.vietnamese;
      return [SpeechSegment(tokens.join(' '), language: lang)];
    }

    // Gán ngôn ngữ cho từ trung tính/mơ hồ theo từ chắc chắn gần nhất phía trước
    // (đầu câu thì theo phía sau).
    final langs = List<String?>.filled(tokens.length, null);
    String? prev;
    for (var i = 0; i < tokens.length; i++) {
      final c = classes[i];
      if (c == 'vi' || c == 'en') prev = c;
      langs[i] = prev;
    }
    String? next;
    for (var i = tokens.length - 1; i >= 0; i--) {
      final c = classes[i];
      if (c == 'vi' || c == 'en') next = c;
      langs[i] ??= next;
    }

    final runs = <_Run>[];
    for (var i = 0; i < tokens.length; i++) {
      if (runs.isEmpty || runs.last.lang != langs[i]) runs.add(_Run(langs[i]!));
      runs.last.tokens.add(tokens[i]);
    }

    // Gộp các đoạn quá ngắn vào đoạn bên cạnh.
    while (runs.length > 1) {
      var idx = -1;
      // Chọn đoạn ngắn nhất; hoà thì ưu tiên gộp đoạn tiếng Anh (mặc định là giọng Việt).
      for (var i = 0; i < runs.length; i++) {
        final n = runs[i].tokens.length;
        if (n >= minRunWords) continue;
        if (idx < 0 ||
            n < runs[idx].tokens.length ||
            (n == runs[idx].tokens.length && runs[i].lang == 'en' && runs[idx].lang != 'en')) {
          idx = i;
        }
      }
      if (idx < 0) break;
      final left = idx > 0 ? runs[idx - 1] : null;
      final right = idx < runs.length - 1 ? runs[idx + 1] : null;
      final target = (left != null && (right == null || left.tokens.length >= right.tokens.length))
          ? left
          : right!;
      if (identical(target, left)) {
        left!.tokens.addAll(runs[idx].tokens);
      } else {
        target.tokens.insertAll(0, runs[idx].tokens);
      }
      runs.removeAt(idx);
      // Ghép các đoạn liền kề cùng ngôn ngữ.
      for (var i = runs.length - 1; i > 0; i--) {
        if (runs[i].lang == runs[i - 1].lang) {
          runs[i - 1].tokens.addAll(runs[i].tokens);
          runs.removeAt(i);
        }
      }
    }

    return [
      for (final r in runs)
        SpeechSegment(
          r.tokens.join(' '),
          language: r.lang == 'en' ? SpeechSegment.english : SpeechSegment.vietnamese,
        ),
    ];
  }
}

class _Run {
  final String lang;
  final List<String> tokens = [];
  _Run(this.lang);
}
