import 'package:flutter/material.dart';

import 'ccmx_design_tokens.dart';

class CcmxPageScaffold extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  const CcmxPageScaffold({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
    this.scrollable = true,
    this.bottomNavigationBar,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final Widget body = Padding(padding: padding, child: child);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: scrollable
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[body],
              )
            : body,
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

class CcmxPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  const CcmxPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, color: colors.primary),
          const SizedBox(width: CcmxSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: CcmxSpacing.xs),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: CcmxSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}

class CcmxHeroPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String primaryValue;
  final String primaryLabel;
  final IconData icon;
  final List<Widget> metrics;

  const CcmxHeroPanel({
    super.key,
    required this.title,
    required this.primaryValue,
    required this.primaryLabel,
    required this.icon,
    this.subtitle,
    this.metrics = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(CcmxSpacing.lg),
      decoration: CcmxDecorations.hero(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CcmxPageHeader(title: title, subtitle: subtitle, icon: icon),
          const SizedBox(height: CcmxSpacing.lg),
          Text(primaryLabel, style: ccmxLabelStyle(context)),
          const SizedBox(height: CcmxSpacing.xs),
          Text(
            primaryValue,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
          ),
          if (metrics.isNotEmpty) ...<Widget>[
            const SizedBox(height: CcmxSpacing.lg),
            Wrap(
              spacing: CcmxSpacing.sm,
              runSpacing: CcmxSpacing.sm,
              children: metrics
                  .map(
                    (Widget metric) => DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(CcmxRadii.md),
                        color: colors.surface.withValues(alpha: 0.42),
                      ),
                      child: metric,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class CcmxMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;

  const CcmxMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(CcmxSpacing.md),
      decoration: CcmxDecorations.panel(context),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color ?? colors.primary),
          const SizedBox(width: CcmxSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: ccmxLabelStyle(context)),
                const SizedBox(height: CcmxSpacing.xs),
                Text(value, style: ccmxValueStyle(context, color: color)),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: CcmxSpacing.xs),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CcmxCryptoListCard extends StatelessWidget {
  final String symbol;
  final String title;
  final String value;
  final String subtitle;
  final Color? valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const CcmxCryptoListCard({
    super.key,
    required this.symbol,
    required this.title,
    required this.value,
    required this.subtitle,
    this.valueColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(CcmxRadii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(CcmxSpacing.md),
          decoration: CcmxDecorations.panel(context),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: colors.primary.withValues(alpha: 0.12),
                child: Text(
                  symbol,
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: CcmxSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: CcmxSpacing.xxs),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CcmxSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(value, style: ccmxValueStyle(context, color: valueColor)),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(height: CcmxSpacing.xs),
                    trailing!,
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CcmxActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool loading;
  final VoidCallback? onTap;

  const CcmxActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(CcmxRadii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(CcmxSpacing.md),
          decoration: CcmxDecorations.panel(context),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CcmxRadii.md),
                  color: colors.primary.withValues(alpha: 0.1),
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, color: colors.primary),
              ),
              const SizedBox(width: CcmxSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: CcmxSpacing.xxs),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                    if (badge != null) ...<Widget>[
                      const SizedBox(height: CcmxSpacing.xs),
                      _CcmxBadge(label: badge!),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: CcmxSpacing.sm),
              Icon(
                Icons.chevron_right,
                color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CcmxSegmentedControl<T extends Object> extends StatelessWidget {
  final T value;
  final List<CcmxSegment<T>> segments;
  final ValueChanged<T> onChanged;

  const CcmxSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CcmxSpacing.xs),
      decoration: CcmxDecorations.panel(context),
      child: SegmentedButton<T>(
        selected: <T>{value},
        showSelectedIcon: false,
        onSelectionChanged: (Set<T> selected) => onChanged(selected.first),
        segments: segments
            .map(
              (CcmxSegment<T> segment) => ButtonSegment<T>(
                value: segment.value,
                icon: segment.icon == null ? null : Icon(segment.icon),
                label: Text(segment.label),
              ),
            )
            .toList(),
      ),
    );
  }
}

class CcmxSegment<T extends Object> {
  final T value;
  final String label;
  final IconData? icon;

  const CcmxSegment({
    required this.value,
    required this.label,
    this.icon,
  });
}

class _CcmxBadge extends StatelessWidget {
  final String label;

  const _CcmxBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: colors.primary.withValues(alpha: 0.1),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}
