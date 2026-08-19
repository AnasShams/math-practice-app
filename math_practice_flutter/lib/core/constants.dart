
import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF2563EB); // Blue-600
  static const primaryDark = Color(0xFF1D4ED8); // Blue-700
  static const secondary = Color(0xFF10B981); // Emerald-500
  static const background = Color(0xFFF8FAFC); // Slate-50
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF1E293B); // Slate-800
  static const textSecondary = Color(0xFF64748B); // Slate-500
  static const border = Color(0xFFE2E8F0); // Slate-200
}

class AppTextStyles {
  static const heading1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  static const heading2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 16,
    color: AppColors.textPrimary,
  );
}
