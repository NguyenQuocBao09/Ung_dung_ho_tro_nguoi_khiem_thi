import 'package:flutter/material.dart';
import '../core/constants/strings_vi.dart';
import '../features/home/home_screen.dart';
import 'theme.dart';

class VisionAssistApp extends StatelessWidget {
  const VisionAssistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: StringsVi.appTitle,
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: const HomeScreen(),
    );
  }
}
