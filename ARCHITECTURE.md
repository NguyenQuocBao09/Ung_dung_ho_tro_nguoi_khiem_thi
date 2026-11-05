# Kiến Trúc Hệ Thống - VisionAssist (Trợ Lý Thị Giác)

> **Dự án:** Ứng dụng di động hỗ trợ người khiếm thị nhận diện tiền tệ, đọc văn bản và cảnh báo vật cản theo thời gian thực.  
> **Nền tảng:** Flutter (Dart), 100% On-Device Edge AI (TensorFlow Lite, Google ML Kit), Hoạt động ngoại tuyến (Offline-First).

---

## 1. Cấu Trúc Thư Mục Dự Án (Directory Structure)

```text
vision_assist/
├── pubspec.yaml
├── README.md
│
├── assets/
│   ├── models/
│   │   ├── currency_mobilenetv3.tflite      # Model phân loại tiền polymer VND
│   │   ├── currency_labels.txt              # 10000, 20000, ..., 500000
│   │   ├── obstacle_yolov8n.tflite          # Model phát hiện vật thể (YOLOv8-nano COCO)
│   │   └── coco_labels.txt
│   └── sounds/
│       ├── mode_change.mp3                  # Âm báo chuyển đổi chế độ
│       ├── alert_beep.mp3                   # Âm beep cảnh báo vật cản theo tần số cự ly
│       └── error.mp3                        # Âm báo lỗi thao tác
│
├── lib/
│   ├── main.dart                            # Điểm khởi chạy ứng dụng
│   │
│   ├── app/
│   │   ├── app.dart                         # MaterialApp cấu hình Semantics trợ năng
│   │   ├── theme.dart                       # Chủ đề tương phản cao (High Contrast), font chữ lớn
│   │   └── di.dart                          # Service Locator / Dependency Injection (GetIt/Riverpod)
│   │
│   ├── core/                                # Module dùng chung (Shared Core Modules)
│   │   ├── accessibility/                   # Tầng 1: Tương tác trợ năng (Non-visual Interaction)
│   │   │   ├── gesture_layer.dart           # Bắt cử chỉ: vuốt, chạm đôi, giữ lâu, lắc máy
│   │   │   └── semantic_labels.dart         # Nhãn trợ năng cho trình đọc màn hình TalkBack/VoiceOver
│   │   │
│   │   ├── feedback/                        # Tầng 1: Phản hồi đa giác quan
│   │   │   ├── feedback_manager.dart        # Hàng đợi ưu tiên (Priority Queue: ngắt lời vs xếp hàng)
│   │   │   ├── feedback_message.dart        # Model thông điệp: nội dung + độ ưu tiên (Urgent, Normal, Info)
│   │   │   ├── tts_service.dart             # Text-to-Speech (flutter_tts, vi-VN, tùy biến tốc độ)
│   │   │   └── haptic_service.dart          # Mẫu rung phản hồi xúc giác (Haptic patterns)
│   │   │
│   │   ├── mode/                            # Tầng 2: Máy trạng thái chế độ hoạt động
│   │   │   ├── app_mode.dart                # Enum: reading, currency, obstacle
│   │   │   └── mode_controller.dart         # State Machine điều phối chuyển đổi chế độ (3 chế độ cốt lõi)
│   │   │
│   │   ├── camera/                          # Tầng 2: Điều khiển phần cứng Camera & Stream
│   │   │   ├── camera_service.dart          # Quản lý CameraController tập trung (Singleton lifecycle)
│   │   │   ├── camera_lifecycle_guard.dart  # Ngắt Camera Stream khi ứng dụng vào nền/khóa màn hình
│   │   │   ├── torch_service.dart           # Bật/tắt đèn Flash trợ sáng tự động hoặc thủ công
│   │   │   ├── frame_throttler.dart         # Lấy mẫu khung hình ngắt quãng (300ms–500ms)
│   │   │   └── frame_converter.dart         # Trích xuất Y-plane / Chuyển đổi định dạng ảnh
│   │   │
│   │   ├── quality/                         # Tầng 2: Kiểm soát chất lượng ảnh đầu vào
│   │   │   ├── blur_detector.dart           # Đo độ mờ (Laplacian variance trực tiếp trên Y-plane)
│   │   │   ├── lighting_detector.dart       # Kiểm tra độ sáng trung bình khung hình
│   │   │   └── quality_guard.dart           # Hướng dẫn người dùng căn chỉnh máy bằng giọng nói
│   │   │
│   │   ├── sensors/                         # Tầng 2: Cảm biến phụ trợ
│   │   │   └── motion_service.dart          # Gia tốc kế, con quay (tạm dừng AI khi thiết bị đứng yên)
│   │   │
│   │   ├── preferences/                     # Cài đặt cá nhân hóa của người dùng
│   │   │   └── user_settings.dart           # Lưu tốc độ đọc TTS, cường độ rung, bật tắt tự động flash
│   │   │
│   │   ├── ml/                              # Tầng 3: Hạ tầng suy luận AI (Edge Inference Engine)
│   │   │   ├── inference_engine.dart        # Interface chuẩn cho mọi model AI
│   │   │   ├── inference_result.dart        # Chuẩn hóa cấu trúc kết quả suy luận
│   │   │   └── isolate_runner.dart          # Đẩy tính toán TFLite & hậu xử lý ma trận ra background Isolate
│   │   │
│   │   └── constants/
│   │       └── strings_vi.dart              # Toàn bộ chuỗi âm thanh / giọng nói hướng dẫn tiếng Việt
│   │
│   └── features/                            # Các tính năng nghiệp vụ khép kín (Feature-First)
│       ├── shell/                           # Kiến trúc khung hiển thị duy nhất (Single Camera Shell)
│       │   ├── camera_viewfinder.dart       # Widget Camera Preview duy nhất chạy xuyên suốt
│       │   └── main_gesture_screen.dart     # Bề mặt bắt cử chỉ cảm ứng toàn màn hình
│       │
│       ├── text_reading/                    # Tính năng 1: Đọc văn bản in ấn (OCR & TTS Offline)
│       │   ├── data/
│       │   │   └── mlkit_ocr_engine.dart    # Google ML Kit Text Recognition (On-device)
│       │   ├── domain/
│       │   │   └── text_postprocessor.dart  # Ghép dòng, chuẩn hóa dấu tiếng Việt, lọc ký tự rác
│       │   └── presentation/
│       │       ├── reading_controller.dart  # Quản lý trạng thái đọc
│       │       └── reading_overlay.dart     # Giao diện lớp phủ (Visual HUD + accessibility announcement)
│       │
│       ├── currency/                        # Tính năng 2: Nhận diện tiền polymer VND (Edge AI)
│       │   ├── data/
│       │   │   └── currency_classifier.dart # TFLite MobileNetV3 (Edge Inference)
│       │   ├── domain/
│       │   │   ├── denomination.dart        # Enum mệnh giá: 10k, 20k, 50k, 100k, 200k, 500k
│       │   │   └── vote_aggregator.dart     # Thuật toán bỏ phiếu 3/5 khung hình chống nhiễu
│       │   └── presentation/
│       │       ├── currency_controller.dart
│       │       └── currency_overlay.dart
│       │
│       └── obstacle/                        # Tính năng 3: Cảnh báo vật cản di chuyển (Real-time YOLO)
│           ├── data/
│           │   └── obstacle_detector.dart   # TFLite YOLOv8n + giải mã NMS
│           ├── domain/
│           │   ├── distance_estimator.dart  # Ước lượng cự ly dựa trên tỉ lệ kích thước Bounding Box
│           │   └── alert_level.dart         # Phân cấp nguy hiểm: An toàn / Gần / Rất gần
│           └── presentation/
│               ├── obstacle_controller.dart
│               └── obstacle_overlay.dart
│
├── test/                                    # Kiểm thử tự động (Unit & Integration Tests)
│   ├── blur_detector_test.dart              # Kiểm tra thuật toán đo độ mờ ảnh
│   ├── vote_aggregator_test.dart            # Kiểm tra cơ chế bỏ phiếu 3/5 khung hình
│   ├── feedback_manager_test.dart           # Kiểm thử hàng đợi ưu tiên (ngắt lời vs xếp hàng)
│   ├── mode_controller_test.dart            # Kiểm thử máy trạng thái chuyển đổi chế độ
│   └── distance_estimator_test.dart         # Kiểm tra tính toán cự ly vật cản
│
├── ml_training/                             # Pipeline huấn luyện mô hình (Python/Google Colab)
│   ├── requirements.txt
│   ├── data/
│   │   ├── raw/                             # Dữ liệu ảnh thô tự chụp + Kaggle VND
│   │   └── train/  val/  test/              # Phân chia dữ liệu theo thư mục mệnh giá
│   ├── notebooks/
│   │   └── train_currency.ipynb             # Huấn luyện Transfer Learning MobileNetV3 + xuất TFLite
│   ├── scripts/
│   │   ├── split_dataset.py                 # Chia tập train/val/test
│   │   ├── augment.py                       # Tăng cường dữ liệu (làm mờ, xoay, nhăn, thiếu sáng)
│   │   ├── export_tflite.py                 # Lượng tử hóa sau huấn luyện (Post-training Quantization FP16/INT8)
│   │   └── evaluate.py                      # Đánh giá Accuracy, Precision, Confusion Matrix
│   └── outputs/
│       └── metrics/                         # Biểu đồ loss, ma trận nhầm lẫn
│
├── evaluation/                              # Báo cáo đánh giá hiệu năng thực nghiệm
│   ├── latency_log.csv                      # Nhật ký độ trễ suy luận (ms/frame) trên thiết bị thực
│   ├── battery_log.csv                      # Nhật ký đo mức tiêu hao năng lượng và nhiệt độ máy
│   ├── ocr_test_cases.md                    # Tập mẫu kiểm thử độ chính xác đọc văn bản
│   └── user_feedback.md                     # Tổng hợp phản hồi từ người dùng khiếm thị thực tế
│
└── docs/                                    # Tài liệu đồ án / thuyết minh
    ├── architecture.png                     # Sơ đồ khối kiến trúc hệ thống
    ├── baocao.docx                          # Báo cáo chuyên đề đồ án tốt nghiệp
    └── screenshots/                         # Ảnh chụp màn hình ứng dụng
```

---

## 2. Các Tầng Kiến Trúc Hệ Thống (Layered Architecture Breakdown)

Hệ thống được tổ chức thành 4 tầng logic độc lập theo nguyên lý **Inversion of Control** và **Separation of Concerns**, hoạt động hoàn toàn On-Device không phụ thuộc Internet:

```text
+--------------------------------------------------------------------------+
|  TẦNG 1: TRỢ NĂNG & PHẢN HỒI (Accessibility & Multimodal Feedback)       |
|  - Cử chỉ phi thị giác: Vuốt ngang (3 chế độ), Chạm đôi (hành động), Lắc  |
|  - Phản hồi: Hàng đợi ưu tiên TTS (tiếng Việt) + Haptic Feedback (Rung)  |
+--------------------------------------------------------------------------+
                                    │
                                    ▼
+--------------------------------------------------------------------------+
|  TẦNG 2: ĐIỀU PHỐI HỆ THỐNG & PHẦN CỨNG (Core Hardware & Quality Guard)  |
|  - Quản lý Camera Stream tập trung (Single Viewfinder Lifecycle)         |
|  - Frame Throttler (300-500ms) kết hợp Motion Sensor (ngắt khi đứng yên) |
|  - Quality Guard: Kiểm tra độ mờ (Y-plane Laplacian) & Độ sáng tự động   |
+--------------------------------------------------------------------------+
                                    │
                                    ▼
+--------------------------------------------------------------------------+
|  TẦNG 3: EDGE AI & INFERENCE PIPELINE (Trí Tuệ Nhân Tạo Tại Biên)        |
|  - Background Isolate Runner (TFLite MobileNetV3 VND & YOLOv8n Obstacle) |
|  - Google ML Kit Text Recognition Engine (Asynchronous On-Device Native) |
|  - 100% Offline: Không gửi ảnh ra ngoài, bảo mật và độ trễ phản hồi tức thì|
+--------------------------------------------------------------------------+
                                    │
                                    ▼
+--------------------------------------------------------------------------+
|  TẦNG 4: NGHIỆP VỤ & LỚP PHỦ GIAO DIỆN (Features & Overlay Presentation) |
|  - Đọc chữ | Nhận diện tiền (Vote 3/5) | Cảnh báo vật cản (3 cấp độ)      |
+--------------------------------------------------------------------------+
```

---

## 3. Các Quyết Định Kỹ Thuật Trọng Yếu (Key Architectural Decisions)

### 3.1. Chuyển Đổi Thuần On-Device (Loại Bỏ Cloud VLM)
* **Lý do loại bỏ Cloud API:**
  1. **Khả dụng mọi nơi (Offline-First):** Người khiếm thị thường xuyên di chuyển ngoài đường, chợ, tầng hầm, phương tiện công cộng nơi kết nối 3G/4G chập chờn hoặc không có. Ứng dụng phải hoạt động 100% không cần Internet.
  2. **Tối ưu độ trễ:** Các API đám mây (Gemini Flash, BLIP-2) có độ trễ truyền dữ liệu qua mạng từ 1.5 – 3 giây, trong khi người khiếm thị cần phản hồi tức thì (< 300ms) để phản ứng với môi trường.
  3. **Chi phí và bảo mật tuyệt đối:** Không tốn chi phí duy trì server hay trả phí API token. Hình ảnh cá nhân và môi trường xung quanh không bao giờ bị truyền ra khỏi thiết bị của người dùng.
* **3 Chế độ cốt lõi tinh gọn:**
  1. `reading`: Đọc văn bản in ấn (ML Kit On-device).
  2. `currency`: Nhận diện tiền giấy polymer VND (TFLite MobileNetV3).
  3. `obstacle`: Phát hiện và cảnh báo cự ly vật cản (TFLite YOLOv8n).

### 3.2. Kiến Trúc Single Camera Shell (Tránh Khởi Tạo Lại Camera)
* **Vấn đề:** Nếu mỗi tính năng là một màn hình riêng biệt, mỗi khi vuốt chuyển chế độ thì camera phải bị hủy rồi mở lại, làm máy bị khựng 1–2 giây và tốn tài nguyên.
* **Giải pháp:** Sử dụng duy nhất một `CameraViewfinder` làm nền ở `features/shell/`. Các tính năng chỉ cung cấp **Overlay** (lớp phủ) và **Controller**. Khi vuốt chuyển chế độ, hệ thống chỉ đổi luồng suy luận AI tương ứng mà **không bao giờ khởi động lại camera**.

### 3.3. Tối Ưu Xử Lý Độ Mờ và Độ Sáng Trên Kênh Y (Y-Plane Only)
* **Vấn đề:** Chuyển đổi khung hình camera (YUV420) sang RGB để tính phương sai Laplacian làm nghẽn CPU và giật khung hình.
* **Giải pháp:** Kênh Plane 0 (Y-Plane) bản chất là ảnh mức xám (Grayscale). `blur_detector.dart` và `lighting_detector.dart` tính toán trực tiếp trên mảng byte Plane Y, bỏ qua bước convert RGB, tiết kiệm hơn 85% chi phí tính toán.

### 3.4. Hàng Đợi Phản Hồi Âm Thanh Theo Độ Ưu Tiên (Priority Feedback Queue)
* **Quy tắc điều phối:**
  1. **Cảnh báo khẩn cấp (Urgent - Mức 1):** Phát hiện vật cản ở cự ly rất gần (< 1m). Ngay lập tức **ngắt lời (interrupt)** câu nói TTS hiện tại và kích hoạt chuỗi rung dồn dập + âm beep cảnh báo.
  2. **Kết quả nhận diện (Normal - Mức 2):** Đọc mệnh giá tiền hoặc đọc đoạn văn bản vừa chụp. Đợi hoàn tất nếu không có nguy cơ va chạm.
  3. **Hướng dẫn phụ trợ (Info - Mức 3):** Nhắc người dùng "Đưa máy sang trái", "Hình ảnh hơi mờ". Tự động hủy nếu người dùng đã chuyển sang thao tác khác.

### 3.5. Quản Lý Năng Lượng & Vòng Đời Ứng Dụng (Thermal & Battery Guard)
* **Tự động ngắt camera:** `camera_lifecycle_guard.dart` lắng nghe sự kiện màn hình tắt hoặc app vào background để tạm dừng luồng camera stream ngay lập tức, tránh nóng máy khi cất vào túi.
* **Suy luận thích ứng:** Kết hợp gia tốc kế (`motion_service.dart`) với `frame_throttler.dart`. Nếu thiết bị đứng yên trên bàn, chu kỳ suy luận tự động giãn từ 300ms lên 1000ms để tiết kiệm pin.
