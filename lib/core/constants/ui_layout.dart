/// Kích thước/vị trí dùng chung cho các lớp phủ trên màn hình camera,
/// để nút điều khiển chính, dòng gợi ý và thẻ kết quả không chồng lên nhau.
class UiLayout {
  UiLayout._();

  /// Nút chính Tạm dừng / Tiếp tục: giữa, phía dưới vùng camera.
  static const double mainButtonSize = 72;
  static const double mainButtonBottom = 24;

  /// Dòng gợi ý chất lượng ảnh (vd. "Ánh sáng yếu") ngay trên nút chính.
  static const double hintPillBottom = mainButtonBottom + mainButtonSize + 12; // 108

  /// Mép dưới của thẻ kết quả khi không có / có dòng gợi ý.
  static const double cardBottom = hintPillBottom + 4; // 112
  static const double cardBottomWithHint = cardBottom + 68; // 180
}
