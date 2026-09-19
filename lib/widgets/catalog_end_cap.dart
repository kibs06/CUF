import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// The home feed's finish line: a quiet sign-off that marks where the catalog
/// actually ends.
///
/// Before this, the feed ended on the same product card repeated to the last
/// item and then blank space — no finish line at all, so it read as the grid
/// breaking rather than the shelf ending.
///
/// Deliberately only a signpost: it says the shelf is finished and names how
/// much the customer just got through. No CTA, no second product rail — the
/// feed has already given them everything it has.
///
/// Rendered only when the grid above is really the WHOLE catalog (no search, no
/// category filter) and only when that grid rendered products — a filtered or
/// empty feed is not "the whole shelf". See
/// `docs/AI/CUSTOMER_HOME_ARCHITECTURE.md`.
class CatalogEndCap extends StatelessWidget {
  /// Pairs in the catalog above this sign-off — the feed's own count.
  final int productCount;

  /// Distinct shops those pairs come from. `0` (or a catalog whose products
  /// carry no `store_id`) omits the figure rather than printing a wrong one.
  final int storeCount;

  const CatalogEndCap({
    super.key,
    required this.productCount,
    this.storeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final counts = catalogSignpostLine(
      productCount: productCount,
      storeCount: storeCount,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 0),
      child: Column(
        children: [
          Container(
            width: 30,
            height: 2,
            decoration: BoxDecoration(
              color: AppConstants.primary.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            "That's the whole shelf",
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(
              fontSize: 17,
              color: AppConstants.secondary.withValues(alpha: 0.75),
            ),
          ),
          if (counts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              counts,
              textAlign: TextAlign.center,
              style: AppConstants.monoStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.45),
              ).copyWith(letterSpacing: 0.6),
            ),
          ],
        ],
      ),
    );
  }
}

/// The finish-line count line: `'128 pairs · 6 workshops'`.
///
/// Either half can be absent and the line degrades instead of lying: no pairs
/// yields `''` (a signpost over an empty grid would be wrong), no shop count
/// yields the pairs alone. Singulars are handled — `'1 pair · 1 workshop'`.
String catalogSignpostLine({
  required int productCount,
  required int storeCount,
}) {
  if (productCount <= 0) return '';
  final pairs = '$productCount ${productCount == 1 ? 'pair' : 'pairs'}';
  if (storeCount <= 0) return pairs;
  return '$pairs · $storeCount ${storeCount == 1 ? 'workshop' : 'workshops'}';
}
