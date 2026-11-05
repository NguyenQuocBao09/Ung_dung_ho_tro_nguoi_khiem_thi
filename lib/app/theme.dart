import 'package:flutter/material.dart';

/// Chủ đề tương phản cao (High Contrast Dark Theme) phục vụ người khiếm thị / thị lực kém
final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF0A0A0A),
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF80D8FF), // Xanh dương sáng tương phản cao
    onPrimary: Color(0xFF00364A),
    secondary: Color(0xFF90CAF9),
    onSecondary: Color(0xFF0D47A1),
    surface: Color(0xFF141414),
    onSurface: Colors.white,
    error: Color(0xFFFF5252),
    onError: Colors.black,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.black,
    foregroundColor: Colors.white,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      letterSpacing: 0.5,
    ),
    iconTheme: IconThemeData(
      color: Colors.white,
      size: 28,
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: const Color(0xFF161616),
    indicatorColor: const Color(0xFF004D73),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        );
      }
      return const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: Color(0xFFB0B0B0),
      );
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const IconThemeData(color: Color(0xFF80D8FF), size: 28);
      }
      return const IconThemeData(color: Color(0xFFB0B0B0), size: 26);
    }),
  ),
  // Đảm bảo mọi nút bấm đều có vùng chạm tối thiểu 48x48dp theo tiêu chuẩn WCAG
  materialTapTargetSize: MaterialTapTargetSize.padded,
  visualDensity: VisualDensity.standard,
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: Color(0xFFB0D7FF),
    foregroundColor: Color(0xFF003258),
    elevation: 4,
    sizeConstraints: BoxConstraints.tightFor(width: 64, height: 64),
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 18, color: Colors.white, height: 1.4),
    bodyMedium: TextStyle(fontSize: 16, color: Colors.white, height: 1.3),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
  ),
);
