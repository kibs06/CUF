import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Wraps an entire skeleton layout in a SINGLE shimmer animation, so one
/// wave sweeps across every placeholder at once instead of each box
/// pulsing independently.
///
/// Place static [SkeletonBox]es (or any painted child) inside.
class ShimmerGroup extends StatelessWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  const ShimmerGroup({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFFEEEEEE), // Colors.grey.shade200
    this.highlightColor = const Color(0xFFF5F5F5), // Colors.grey.shade100
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
