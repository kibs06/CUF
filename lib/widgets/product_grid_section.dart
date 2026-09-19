import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../constants/app_constants.dart';
import '../screens/customer/product_detail_screen.dart';
import '../utils/product_grid_ratio.dart';
import 'product_section_header.dart';
import 'sole_product_card.dart';

/// The shared body of a curated home section rendered as a grid: a heading over
/// the **same 2-column masonry grid the Artisan Catalog uses**, card for card
/// and gutter for gutter.
///
/// The heading is either the plain text one ([ProductSectionHeader]: title +
/// optional muted meta) or, for a section that wants a poster, a [tile] that
/// takes the grid's **first cell** — so "Based on your size" is a `FitCard` the
/// size of a product card, top-left of its own grid, rather than a line of text
/// above it. The two are mutually exclusive by assert: a section has one
/// heading, and it either says the section's name or shows it.
///
/// Sibling of `ProductRailSection` — that one is the horizontal strip, this one
/// is the feed's own grid. Which a section uses is a product decision about how
/// much room it deserves, not a difference in the cards: both end in
/// [SoleProductCard]'s tap-through to [ProductDetailScreen], and neither
/// scrolls on its own. The grid is `shrinkWrap` + `NeverScrollableScrollPhysics`
/// so it grows to its contents inside the feed's one scroll view, exactly like
/// the catalog — a nested scrollable here would trap the customer's drag.
///
/// **The card heights come from [productGridRatio], keyed off the product id.**
/// That is the catalog's rule, and taking it here is what makes the two grids
/// read as one design rather than "the grid and the staggered grid": a card is
/// the same height in both because it is the same product, not because of the
/// index it happens to sit at.
///
/// **Two of these grids in one scroll view is fine.** The home feed carries
/// this one *and* the catalog's, which a note in
/// `customer_home_screen.dart` used to forbid; it was never reproduced with the
/// box-level `MasonryGridView.count` these two use, and
/// `test/widgets/nested_masonry_scroll_test.dart` now pins the behaviour — the
/// feed still reaches its last card.
///
/// **Self-spacing, and assumes a non-empty list.** Like `ProductRailSection` it
/// does NOT hide itself — that belongs to the section widget above it, which is
/// the only thing that knows whether "nothing to show" means "not applicable"
/// (no size on file) or "empty catalog". Owning the trailing gap here is what
/// lets a section render nothing with no residual gap behind it.
class ProductGridSection extends StatelessWidget {
  const ProductGridSection({
    super.key,
    required this.products,
    this.title,
    this.meta,
    this.tile,
    this.trailing,
  }) : assert(
         (title != null) ^ (tile != null),
         'A section has exactly one heading: a title, or a tile',
       );

  /// Section title in the serif headline face — the heading when no [tile] is
  /// given. Null only when [tile] supplies the heading instead.
  final String? title;

  /// Optional quiet line beside the title — the size that drove "Based on your
  /// size" used to be the current member.
  final String? meta;

  /// A poster heading occupying the grid's first cell (top-left), in place of
  /// the [ProductSectionHeader]. Whatever is passed here must have a bounded
  /// height — [FitCard] itself does not, so it is wrapped in an `AspectRatio`
  /// by its caller. Null when the caller wants the plain text heading.
  final Widget? tile;

  /// A widget shown in the grid's **bottom-right corner**, beside the last
  /// product — the "See more" card that closes the grid. It is NOT a cell of
  /// the masonry flow (see [build] for why): the flow's last product comes out
  /// to join it, so the grid closes as one fixed row — product left, [trailing]
  /// right, one cell wide each. Must have a bounded height, like [tile].
  final Widget? trailing;

  /// The cards to show, in the order the provider ranked them. Expected
  /// non-empty — see the class doc.
  final List<Map<String, dynamic>> products;

  /// The catalog's column count. Stated once so a later grid section cannot
  /// quietly become a 3-column outlier on a page of 2-column feeds.
  static const int crossAxisCount = 2;

  @override
  Widget build(BuildContext context) {
    // The tile costs the product list nothing: one more cell in the same grid,
    // so the geometry, the gutter and the cards' widths are untouched.
    final leading = tile == null ? 0 : 1;

    // The masonry grid packs every cell into whichever column is currently
    // SHORTER, so neither a trailing card nor the product above it can be
    // steered to a column — on a shelf whose left column runs short, the card
    // landed under a right-column product and the left column stayed empty
    // below it. So the closing row is not packed at all: when [trailing] is
    // given, the LAST product comes out of the flow to join it, and the section
    // ends on one fixed row — product left, card right, one cell wide each,
    // seamed by the same gutter every grid row uses. The flow above keeps the
    // masonry look; the ending is the one row this design wants deterministic.
    //
    // The last product is only pulled out when there is a card to pair it with:
    // without [trailing] the flow packs every product, as the catalog does.
    final flowCount = trailing == null
        ? products.length + leading
        : products.length + leading - 1;
    final last = trailing == null ? null : products.last;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth =
            (constraints.maxWidth -
                2 * AppConstants.feedMargin -
                AppConstants.productGridGutter) /
            2;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A tiled section's heading IS the grid's first cell, so all it
            // gets up here is the same 4px of air the text heading opens with;
            // a titled section renders that heading as its own row instead.
            if (tile != null)
              const SizedBox(height: 4)
            else
              ProductSectionHeader(title: title!, meta: meta),
            MasonryGridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.feedMargin,
              ),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: AppConstants.productGridGutter,
              mainAxisSpacing: AppConstants.productGridGutter,
              itemCount: flowCount,
              itemBuilder: (context, index) {
                if (tile != null && index == 0) return tile!;
                final prod = products[index - leading];
                return SoleProductCard(
                  product: prod,
                  imageAspectRatio: productGridRatio(prod),
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
            if (trailing != null)
              Padding(
                // The grid above has no bottom padding, so the gutter here is
                // the same seam a grid row would have — the pair reads as the
                // flow's last row, not as something bolted under the grid.
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.feedMargin,
                  AppConstants.productGridGutter,
                  AppConstants.feedMargin,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The last product, in the LEFT column at full cell width.
                    SizedBox(
                      width: cellWidth,
                      child: SoleProductCard(
                        product: last!,
                        imageAspectRatio: productGridRatio(last),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductDetailScreen(product: last),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: AppConstants.productGridGutter),
                    // The card, in the RIGHT column — the mirror of the tile
                    // that opened the grid on the left.
                    SizedBox(width: cellWidth, child: trailing!),
                  ],
                ),
              ),
            // Owned here, not by the caller: the section hides itself when it
            // has nothing to show, and a caller-side spacer would leave a gap
            // where the grid is not.
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
