import 'package:flutter/material.dart';

import 'ccmx_design_tokens.dart';

class CcmxFormSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const CcmxFormSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(CcmxSpacing.lg),
      decoration: CcmxDecorations.panel(context),
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
          ...children.expand(
            (Widget child) => <Widget>[
              child,
              const SizedBox(height: CcmxSpacing.md),
            ],
          ),
        ],
      ),
    );
  }
}

class CcmxTextFieldShell extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? helperText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;

  const CcmxTextFieldShell({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helperText,
    this.keyboardType,
    this.obscureText = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CcmxRadii.md),
        ),
      ),
    );
  }
}

class CcmxPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onPressed;

  const CcmxPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.loading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon),
                const SizedBox(width: CcmxSpacing.sm),
              ],
              Text(label),
            ],
          );

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CcmxSpacing.md),
          child: content,
        ),
      ),
    );
  }
}
