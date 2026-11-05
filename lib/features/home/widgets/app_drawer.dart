import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings_vi.dart';
import '../../../core/feedback/tts_service.dart';
import '../../../core/mode/app_mode.dart';
import '../../../core/mode/mode_controller.dart';

/// Ngăn kéo điều hướng (Navigation Drawer) thiết kế theo mẫu Lookout
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(appModeProvider);
    final isTalkBackOn = MediaQuery.accessibleNavigationOf(context);

    return Drawer(
      backgroundColor: const Color(0xFF1B1C1E),
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. PHẦN ĐẦU (Header): Biểu tượng + Tiêu đề "Vision Assist"
            Semantics(
              header: true,
              label: StringsVi.drawerHeaderTitle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF5B69D6), // Màu xanh tím đặc trưng
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.visibility,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Co chữ lại nếu không đủ chỗ (tên dài / cỡ chữ hệ thống lớn).
                    const Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          StringsVi.drawerHeaderTitle,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // 2. DANH SÁCH CHẾ ĐỘ HOẠT ĐỘNG
            Expanded(
              child: Semantics(
                label: StringsVi.drawerMenuA11yLabel,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    // Mục 1: Nhận diện tiền mặt
                    _buildDrawerItem(
                      context: context,
                      ref: ref,
                      icon: Icons.payments_outlined,
                      title: StringsVi.drawerModeCurrency,
                      mode: AppMode.currency,
                      isSelected: currentMode == AppMode.currency,
                      isTalkBackOn: isTalkBackOn,
                    ),

                    const SizedBox(height: 6),

                    // Mục 2: Đọc văn bản
                    _buildDrawerItem(
                      context: context,
                      ref: ref,
                      icon: Icons.document_scanner_outlined,
                      title: StringsVi.drawerModeReading,
                      mode: AppMode.reading,
                      isSelected: currentMode == AppMode.reading,
                      isTalkBackOn: isTalkBackOn,
                    ),

                    const SizedBox(height: 6),

                    // Mục 3: Cảnh báo vật cản
                    _buildDrawerItem(
                      context: context,
                      ref: ref,
                      icon: Icons.warning_amber_rounded,
                      title: StringsVi.drawerModeObstacle,
                      mode: AppMode.obstacle,
                      isSelected: currentMode == AppMode.obstacle,
                      isTalkBackOn: isTalkBackOn,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required BuildContext context,
    required WidgetRef ref,
    required IconData icon,
    required String title,
    required AppMode mode,
    required bool isSelected,
    required bool isTalkBackOn,
  }) {
    final semanticsLabel = isSelected
        ? '$title, ${StringsVi.modeSelectedNotice}'
        : title;

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticsLabel,
      child: Material(
        color: isSelected ? const Color(0xFF004D74) : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () {
            // Đóng Drawer
            Navigator.of(context).pop();

            // Nếu đổi sang chế độ mới thì cập nhật
            if (!isSelected) {
              ref.read(appModeProvider.notifier).setMode(mode);

              // Thông báo cho người dùng
              if (isTalkBackOn) {
                SemanticsService.sendAnnouncement(
                  View.of(context),
                  mode.title,
                  TextDirection.ltr,
                );
              } else {
                ref.read(ttsServiceProvider).speak(mode.title);
              }
            }
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56), // Chuẩn touch target >= 48dp
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 26,
                    color: isSelected ? Colors.white : const Color(0xFFC4C7C5),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? Colors.white : const Color(0xFFE2E2E6),
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

