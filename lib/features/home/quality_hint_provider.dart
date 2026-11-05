import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quality/lighting_monitor.dart';

/// Gợi ý chất lượng ảnh hiển thị dạng viên thuốc trên màn hình camera.
/// Trước đây là giá trị giả lập cố định "Ánh sáng yếu"; nay lấy từ đo độ sáng
/// thật của luồng camera ([LightingMonitor]). null = đủ sáng / chưa đo → không hiện.
final Provider<String?> qualityHintProvider = lowLightHintProvider;
