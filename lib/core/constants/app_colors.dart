import 'package:flutter/material.dart';

class AppColors {
  // Quadrangular Church Brand Colors
  static const Color red = Color(0xFFC62828);
  static const Color redLight = Color(0xFFEF5350);
  static const Color redDark = Color(0xFF8E0000);

  static const Color yellow = Color(0xFFF9A825);
  static const Color yellowLight = Color(0xFFFFD95B);
  static const Color yellowDark = Color(0xFFC17900);

  static const Color blue = Color(0xFF1565C0);
  static const Color blueLight = Color(0xFF5E92F3);
  static const Color blueDark = Color(0xFF003C8F);

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  // Background
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF2C2C2C);

  // Text
  static const Color textPrimaryLight = Color(0xFF1A1A1A);
  static const Color textPrimaryDark = Color(0xFFF0F0F0);
  static const Color textSecondaryLight = Color(0xFF757575);
  static const Color textSecondaryDark = Color(0xFFAAAAAA);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blue, red],
  );

  static const LinearGradient warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [red, yellow],
  );

  static const LinearGradient coolGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blueDark, blue],
  );

  static const LinearGradient authGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [blueDark, blue, Color(0xFF8E0000)],
    stops: [0.0, 0.5, 1.0],
  );

  // Status colors
  static const Color success = Color(0xFF2E7D32);
  static const Color error = Color(0xFFC62828);
  static const Color warning = Color(0xFFF9A825);
  static const Color info = Color(0xFF1565C0);

  // Instruments colors
  static const Color vocalist = Color(0xFFC62828);
  static const Color guitar = Color(0xFF1565C0);
  static const Color bass = Color(0xFF4A148C);
  static const Color drums = Color(0xFF1B5E20);
  static const Color keyboard = Color(0xFFF9A825);
}
