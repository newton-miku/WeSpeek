import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static const List<String> _fontFallbacks = [
    "Microsoft YaHei",
    "PingFang SC",
    "Heiti SC",
    "Segoe UI Emoji",
    "Segoe UI Symbol",
    "Noto Color Emoji",
    "sans-serif",
  ];

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgPrimary,

      fontFamilyFallback: _fontFallbacks,

      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accentGlow,
        surface: AppColors.bgSecondary,
        error: AppColors.danger,
      ),

      /*
      cardTheme: const CardTheme(
        color: AppColors.bgTertiary,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      */
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 20),

      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.bgSecondary,
        surfaceTintColor: Colors.transparent,
      ),

      textTheme: const TextTheme(
        bodyLarge: TextStyle(
          color: AppColors.textPrimary,
          fontFamilyFallback: _fontFallbacks,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textPrimary,
          fontFamilyFallback: _fontFallbacks,
        ),
        bodySmall: TextStyle(
          color: AppColors.textSecondary,
          fontFamilyFallback: _fontFallbacks,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
          fontFamilyFallback: _fontFallbacks,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontFamilyFallback: _fontFallbacks,
        ),
        titleSmall: TextStyle(
          color: AppColors.textPrimary,
          fontFamilyFallback: _fontFallbacks,
        ),
        labelLarge: TextStyle(
          color: AppColors.textPrimary,
          fontFamilyFallback: _fontFallbacks,
        ),
      ),
    );
  }
}
