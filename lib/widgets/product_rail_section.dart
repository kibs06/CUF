import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../screens/customer/product_detail_screen.dart';
import 'best_sellers_section.dart';
import 'horizontal_product_card.dart';
import 'product_section_header.dart';

/// The shared body of a curated home rail: a header (title + optional muted
/// meta) over one horizontal strip of [HorizontalProductCard]s.
///
/// Extracted once the Men's / Women's / Kids' rails arrived and their bodies
/// were byte-for-byte the same — copies of a header row, a
/// `ListView.separated` and a trailing gap is the kind of duplication that
/// drifts (one rail gaining a 14px gap, another a different card size) without
/// anything failing. Callers own the two things that actually differ: which
/// products to show, and what (if anything) to say beside the title.
///
/// "Based on your size" renders through `ProductGridSection` instead — one section
/// wanted the feed's own 2-column grid rather than a strip — so this is now the
/// rails' body (Men's / Women's / Kids') sharing [ProductSectionHeader] with
/// it rather than its header.
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

  /// Section title in the serif headline face (e.g. "Based on your size",
  /// "Men's").
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
        ProductSectionHeader(title: title, meta: meta),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.feedMargin,
            ),
            itemCount: products.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppConstants.productGridGutter),
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
