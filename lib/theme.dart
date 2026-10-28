import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CampusPalette extends ThemeExtension<CampusPalette> {
  static const header = Color(0xFF2E303B);
  const CampusPalette({
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.primary,
    required this.selected,
    required this.warm,
    required this.violet,
  });
  final Color background,
      sidebar,
      surface,
      ink,
      muted,
      line,
      primary,
      selected,
      warm,
      violet;
  static const light = CampusPalette(
    background: Color(0xFFF3F4F8),
    sidebar: Colors.white,
    surface: Colors.white,
    ink: Color(0xFF30333A),
    muted: Color(0xFF62656D),
    line: Color(0xFFE5E7ED),
    primary: Color(0xFF4C62D5),
    selected: Color(0xFFF0F1FA),
    warm: Color(0xFF9B6A19),
    violet: Color(0xFF7155A5),
  );
  static const dark = CampusPalette(
    background: Color(0xFF1E2028),
    sidebar: Color(0xFF252730),
    surface: Color(0xFF292C36),
    ink: Color(0xFFE9EAF0),
    muted: Color(0xFFB2B5C4),
    line: Color(0xFF424654),
    primary: Color(0xFFB0BDFE),
    selected: Color(0xFF363C5B),
    warm: Color(0xFFF0BF79),
    violet: Color(0xFFC6B3F0),
  );
  static CampusPalette of(BuildContext context) =>
      Theme.of(context).extension<CampusPalette>()!;
  List<Color> get courseColors => [
    primary,
    violet,
    warm,
    background.computeLuminance() < .1
        ? const Color(0xFF83D6C7)
        : const Color(0xFF287B70),
  ];
  Color courseText(Color color) =>
      background.computeLuminance() < .1 ? color : Color.lerp(color, ink, .15)!;
  @override
  CampusPalette copyWith() => this;
  @override
  CampusPalette lerp(CampusPalette? other, double t) =>
      other == null || t < .5 ? this : other;
}

ThemeData campusTheme(Brightness brightness) {
  final p = brightness == Brightness.dark
      ? CampusPalette.dark
      : CampusPalette.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.primary,
        brightness: brightness,
      ).copyWith(
        primary: p.primary,
        surface: p.surface,
        onSurface: p.ink,
        onPrimary: brightness == Brightness.dark
            ? const Color(0xFF102A26)
            : Colors.white,
        outline: p.line,
        surfaceContainerHighest: p.selected,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.background,
    fontFamily: defaultTargetPlatform == TargetPlatform.windows
        ? 'Segoe UI'
        : '.AppleSystemUIFont',
    fontFamilyFallback: const [
      'PingFang SC',
      'Microsoft YaHei UI',
      'Helvetica Neue',
    ],
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: p.ink,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        height: 1.5,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.7, color: p.ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: p.ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: p.muted),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: p.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(44, 44),
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: p.muted,
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
  );
}
