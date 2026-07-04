import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SoleCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? shadow;
  final Border? border;
  final double? width;
  final double? height;

  const SoleCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.borderRadius,
    this.shadow,
    this.border,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin ?? EdgeInsets.zero,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? AppConstants.surfaceLight,
        borderRadius: borderRadius ?? AppConstants.cardRadius,
        boxShadow: shadow ?? AppConstants.warmShadow,
        border: border ?? Border.all(color: AppConstants.primary.withOpacity(0.08), width: 1),
      ),
      child: child,
    );
  }
}
