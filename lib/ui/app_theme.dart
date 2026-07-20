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
        return 'Azul financiero frio, profundo y corporativo.';
      case CcmxThemeStyle.bitcoinDark:
        return 'Carbon calido con naranja BTC dominante.';
      case CcmxThemeStyle.terminalGreen:
        return 'Terminal sobria: verde tecnico sin saturar.';
      case CcmxThemeStyle.highContrast:
        return 'Maxima legibilidad y bordes marcados.';
      case CcmxThemeStyle.seriousLight:
        return 'Claro financiero, sobrio y de alta lectura.';
    }
  }

  CcmxThemePalette paletteFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return switch (this) {
        CcmxThemeStyle.proDark => CcmxThemePalette.seriousLight.withAccent(
          const Color(0xFF5B4FCF),
          const Color(0xFFE7E3FF),
        ),
        CcmxThemeStyle.graphite => CcmxThemePalette.seriousLight.withAccent(
          const Color(0xFF334155),
          const Color(0xFFE2E8F0),
        ),
        CcmxThemeStyle.institutionalBlue =>
          CcmxThemePalette.seriousLight.withAccent(
            const Color(0xFF075985),
            const Color(0xFFE0F2FE),
          ),
        CcmxThemeStyle.bitcoinDark => CcmxThemePalette.seriousLight.withAccent(
          const Color(0xFFB45309),
          const Color(0xFFFFEDD5),
        ),
        CcmxThemeStyle.terminalGreen =>
          CcmxThemePalette.seriousLight.withAccent(
            const Color(0xFF047857),
            const Color(0xFFD1FAE5),
          ),
        CcmxThemeStyle.highContrast => CcmxThemePalette.seriousLight.withAccent(
          const Color(0xFF000000),
          const Color(0xFFE5E7EB),
        ),
        CcmxThemeStyle.seriousLight => CcmxThemePalette.seriousLight,
      };
    }

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
        return CcmxThemePalette.graphite;
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

  CcmxThemePalette withAccent(Color primary, Color primarySoft) =>
      CcmxThemePalette(
        background: background,
        surface: surface,
        surfaceAlt: surfaceAlt,
        primary: primary,
        primarySoft: primarySoft,
        border: border,
        positive: positive,
        negative: negative,
        warning: warning,
        textMain: textMain,
        textMuted: textMuted,
      );

  static const CcmxThemePalette proDark = CcmxThemePalette(
    background: Color(0xFF070910),
    surface: Color(0xFF10131D),
    surfaceAlt: Color(0xFF181D2A),
    primary: Color(0xFF8F7BFF),
    primarySoft: Color(0xFF211D40),
    border: Color(0xFF2A3040),
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
    background: Color(0xFF031322),
    surface: Color(0xFF071D33),
    surfaceAlt: Color(0xFF0C2E4F),
    primary: Color(0xFF38BDF8),
    primarySoft: Color(0xFF082F49),
    border: Color(0xFF155E75),
    positive: Color(0xFF2DD4BF),
    negative: Color(0xFFFB7185),
    warning: Color(0xFFF59E0B),
    textMain: Color(0xFFF8FAFC),
    textMuted: Color(0xFFB6C7DA),
  );

  static const CcmxThemePalette bitcoinDark = CcmxThemePalette(
    background: Color(0xFF130904),
    surface: Color(0xFF1F1005),
    surfaceAlt: Color(0xFF341A04),
    primary: Color(0xFFFFB020),
    primarySoft: Color(0xFF4A2604),
    border: Color(0xFF8A4B0A),
    positive: Color(0xFF84CC16),
    negative: Color(0xFFEF4444),
    warning: Color(0xFFFFC857),
    textMain: Color(0xFFFFF7ED),
    textMuted: Color(0xFFE7C99A),
  );

  static const CcmxThemePalette terminalGreen = CcmxThemePalette(
    background: Color(0xFF020805),
    surface: Color(0xFF06120B),
    surfaceAlt: Color(0xFF0B2114),
    primary: Color(0xFF00D26A),
    primarySoft: Color(0xFF052E1A),
    border: Color(0xFF128047),
    positive: Color(0xFF22C55E),
    negative: Color(0xFFFF6B6B),
    warning: Color(0xFFEAB308),
    textMain: Color(0xFFF1FFF7),
    textMuted: Color(0xFFB7F7C7),
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

  static const double cardRadius = 20;
  static const double inputRadius = 14;
  static const double cardBorderAlpha = 0.42;
  static const double navigationHeight = 72;
  static const double navigationLabelSize = 11.5;
  static const FontWeight navigationLabelWeight = FontWeight.w700;
}

@immutable
class CcmxVisualTokens {
  const CcmxVisualTokens({
    required this.backgroundSecondary,
    required this.cardBackground,
    required this.cardBorder,
    required this.cardRadius,
    required this.borderWidth,
    required this.shadow,
    required this.shadowOpacity,
    required this.surfacePrimary,
    required this.surfaceElevated,
    required this.selectedBackground,
    required this.selectedBorder,
    required this.sheetBackground,
    required this.menuBackground,
    required this.pressedOverlay,
    required this.divider,
    required this.gradientStart,
    required this.gradientEnd,
    required this.primaryAccent,
    required this.secondaryAccent,
    required this.tertiaryAccent,
    required this.glowColor,
    required this.chartPrimary,
    required this.chartSecondary,
    required this.chartMarker,
    required this.chartGrid,
    required this.chartFill,
    required this.chartTooltip,
  });

  final Color backgroundSecondary;
  final Color cardBackground;
  final Color cardBorder;
  final double cardRadius;
  final double borderWidth;
  final Color shadow;
  final double shadowOpacity;
  final Color surfacePrimary;
  final Color surfaceElevated;
  final Color selectedBackground;
  final Color selectedBorder;
  final Color sheetBackground;
  final Color menuBackground;
  final Color pressedOverlay;
  final Color divider;
  final Color gradientStart;
  final Color gradientEnd;
  final Color primaryAccent;
  final Color secondaryAccent;
  final Color tertiaryAccent;
  final Color glowColor;
  final Color chartPrimary;
  final Color chartSecondary;
  final Color chartMarker;
  final Color chartGrid;
  final Color chartFill;
  final Color chartTooltip;

  static CcmxVisualTokens of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return CcmxVisualTokens(
      backgroundSecondary: colors.surface.withValues(
        alpha: isDark ? 0.84 : 0.96,
      ),
      cardBackground: colors.surface,
      cardBorder: colors.outlineVariant.withValues(alpha: isDark ? 0.58 : 0.72),
      cardRadius: CcmxThemeTokens.cardRadius,
      borderWidth: 1,
      shadow: colors.shadow,
      shadowOpacity: isDark ? 0.22 : 0.10,
      surfacePrimary: colors.surface,
      surfaceElevated: colors.surfaceContainerHighest,
      selectedBackground: colors.primaryContainer.withValues(
        alpha: isDark ? 0.72 : 0.86,
      ),
      selectedBorder: colors.primary.withValues(alpha: isDark ? 0.70 : 0.82),
      sheetBackground: colors.surface,
      menuBackground: colors.surfaceContainerHighest,
      pressedOverlay: colors.primary.withValues(alpha: 0.12),
      divider: colors.outlineVariant.withValues(alpha: 0.42),
      gradientStart: colors.primary.withValues(alpha: isDark ? 0.22 : 0.14),
      gradientEnd: colors.surface.withValues(alpha: 0.0),
      primaryAccent: colors.primary,
      secondaryAccent: colors.secondary,
      tertiaryAccent: colors.tertiary,
      glowColor: colors.primary.withValues(alpha: isDark ? 0.28 : 0.18),
      chartPrimary: colors.primary,
      chartSecondary: colors.secondary,
      chartMarker: colors.tertiary,
      chartGrid: colors.outlineVariant.withValues(alpha: 0.36),
      chartFill: colors.primary.withValues(alpha: isDark ? 0.18 : 0.12),
      chartTooltip: colors.inverseSurface.withValues(
        alpha: isDark ? 0.90 : 0.96,
      ),
    );
  }
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
        height: CcmxThemeTokens.navigationHeight,
        backgroundColor: palette.surface,
        elevation: 0,
        indicatorColor: palette.primarySoft.withValues(alpha: 0.92),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.border.withValues(alpha: 0.48)),
        ),
        iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? palette.primary : palette.textMuted,
            size: selected ? 27 : 25,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((
          Set<WidgetState> states,
        ) {
          final bool selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? palette.primary : palette.textMuted,
            fontSize: CcmxThemeTokens.navigationLabelSize,
            fontWeight: selected
                ? FontWeight.w800
                : CcmxThemeTokens.navigationLabelWeight,
            height: 1.0,
            letterSpacing: -0.1,
          );
        }),
      ),
      dividerColor: palette.border,
      dividerTheme: DividerThemeData(
        color: palette.border.withValues(alpha: 0.42),
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedColor: palette.primarySoft,
        side: BorderSide(color: palette.border.withValues(alpha: 0.55)),
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
          borderSide: BorderSide(color: palette.border.withValues(alpha: 0.58)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CcmxThemeTokens.inputRadius),
          borderSide: BorderSide(color: palette.primary.withValues(alpha: 0.7)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? palette.primarySoft
                : palette.surfaceAlt,
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? palette.textMain
                : palette.textMuted,
          ),
          iconColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? palette.primary
                : palette.textMuted,
          ),
          side: WidgetStateProperty.resolveWith<BorderSide?>(
            (Set<WidgetState> states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? palette.primary.withValues(alpha: 0.70)
                  : palette.border.withValues(alpha: 0.58),
            ),
          ),
          overlayColor: WidgetStateProperty.all(
            palette.primary.withValues(alpha: 0.10),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? palette.primary
              : palette.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? palette.primarySoft
              : palette.surfaceAlt,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? palette.primary.withValues(alpha: 0.62)
              : palette.border.withValues(alpha: 0.72),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textMain,
          side: BorderSide(color: palette.border.withValues(alpha: 0.74)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
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
