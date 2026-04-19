import 'package:flutter/material.dart';

/// Small square app-icon avatar for use in AppBars and empty states.
///
/// Renders the bundled brand asset (`assets/branding/app_icon.png`) inside a
/// subtly tinted rounded square so it sits nicely next to text on both light
/// and dark themes.
class BrandLogo extends StatelessWidget {
  final double size;
  final EdgeInsetsGeometry? margin;
  final double padding;

  const BrandLogo({
    super.key,
    this.size = 28,
    this.margin,
    this.padding = 3,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Image.asset(
        'assets/branding/app_icon.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
