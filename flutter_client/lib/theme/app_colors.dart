import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds
  static const Color bgPrimary = Color(0xFF09090B); // Main app background
  static const Color bgSecondary = Color(
    0xFF18181B,
  ); // Panels (Sidebar, Topbar)
  static const Color bgTertiary = Color(0xFF27272A); // Cards, Inputs
  static const Color bgHover = Color(0xFF3F3F46); // Hover states

  // Accents
  static const Color accent = Color(0xFF06B6D4); // Cyan
  static const Color accentGlow = Color(0xFF22D3EE); // Lighter Cyan for glow
  static const Color selfHighlight = Color(0xFFF59E0B); // Amber for "Me"

  // Status
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color danger = Color(0xFFEF4444); // Red
  static const Color warning = Color(0xFFF59E0B); // Amber

  // Text
  static const Color textPrimary = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textTertiary = Color(0xFF71717A);

  // Borders
  static const Color border = Color(0xFF27272A);
  static const Color borderHighlight = Color(0xFF3F3F46);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient speakingGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF34D399)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
