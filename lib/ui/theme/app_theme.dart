import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static const primary = Color(0xFF00A884);
  static const darkBackground = Color(0xFF070A0F);
  static const darkSurface = Color(0xFF111827);
  static const darkSurfaceAlt = Color(0xFF182233);
  static const textMuted = Color(0xFF6B7280);

  static ThemeData light() {
    return FlexThemeData.light(
      scheme: FlexScheme.tealM3,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 6,
      appBarStyle: FlexAppBarStyle.scaffoldBackground,
      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        tintedDisabledControls: true,
        blendOnLevel: 8,
        blendOnColors: false,
        useM2StyleDividerInM3: true,
        inputDecoratorRadius: 16,
        cardRadius: 12,
        navigationBarIndicatorRadius: 16,
        alignedDropdown: true,
      ),
      keyColors: const FlexKeyColors(useSecondary: true, useTertiary: true),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    ).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF7F9FA),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    );
  }

  static ThemeData dark() {
    return FlexThemeData.dark(
      scheme: FlexScheme.tealM3,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 14,
      appBarStyle: FlexAppBarStyle.scaffoldBackground,
      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        tintedDisabledControls: true,
        blendOnLevel: 18,
        inputDecoratorRadius: 16,
        cardRadius: 12,
        navigationBarIndicatorRadius: 16,
        alignedDropdown: true,
      ),
      keyColors: const FlexKeyColors(useSecondary: true, useTertiary: true),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    ).copyWith(scaffoldBackgroundColor: darkBackground);
  }
}
