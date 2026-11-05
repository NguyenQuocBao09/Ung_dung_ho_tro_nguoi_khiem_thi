/// Thông tin cho từng lớp COCO: tên tiếng Việt để đọc và kích thước thực tế điển hình (mét)
/// dùng cho ước lượng khoảng cách xấp xỉ.
///
/// Kích thước là giá trị điển hình do nhóm tự đặt, KHÔNG phải số đo hiệu chuẩn.
class ObstacleClassInfo {
  final String nameVi;
  final double typicalHeightM;
  final double typicalWidthM;

  const ObstacleClassInfo(this.nameVi, this.typicalHeightM, this.typicalWidthM);

  /// Vật đủ lớn để người đi bộ có thể va phải: chỉ những vật này mới được phép
  /// phát cảnh báo "Gần" / "Rất gần". Vật nhỏ (cốc, điện thoại...) vẫn được nhận
  /// diện và đọc tên, nhưng không phát cảnh báo khẩn cấp.
  bool get canObstruct => typicalHeightM >= 0.4;
}

class ObstacleClasses {
  ObstacleClasses._();

  /// Toàn bộ 80 lớp COCO. Khoá là tên nhãn đúng như trong `coco_labels.txt`.
  static const Map<String, ObstacleClassInfo> all = {
    'person': ObstacleClassInfo('Người', 1.65, 0.5),
    'bicycle': ObstacleClassInfo('Xe đạp', 1.0, 1.7),
    'car': ObstacleClassInfo('Ô tô', 1.5, 4.2),
    'motorcycle': ObstacleClassInfo('Xe máy', 1.1, 1.9),
    'airplane': ObstacleClassInfo('Máy bay', 12.0, 35.0),
    'bus': ObstacleClassInfo('Xe buýt', 3.0, 10.0),
    'train': ObstacleClassInfo('Tàu hoả', 4.0, 20.0),
    'truck': ObstacleClassInfo('Xe tải', 3.0, 7.0),
    'boat': ObstacleClassInfo('Thuyền', 1.5, 5.0),
    'traffic light': ObstacleClassInfo('Đèn giao thông', 1.0, 0.35),
    'fire hydrant': ObstacleClassInfo('Trụ cứu hoả', 0.8, 0.4),
    'stop sign': ObstacleClassInfo('Biển báo dừng', 0.75, 0.75),
    'parking meter': ObstacleClassInfo('Cột thu phí đỗ xe', 1.3, 0.3),
    'bench': ObstacleClassInfo('Ghế băng', 0.85, 1.5),
    'bird': ObstacleClassInfo('Chim', 0.2, 0.25),
    'cat': ObstacleClassInfo('Mèo', 0.3, 0.45),
    'dog': ObstacleClassInfo('Chó', 0.6, 0.8),
    'horse': ObstacleClassInfo('Ngựa', 1.6, 2.2),
    'sheep': ObstacleClassInfo('Cừu', 0.9, 1.2),
    'cow': ObstacleClassInfo('Bò', 1.4, 2.2),
    'elephant': ObstacleClassInfo('Voi', 3.0, 5.0),
    'bear': ObstacleClassInfo('Gấu', 1.2, 1.8),
    'zebra': ObstacleClassInfo('Ngựa vằn', 1.4, 2.2),
    'giraffe': ObstacleClassInfo('Hươu cao cổ', 5.0, 3.0),
    'backpack': ObstacleClassInfo('Ba lô', 0.45, 0.3),
    'umbrella': ObstacleClassInfo('Ô dù', 1.0, 1.0),
    'handbag': ObstacleClassInfo('Túi xách', 0.3, 0.35),
    'tie': ObstacleClassInfo('Cà vạt', 0.5, 0.08),
    'suitcase': ObstacleClassInfo('Va li', 0.65, 0.45),
    'frisbee': ObstacleClassInfo('Đĩa ném', 0.25, 0.25),
    'skis': ObstacleClassInfo('Ván trượt tuyết', 1.7, 0.3),
    'snowboard': ObstacleClassInfo('Ván trượt tuyết', 1.5, 0.3),
    'sports ball': ObstacleClassInfo('Quả bóng', 0.22, 0.22),
    'kite': ObstacleClassInfo('Con diều', 0.8, 0.8),
    'baseball bat': ObstacleClassInfo('Gậy bóng chày', 0.85, 0.07),
    'baseball glove': ObstacleClassInfo('Găng bóng chày', 0.3, 0.25),
    'skateboard': ObstacleClassInfo('Ván trượt', 0.2, 0.8),
    'surfboard': ObstacleClassInfo('Ván lướt sóng', 1.8, 0.5),
    'tennis racket': ObstacleClassInfo('Vợt tennis', 0.7, 0.3),
    'bottle': ObstacleClassInfo('Chai', 0.25, 0.08),
    'wine glass': ObstacleClassInfo('Ly rượu', 0.2, 0.08),
    'cup': ObstacleClassInfo('Cốc', 0.1, 0.08),
    'fork': ObstacleClassInfo('Nĩa', 0.2, 0.03),
    'knife': ObstacleClassInfo('Dao', 0.22, 0.03),
    'spoon': ObstacleClassInfo('Thìa', 0.18, 0.04),
    'bowl': ObstacleClassInfo('Bát', 0.08, 0.15),
    'banana': ObstacleClassInfo('Chuối', 0.2, 0.2),
    'apple': ObstacleClassInfo('Táo', 0.08, 0.08),
    'sandwich': ObstacleClassInfo('Bánh mì kẹp', 0.08, 0.15),
    'orange': ObstacleClassInfo('Quả cam', 0.08, 0.08),
    'broccoli': ObstacleClassInfo('Bông cải xanh', 0.15, 0.15),
    'carrot': ObstacleClassInfo('Cà rốt', 0.2, 0.04),
    'hot dog': ObstacleClassInfo('Bánh mì xúc xích', 0.06, 0.18),
    'pizza': ObstacleClassInfo('Bánh pizza', 0.05, 0.3),
    'donut': ObstacleClassInfo('Bánh donut', 0.04, 0.1),
    'cake': ObstacleClassInfo('Bánh ngọt', 0.12, 0.2),
    'chair': ObstacleClassInfo('Ghế', 0.9, 0.5),
    'couch': ObstacleClassInfo('Ghế sofa', 0.85, 1.9),
    'potted plant': ObstacleClassInfo('Chậu cây', 0.8, 0.5),
    'bed': ObstacleClassInfo('Giường', 0.6, 1.6),
    'dining table': ObstacleClassInfo('Bàn', 0.75, 1.2),
    'toilet': ObstacleClassInfo('Bồn cầu', 0.75, 0.4),
    'tv': ObstacleClassInfo('Ti vi', 0.6, 1.0),
    'laptop': ObstacleClassInfo('Máy tính xách tay', 0.25, 0.35),
    'mouse': ObstacleClassInfo('Chuột máy tính', 0.04, 0.07),
    'remote': ObstacleClassInfo('Điều khiển từ xa', 0.18, 0.05),
    'keyboard': ObstacleClassInfo('Bàn phím', 0.15, 0.45),
    'cell phone': ObstacleClassInfo('Điện thoại', 0.15, 0.075),
    'microwave': ObstacleClassInfo('Lò vi sóng', 0.3, 0.5),
    'oven': ObstacleClassInfo('Lò nướng', 0.6, 0.6),
    'toaster': ObstacleClassInfo('Máy nướng bánh', 0.2, 0.28),
    'sink': ObstacleClassInfo('Bồn rửa', 0.25, 0.5),
    'refrigerator': ObstacleClassInfo('Tủ lạnh', 1.7, 0.7),
    'book': ObstacleClassInfo('Sách', 0.24, 0.17),
    'clock': ObstacleClassInfo('Đồng hồ', 0.3, 0.3),
    'vase': ObstacleClassInfo('Bình hoa', 0.3, 0.15),
    'scissors': ObstacleClassInfo('Kéo', 0.2, 0.08),
    'teddy bear': ObstacleClassInfo('Gấu bông', 0.4, 0.3),
    'hair drier': ObstacleClassInfo('Máy sấy tóc', 0.25, 0.2),
    'toothbrush': ObstacleClassInfo('Bàn chải đánh răng', 0.19, 0.02),
  };

  static ObstacleClassInfo? of(String cocoLabel) => all[cocoLabel];
}
