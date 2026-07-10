import 'package:flutter/material.dart';

class CcmxColors {
  static const Color graphite = Color(0xFF090B12);
  static const Color graphiteElevated = Color(0xFF10131D);
  static const Color graphiteSoft = Color(0xFF171B27);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color violetSoft = Color(0xFF6D5DF7);
  static const Color cyan = Color(0xFF38BDF8);
  static const Color positive = Color(0xFF22C55E);
  static const Color negative = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
}

class CcmxSpacing {
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

class CcmxRadii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 22;
}

class CcmxDurations {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
}

class CcmxBreakpoints {
  static const double compact = 420;
  static const double tablet = 720;
  static const double desktop = 1080;
}

class CcmxDecorations {
  static BoxDecoration panel(BuildContext context, {bool accent = false}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(CcmxRadii.lg),
      color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
      border: Border.all(
        color: accent
            ? colors.primary.withValues(alpha: 0.22)
            : colors.outlineVariant.withValues(alpha: 0.45),
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  static BoxDecoration hero(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(CcmxRadii.xl),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          colors.primaryContainer.withValues(alpha: 0.42),
          colors.surfaceContainerHighest.withValues(alpha: 0.78),
        ],
      ),
      border: Border.all(color: colors.primary.withValues(alpha: 0.14)),
    );
  }
}

TextStyle? ccmxLabelStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        );

TextStyle? ccmxValueStyle(BuildContext context, {Color? color}) =>
    Theme.of(context).textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          height: 1.08,
        );
