I. Lý do chọn đề tài.
Thực trạng xã hội: Người khiếm thị và người suy giảm thị lực gặp rất nhiều rào cản trong cuộc sống thường nhật, đặc biệt là việc tiếp cận thông tin dạng chữ in (hóa đơn, sách báo, biển báo) và tự chủ tài chính cá nhân (phân biệt các mệnh giá tiền mặt khi mua sắm).
Hạn chế của giải pháp hiện có: Các thiết bị phần cứng hỗ trợ chuyên dụng thường có giá thành đắt đỏ, cồng kềnh. Các ứng dụng quốc tế phổ biến (như Seeing AI, Envision AI) lại chưa hỗ trợ tối ưu cho các đặc thù tại Việt Nam, đặc biệt là nhận diện tiền polymer Việt Nam (VND) và giọng đọc tiếng Việt mượt mà.
Tính khả thi: Tận dụng năng lực xử lý mạnh mẽ của smartphone hiện đại cùng các công nghệ Trí tuệ nhân tạo (AI/Computer Vision) chạy trực tiếp trên thiết, đề tài hướng tới xây dựng một giải pháp phần mềm độc lập, chi phí bằng 0 cho người dùng cuối nhưng mang lại giá trị nhân văn và tính thực tiễn cao.
II. Mục tiêu đề tài.
Mục tiêu tổng quát: Xây dựng một ứng dụng di động chạy trên hệ điều hành Android đóng vai trò như một "trợ lý thị giác", chuyển đổi các thông tin hình ảnh từ camera thành âm thanh phản hồi cho người khiếm thị theo thời gian thực.
Cụ thể:
-	Xây dựng giao diện phi hình ảnh (Non-visual UI/UX) điều hướng hoàn toàn bằng cử chỉ chạm vuốt, rung phản hồi và tương thích chuẩn trợ năng (TalkBack/VoiceOver).
-	Triển khai chức năng trích xuất và đọc to văn bản tiếng Việt tức thì từ camera (OCR và Text-to-Speech).
-	Huấn luyện và nhúng mô hình học máy nhận diện chính xác các mệnh giá tiền polymer Việt Nam (từ 10.000 VNĐ đến 500.000 VNĐ) và các vật thể trong môi trường xung quanh chạy offline không cần Internet.
III. Đối tượng và phạm vi nghiên cứu.
Đối tượng nghiên cứu:
-	Các mô hình thị giác máy tính và học sâu phục vụ tác vụ nhận diện vật thể, phân loại hình ảnh và nhận dạng ký tự quang học (OCR).
-	Các phương pháp tối ưu hóa và nén mô hình để thực thi suy luận thời gian thực (Real-time Edge Inference) trên thiết bị di động.
-	Các nguyên tắc và tiêu chuẩn thiết kế trải nghiệm người dùng không thị giác (Non-visual Accessibility Guidelines như WCAG cho Mobile, TalkBack/VoiceOver integration).
Người dùng mục tiêu:
Người khiếm thị toàn phần hoặc người có thị lực suy giảm.
Phạm vi nghiên cứu và ứng dụng:
-	Phạm vi chức năng: Tập trung vào 3 tác vụ chính: (1) Đọc văn bản in ấn phổ biến (tài liệu, nhãn thuốc, bao bì, hóa đơn); (2) Nhận diện mệnh giá tiền mặt Việt Nam (tiền giấy và polymer lưu hành hợp pháp); (3) Cảnh báo vật cản/vật dụng cơ bản trong tầm nhìn gần.
-	Phạm vi nền tảng & phần cứng: Ứng dụng độc lập (standalone) trên hệ điều hành Android/iOS, sử dụng camera và cảm biến sẵn có của smartphone phổ thông mà không phụ thuộc vào thiết bị ngoại vi chuyên dụng (kính thông minh, gậy cảm biến).
-	Phạm vi điều kiện vận hành: Ưu tiên xử lý ngoại tuyến (offline on-device) cho các tác vụ di chuyển và nhận diện tiền tệ để đảm bảo tính sẵn sàng cao; môi trường hoạt động trong điều kiện ánh sáng tự nhiên hoặc có hỗ trợ đèn flash của điện thoại.
IV. Các tính năng cốt lõi.
Chức năng	Mô tả	Công nghệ sử dụng
Đọc văn bản (OCR & TTS)	Hướng camera vào trang sách, bao bì thuốc hoặc hóa đơn để máy đọc to nội dung bằng tiếng Việt chuẩn.	Google ML Kit Text Recognition / Tesseract + Text-to-Speech (Google TTS / FPT.AI API).
Cảnh báo vật cản	Phát hiện các vật cản nguy hiểm phía trước (ghế, bàn, cửa, bậc thang, phương tiện) và cảnh báo âm thanh/rung theo khoảng cách.	Mô hình phát hiện vật thể dạng nhẹ (YOLOv8-Nano / MobileNet-SSD) tối ưu qua TFLite / ONNX.
Nhận diện tiền mặt (VND)	Phân biệt chính xác mệnh giá tiền Việt Nam (từ 10.000đ đến 500.000đ) kể cả trong điều kiện nhăn hoặc thiếu sáng.	Mô hình phân loại ảnh tùy biến (Transfer Learning trên MobileNetV3 / EfficientNet-Lite).
Mô tả cảnh tổng quan	Chụp một bức ảnh và tóm tắt ngắn gọn bối cảnh (Ví dụ: "Trước mặt là phòng khách, có một người đang ngồi trên sofa").	Gọi API mô hình thị giác ngôn ngữ nhỏ (VLM như Gemini Flash / BLIP-2 qua Cloud API).
Giao diện tiếp cận (Accessibility UI)	Không dùng nút bấm nhỏ thông thường; dùng cử chỉ vuốt, chạm đôi, rung xúc giác (haptic feedback) và tích hợp TalkBack / VoiceOver.	Flutter / Native Accessibility APIs.

V. Kiến trúc hệ thống và luồng xử lý dữ liệu.
5.1 Kiến trúc hệ thống.
Tầng Giao diện(Presentation & Accessibility Layer): Tối ưu cho người khiếm thị, sử dụng TalkBack/VoiceOver, cử chỉ, giọng nói và rung để tương tác. 
Tầng Nghiệp vụ(Application Core & Logic Layer): Điều phối camera và các chức năng đọc văn bản, nhận diện tiền, phát hiện vật cản, đồng thời tối ưu chất lượng và tốc độ xử lý hình ảnh. 
Tầng Edge AI: Xử lý AI trực tiếp trên điện thoại, gồm 3 mô-đun: nhận diện tiền tệ, phát hiện vật cản và OCR tiếng Việt. 
Tầng Cloud(Cloud Extension Layer): Chức năng tùy chọn qua Internet, sử dụng AI trên đám mây để mô tả cảnh và trả lời các câu hỏi phức tạp khi Edge AI không xử lý được.
5.2 Luồng xử lý dữ liệu.
Thu nhận dữ liệu (Data Ingestion)  Tiền xử lý cục bộ (Preprocessing & Quality Check)  Suy luận thời gian thực (Inference Execution)  Hậu xử lý & Phản hồi đa giác quan (Multimodal Feedback).
5.3 Đặc tả dữ liệu.
Dữ liệu đầu vào:
-	Dữ liệu thị giác: Luồng khung hình video liên tục (Camera Stream) trích xuất từ camera sau của điện thoại thông minh, định dạng chuẩn YUV420 hoặc RGB, độ phân giải tối thiểu 720p.
-	Tín hiệu tương tác điều khiển: Các thao tác chạm vuốt trên màn hình cảm ứng (cử chỉ phi thị giác), thao tác rung lắc máy từ cảm biến gia tốc kế (Accelerometer), hoặc lệnh điều khiển qua trình đọc màn hình TalkBack/VoiceOver.
-	Dữ liệu cảm biến phụ trợ: Trạng thái chuyển động của thiết bị từ con quay hồi chuyển (Gyroscope) nhằm kích hoạt hoặc tạm dừng cơ chế lấy mẫu hình ảnh.
Dữ liệu đầu ra :
-	Tín hiệu âm thanh (Audio Output): Chuỗi âm thanh giọng nói tiếng Việt tự nhiên được tổng hợp qua engine Text-to-Speech (TTS), phát ra qua loa ngoài hoặc tai nghe của người dùng.
-	Phản hồi xúc giác (Haptic Output): Các kiểu rung vật lý với tần số và độ dài khác nhau (rung đơn ngắn báo hiệu hoàn tất thao tác, chuỗi rung dồn dập cảnh báo vật cản ở cự ly gần nguy hiểm).
VI. Lộ trình triển khai dự kiến.
Giai đoạn 1: Khảo sát & Chuẩn bị dữ liệu
-	Thu thập dữ liệu tiền VND và hình ảnh chướng ngại vật trong nhà.
-	Tiền xử lý, gán nhãn (Labeling) và tăng cường dữ liệu (Data Augmentation).
Giai đoạn 2: Huấn luyện & Tối ưu mô hình
-	Huấn luyện mô hình nhận diện tiền VND và vật thể bằng Transfer Learning.
-	Đánh giá Precision/Recall, lượng tử hóa mô hình (Quantization INT8/FP16) để chuyển đổi sang TFLite.
Giai đoạn 3: Phát triển ứng dụng di động
-	Xây dựng khung ứng dụng Flutter với kiến trúc hướng tiếp cận (Accessible UI).
-	Tích hợp camera stream trực tiếp và luồng suy luận mô hình (Inference Pipeline).
-	Tích hợp module Text-to-Speech và cơ chế phản hồi rung.
Giai đoạn 4: Thử nghiệm & Đánh giá
-	Kiểm thử độ trễ suy luận (FPS), mức tiêu thụ pin và tài nguyên RAM.
-	Phỏng vấn trải nghiệm thực tế với nhóm người dùng khiếm thị để tinh chỉnh cử chỉ thao tác.
-	Hoàn thiện báo cáo.
VII. Khó khăn và phương hướng giải quyết.
Tài nguyên phần cứng di động hạn chế: Chạy suy luận liên tục khiến máy nhanh nóng và hao pin.
Giải pháp: Áp dụng cơ chế suy luận ngắt quãng (chạy inference theo chu kỳ 300-500ms thay vì mọi khung hình 30fps), chỉ kích hoạt khi cảm biến gia tốc phát hiện người dùng đang di chuyển.
Chất lượng ảnh đầu vào của người khiếm thị: Ảnh chụp thường bị rung tay, lệch góc hoặc quá gần/xa.
Giải pháp: Tích hợp thuật toán kiểm tra độ nét (Laplacian variance) và phát giọng nói hướng dẫn căn chỉnh (ví dụ: "Đưa máy ra xa hơn", "Nghiêng máy sang phải").
VIII. Tài liệu tham khảo.
Computer Vision-Based Obstacle Detection Mobile System for Visually Impaired Individuals 
https://www.mdpi.com/2414-4088/9/5/48
Tài liệu nén và suy luận mô hình trên thiết bị (TensorFlow Lite):
Quy trình chuyển đổi mô hình (Converter), lượng tử hóa sau huấn luyện (Post-training quantization), và chạy suy luận tối ưu phần cứng (NNAPI / GPU Delegates) trên Android/iOS.
https://www.tensorflow.org/model_optimization/guide/quantization/post_training
Giải pháp nhận dạng ký tự quang học offline (Google ML Kit):
https://developers.google.com/ml-kit/vision/text-recognition/v2
Phát triển ứng dụng trợ năng trên nền tảng Flutter:
https://docs.flutter.dev/ui/accessibility-and-localization/accessibility
Thư viện suy luận YOLO thời gian thực (Ultralytics YOLOv8):
https://docs.ultralytics.com/modes/export
Web Content Accessibility Guidelines (WCAG 2.1 / 2.2) - W3C:
https://www.w3.org/TR/WCAG21/
Nguyên tắc trợ năng cho hệ điều hành di động:
https://developer.android.com/guide/topics/ui/accessibility
Dataset tham khảo:
COCO Dataset (Common Objects in Context): Tập dữ liệu chuẩn gồm hơn 80 lớp vật thể thường gặp (người, bàn, ghế, cầu thang, phương tiện), phục vụ việc tinh chỉnh (fine-tune) mô hình phát hiện chướng ngại vật trong nhà.
https://cocodataset.org/
Kaggle - Vietnamese Currency Dataset: Tập dữ liệu mẫu về các mệnh giá tiền polymer Việt Nam để tham khảo cấu trúc phân chia thư mục train/val/test và phương pháp tiền xử lý ảnh.
https://www.kaggle.com/datasets/phamtrananhtuan/vnd-data

