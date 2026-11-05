import 'dart:math' as math;

/// Hình chữ nhật chuẩn hoá (0..1) trong ảnh đã xoay về chiều đứng.
class NormRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const NormRect(this.left, this.top, this.right, this.bottom);

  static const full = NormRect(0, 0, 1, 1);

  double get width => right - left;
  double get height => bottom - top;
  double get area => math.max(0, width) * math.max(0, height);
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  bool get isFull => left <= 0 && top <= 0 && right >= 1 && bottom >= 1;

  double iou(NormRect o) {
    final l = math.max(left, o.left);
    final t = math.max(top, o.top);
    final r = math.min(right, o.right);
    final b = math.min(bottom, o.bottom);
    final inter = math.max(0.0, r - l) * math.max(0.0, b - t);
    final union = area + o.area - inter;
    return union <= 0 ? 0 : inter / union;
  }

  /// Dịch/thu gọn để nằm trọn trong khung [0,1] mà giữ kích thước (nếu vừa).
  NormRect clampInside() {
    final w = math.min(1.0, width);
    final h = math.min(1.0, height);
    final l = left.clamp(0.0, 1.0 - w);
    final t = top.clamp(0.0, 1.0 - h);
    return NormRect(l, t, l + w, t + h);
  }

  NormRect lerp(NormRect o, double t) => NormRect(
        left + (o.left - left) * t,
        top + (o.top - top) * t,
        right + (o.right - right) * t,
        bottom + (o.bottom - bottom) * t,
      );

  @override
  String toString() =>
      'NormRect(${left.toStringAsFixed(2)}, ${top.toStringAsFixed(2)}, '
      '${right.toStringAsFixed(2)}, ${bottom.toStringAsFixed(2)})';
}

/// Điểm của một vùng quét: xác suất mệnh giá cao nhất (đã bỏ lớp none) và chỉ số lớp đó.
class WindowScore {
  final NormRect rect;
  final int classIndex;
  final double moneyProb;

  const WindowScore(this.rect, this.classIndex, this.moneyProb);
}

/// Định vị tờ tiền bằng chính model phân loại: chấm điểm nhiều vùng có hình dạng tờ tiền
/// rồi chọn vùng tốt nhất.
///
/// Lý do: model được huấn luyện trên ảnh tờ tiền lấp kín khung (đã bị ép vuông 224x224).
/// Đưa cả khung hình camera vào thì tờ tiền chỉ chiếm một phần nhỏ, bị méo khác lúc huấn luyện.
/// Cắt các vùng theo tỉ lệ tờ tiền (~2.2:1, ngang hoặc dọc) rồi ép vuông sẽ tái tạo
/// đúng điều kiện huấn luyện. Khung bao trả về chỉ là **vùng ước lượng**, không phải
/// đường viền chính xác của tờ tiền.
class NoteWindowSearch {
  /// Tỉ lệ dài/rộng tờ polymer VND (khoảng 2.1–2.35).
  final double aspect;

  /// Kích thước vùng so với cạnh tương ứng của khung hình.
  final List<double> scales;

  /// Số vị trí trên mỗi trục khi vùng nhỏ hơn khung hình.
  final int positions;

  /// Chỉ tinh chỉnh khi vùng tốt nhất đạt ít nhất mức này.
  final double refineMinProb;

  const NoteWindowSearch({
    this.aspect = 2.2,
    this.scales = const [0.9, 0.6],
    this.positions = 3,
    this.refineMinProb = 0.3,
  });

  /// Vùng quét thô: toàn khung + vùng ngang/dọc ở mỗi tỉ lệ, rải đều trên lưới.
  List<NormRect> coarseWindows(int imageWidth, int imageHeight) {
    final w = imageWidth.toDouble();
    final h = imageHeight.toDouble();
    final out = <NormRect>[NormRect.full];
    for (final horizontal in const [true, false]) {
      for (final s in scales) {
        double ww, hh;
        if (horizontal) {
          ww = s * w;
          hh = ww / aspect;
          if (hh > h) {
            hh = h;
            ww = hh * aspect;
          }
        } else {
          hh = s * h;
          ww = hh / aspect;
          if (ww > w) {
            ww = w;
            hh = ww * aspect;
          }
        }
        final nx = ww >= w * 0.9 ? 1 : positions;
        final ny = hh >= h * 0.9 ? 1 : positions;
        for (var iy = 0; iy < ny; iy++) {
          for (var ix = 0; ix < nx; ix++) {
            final x = (w - ww) * (nx > 1 ? ix / (nx - 1) : 0.5);
            final y = (h - hh) * (ny > 1 ? iy / (ny - 1) : 0.5);
            out.add(NormRect(x / w, y / h, (x + ww) / w, (y + hh) / h));
          }
        }
      }
    }
    return out;
  }

  /// Vùng tinh chỉnh quanh vùng tốt nhất: thu nhỏ/phóng to 25% và dịch 20% theo 4 hướng.
  List<NormRect> refineWindows(NormRect best) {
    if (best.isFull) return const [];
    final cw = best.width;
    final ch = best.height;
    final cx = best.centerX;
    final cy = best.centerY;
    final out = <NormRect>[];
    for (final s in const [0.75, 1.25]) {
      out.add(NormRect(
        cx - cw * s / 2,
        cy - ch * s / 2,
        cx + cw * s / 2,
        cy + ch * s / 2,
      ).clampInside());
    }
    const shifts = [
      [-0.2, 0.0],
      [0.2, 0.0],
      [0.0, -0.2],
      [0.0, 0.2],
    ];
    for (final d in shifts) {
      out.add(NormRect(
        best.left + d[0] * cw,
        best.top + d[1] * ch,
        best.right + d[0] * cw,
        best.bottom + d[1] * ch,
      ).clampInside());
    }
    return out;
  }

  /// Vùng bám theo khi khung trước đã thấy tiền: chính vùng cũ + 6 vùng tinh chỉnh quanh nó.
  /// Ít lần chạy model hơn nhiều so với quét thô toàn bộ.
  List<NormRect> trackingWindows(NormRect previous) {
    final p = previous.clampInside();
    return [p, ...refineWindows(p)];
  }

  /// Vùng có xác suất mệnh giá cao nhất, hoặc null nếu danh sách rỗng.
  static WindowScore? best(List<WindowScore> scores) {
    WindowScore? b;
    for (final s in scores) {
      if (b == null || s.moneyProb > b.moneyProb) b = s;
    }
    return b;
  }

  /// Số vùng "ủng hộ" vùng tốt nhất: cùng lớp, xác suất >= [minProb], chồng lấn IoU > 0.3
  /// (tính cả chính vùng tốt nhất). Dùng để loại kết quả chỉ do MỘT mẩu cắt đoán bừa.
  static int support(List<WindowScore> scores, WindowScore best, double minProb) {
    var n = 0;
    for (final s in scores) {
      if (s.classIndex == best.classIndex &&
          s.moneyProb >= minProb &&
          s.rect.iou(best.rect) > 0.3) {
        n++;
      }
    }
    return n;
  }

  /// Gộp các vùng đồng ý với vùng tốt nhất (cùng lớp, điểm >= 80% điểm tốt nhất,
  /// chồng lấn IoU > 0.3, không tính vùng toàn khung) thành một khung bao,
  /// trung bình có trọng số theo điểm.
  static NormRect fuseBox(List<WindowScore> scores, WindowScore best) {
    var sw = 0.0, l = 0.0, t = 0.0, r = 0.0, b = 0.0;
    for (final s in scores) {
      if (s.classIndex != best.classIndex) continue;
      if (s.moneyProb < 0.8 * best.moneyProb) continue;
      if (s.rect.isFull) continue;
      if (s.rect.iou(best.rect) <= 0.3) continue;
      sw += s.moneyProb;
      l += s.rect.left * s.moneyProb;
      t += s.rect.top * s.moneyProb;
      r += s.rect.right * s.moneyProb;
      b += s.rect.bottom * s.moneyProb;
    }
    if (sw <= 0) return best.rect;
    return NormRect(l / sw, t / sw, r / sw, b / sw);
  }
}

/// Làm mượt khung bao giữa các khung hình để không giật; reset khi đổi mệnh giá hoặc mất tiền.
class BoxSmoother {
  final double alpha;
  NormRect? _box;
  String? _label;

  BoxSmoother({this.alpha = 0.5});

  NormRect? get box => _box;

  NormRect update(NormRect next, String label) {
    final prev = _box;
    if (prev == null || _label != label || prev.iou(next) < 0.1) {
      _box = next;
    } else {
      _box = prev.lerp(next, alpha);
    }
    _label = label;
    return _box!;
  }

  void reset() {
    _box = null;
    _label = null;
  }
}
