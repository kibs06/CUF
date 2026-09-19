import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../screens/customer/product_detail_screen.dart';
import 'best_sellers_section.dart';
import 'horizontal_product_card.dart';

/// The shared body of a curated home rail: a header (title + optional muted
/// meta) over one horizontal strip of [HorizontalProductCard]s.
///
/// Extracted once the Men's / Women's / Kids' rails arrived and their bodies
/// were byte-for-byte the same as "In your size"'s — four copies of a header
/// row, a `ListView.separated` and a trailing gap is the kind of duplication
/// that drifts (one rail gaining a 14px gap, another a different card size)
/// without anything failing. Callers own the two things that actually differ:
/// which products to show, and what (if anything) to say beside the title.
///
/// **Self-spacing, and assumes a non-empty list.** It does NOT hide itself —
/// that belongs to the section widget above it, which is the only thing that
/// knows whether "nothing to show" means "not applicable" (no size on file, no
/// matching audience) or "empty catalog". Owning the trailing gap here is what
/// lets a section render nothing with no residual gap behind it.
class ProductRailSection extends StatelessWidget {
  const ProductRailSection({
    super.key,
    required this.title,
    required this.products,
    this.meta,
  });

  /// Section title in the serif headline face (e.g. "In your size", "Men's").
  final String title;

  /// Optional quiet line beside the title — the size that drove "In your
  /// size" is the current member. Plain muted text rather than a badge: a chip
  /// would put the section title and this detail in competition.
  final String? meta;

  /// The cards to show, in the order the provider ranked them. Expected
  /// non-empty — see the class doc.
  final List<Map<String, dynamic>> products;

  /// Strip height — the same 130x180 card rail the profile's "Buy Again" /
  /// "Recently Viewed" sections use.
  static const double railHeight = BestSellersSection.railHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
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
                      Text(
                        title,
                        style: AppConstants.headlineStyle(fontSize: 16),
                      ),
                      if (meta != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          meta!,
                          style: AppConstants.monoStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            // Resolved per paint: `secondary` follows the
                            // published brightness, so this ink is right in
                            // both modes without a theme lookup here.
                            color:
                                AppConstants.secondary.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final prod = products[index];
              return HorizontalProductCard(
                product: prod,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(product: prod),
                    ),
                  );
                },
              );
            },
          ),
        ),
        // Owned here, not by the caller: the section hides itself when it has
        // nothing to show, and a caller-side spacer would leave a gap where
        // the rail is not.
        const SizedBox(height: 16),
      ],
    );
  }
}
