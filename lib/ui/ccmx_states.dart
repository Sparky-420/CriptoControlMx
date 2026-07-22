import 'package:flutter/material.dart';

import 'ccmx_design_tokens.dart';

class CcmxEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const CcmxEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return _CcmxStateShell(
      icon: icon,
      title: title,
      subtitle: subtitle,
      action: action,
    );
  }
}

class CcmxLoadingState extends StatelessWidget {
  final String title;
  final String subtitle;

  const CcmxLoadingState({
    super.key,
    this.title = 'Cargando',
    this.subtitle = 'Preparando la lectura.',
  });

  @override
  Widget build(BuildContext context) {
    return _CcmxStateShell(
      icon: Icons.hourglass_empty_outlined,
      title: title,
      subtitle: subtitle,
      leading: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class CcmxErrorState extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;

  const CcmxErrorState({
    super.key,
    this.title = 'No se pudo completar',
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return _CcmxStateShell(
      icon: Icons.error_outline,
      title: title,
      subtitle: subtitle,
      action: action,
      tone: Theme.of(context).colorScheme.error,
    );
  }
}

class _CcmxStateShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final Widget? leading;
  final Color? tone;

  const _CcmxStateShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.leading,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = tone ?? colors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CcmxSpacing.lg),
      decoration: CcmxDecorations.panel(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          leading ??
              Icon(icon, color: accent, size: 30),
          const SizedBox(height: CcmxSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: CcmxSpacing.xs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: CcmxSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}
