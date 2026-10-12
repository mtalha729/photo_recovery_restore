import 'package:flutter/material.dart';

import '../foundations/app_colors.dart';
import '../foundations/app_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final seed = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    final scheme = isDark
        ? seed.copyWith(
            primary: const Color(0xFF9CADFF),
            onPrimary: const Color(0xFF102568),
            primaryContainer: AppColors.primaryDark,
            onPrimaryContainer: const Color(0xFFE8EBFF),
            secondary: const Color(0xFF62DDE7),
            onSecondary: const Color(0xFF003238),
            secondaryContainer: const Color(0xFF0B4C56),
            onSecondaryContainer: const Color(0xFFC7F6FA),
            surface: AppColors.darkSurface,
            onSurface: const Color(0xFFE8EDF8),
            surfaceContainer: const Color(0xFF151F30),
            surfaceContainerHigh: AppColors.darkSurfaceHigh,
            surfaceContainerHighest: const Color(0xFF263348),
            outline: const Color(0xFF94A3B8),
            outlineVariant: const Color(0xFF34435A),
            error: const Color(0xFFFFB4AB),
          )
        : seed.copyWith(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFE5EAFF),
            onPrimaryContainer: AppColors.primaryDark,
            secondary: AppColors.accent,
            onSecondary: const Color(0xFF003238),
            secondaryContainer: const Color(0xFFC7F6FA),
            onSecondaryContainer: const Color(0xFF003238),
            surface: AppColors.lightSurfaceHigh,
            onSurface: const Color(0xFF172033),
            surfaceContainer: const Color(0xFFF1F4F9),
            surfaceContainerHigh: const Color(0xFFE9EEF6),
            surfaceContainerHighest: const Color(0xFFE0E7F0),
            outline: const Color(0xFF72809A),
            outlineVariant: const Color(0xFFD3DAE6),
            error: AppColors.error,
          );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.45,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 15,
          height: 1.42,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.large),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .65)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, AppTouchTargets.minimum),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, AppTouchTargets.minimum),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        minWidth: 80,
        groupAlignment: -0.8,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppTouchTargets.minimum),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkSurfaceHigh : const Color(0xFF172033),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
    );
  }
}
