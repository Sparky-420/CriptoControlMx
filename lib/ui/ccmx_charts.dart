import 'package:flutter/material.dart';

import 'ccmx_design_tokens.dart';

class CcmxChartPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<CcmxChartLegendItem> legend;
  final double minHeight;

  const CcmxChartPanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.legend = const <CcmxChartLegendItem>[],
    this.minHeight = 220,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(CcmxSpacing.lg),
      decoration: CcmxDecorations.panel(context, accent: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
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
          const SizedBox(height: CcmxSpacing.md),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: child,
          ),
          if (legend.isNotEmpty) ...<Widget>[
            const SizedBox(height: CcmxSpacing.md),
            Wrap(
              spacing: CcmxSpacing.md,
              runSpacing: CcmxSpacing.sm,
              children: legend,
            ),
          ],
        ],
      ),
    );
  }
}

class CcmxChartLegendItem extends StatelessWidget {
  final String label;
  final Color color;

  const CcmxChartLegendItem({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: CcmxSpacing.xs),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
