/// Toàn bộ chuỗi hiển thị và giọng nói tiếng Việt cho ứng dụng Vision Assist.
/// Không đặt chuỗi tiếng Việt rải rác trong các file UI/Logic.
class StringsVi {
  StringsVi._();

  // Thông tin chung
  /// Tên tiếng Anh để gọi được bằng trợ lý giọng nói (vd. Bixby chưa hỗ trợ tiếng Việt).
  static const String appTitle = 'Vision Assist';
  static const String appSlogan = 'Trợ lý thị giác cho người khiếm thị';

  // Tên các chế độ hoạt động
  static const String modeReading = 'Đọc chữ';
  static const String modeCurrency = 'Nhận diện tiền';
  static const String modeObstacle = 'Cảnh báo vật cản';

  // Tên chế độ hiển thị trong ngăn kéo (Drawer - theo mẫu thiết kế Lookout)
  static const String drawerHeaderTitle = appTitle;
  static const String drawerMenuA11yLabel = 'Trình đơn chọn chế độ';
  static const String drawerModeCurrency = 'Nhận diện tiền mặt';
  static const String drawerModeReading = 'Đọc văn bản';
  static const String drawerModeObstacle = 'Cảnh báo vật cản';
  static const String modeSelectedNotice = 'Đang chọn';

  // Mô tả chuyển chế độ (Semantics Actions)
  static const String actionSwitchToReading = 'Chuyển sang chế độ đọc chữ';
  static const String actionSwitchToCurrency = 'Chuyển sang chế độ nhận diện tiền';
  static const String actionSwitchToObstacle = 'Chuyển sang chế độ cảnh báo vật cản';
  static const String actionRepeatFeedback = 'Đọc lại gợi ý hoặc trạng thái';

  // AppBar và Menu
  static const String menuButton = 'Trình đơn cài đặt';
  static const String infoButton = 'Hướng dẫn sử dụng';
  static const String infoDialogTitle = 'Hướng dẫn sử dụng';
  static const String closeButton = 'Đóng';
  static const String guideStopButton = 'Dừng hướng dẫn';
  static const String guideStopHint = 'Chạm hai lần để dừng đọc và đóng hướng dẫn';

  /// Hướng dẫn bằng giọng nói: đọc tự động lần đầu mở app và khi bấm nút Hướng dẫn.
  /// Mỗi phần tử là một câu/đoạn; màn hình hướng dẫn cũng hiển thị đúng nội dung này.
  static const List<String> voiceGuideSteps = [
    'Chào mừng bạn đến với $appTitle, trợ lý thị giác cho người khiếm thị. '
        'Ứng dụng xử lý hình ảnh ngay trên điện thoại, không cần kết nối mạng.',
    'Ứng dụng có ba chế độ: Đọc văn bản, Nhận diện tiền, và Cảnh báo vật cản. '
        'Khi mở ứng dụng, chế độ Đọc văn bản được bật sẵn.',
    'Để đổi chế độ, bấm nút Trình đơn ở góc trên bên trái rồi chọn chế độ. '
        'Nếu dùng TalkBack, chọn vùng máy ảnh, vuốt lên hoặc xuống để chọn hành động đổi chế độ, '
        'rồi chạm hai lần để thực hiện.',
    'Chế độ Đọc văn bản: hướng máy ảnh vào trang giấy và giữ máy yên, ứng dụng sẽ tự đọc. '
        'Nếu nghe báo chữ bị cắt ở mép, hãy đưa điện thoại ra xa hơn một chút.',
    'Chế độ Nhận diện tiền: đưa tờ tiền polymer vào trước máy ảnh, '
        'ứng dụng chỉ đọc mệnh giá khi đã nhận ra rõ.',
    'Chế độ Cảnh báo vật cản chỉ mang tính hỗ trợ, không phát hiện được mọi vật '
        'và khoảng cách chỉ là ước lượng. Hãy luôn dùng gậy dò đường.',
    'Nút lớn ở giữa phía dưới màn hình dùng để tạm dừng hoặc tiếp tục. '
        'Khi xung quanh quá tối, ứng dụng sẽ tự bật đèn flash.',
    'Mục Gần đây ở thanh dưới cùng lưu các kết quả đã đọc để bạn nghe lại.',
    'Muốn nghe lại hướng dẫn này, bấm nút Hướng dẫn sử dụng ở góc trên bên phải màn hình. '
        'Chúc bạn sử dụng thuận lợi.',
  ];

  // Kính ngắm máy ảnh & Nút chụp
  static const String cameraViewfinderLabel = 'Kính ngắm máy ảnh';
  static const String cameraViewfinderHint = 'Chạm hai lần để tạm dừng hoặc tiếp tục';
  static const String capturingText = 'Đang chụp';

  // Thông báo chất lượng hình ảnh (Quality Pill)
  static const String hintLowLight = 'Ánh sáng yếu';
  static const String hintLowLightTorchOn = 'Ánh sáng yếu\nĐã bật đèn flash';
  static const String lowLightTorchOnNotice = 'Ánh sáng yếu, đã bật đèn flash';
  static const String hintBlurry = 'Hình ảnh bị mờ, vui lòng giữ yên máy';
  static const String hintNormal = 'Chất lượng hình ảnh tốt';
  static const String qualityPillLabel = 'Gợi ý:';

  // Điều hướng dưới (Bottom Navigation Bar)
  static const String navView = 'Xem';
  static const String navRecent = 'Gần đây';

  // Màn hình Gần đây
  static const String recentScreenTitle = 'Gần đây';
  static const String recentEmptyText = 'Chưa có kết quả nào được lưu gần đây.';
  static const String backButton = 'Quay lại';
  static const String recentTypeReading = 'Đọc văn bản';
  static const String recentTypeCurrency = 'Nhận diện tiền';
  static const String recentItemHint = 'Chạm hai lần để nghe lại';
  static const String recentClearAll = 'Xóa tất cả';
  static const String recentClearConfirmTitle = 'Xóa toàn bộ lịch sử?';
  static const String recentClearConfirmBody =
      'Các kết quả đã lưu trên máy sẽ bị xóa và không thể khôi phục.';
  static const String recentCleared = 'Đã xóa lịch sử';
  static const String cancelButton = 'Hủy';
  static const String recentPrivacyNote = 'Chỉ lưu văn bản trên máy này, không lưu ảnh.';

  // Quyền truy cập máy ảnh (Camera Permission)
  static const String cameraPermissionRequiredTitle = 'Cần quyền truy cập máy ảnh';
  static const String cameraPermissionDeniedMessage =
      'Ứng dụng cần quyền sử dụng máy ảnh để nhận diện môi trường xung quanh cho bạn. Vui lòng bấm nút bên dưới để mở Cài đặt và cấp quyền.';
  static const String openSettingsButton = 'Mở Cài đặt hệ thống';
  static const String retryPermissionButton = 'Thử lại cấp quyền';
  static const String cameraLoading = 'Đang khởi động máy ảnh, vui lòng chờ';
  static const String cameraError = 'Không thể kết nối máy ảnh. Vui lòng khởi động lại ứng dụng.';

  // Nhận diện tiền tệ (Currency Recognition)
  static const String currencyProcessing = 'Đang nhận diện tờ tiền';
  static const String currencyDetecting = 'Đang nhận diện…';
  static const String currencyNotRecognized = 'Không nhận diện được tiền';
  static const String currencyUnclear = 'Chưa nhận diện rõ mệnh giá, vui lòng điều chỉnh camera';
  static const String currencyModelLoading = 'Mô hình nhận diện tiền đang tải';
  static const String currencyModelError = 'Không thể khởi tạo mô hình nhận diện tiền';
  static const String currencyResultPrefix = 'Kết quả';
  static const String currencyConfidence = 'Độ tin cậy';
  static const String currencyInferenceTime = 'Thời gian xử lý';
  static const String hintBringCloser = 'Hãy đưa tờ tiền gần camera hơn';
  static const String actionReadAgain = 'Đọc lại';
  static const String actionNewBill = 'Tờ khác';
  static const String actionPauseCurrency = 'Tạm dừng nhận diện';
  static const String actionResumeCurrency = 'Tiếp tục nhận diện';
  static const String currencyPausedNotice = 'Đã tạm dừng nhận diện tiền';
  static const String currencyResumedNotice = 'Đang tiếp tục nhận diện tiền';
  static const String currencyNoLastBill = 'Chưa có tờ tiền nào được đọc';
  static const String actionToggleTorch = 'Đèn pin';
  static const String torchTurnedOn = 'Đã bật đèn pin';
  static const String torchTurnedOff = 'Đã tắt đèn pin';

  // Đọc chữ tự động (Text Reading)
  static const String hintNoTextFound = 'Chưa thấy chữ, hãy đưa văn bản vào giữa khung hình';
  static const String hintTextCutAtEdge = 'Chữ bị cắt ở mép, hãy đưa điện thoại ra xa hơn một chút';
  static const String actionRestartReading = 'Đọc lại từ đầu';
  static const String actionPauseReading = 'Tạm dừng tự đọc';
  static const String actionResumeReading = 'Tiếp tục tự đọc';
  static const String readingPausedNotice = 'Đã tạm dừng tự đọc';
  static const String readingResumedNotice = 'Đang tiếp tục tự đọc';
  static const String readingOverlayTitle = 'Văn bản nhận dạng';
  static const String readingStatusAuto = 'Đang tự động đọc chữ...';
  static const String readingStatusPaused = 'Đang tạm dừng';

  // Cảnh báo vật cản (Obstacle Detection)
  static const String obstacleIntro =
      'Nhận diện vật thể phía trước. Chỉ mang tính hỗ trợ, không phát hiện được mọi vật. Hãy tiếp tục dùng gậy dò đường.';
  static const String obstacleModelError =
      'Không thể khởi tạo mô hình phát hiện vật cản. Chức năng cảnh báo đang tắt.';
  static const String obstacleCameraBlocked =
      'Camera bị che hoặc quá tối, không thể cảnh báo vật cản';
  static const String obstacleProcessingError = 'Lỗi xử lý hình ảnh, cảnh báo vật cản tạm ngưng';
  static const String obstacleDangerPrefix = 'Cẩn thận!';
  static const String obstacleVeryClose = 'rất gần';
  static const String obstacleAbout = 'khoảng';
  static const String obstacleMeters = 'mét';
  static const String obstacleDirLeft = 'bên trái';
  static const String obstacleDirAhead = 'phía trước';
  static const String obstacleDirRight = 'bên phải';
  static const String obstacleLevelSafe = 'Chưa thấy vật cản gần';
  static const String obstacleNothing = 'Chưa nhận ra vật thể nào phía trước';
  static const String obstacleNear = 'ở gần';
  static const String actionReadScene = 'Đọc lại các vật thể';
  static const String obstacleLevelWarning = 'Gần';
  static const String obstacleLevelDanger = 'Rất gần';
  static const String obstaclePausedNotice = 'Đã tạm dừng cảnh báo vật cản';
  static const String obstacleResumedNotice = 'Đang tiếp tục cảnh báo vật cản';
  static const String actionPauseObstacle = 'Tạm dừng cảnh báo';
  static const String actionResumeObstacle = 'Tiếp tục cảnh báo';
  static const String obstacleDisclaimer = 'Khoảng cách chỉ là ước lượng';
}
