import 'package:flutter/material.dart';

/// 「随时听」Material 3 视觉主题。
/// 采用黑胶绯红（Vinyl Crimson）与暖调曜石黑 / 象牙宣纸白配色，
/// 兼顾浅色与深色模式、大字号缩放与最小 48dp 触控可达性。
abstract final class AppTheme {
  static const Color brandCrimson = Color(0xFFC82829);
  static const Color brandCrimsonDark = Color(0xFFFF6B6B);
  static const Color trialAmberLight = Color(0xFFB45309);
  static const Color trialAmberDark = Color(0xFFFBBF24);
  static const Color trialSurfaceLight = Color(0xFFFEF3C7);
  static const Color trialSurfaceDark = Color(0xFF3F2B0B);

  static ThemeData light() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: brandCrimson,
      brightness: Brightness.light,
      primary: const Color(0xFFC42424),
      secondary: const Color(0xFF7B3F3F),
      tertiary: const Color(0xFF9A5B13),
      surface: const Color(0xFFFAF7F5),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF6F0EC),
      surfaceContainer: const Color(0xFFF0E8E3),
      surfaceContainerHigh: const Color(0xFFE9DFD8),
      surfaceContainerHighest: const Color(0xFFE1D5CD),
    );

    return _buildTheme(baseScheme, Brightness.light);
  }

  static ThemeData dark() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: brandCrimson,
      brightness: Brightness.dark,
      primary: const Color(0xFFFF6666),
      onPrimary: const Color(0xFF470005),
      primaryContainer: const Color(0xFF7F1619),
      onPrimaryContainer: const Color(0xFFFFDAD7),
      secondary: const Color(0xFFE6BDBB),
      tertiary: const Color(0xFFF5B851),
      surface: const Color(0xFF121011),
      surfaceContainerLowest: const Color(0xFF0C0A0B),
      surfaceContainerLow: const Color(0xFF1A1618),
      surfaceContainer: const Color(0xFF211C1E),
      surfaceContainerHigh: const Color(0xFF2B2427),
      surfaceContainerHighest: const Color(0xFF362E31),
    );

    return _buildTheme(baseScheme, Brightness.dark);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer,
        useIndicator: true,
        labelType: NavigationRailLabelType.all,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: colorScheme.outlineVariant),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.16),
        trackHeight: 4,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHighest
            : const Color(0xFF241E20),
        contentTextStyle: TextStyle(
          color: isDark ? colorScheme.onSurface : Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
