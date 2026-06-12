import 'package:flutter/material.dart';

/// Passive theme scaffold for a future migration. This file is intentionally
/// not imported by the app yet, so it must not change the current APK.
enum CcmxThemeMode { system, light, dark }

extension CcmxThemeModeDetails on CcmxThemeMode {
  String get label {
    switch (this) {
      case CcmxThemeMode.system:
        return 'Sistema';
      case CcmxThemeMode.light:
        return 'Claro';
      case CcmxThemeMode.dark:
        return 'Oscuro';
    }
  }

  ThemeMode get materialThemeMode {
    switch (this) {
      case CcmxThemeMode.system:
        return ThemeMode.system;
      case CcmxThemeMode.light:
        return ThemeMode.light;
      case CcmxThemeMode.dark:
        return ThemeMode.dark;
    }
  }
}

enum CcmxThemeStyle {
  proDark,
  graphite,
  institutionalBlue,
  bitcoinDark,
  terminalGreen,
  highContrast,
  seriousLight,
}

extension CcmxThemeStyleDetails on CcmxThemeStyle {
  String get label {
    switch (this) {
      case CcmxThemeStyle.proDark:
        return 'Pro oscuro';
      case CcmxThemeStyle.graphite:
        return 'Grafito';
      case CcmxThemeStyle.institutionalBlue:
        return 'Azul institucional';
      case CcmxThemeStyle.bitcoinDark:
        return 'Bitcoin dark';
      case CcmxThemeStyle.terminalGreen:
        return 'Verde terminal';
      case CcmxThemeStyle.highContrast:
        return 'Alto contraste';
      case CcmxThemeStyle.seriousLight:
        return 'Modo claro serio';
    }
  }

  String get description {
    switch (this) {
      case CcmxThemeStyle.proDark:
        return 'Negro profundo con acentos violeta premium.';
      case CcmxThemeStyle.graphite:
        return 'Neutros sobrios para lectura prolongada.';
      case CcmxThemeStyle.institutionalBlue:
        return 'Azules financieros con contraste limpio.';
      case CcmxThemeStyle.bitcoinDark:
        return 'Carbon y naranja BTC en paleta completa.';
      case CcmxThemeStyle.terminalGreen:
        return 'Oscuro tecnico con energia terminal.';
      case CcmxThemeStyle.highContrast:
        return 'Maxima legibilidad y bordes marcados.';
      case CcmxThemeStyle.seriousLight:
        return 'Claro financiero, sobrio y de alta lectura.';
    }
  }

  CcmxThemePalette paletteFor(Brightness brightness) {
    switch (this) {
      case CcmxThemeStyle.proDark:
        return CcmxThemePalette.proDark;
      case CcmxThemeStyle.graphite:
        return CcmxThemePalette.graphite;
      case CcmxThemeStyle.institutionalBlue:
        return CcmxThemePalette.institutionalBlue;
      case CcmxThemeStyle.bitcoinDark:
        return CcmxThemePalette.bitcoinDark;
      case CcmxThemeStyle.terminalGreen:
        return CcmxThemePalette.terminalGreen;
      case CcmxThemeStyle.highContrast:
        return CcmxThemePalette.highContrast;
      case CcmxThemeStyle.seriousLight:
        return brightness == Brightness.light
            ? CcmxThemePalette.seriousLight
            : CcmxThemePalette.graphite;
    }
  }
}

@immutable
class CcmxThemePalette {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color primary;
  final Color primarySoft;
  final Color border;
  final Color positive;
  final Color negative;
  final Color warning;
  final Color textMain;
  final Color textMuted;

  const CcmxThemePalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.primary,
    required this.primarySoft,
    required this.border,
    required this.positive,
    required this.negative,
    required this.warning,
    required this.textMain,
    required this.textMuted,
  });

  static const CcmxThemePalette proDark = CcmxThemePalette(
    background: Color(0xFF090B12),
    surface: Color(0xFF111520),
    surfaceAlt: Color(0xFF1B2233),
    primary: Color(0xFF9B8CFF),
    primarySoft: Color(0xFF28234F),
    border: Color(0xFF30384C),
    positive: Color(0xFF22C55E),
    negative: Color(0xFFEF4444),
    warning: Color(0xFFF59E0B),
    textMain: Color(0xFFF8FAFC),
    textMuted: Color(0xFF94A3B8),
  );

  static const CcmxThemePalette graphite = CcmxThemePalette(
    background: Color(0xFF111315),
    surface: Color(0xFF1B1F23),
    surfaceAlt: Color(0xFF272C31),
    primary: Color(0xFFCBD5E1),
    primarySoft: Color(0xFF334155),
    border: Color(0xFF3B424A),
    positive: Color(0xFF16A34A),
    negative: Color(0xFFDC2626),
    warning: Color(0xFFD97706),
    textMain: Color(0xFFF1F5F9),
    textMuted: Color(0xFFA1A1AA),
  );

  static const CcmxThemePalette institutionalBlue = CcmxThemePalette(
    background: Color(0xFF07111F),
    surface: Color(0xFF0E1B2E),
    surfaceAlt: Color(0xFF162A46),
    primary: Color(0xFF60A5FA),
    primarySoft: Color(0xFF12345C),
    border: Color(0xFF25496F),
    positive: Color(0xFF10B981),
    negative: Color(0xFFF43F5E),
    warning: Color(0xFFFBBF24),
    textMain: Color(0xFFF8FAFC),
    textMuted: Color(0xFF93A8C2),
  );

  static const CcmxThemePalette bitcoinDark = CcmxThemePalette(
    background: Color(0xFF0D0A06),
    surface: Color(0xFF17110A),
    surfaceAlt: Color(0xFF2A1B0D),
    primary: Color(0xFFF7931A),
    primarySoft: Color(0xFF3A220C),
    border: Color(0xFF5C3A16),
    positive: Color(0xFF22C55E),
    negative: Color(0xFFEF4444),
    warning: Color(0xFFF59E0B),
    textMain: Color(0xFFFFFBEB),
    textMuted: Color(0xFFD6B98A),
  );

  static const CcmxThemePalette terminalGreen = CcmxThemePalette(
    background: Color(0xFF020A06),
    surface: Color(0xFF07140D),
    surfaceAlt: Color(0xFF0E2618),
    primary: Color(0xFF39FF88),
    primarySoft: Color(0xFF073D20),
    border: Color(0xFF176B3A),
    positive: Color(0xFF22C55E),
    negative: Color(0xFFF87171),
    warning: Color(0xFFFACC15),
    textMain: Color(0xFFEFFFF5),
    textMuted: Color(0xFF88B99C),
  );

  static const CcmxThemePalette highContrast = CcmxThemePalette(
    background: Color(0xFF000000),
    surface: Color(0xFF0B0B0B),
    surfaceAlt: Color(0xFF1F1F1F),
    primary: Color(0xFFFFFFFF),
    primarySoft: Color(0xFF2C2C2C),
    border: Color(0xFFFFFFFF),
    positive: Color(0xFF00E676),
    negative: Color(0xFFFF1744),
    warning: Color(0xFFFFD600),
    textMain: Color(0xFFFFFFFF),
    textMuted: Color(0xFFE0E0E0),
  );

  static const CcmxThemePalette seriousLight = CcmxThemePalette(
    background: Color(0xFFF6F8FB),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE9EEF5),
    primary: Color(0xFF1F3A5F),
    primarySoft: Color(0xFFDCE7F7),
    border: Color(0xFFC8D2E0),
    positive: Color(0xFF047857),
    negative: Color(0xFFB91C1C),
    warning: Color(0xFFB45309),
    textMain: Color(0xFF0F172A),
    textMuted: Color(0xFF475569),
  );

  ColorScheme toColorScheme(Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: _ccmxBestOnColor(primary),
        primaryContainer: primarySoft,
        onPrimaryContainer: textMain,
        secondary: positive,
        onSecondary: _ccmxBestOnColor(positive),
        secondaryContainer: positive.withValues(alpha: 0.18),
        onSecondaryContainer: textMain,
        tertiary: warning,
        onTertiary: _ccmxBestOnColor(warning),
        tertiaryContainer: warning.withValues(alpha: 0.20),
        onTertiaryContainer: textMain,
        error: negative,
        onError: _ccmxBestOnColor(negative),
        errorContainer: negative.withValues(alpha: 0.18),
        onErrorContainer: textMain,
        surface: surface,
        onSurface: textMain,
        surfaceContainerHighest: surfaceAlt,
        onSurfaceVariant: textMuted,
        outline: border,
        outlineVariant: border.withValues(alpha: 0.55),
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: textMain,
        onInverseSurface: surface,
        inversePrimary: primarySoft,
      );
}

class CcmxThemeTokens {
  const CcmxThemeTokens._();

  static const double cardRadius = 24;
  static const double inputRadius = 16;
  static const double cardBorderAlpha = 0.55;
  static const FontWeight navigationLabelWeight = FontWeight.w700;
}

class CcmxAppTheme {
  const CcmxAppTheme._();

  static ThemeData build({
    required CcmxThemeStyle style,
    required Brightness brightness,
  }) {
    return fromPalette(
      palette: style.paletteFor(brightness),
      brightness: brightness,
    );
  }

  static ThemeData fromPalette({
    required CcmxThemePalette palette,
    required Brightness brightness,
  }) {
    final ColorScheme scheme = palette.toColorScheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      cardTheme: CardThemeData(
        elevation: 0,
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CcmxThemeTokens.cardRadius),
          side: BorderSide(
            color: palette.border.withValues(
              alpha: CcmxThemeTokens.cardBorderAlpha,
            ),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.textMain,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        indicatorColor: palette.primarySoft,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            color: palette.textMain,
            fontWeight: CcmxThemeTokens.navigationLabelWeight,
          ),
        ),
      ),
      dividerColor: palette.border,
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedColor: palette.primarySoft,
        side: BorderSide(color: palette.border),
        labelStyle: TextStyle(color: palette.textMain),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CcmxThemeTokens.inputRadius),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CcmxThemeTokens.inputRadius),
          borderSide: BorderSide(color: palette.border),
        ),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            bodyColor: palette.textMain,
            displayColor: palette.textMain,
          ),
    );
  }
}

Color _ccmxBestOnColor(Color color) {
  return color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
}
