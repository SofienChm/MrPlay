import 'package:flutter/material.dart';

class AppColors {
  // Primary gradient colors
  static const Color primaryStart = Color(0xFF1A237E);
  static const Color primaryEnd = Color(0xFF00C853);

  // Background
  static const Color backgroundDark = Color(0xFF121212);
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color surfaceLight = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textDark = Color(0xFF212121);

  // Card
  static const Color cardBackground = Color(0xFF2C2C2C);
  static const Color cardBorder = Color(0xFF3C3C3C);

  // Search bar
  static const Color searchBackground = Color(0x33FFFFFF);
  static const Color searchText = Color(0xFFFFFFFF);
  static const Color searchHint = Color(0x99FFFFFF);

  // Gradient for background
  static const List<Color> hubGradient = [
    Color(0xFF1A237E),
    Color(0xFF283593),
    Color(0xFF1565C0),
    Color(0xFF00897B),
    Color(0xFF00C853),
  ];

  // Platform card gradients
  static const Map<String, List<Color>> categoryGradients = {
    'video': [Color(0xFF1565C0), Color(0xFF0D47A1)],
    'music': [Color(0xFFD32F2F), Color(0xFFB71C1C)],
    'education': [Color(0xFF43A047), Color(0xFF2E7D32)],
    'social': [Color(0xFF7B1FA2), Color(0xFF4A148C)],
    'streaming': [Color(0xFFE65100), Color(0xFFBF360C)],
  };
}
