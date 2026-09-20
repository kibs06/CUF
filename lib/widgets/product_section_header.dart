import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// The shared header of a curated home section: a title in the serif headline
/// face with an optional quiet line beside it (e.g. "Based on your size ·
/// EU 42").
///
/// Extracted when "Based on your size" stopped being a rail: [ProductRailSection]
/// (the horizontal strips) and [ProductGridSection] (The Workshop Collection's
/// 2-column masonry) are two different bodies over the same header, and a
/// second copy of a thirty-line row is how one of them ends up at 15px while
/// the other stays 16.
class ProductSectionHeader extends StatelessWidget {
  const ProductSectionHeader({super.key, required this.title, this.meta});

  /// Section title in the serif headline face (e.g. "Based on your size",
  /// "Men's").
  final String title;

  /// Optional quiet line beside the title — the size that drove "In your
  /// size" is the current member. Plain muted text rather than a badge: a chip
  /// would put the section title and this detail in competition.
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.feedMargin,
        4,
        AppConstants.feedMargin,
        10,
      ),
      child: Row(
        children: [
          // Expanded + FittedBox(scaleDown) so a narrow screen or a large
          // text scale shrinks the label group instead of overflowing the
          // row (the same guarantee the Best Sellers header makes).
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppConstants.headlineStyle(fontSize: 16)),
                  if (meta != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      meta!,
                      style: AppConstants.monoStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        // Resolved per paint: `secondary` follows the
                        // published brightness, so this ink is right in both
                        // modes without a theme lookup here.
                        color: AppConstants.secondary.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
