import 'package:flutter/material.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';

class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color ?? AppColors.accent,
        disabledBackgroundColor: AppColors.surfaceHigh,
        minimumSize: Size(expanded ? double.infinity : 0, 56),
      ),
      icon: Icon(icon ?? Icons.chevron_right, size: 22),
      label: Text(label),
    );
    return child;
  }
}
