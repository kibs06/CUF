import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// A category filter tab: the label, and **an underline** when it is the active
/// filter — the control the search results page and every shelf listing page
/// put above their grid.
///
/// **No box, no fill, no border on the label itself.** A row of bordered chips
/// beside the bordered sort control ([ProductSortChip]) reads as a toolbar of
/// buttons, when only one of them is a *state*. The underline says "you are
/// here" without competing with the sort control or the grid below it, and the
/// row stays legible as the number of chips changes — which it does, because
/// chips only exist for categories that actually hold something: on the search
/// page, the ones the query found; on a shelf, the ones the shelf holds.
///
/// The underline is **grown to the label's own width** ([_measureLabel], the
/// same technique the product hero's category tabs use) rather than to the
/// chip's padding, so it reads as part of the word. It animates from zero width
/// on select, which is why the unselected state is a zero-width bar rather than
/// a transparent placeholder.
class UnderlineCategoryChip extends StatelessWidget {
  const UnderlineCategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.indicatorKey,
  });

  final String label;

  /// Whether this chip is the filter in force.
  final bool selected;

  final VoidCallback onTap;

  /// Key for the underline itself, so a caller's test can read *this* chip's
  /// indicator without depending on traversal order (the convention the
  /// search page's chips already use). Null leaves the indicator unkeyed.
  final Key? indicatorKey;

  @override
  Widget build(BuildContext context) {
    // A Builder, so the ambient style is read from *below* the Scaffold (which
    // installs Material's `bodyMedium` as the DefaultTextStyle). Reading it from
    // the caller's context would find no DefaultTextStyle at all, and the
    // measured underline would come out narrower than the label it sits under —
    // `bodyMedium` carries `letterSpacing: 0.25`, ~2px on a 7-character label.
    return Builder(
      builder: (context) {
        // The label's effective style: DefaultTextStyle merged with the app's
        // body style, i.e. the same merge `Text` performs — so the underline is
        // measured in exactly the style the label is painted in.
        final labelStyle = DefaultTextStyle.of(context).style.merge(
          AppConstants.bodyStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? AppConstants.primary
                : AppConstants.secondary.withValues(alpha: 0.65),
          ),
        );
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: 4),
                // Grows from the centre on select. Width 0 (not a transparent
                // placeholder) so the transition animates.
                AnimatedContainer(
                  key: indicatorKey,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  height: 2,
                  width: selected ? _measureLabel(label, labelStyle) : 0,
                  decoration: BoxDecoration(
                    color: AppConstants.primary,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The rendered width of [label] in [style] — so the underline spans exactly
  /// the label. Same technique as the product hero's category tabs.
  static double _measureLabel(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}
