enum FeedbackPriority { urgent, normal, info }

class FeedbackMessage {
  final String text;
  final FeedbackPriority priority;
  FeedbackMessage({required this.text, this.priority = FeedbackPriority.normal});
}

/// Một đoạn câu đọc bằng một ngôn ngữ TTS cụ thể (BCP-47, vd. `vi-VN`, `en-US`).
class SpeechSegment {
  static const String vietnamese = 'vi-VN';
  static const String english = 'en-US';

  final String text;
  final String language;

  const SpeechSegment(this.text, {this.language = vietnamese});

  @override
  bool operator ==(Object other) =>
      other is SpeechSegment && other.text == text && other.language == language;

  @override
  int get hashCode => Object.hash(text, language);

  @override
  String toString() => '[$language] $text';
}
