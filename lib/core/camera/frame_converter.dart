import 'dart:math' as math;
import 'dart:typed_data';

/// Khung hình YUV dạng thuần Dart (không phụ thuộc Flutter/camera plugin) để có thể
/// gửi sang isolate nền và kiểm thử đơn vị.
///
/// Hỗ trợ hai bố cục mà plugin `camera` trên Android có thể trả về:
/// - **NV21 một plane** (khi `ImageFormatGroup.nv21`, camera_android gộp Y + VU vào
///   một mảng, `bytesPerRow == width`).
/// - **YUV420 ba plane** (Y, U, V riêng, có `bytesPerRow` / `bytesPerPixel`).
class YuvFrame {
  final int width;
  final int height;

  final Uint8List yBytes;
  final int yRowStride;

  final Uint8List uBytes;
  final Uint8List vBytes;
  final int uvRowStride;
  final int uvPixelStride;

  /// Góc xoay cảm biến (0/90/180/270, theo chiều kim đồng hồ) để đưa ảnh về đứng.
  final int rotationDegrees;

  const YuvFrame({
    required this.width,
    required this.height,
    required this.yBytes,
    required this.yRowStride,
    required this.uBytes,
    required this.vBytes,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.rotationDegrees,
  });

  /// Tạo từ bộ đệm NV21 một plane: [Y: rowStride*height][VU xen kẽ: rowStride*height/2].
  factory YuvFrame.fromNv21({
    required Uint8List bytes,
    required int width,
    required int height,
    int? rowStride,
    int rotationDegrees = 0,
  }) {
    final stride = rowStride ?? width;
    final ySize = stride * height;
    if (bytes.length < ySize + stride * (height ~/ 2)) {
      throw ArgumentError(
        'Bộ đệm NV21 quá nhỏ: ${bytes.length} < ${ySize + stride * (height ~/ 2)}',
      );
    }
    final uv = Uint8List.sublistView(bytes, ySize);
    return YuvFrame(
      width: width,
      height: height,
      yBytes: bytes,
      yRowStride: stride,
      // NV21: V đứng trước, U đứng sau trong mỗi cặp.
      vBytes: uv,
      uBytes: Uint8List.sublistView(uv, 1),
      uvRowStride: stride,
      uvPixelStride: 2,
      rotationDegrees: rotationDegrees,
    );
  }

  /// Kích thước ảnh sau khi xoay về chiều đứng.
  int get uprightWidth => (rotationDegrees % 180 == 0) ? width : height;
  int get uprightHeight => (rotationDegrees % 180 == 0) ? height : width;

  /// Độ sáng trung bình (0..255) chỉ tính trên vùng Y, lấy mẫu thưa theo lưới.
  double averageLuminance({int step = 16}) {
    var sum = 0;
    var count = 0;
    for (var y = 0; y < height; y += step) {
      final row = y * yRowStride;
      for (var x = 0; x < width; x += step) {
        sum += yBytes[row + x];
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }
}

/// Ảnh RGB 8-bit đã xoay về chiều đứng (RGBRGB..., không padding).
class RgbImage {
  final int width;
  final int height;
  final Uint8List pixels;

  RgbImage(this.width, this.height, [Uint8List? pixels])
      : pixels = pixels ?? Uint8List(width * height * 3) {
    if (this.pixels.length != width * height * 3) {
      throw ArgumentError('Bộ đệm RGB sai kích thước');
    }
  }
}

/// Chuyển khung YUV sang ảnh RGB đứng, thu nhỏ để cạnh dài không vượt [maxSide]
/// (lấy mẫu láng giềng gần nhất). Dùng khi cần cắt nhiều vùng từ cùng một khung hình.
RgbImage yuvToUprightRgb(YuvFrame f, {int maxSide = 512}) {
  final uw = f.uprightWidth;
  final uh = f.uprightHeight;
  final scale = math.min(1.0, maxSide / math.max(uw, uh));
  final outW = math.max(1, (uw * scale).round());
  final outH = math.max(1, (uh * scale).round());
  final out = RgbImage(outW, outH);
  final px = out.pixels;
  final rot = f.rotationDegrees % 360;
  final w = f.width;
  final h = f.height;
  final sxStep = uw / outW;
  final syStep = uh / outH;

  var i = 0;
  for (var oy = 0; oy < outH; oy++) {
    final ry = math.min(uh - 1, ((oy + 0.5) * syStep).floor());
    for (var ox = 0; ox < outW; ox++) {
      final rx = math.min(uw - 1, ((ox + 0.5) * sxStep).floor());
      int sx, sy;
      switch (rot) {
        case 90:
          sx = ry;
          sy = h - 1 - rx;
          break;
        case 180:
          sx = w - 1 - rx;
          sy = h - 1 - ry;
          break;
        case 270:
          sx = w - 1 - ry;
          sy = rx;
          break;
        default:
          sx = rx;
          sy = ry;
      }
      final yv = f.yBytes[sy * f.yRowStride + sx];
      final uvIndex = (sy >> 1) * f.uvRowStride + (sx >> 1) * f.uvPixelStride;
      final u = f.uBytes[uvIndex] - 128;
      final v = f.vBytes[uvIndex] - 128;
      px[i++] = (yv + 1.402 * v).round().clamp(0, 255);
      px[i++] = (yv - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
      px[i++] = (yv + 1.772 * u).round().clamp(0, 255);
    }
  }
  return out;
}

/// Cắt vùng chuẩn hoá [left, top, right, bottom] (0..1) của [src] và co giãn thẳng
/// (không giữ tỉ lệ) về [dstSize] x [dstSize], nội suy song tuyến, ghi float32 0..255 vào [out].
void cropResizeToFloat(
  RgbImage src,
  double left,
  double top,
  double right,
  double bottom,
  int dstSize,
  Float32List out,
) {
  if (out.length != dstSize * dstSize * 3) {
    throw ArgumentError('Bộ đệm đầu ra sai kích thước');
  }
  final x0 = left.clamp(0.0, 1.0) * src.width;
  final y0 = top.clamp(0.0, 1.0) * src.height;
  final cw = math.max(1e-6, (right.clamp(0.0, 1.0) * src.width) - x0);
  final ch = math.max(1e-6, (bottom.clamp(0.0, 1.0) * src.height) - y0);
  final sx = cw / dstSize;
  final sy = ch / dstSize;
  final maxX = src.width - 1;
  final maxY = src.height - 1;
  final px = src.pixels;
  final stride = src.width * 3;

  var i = 0;
  for (var oy = 0; oy < dstSize; oy++) {
    final fy = (y0 + (oy + 0.5) * sy - 0.5).clamp(0.0, maxY.toDouble());
    final yA = fy.floor();
    final yB = math.min(yA + 1, maxY);
    final wy = fy - yA;
    final rowA = yA * stride;
    final rowB = yB * stride;
    for (var ox = 0; ox < dstSize; ox++) {
      final fx = (x0 + (ox + 0.5) * sx - 0.5).clamp(0.0, maxX.toDouble());
      final xA = fx.floor();
      final xB = math.min(xA + 1, maxX);
      final wx = fx - xA;
      final a = rowA + xA * 3;
      final b = rowA + xB * 3;
      final c = rowB + xA * 3;
      final d = rowB + xB * 3;
      for (var k = 0; k < 3; k++) {
        final top = px[a + k] + (px[b + k] - px[a + k]) * wx;
        final bot = px[c + k] + (px[d + k] - px[c + k]) * wx;
        out[i++] = top + (bot - top) * wy;
      }
    }
  }
}

/// Thông số letterbox đã dùng, để quy đổi bounding box từ không gian model về ảnh gốc.
class LetterboxInfo {
  /// Tỉ lệ co giãn ảnh đứng -> ảnh model.
  final double scale;

  /// Phần đệm (pixel trong không gian model) ở trái và trên.
  final double padX;
  final double padY;

  /// Kích thước ảnh đứng (sau xoay).
  final int srcWidth;
  final int srcHeight;

  final int dstSize;

  const LetterboxInfo({
    required this.scale,
    required this.padX,
    required this.padY,
    required this.srcWidth,
    required this.srcHeight,
    required this.dstSize,
  });

  factory LetterboxInfo.compute(int srcWidth, int srcHeight, int dstSize) {
    final scale = math.min(dstSize / srcWidth, dstSize / srcHeight);
    final newW = srcWidth * scale;
    final newH = srcHeight * scale;
    return LetterboxInfo(
      scale: scale,
      padX: (dstSize - newW) / 2,
      padY: (dstSize - newH) / 2,
      srcWidth: srcWidth,
      srcHeight: srcHeight,
      dstSize: dstSize,
    );
  }
}

/// Chuyển trực tiếp khung YUV sang tensor RGB float32 [dstSize x dstSize x 3], giá trị 0..1,
/// có xoay về chiều đứng và letterbox (giữ tỉ lệ, đệm màu xám 114 như Ultralytics).
///
/// Lấy mẫu láng giềng gần nhất trực tiếp từ YUV, không tạo ảnh RGB trung gian kích thước đầy đủ.
/// Ghi kết quả vào [out] nếu được cung cấp (tái sử dụng bộ đệm).
LetterboxInfo yuvToLetterboxedRgbFloat(
  YuvFrame f,
  int dstSize, {
  Float32List? out,
}) {
  final buffer = out ?? Float32List(dstSize * dstSize * 3);
  if (buffer.length != dstSize * dstSize * 3) {
    throw ArgumentError('Bộ đệm đầu ra sai kích thước');
  }
  final lb = LetterboxInfo.compute(f.uprightWidth, f.uprightHeight, dstSize);
  const pad = 114.0 / 255.0;
  final rot = f.rotationDegrees % 360;
  final w = f.width;
  final h = f.height;
  final inv = 1.0 / lb.scale;

  var i = 0;
  for (var oy = 0; oy < dstSize; oy++) {
    final ry = ((oy + 0.5 - lb.padY) * inv).floor();
    for (var ox = 0; ox < dstSize; ox++) {
      final rx = ((ox + 0.5 - lb.padX) * inv).floor();
      if (rx < 0 || ry < 0 || rx >= lb.srcWidth || ry >= lb.srcHeight) {
        buffer[i++] = pad;
        buffer[i++] = pad;
        buffer[i++] = pad;
        continue;
      }
      // (rx, ry) trong ảnh đứng -> (sx, sy) trong ảnh cảm biến.
      int sx, sy;
      switch (rot) {
        case 90:
          sx = ry;
          sy = h - 1 - rx;
          break;
        case 180:
          sx = w - 1 - rx;
          sy = h - 1 - ry;
          break;
        case 270:
          sx = w - 1 - ry;
          sy = rx;
          break;
        default:
          sx = rx;
          sy = ry;
      }
      final yv = f.yBytes[sy * f.yRowStride + sx];
      final uvIndex = (sy >> 1) * f.uvRowStride + (sx >> 1) * f.uvPixelStride;
      final u = f.uBytes[uvIndex] - 128;
      final v = f.vBytes[uvIndex] - 128;

      final r = (yv + 1.402 * v).clamp(0, 255);
      final g = (yv - 0.344136 * u - 0.714136 * v).clamp(0, 255);
      final b = (yv + 1.772 * u).clamp(0, 255);
      buffer[i++] = r / 255.0;
      buffer[i++] = g / 255.0;
      buffer[i++] = b / 255.0;
    }
  }
  return lb;
}
