import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF3157F5);
  static const primaryDark = Color(0xFF1737C7);
  static const accent = Color(0xFF23C7D9);
  static const protection = Color(0xFF14B8A6);

  static const lightBackground = Color(0xFFF7F9FC);
  static const lightSurfaceHigh = Color(0xFFFFFFFF);
  static const darkBackground = Color(0xFF080D1A);
  static const darkSurface = Color(0xFF111827);
  static const darkSurfaceHigh = Color(0xFF1B2638);

  static const verified = Color(0xFF12B76A);
  static const protected = protection;
  static const possibleCopy = Color(0xFF3157F5);
  static const warning = Color(0xFFF79009);
  static const corrupted = Color(0xFFF04438);
  static const unavailable = Color(0xFF667085);
  static const error = corrupted;
  static const currentMedia = Color(0xFF475467);
}
