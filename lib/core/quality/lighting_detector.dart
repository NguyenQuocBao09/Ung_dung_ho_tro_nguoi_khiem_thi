// Kiểm tra độ sáng trung bình của khung hình và quyết định bật/tắt đèn flash.
import 'dart:math';
import 'dart:typed_data';

/// Độ sáng trung bình (0..255) của mặt phẳng Y, lấy mẫu thưa theo lưới
/// [gridCols] x [gridRows]. Chỉ đọc vùng Y (`rowStride * height` byte đầu), bỏ
/// qua padding cuối dòng và phần UV phía sau (NV21 một plane).
/// Trả về null nếu dữ liệu không đủ.
double? sampleLumaMean(
  Uint8List bytes, {
  required int width,
  required int height,
  required int rowStride,
  int gridCols = 32,
  int gridRows = 32,
}) {
  if (width <= 0 || height <= 0 || rowStride < width) return null;
  if (bytes.length < rowStride * (height - 1) + width) return null;
  final cols = min(gridCols, width);
  final rows = min(gridRows, height);
  var total = 0;
  for (var r = 0; r < rows; r++) {
    final y = ((r + 0.5) * height / rows).floor();
    final base = y * rowStride;
    for (var c = 0; c < cols; c++) {
      final x = ((c + 0.5) * width / cols).floor();
      total += bytes[base + x];
    }
  }
  return total / (rows * cols);
}

/// Hành động mà [LightingDecider] yêu cầu sau một mẫu độ sáng.
enum LightingAction {
  none,

  /// Môi trường tối: hiện cảnh báo và bật đèn flash.
  enterLowLight,

  /// Đủ sáng (khi đèn đang tắt): ẩn cảnh báo.
  exitLowLight,

  /// Đèn đang bật mà ảnh rất sáng: tắt đèn tạm để đo ánh sáng môi trường thật.
  startProbe,

  /// Đo thử xong: môi trường vẫn tối → bật lại đèn.
  probeStillDark,

  /// Đo thử xong: môi trường đã đủ sáng → giữ đèn tắt, ẩn cảnh báo.
  probeBright,
}

/// Logic quyết định ánh sáng (Dart thuần, dễ kiểm thử).
///
/// - Có trễ (hysteresis): vào trạng thái tối khi độ sáng < [darkThreshold] liên
///   tiếp [samplesToSwitch] mẫu; ra khỏi khi > [brightThreshold].
/// - Khi đèn flash đang bật, ảnh sáng lên do chính đèn nên không thể dùng độ sáng
///   hiện tại để quyết định tắt. Thay vào đó, nếu ảnh rất sáng (> [torchBrightThreshold])
///   liên tiếp, tắt đèn tạm ([startProbe]) rồi đo lại sau [probeSettle].
/// - Sau một lần đo thử mà vẫn tối, chờ [probeCooldown] mới thử lại để đèn không nháy liên tục.
///
/// Các ngưỡng là giá trị khởi điểm, CHƯA được hiệu chỉnh đo đạc trên nhiều môi trường.
class LightingDecider {
  final double darkThreshold;
  final double brightThreshold;
  final double torchBrightThreshold;
  final int samplesToSwitch;
  final Duration probeSettle;
  final Duration probeCooldown;

  LightingDecider({
    this.darkThreshold = 45,
    this.brightThreshold = 60,
    this.torchBrightThreshold = 110,
    this.samplesToSwitch = 3,
    this.probeSettle = const Duration(milliseconds: 800),
    this.probeCooldown = const Duration(seconds: 30),
  }) : assert(brightThreshold >= darkThreshold);

  bool _isLowLight = false;
  int _darkCount = 0;
  int _brightCount = 0;
  DateTime? _probeStartedAt;
  DateTime? _noProbeUntil;

  bool get isLowLight => _isLowLight;
  bool get isProbing => _probeStartedAt != null;

  /// [torchOn]: đèn flash hiện có đang bật không.
  LightingAction onSample(double luma, DateTime now, {required bool torchOn}) {
    // Đang đo thử với đèn tắt: chờ camera tự cân bằng phơi sáng rồi lấy 1 mẫu.
    final probeAt = _probeStartedAt;
    if (probeAt != null) {
      if (now.difference(probeAt) < probeSettle) return LightingAction.none;
      _probeStartedAt = null;
      _darkCount = 0;
      _brightCount = 0;
      if (luma < brightThreshold) {
        _noProbeUntil = now.add(probeCooldown);
        return LightingAction.probeStillDark;
      }
      _isLowLight = false;
      return LightingAction.probeBright;
    }

    if (!_isLowLight) {
      _darkCount = luma < darkThreshold ? _darkCount + 1 : 0;
      if (_darkCount >= samplesToSwitch) {
        _isLowLight = true;
        _darkCount = 0;
        _brightCount = 0;
        return LightingAction.enterLowLight;
      }
      return LightingAction.none;
    }

    // Đang ở trạng thái tối.
    if (torchOn) {
      _brightCount = luma > torchBrightThreshold ? _brightCount + 1 : 0;
      final cooled = _noProbeUntil == null || !now.isBefore(_noProbeUntil!);
      if (_brightCount >= samplesToSwitch && cooled) {
        _brightCount = 0;
        _probeStartedAt = now;
        return LightingAction.startProbe;
      }
      return LightingAction.none;
    }

    _brightCount = luma > brightThreshold ? _brightCount + 1 : 0;
    if (_brightCount >= samplesToSwitch) {
      _isLowLight = false;
      _brightCount = 0;
      return LightingAction.exitLowLight;
    }
    return LightingAction.none;
  }

  void reset() {
    _isLowLight = false;
    _darkCount = 0;
    _brightCount = 0;
    _probeStartedAt = null;
    _noProbeUntil = null;
  }
}
