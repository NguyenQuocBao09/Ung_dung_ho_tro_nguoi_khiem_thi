package com.example.vision_assist

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Giữ màn hình sáng khi app đang hiển thị: nếu màn hình tự tắt, app chuyển sang
        // paused và camera stream bị dừng -> mất cảnh báo vật cản / nhận diện liên tục.
        // Cờ tự hết hiệu lực khi app vào nền, không cần quyền WAKE_LOCK.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
