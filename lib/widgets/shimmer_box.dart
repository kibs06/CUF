import 'package:flutter/material.dart';

import 'shimmer_group.dart';

class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    // Delegate to ShimmerGroup + SkeletonBox so the placeholder styling
    // lives in exactly one place. Same behavior, same colors as before.
    return ShimmerGroup(
      child: SkeletonBox(
        width: width,
        height: height,
        borderRadius: borderRadius,
      ),
    );
  }
}
