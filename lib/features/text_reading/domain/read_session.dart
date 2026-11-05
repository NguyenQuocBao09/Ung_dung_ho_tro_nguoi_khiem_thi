import 'dart:math';

/// Thuật toán khoảng cách Levenshtein giữa hai chuỗi
int levenshteinDistance(String s1, String s2) {
  if (s1 == s2) return 0;
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;

  final r1 = s1.runes.toList();
  final r2 = s2.runes.toList();

  final len1 = r1.length;
  final len2 = r2.length;

  List<int> previousRow = List<int>.generate(len2 + 1, (i) => i);
  List<int> currentRow = List<int>.filled(len2 + 1, 0);

  for (int i = 0; i < len1; i++) {
    currentRow[0] = i + 1;
    for (int j = 0; j < len2; j++) {
      final cost = (r1[i] == r2[j]) ? 0 : 1;
      currentRow[j + 1] = min(
        currentRow[j] + 1, // Insertion
        min(
          previousRow[j + 1] + 1, // Deletion
          previousRow[j] + cost, // Substitution
        ),
      );
    }
    final temp = previousRow;
    previousRow = currentRow;
    currentRow = temp;
  }

  return previousRow[len2];
}

/// Độ tương đồng Levenshtein chuẩn hóa trong khoảng [0.0, 1.0]
double normalizedLevenshteinSimilarity(String s1, String s2) {
  if (s1 == s2) return 1.0;
  final r1 = s1.runes.length;
  final r2 = s2.runes.length;
  final maxLen = max(r1, r2);
  if (maxLen == 0) return 1.0;

  final dist = levenshteinDistance(s1, s2);
  return (1.0 - (dist / maxLen)).clamp(0.0, 1.0);
}

/// Một dòng chữ OCR trên một khung hình, toạ độ chuẩn hoá 0..1 trong ảnh ĐỨNG
/// (đã xoay theo hướng cảm biến). [blockIndex] là chỉ số khối (đoạn) ML Kit
/// trong khung hình đó.
class OcrLine {
  final String text;
  final int blockIndex;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const OcrLine({
    required this.text,
    this.blockIndex = 0,
    this.left = 0.2,
    this.top = 0.4,
    this.right = 0.8,
    this.bottom = 0.45,
  });

  /// Dòng chạm mép khung hình -> nhiều khả năng bị cắt, OCR sai/thiếu chữ.
  bool touchesEdge(double margin) =>
      left <= margin || top <= margin || right >= 1 - margin || bottom >= 1 - margin;
}

/// Kết quả một khung hình của [ReadSession].
class ReadFrameResult {
  /// Các đoạn cần đọc, đã sắp theo thứ tự đọc (trên xuống, trái sang phải).
  /// Mỗi đoạn là các dòng cùng khối ML Kit, đã ghép bằng dấu cách.
  final List<String> paragraphs;

  /// Số dòng bị bỏ qua vì chạm mép khung hình.
  final int edgeCutLines;

  /// Số dòng hợp lệ (không chạm mép) nhìn thấy trong khung hình này.
  final int visibleLines;

  /// Khung bao các khối văn bản đang thấy (để vẽ lên preview), theo thứ tự đọc.
  final List<TextBlockBox> blocks;

  const ReadFrameResult({
    this.paragraphs = const [],
    this.edgeCutLines = 0,
    this.visibleLines = 0,
    this.blocks = const [],
  });
}

/// Hình chữ nhật chuẩn hoá 0..1 trong ảnh đứng.
class TextRect {
  final double left, top, right, bottom;
  const TextRect(this.left, this.top, this.right, this.bottom);

  double get height => bottom - top;

  TextRect union(TextRect o) =>
      TextRect(min(left, o.left), min(top, o.top), max(right, o.right), max(bottom, o.bottom));

  /// Phần chồng lấn theo chiều dọc.
  double verticalOverlap(TextRect o) => max(0.0, min(bottom, o.bottom) - max(top, o.top));

  @override
  bool operator ==(Object other) =>
      other is TextRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// Khung bao một khối (đoạn) văn bản.
class TextBlockBox {
  final int blockIndex;
  final TextRect rect;

  /// Mọi dòng trong khối đã được đọc.
  final bool read;

  const TextBlockBox({required this.blockIndex, required this.rect, required this.read});
}

/// Thứ tự đọc "trên xuống dưới, trái sang phải" cho các hình chữ nhật:
/// gom thành hàng (chồng lấn dọc ≥ 50% chiều cao của hình thấp hơn), hàng sắp
/// từ trên xuống, trong hàng sắp từ trái sang phải. Trả về danh sách chỉ số.
///
/// Với trang 2 cột, hai khối cột cao gần bằng nhau sẽ cùng hàng → đọc hết cột
/// trái rồi đến cột phải (vì mỗi khối được đọc trọn trước khi sang khối sau).
List<int> readingOrder(List<TextRect> rects) {
  final idx = List<int>.generate(rects.length, (i) => i)
    ..sort((a, b) => rects[a].top.compareTo(rects[b].top));
  final rows = <List<int>>[];
  final rowSpan = <TextRect>[];
  for (final i in idx) {
    final r = rects[i];
    var placed = false;
    for (var k = 0; k < rows.length; k++) {
      final span = rowSpan[k];
      final minH = min(r.height, span.height);
      if (minH > 0 && r.verticalOverlap(span) >= 0.5 * minH) {
        rows[k].add(i);
        rowSpan[k] = span.union(r);
        placed = true;
        break;
      }
    }
    if (!placed) {
      rows.add([i]);
      rowSpan.add(r);
    }
  }
  final rowOrder = List<int>.generate(rows.length, (k) => k)
    ..sort((a, b) => rowSpan[a].top.compareTo(rowSpan[b].top));

  // Trong một hàng: gom thành cột (chồng lấn ngang ≥ 50% bề rộng hẹp hơn),
  // cột từ trái sang phải, trong cột từ trên xuống.
  List<int> orderRow(List<int> row) {
    row.sort((a, b) => rects[a].left.compareTo(rects[b].left));
    final cols = <List<int>>[];
    final colSpan = <TextRect>[];
    for (final i in row) {
      final r = rects[i];
      var placed = false;
      for (var k = 0; k < cols.length; k++) {
        final s = colSpan[k];
        final overlap = max(0.0, min(r.right, s.right) - max(r.left, s.left));
        final minW = min(r.right - r.left, s.right - s.left);
        if (minW > 0 && overlap >= 0.5 * minW) {
          cols[k].add(i);
          colSpan[k] = s.union(r);
          placed = true;
          break;
        }
      }
      if (!placed) {
        cols.add([i]);
        colSpan.add(r);
      }
    }
    return [
      for (final c in cols) ...(c..sort((a, b) => rects[a].top.compareTo(rects[b].top))),
    ];
  }

  return [for (final k in rowOrder) ...orderRow(rows[k])];
}

/// Một dòng được theo dõi qua nhiều khung hình.
class _LineTrack {
  /// Các biến thể OCR gần nhất (văn bản gốc, giữ dấu câu và chữ hoa).
  final List<String> rawVariants = [];
  final List<String> normVariants = [];

  /// Chỉ số các khung hình mà dòng xuất hiện.
  final List<int> seenFrames = [];
  final int firstFrame;
  bool read = false;

  /// Khung hình đầu tiên dòng đạt đồng thuận (chờ đọc).
  int? stableFrame;

  /// Văn bản đại diện (chuẩn hoá) — dùng để so khớp.
  String representativeNorm = '';
  String representativeRaw = '';

  _LineTrack(this.firstFrame);

  int get lastFrame => seenFrames.isEmpty ? firstFrame : seenFrames.last;

  void add(String raw, String norm, int frame, int maxVariants) {
    rawVariants.add(raw);
    normVariants.add(norm);
    if (rawVariants.length > maxVariants) {
      rawVariants.removeAt(0);
      normVariants.removeAt(0);
    }
    if (seenFrames.isEmpty || seenFrames.last != frame) seenFrames.add(frame);
    if (seenFrames.length > 16) seenFrames.removeAt(0);
    _updateRepresentative();
  }

  int hitsSince(int frameFrom) => seenFrames.where((f) => f >= frameFrom).length;

  /// Chọn biến thể "trung tâm" (medoid): tổng độ tương đồng với các biến thể
  /// khác lớn nhất. Lỗi OCR ngẫu nhiên ở một khung sẽ không được chọn.
  void _updateRepresentative() {
    var bestIdx = normVariants.length - 1;
    var bestScore = -1.0;
    for (var i = 0; i < normVariants.length; i++) {
      var score = 0.0;
      for (var j = 0; j < normVariants.length; j++) {
        if (i != j) score += normalizedLevenshteinSimilarity(normVariants[i], normVariants[j]);
      }
      // Hoà điểm -> ưu tiên biến thể mới hơn (i lớn hơn).
      if (score >= bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }
    representativeNorm = normVariants[bestIdx];
    representativeRaw = rawVariants[bestIdx];
  }
}

/// Phiên đọc chữ tự động (ReadSession) - Dart thuần, không phụ thuộc Flutter.
///
/// Khác bản cũ (đọc từng dòng ngay khi dòng đạt đồng thuận, theo văn bản của
/// khung hiện tại), bản này:
/// 1. Theo dõi mỗi dòng qua nhiều khung (track) và đọc biến thể ổn định nhất
///    (medoid) thay vì biến thể của khung hiện tại → chữ không "nhảy".
/// 2. Chỉ đọc khi các dòng đang thấy đã ổn định, rồi đọc theo thứ tự trên
///    xuống dưới / theo khối → không lộn thứ tự.
/// 3. Dòng đã đọc vẫn được giữ track, biến thể OCR sai của nó gắn vào track cũ
///    thay vì bị coi là dòng mới → không đọc lặp với chữ khác.
/// 4. Bỏ qua dòng chạm mép khung hình (thường bị cắt nửa chữ).
class ReadSession {
  final int windowSize;
  final int requiredConsensus;

  /// Ngưỡng tương đồng để coi hai lần OCR là CÙNG một dòng.
  final double similarityThreshold;
  final int minLineLength;
  final double minLetterRatio;
  final Duration silenceResetDuration;

  /// Lề (tỉ lệ khung hình) để coi một dòng là chạm mép.
  final double edgeMargin;

  /// Số biến thể tối đa giữ cho mỗi dòng.
  final int maxVariants;

  /// Số khung tối đa chờ các dòng chưa ổn định trước khi vẫn đọc dòng đã ổn định.
  final int maxWaitFrames;

  final List<_LineTrack> _tracks = [];
  final List<String> _readLines = [];
  final List<List<String>> _recentFrames = [];
  int _frameIndex = -1;
  DateTime? _lastSeenTextTime;

  static final RegExp _punctuationRegex = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _letterRegex = RegExp(r'^\p{L}$', unicode: true);

  ReadSession({
    this.windowSize = 4,
    this.requiredConsensus = 3,
    this.similarityThreshold = 0.7,
    this.minLineLength = 3,
    this.minLetterRatio = 0.6,
    this.silenceResetDuration = const Duration(seconds: 3),
    this.edgeMargin = 0.015,
    this.maxVariants = 6,
    this.maxWaitFrames = 2,
  }) : assert(requiredConsensus <= windowSize, 'requiredConsensus must be <= windowSize');

  /// Các dòng đã đọc trong phiên hiện tại (văn bản gốc).
  List<String> get readLines => List.unmodifiable(_readLines);

  /// Các dòng hợp lệ (chuẩn hoá) của những khung hình gần nhất.
  List<List<String>> get recentFrames => List.unmodifiable(_recentFrames);

  /// Thời điểm cuối cùng nhìn thấy văn bản
  DateTime? get lastSeenTextTime => _lastSeenTextTime;

  /// Chuẩn hóa chuỗi: chữ thường, bỏ dấu câu, gộp khoảng trắng, giữ ký tự Unicode
  String normalizeText(String input) {
    var text = input.toLowerCase();
    text = text.replaceAll(_punctuationRegex, ' ');
    text = text.replaceAll(_whitespaceRegex, ' ').trim();
    return text;
  }

  /// Kiểm tra dòng có hợp lệ không:
  /// - Không ngắn hơn [minLineLength] ký tự
  /// - Có ít nhất [minLetterRatio] (mặc định 60%) là chữ cái
  bool isValidLine(String normalized) {
    if (normalized.length < minLineLength) {
      return false;
    }

    int letterCount = 0;
    int nonSpaceCount = 0;

    for (final rune in normalized.runes) {
      final char = String.fromCharCode(rune);
      if (char.trim().isEmpty) continue;
      nonSpaceCount++;
      if (_letterRegex.hasMatch(char)) {
        letterCount++;
      }
    }

    if (nonSpaceCount == 0) return false;
    return letterCount / nonSpaceCount >= minLetterRatio;
  }

  /// Độ tương đồng giữa một dòng mới và một track. Dòng bị cắt một phần
  /// (chuỗi con dài ≥ 60%) vẫn được coi là cùng dòng.
  double _matchScore(String norm, _LineTrack t) {
    var best = 0.0;
    for (final v in t.normVariants.toSet()) {
      best = max(best, normalizedLevenshteinSimilarity(norm, v));
      if (best < similarityThreshold) {
        final shorter = norm.length <= v.length ? norm : v;
        final longer = norm.length <= v.length ? v : norm;
        if (shorter.length >= 8 && shorter.length >= 0.5 * longer.length && longer.contains(shorter)) {
          best = similarityThreshold;
        }
      }
    }
    return best;
  }

  /// Tiện ích cho trường hợp chỉ có văn bản (không có toạ độ): mỗi chuỗi là
  /// một dòng giữa khung hình, cùng một khối, theo thứ tự cho trước.
  ReadFrameResult onTextFrame(List<String> rawLines, DateTime now) {
    return onFrame([
      for (var i = 0; i < rawLines.length; i++)
        OcrLine(text: rawLines[i], top: 0.3 + 0.001 * i, bottom: 0.31 + 0.001 * i),
    ], now);
  }

  /// Xử lý một khung hình, trả về các đoạn mới cần đọc (đã sắp thứ tự).
  ReadFrameResult onFrame(List<OcrLine> lines, DateTime now) {
    // 1. Lọc dòng hợp lệ, bỏ dòng chạm mép.
    var edgeCut = 0;
    final valid = <(OcrLine, String)>[];
    for (final l in lines) {
      final norm = normalizeText(l.text);
      if (!isValidLine(norm)) continue;
      if (l.touchesEdge(edgeMargin)) {
        edgeCut++;
        continue;
      }
      if (valid.any((v) => v.$2 == norm)) continue;
      valid.add((l, norm));
    }

    // 2. Reset phiên khi không thấy chữ quá lâu.
    if (_lastSeenTextTime != null && now.difference(_lastSeenTextTime!) >= silenceResetDuration) {
      reset();
    }
    if (valid.isEmpty) {
      return ReadFrameResult(edgeCutLines: edgeCut);
    }
    _lastSeenTextTime = now;
    _frameIndex++;
    final frame = _frameIndex;

    _recentFrames.add([for (final v in valid) v.$2]);
    if (_recentFrames.length > windowSize) _recentFrames.removeAt(0);

    // 3. Ghép mỗi dòng với track giống nhất (tham lam, một-một trong khung).
    final pairs = <(int, int, double)>[]; // (lineIdx, trackIdx, score)
    for (var i = 0; i < valid.length; i++) {
      for (var j = 0; j < _tracks.length; j++) {
        final s = _matchScore(valid[i].$2, _tracks[j]);
        if (s >= similarityThreshold) pairs.add((i, j, s));
      }
    }
    pairs.sort((a, b) => b.$3.compareTo(a.$3));
    final lineTrack = List<_LineTrack?>.filled(valid.length, null);
    final usedTracks = <int>{};
    for (final p in pairs) {
      if (lineTrack[p.$1] != null || usedTracks.contains(p.$2)) continue;
      lineTrack[p.$1] = _tracks[p.$2];
      usedTracks.add(p.$2);
    }
    for (var i = 0; i < valid.length; i++) {
      final t = lineTrack[i] ?? (_LineTrack(frame)..representativeNorm = valid[i].$2);
      if (lineTrack[i] == null) {
        _tracks.add(t);
        lineTrack[i] = t;
      }
      t.add(valid[i].$1.text.trim(), valid[i].$2, frame, maxVariants);
    }

    // Bỏ track chưa đọc đã lâu không thấy (nhiễu); giữ track đã đọc để chống đọc lặp.
    _tracks.removeWhere((t) => !t.read && frame - t.lastFrame > windowSize * 2);

    // 4. Quyết định đọc: chỉ khi mọi dòng đang thấy đã ổn định (hoặc là nhiễu
    // kéo dài), để đọc cả đoạn theo đúng thứ tự thay vì từng mảnh rời rạc.
    final windowStart = frame - windowSize + 1;
    bool isStable(_LineTrack t) => t.hitsSince(windowStart) >= requiredConsensus;
    bool isPending(_LineTrack t) => !isStable(t) && frame - t.firstFrame < windowSize;

    final visible = <int>[for (var i = 0; i < valid.length; i++) i];
    final anyPending = visible.any((i) => !lineTrack[i]!.read && isPending(lineTrack[i]!));
    final toRead = visible.where((i) => !lineTrack[i]!.read && isStable(lineTrack[i]!)).toList();
    for (final i in toRead) {
      lineTrack[i]!.stableFrame ??= frame;
    }
    // Không chờ mãi: nếu nhiễu mới liên tục xuất hiện, sau [maxWaitFrames] khung
    // vẫn đọc các dòng đã ổn định.
    final waitedEnough = toRead.any((i) => frame - lineTrack[i]!.stableFrame! >= maxWaitFrames);
    final validLines = [for (final v in valid) v.$1];
    if (toRead.isEmpty || (anyPending && !waitedEnough)) {
      return ReadFrameResult(
        edgeCutLines: edgeCut,
        visibleLines: valid.length,
        blocks: _blockBoxes(validLines, (i) => lineTrack[i]!.read),
      );
    }

    // 5. Sắp thứ tự đọc: khối (đoạn) từ trên xuống, khối cùng hàng từ trái sang
    // phải; trong khối, dòng từ trên xuống, mảnh dòng cùng hàng từ trái sang phải.
    final blockRank = <int, int>{};
    final blocks = _blockBoxes(validLines, (_) => false);
    final orderedBlocks = readingOrder(blocks.map((b) => b.rect).toList());
    for (var r = 0; r < orderedBlocks.length; r++) {
      blockRank[blocks[orderedBlocks[r]].blockIndex] = r;
    }
    final lineRank = <int, int>{};
    for (final b in blockRank.keys) {
      final idx = [for (final i in toRead) if (valid[i].$1.blockIndex == b) i];
      final order = readingOrder([for (final i in idx) _rectOf(valid[i].$1)]);
      for (var r = 0; r < order.length; r++) {
        lineRank[idx[order[r]]] = r;
      }
    }
    toRead.sort((a, b) {
      final ba = blockRank[valid[a].$1.blockIndex]!, bb = blockRank[valid[b].$1.blockIndex]!;
      if (ba != bb) return ba.compareTo(bb);
      return lineRank[a]!.compareTo(lineRank[b]!);
    });

    final paragraphs = <String>[];
    int? currentBlock;
    final buffer = <String>[];
    void flush() {
      if (buffer.isNotEmpty) paragraphs.add(buffer.join(' '));
      buffer.clear();
    }

    for (final i in toRead) {
      final t = lineTrack[i]!;
      t.read = true;
      final text = t.representativeRaw;
      _readLines.add(text);
      if (currentBlock != null && currentBlock != valid[i].$1.blockIndex) flush();
      currentBlock = valid[i].$1.blockIndex;
      buffer.add(text);
    }
    flush();

    return ReadFrameResult(
      paragraphs: paragraphs,
      edgeCutLines: edgeCut,
      visibleLines: valid.length,
      blocks: _blockBoxes(validLines, (i) => lineTrack[i]!.read),
    );
  }

  static TextRect _rectOf(OcrLine l) => TextRect(l.left, l.top, l.right, l.bottom);

  /// Gom các dòng theo khối ML Kit thành khung bao; khối "đã đọc" khi mọi dòng
  /// của nó đã được đọc. Thứ tự trả về theo thứ tự đọc.
  static List<TextBlockBox> _blockBoxes(List<OcrLine> lines, bool Function(int) isRead) {
    final rects = <int, TextRect>{};
    final allRead = <int, bool>{};
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final r = _rectOf(l);
      rects[l.blockIndex] = rects[l.blockIndex]?.union(r) ?? r;
      allRead[l.blockIndex] = (allRead[l.blockIndex] ?? true) && isRead(i);
    }
    final keys = rects.keys.toList();
    final order = readingOrder([for (final k in keys) rects[k]!]);
    return [
      for (final o in order)
        TextBlockBox(blockIndex: keys[o], rect: rects[keys[o]]!, read: allRead[keys[o]]!),
    ];
  }

  /// Đặt lại toàn bộ trạng thái phiên đọc
  void reset() {
    _tracks.clear();
    _readLines.clear();
    _recentFrames.clear();
    _frameIndex = -1;
    _lastSeenTextTime = null;
  }
}
