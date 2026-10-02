import 'package:flutter/material.dart';

/// الهوية البصرية للموسوعة: الوضع النهاري يحتفظ بالمظهر الداكن الحالي،
/// بينما الوضع الليلي يستخدم الأسود الحقيقي.
class AppColors {
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkSurfaceAlt = Color(0xFF1E1C1A);
  static const Color antiqueBronze = Color(0xFFB08D57);
  static const Color softGold = Color(0xFFD4AF6A);
  static const Color darkTextPrimary = Color(0xFFEDE6DA);
  static const Color darkTextSecondary = Color(0xFFB7AFA2);
  static const Color darkDivider = Color(0xFF3A3631);
  static const Color lightBackground = Color(0xFF121212);
  static const Color lightSurface = Color(0xFF1E1C1A);
  static const Color lightSurfaceAlt = Color(0xFF262320);
  static const Color bronzeOnLight = Color(0xFFB08D57);
  static const Color lightTextPrimary = Color(0xFFEDE6DA);
  static const Color lightTextSecondary = Color(0xFFB7AFA2);
  static const Color lightDivider = Color(0xFF3A3631);
  static const Color success = Color(0xFF5A7D5A);
  static const Color danger = Color(0xFFA84C4C);
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark, colorScheme: ColorScheme.fromSeed(seedColor: AppColors.antiqueBronze, brightness: Brightness.dark, primary: AppColors.antiqueBronze, secondary: AppColors.softGold, surface: AppColors.darkSurface), scaffoldBackgroundColor: AppColors.darkBackground);
    return base.copyWith(
      appBarTheme: const AppBarTheme(backgroundColor: AppColors.darkBackground, foregroundColor: AppColors.softGold, elevation: 0, centerTitle: true, titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.softGold, letterSpacing: 0.2), iconTheme: IconThemeData(color: AppColors.antiqueBronze)),
      cardTheme: CardThemeData(color: AppColors.darkSurface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.darkDivider, width: 1)), margin: EdgeInsets.zero),
      dividerTheme: const DividerThemeData(color: AppColors.darkDivider, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: AppColors.darkSurfaceAlt, hintStyle: const TextStyle(color: AppColors.darkTextSecondary), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: AppColors.darkDivider)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: AppColors.darkDivider)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: AppColors.softGold, width: 1.4))),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.antiqueBronze, linearTrackColor: AppColors.darkSurfaceAlt),
      textTheme: base.textTheme.apply(bodyColor: AppColors.darkTextPrimary, displayColor: AppColors.darkTextPrimary),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: AppColors.antiqueBronze, foregroundColor: Colors.black),
      switchTheme: SwitchThemeData(thumbColor: WidgetStateProperty.all(AppColors.softGold), trackColor: WidgetStateProperty.all(AppColors.darkSurfaceAlt)),
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.darkSurface, titleTextStyle: TextStyle(color: AppColors.softGold, fontWeight: FontWeight.w700, fontSize: 17), contentTextStyle: TextStyle(color: AppColors.darkTextPrimary, fontSize: 14.5)),
    );
  }

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark, colorScheme: ColorScheme.fromSeed(seedColor: AppColors.bronzeOnLight, brightness: Brightness.dark, primary: AppColors.bronzeOnLight, secondary: AppColors.softGold, surface: AppColors.lightSurface), scaffoldBackgroundColor: AppColors.lightBackground);
    return base.copyWith(
      appBarTheme: const AppBarTheme(backgroundColor: AppColors.lightBackground, foregroundColor: AppColors.softGold, elevation: 0, centerTitle: true, titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.softGold, letterSpacing: 0.2), iconTheme: IconThemeData(color: AppColors.bronzeOnLight)),
      cardTheme: CardThemeData(color: AppColors.lightSurface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.lightDivider, width: 1)), margin: EdgeInsets.zero),
      dividerTheme: const DividerThemeData(color: AppColors.lightDivider, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: AppColors.lightSurfaceAlt, hintStyle: const TextStyle(color: AppColors.lightTextSecondary), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: AppColors.lightDivider)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: AppColors.lightDivider)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: AppColors.softGold, width: 1.4))),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.bronzeOnLight, linearTrackColor: AppColors.lightSurfaceAlt),
      textTheme: base.textTheme.apply(bodyColor: AppColors.lightTextPrimary, displayColor: AppColors.lightTextPrimary),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: AppColors.bronzeOnLight, foregroundColor: Colors.black),
      switchTheme: SwitchThemeData(thumbColor: WidgetStateProperty.all(AppColors.softGold), trackColor: WidgetStateProperty.all(AppColors.lightSurfaceAlt)),
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.lightSurface, titleTextStyle: TextStyle(color: AppColors.softGold, fontWeight: FontWeight.w700, fontSize: 17), contentTextStyle: TextStyle(color: AppColors.lightTextPrimary, fontSize: 14.5)),
    );
  }
}

extension AppColorsContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get textPrimary => isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get textSecondary => isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  Color get accent => isDark ? AppColors.softGold : AppColors.bronzeOnLight;
  Color get surface => isDark ? AppColors.darkSurface : AppColors.lightSurface;
  Color get surfaceAlt => isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
  Color get divider => isDark ? AppColors.darkDivider : AppColors.lightDivider;
}
