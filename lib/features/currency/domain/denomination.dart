/// Các mệnh giá tiền tệ Việt Nam (VND) và lớp không phải tiền (none)
enum Denomination {
  d1k,
  d2k,
  d5k,
  d10k,
  d20k,
  d50k,
  d100k,
  d200k,
  d500k,
  none,
  unknown;

  /// Mã nhãn tương ứng trong mô hình TFLite (currency_labels.txt)
  String get code {
    switch (this) {
      case Denomination.d1k:
        return '1k';
      case Denomination.d2k:
        return '2k';
      case Denomination.d5k:
        return '5k';
      case Denomination.d10k:
        return '10k';
      case Denomination.d20k:
        return '20k';
      case Denomination.d50k:
        return '50k';
      case Denomination.d100k:
        return '100k';
      case Denomination.d200k:
        return '200k';
      case Denomination.d500k:
        return '500k';
      case Denomination.none:
        return 'none';
      case Denomination.unknown:
        return 'unknown';
    }
  }

  /// Tên mệnh giá hiển thị trực quan (Visual HUD)
  String get displayName {
    switch (this) {
      case Denomination.d1k:
        return '1.000 đ';
      case Denomination.d2k:
        return '2.000 đ';
      case Denomination.d5k:
        return '5.000 đ';
      case Denomination.d10k:
        return '10.000 đ';
      case Denomination.d20k:
        return '20.000 đ';
      case Denomination.d50k:
        return '50.000 đ';
      case Denomination.d100k:
        return '100.000 đ';
      case Denomination.d200k:
        return '200.000 đ';
      case Denomination.d500k:
        return '500.000 đ';
      case Denomination.none:
        return 'Không phải tiền';
      case Denomination.unknown:
        return 'Chưa rõ';
    }
  }

  /// Kiểm tra có phải là một mệnh giá tiền hay không
  bool get isMoney => this != Denomination.none && this != Denomination.unknown;

  /// Chuyển đổi từ chuỗi nhãn sang enum Denomination
  static Denomination fromCode(String code) {
    final normalized = code.trim().toLowerCase();
    switch (normalized) {
      case '1k':
      case '1000':
        return Denomination.d1k;
      case '2k':
      case '2000':
        return Denomination.d2k;
      case '5k':
      case '5000':
        return Denomination.d5k;
      case '10k':
      case '10000':
        return Denomination.d10k;
      case '20k':
      case '20000':
        return Denomination.d20k;
      case '50k':
      case '50000':
        return Denomination.d50k;
      case '100k':
      case '100000':
        return Denomination.d100k;
      case '200k':
      case '200000':
        return Denomination.d200k;
      case '500k':
      case '500000':
        return Denomination.d500k;
      case 'none':
        return Denomination.none;
      default:
        return Denomination.unknown;
    }
  }
}
