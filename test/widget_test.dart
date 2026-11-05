import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/app/app.dart';
import 'package:vision_assist/core/constants/strings_vi.dart';

void main() {
  testWidgets('Màn hình chính khởi chạy hiển thị đúng tiêu đề chế độ mặc định',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: VisionAssistApp(),
      ),
    );

    // Kiểm tra có tiêu đề chế độ Đọc chữ
    expect(find.text(StringsVi.modeReading), findsOneWidget);
    // Kiểm tra có nút điều hướng Xem và Gần đây
    expect(find.text(StringsVi.navView), findsOneWidget);
    expect(find.text(StringsVi.navRecent), findsOneWidget);
    // Không còn nút máy ảnh trùng chức năng; chỉ một nút chính Tạm dừng/Tiếp tục.
    expect(find.byIcon(Icons.camera_alt), findsNothing);
    expect(find.byKey(const ValueKey('main_pause_button')), findsOneWidget);
  });

  testWidgets('Bấm vào nút 3 gạch ngang sẽ mở Drawer Vision Assist với 3 chế độ',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: VisionAssistApp(),
      ),
    );

    // Tìm và nhấn vào biểu tượng 3 gạch ngang (menu)
    final menuButton = find.byIcon(Icons.menu);
    expect(menuButton, findsOneWidget);
    await tester.tap(menuButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Kiểm tra Drawer hiển thị tiêu đề "Vision Assist"
    expect(find.text(StringsVi.drawerHeaderTitle), findsOneWidget);

    // Kiểm tra hiển thị đầy đủ 3 chế độ theo ảnh mẫu
    expect(find.text(StringsVi.drawerModeCurrency), findsOneWidget);
    expect(find.text(StringsVi.drawerModeReading), findsOneWidget);
    expect(find.text(StringsVi.drawerModeObstacle), findsOneWidget);

    // Bấm chọn "Nhận diện tiền mặt"
    await tester.tap(find.text(StringsVi.drawerModeCurrency));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Drawer đã đóng và tiêu đề trên AppBar chuyển thành "Nhận diện tiền"
    expect(find.text(StringsVi.modeCurrency), findsOneWidget);
  });
}
