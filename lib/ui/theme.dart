import 'package:flutter/material.dart';

/// Brand colours, loosely inspired by Duolingo's palette.
/// Fonts bundled with the math renderer, used for symbols the system font
/// may lack (∠, →, ⇒, ≈ ...), on every device.
const symbolFontFallback = [
  'packages/flutter_math_fork/KaTeX_Main',
  'packages/flutter_math_fork/KaTeX_AMS',
];

class AppColors {
  static const green = Color(0xFF58CC02);
  static const greenDark = Color(0xFF46A302);
  static const red = Color(0xFFFF4B4B);
  static const redDark = Color(0xFFD33131);
  static const blue = Color(0xFF1CB0F6);
  static const blueDark = Color(0xFF1899D6);
  static const gold = Color(0xFFFFC800);
  static const orange = Color(0xFFFF9600);
  static const grey = Color(0xFFE5E5E5);
  static const greyDark = Color(0xFFAFAFAF);

  static Color darken(Color c, [double amount = 0.15]) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  static Color lighten(Color c, [double amount = 0.35]) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 0.97)).toColor();
  }
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.green,
    brightness: brightness,
    primary: dark ? const Color(0xFF7ED957) : AppColors.greenDark,
    surface: dark ? const Color(0xFF131F24) : Colors.white,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: dark ? const Color(0xFFF1F7FB) : const Color(0xFF3C3C3C),
      displayColor: dark ? const Color(0xFFF1F7FB) : const Color(0xFF3C3C3C),
      fontFamilyFallback: symbolFontFallback,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
    dividerTheme: DividerThemeData(color: borderColor(brightness)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: AppColors.blue.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(
        base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

Color borderColor(Brightness b) =>
    b == Brightness.dark ? const Color(0xFF37464F) : AppColors.grey;

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get border => borderColor(Theme.of(this).brightness);
}
