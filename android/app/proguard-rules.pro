# ML Kit Text Recognition: plugin tham chiếu các gói ngôn ngữ (Trung/Nhật/Hàn/Devanagari)
# mà dự án không dùng (chỉ dùng Latin). Bỏ cảnh báo để R8 build được bản release.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit khởi tạo các ComponentRegistrar bằng reflection (tên lớp đọc từ AndroidManifest,
# gọi constructor không tham số). R8 đã xoá constructor -> "NoSuchMethodException <init> []"
# lúc khởi động và mọi lần processImage đều lỗi (đã xác nhận qua logcat trên S25 FE).
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }

# TensorFlow Lite: giữ lớp được gọi qua JNI/FFI.
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.gpu.**
