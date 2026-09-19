import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../constants/app_constants.dart';

/// Wraps an entire skeleton layout in a SINGLE shimmer animation, so one
/// wave sweeps across every placeholder at once instead of each box
/// pulsing independently.
///
/// Place static [SkeletonBox]es (or any painted child) inside.
class ShimmerGroup extends StatelessWidget {
  final Widget child;

  /// Nullable so the constructor can stay `const`: the defaults are
  /// brightness-aware surface tones now, so they are resolved in [build]
  /// instead of at the declaration.
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerGroup({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      // Skeleton tones track the surfaces they stand in for: the deeper band
      // tone as the base, the raised card tone as the sweep's highlight. On
      // dark both resolve to near-black greys, so the placeholder stays the
      // same family as the page behind it.
      baseColor: baseColor ?? AppConstants.creamDeep,
      highlightColor: highlightColor ?? AppConstants.sellerCardBg,
      child: child,
    );
  }
}

/// A static placeholder block (no animation of its own) meant to be placed
/// inside a [ShimmerGroup]. The ShaderMask from the group drives the
/// visible shimmer color, so the block itself just needs to paint an area.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
