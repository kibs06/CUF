import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../screens/customer/product_detail_screen.dart';
import '../utils/product_grid_ratio.dart';
import 'product_section_header.dart';
import 'sole_product_card.dart';
import 'two_column_masonry.dart';

/// The shared body of a curated home section rendered as a grid: a heading over
/// the **same 2-column masonry grid The Workshop Collection uses**, card for card
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
/// scrolls on its own.
///
/// **The card heights come from [productGridRatio], keyed off the product id.**
/// That is the catalog's rule, and taking it here is what makes the two grids
/// read as one design rather than "the grid and the staggered grid": a card is
/// the same height in both because it is the same product, not because of the
/// index it happens to sit at.
///
/// **The grid closes on the shelf's door, in its own columns.** A [trailing]
/// card — the `SeeMoreCard` — is the grid's last cell, and the last product
/// leaves the flow to stand beside it: anchor left, door right, the mirror of
/// the poster that opened the grid. Both are placed by [TwoColumnMasonry]
/// against their **own** column rather than pinned as one row under the grid, so
/// the shorter column no longer shows its leftover height as a hole above them
/// (the bug this pair replaced), and the door is sized so that the two close on
/// one bottom edge.
///
/// The grid is content-sized inside the feed's one scroll view — [TwoColumnMasonry]
/// lays its cells out and reports their total height, so nothing here scrolls
/// on its own and a nested scrollable cannot trap the customer's drag. The home
/// feed carries this grid *and* the catalog's own masonry below it;
/// `test/widgets/nested_masonry_scroll_test.dart` pins that the feed still
/// reaches its last card.
///
/// **Self-spacing, and assumes a non-empty list.** Like `ProductRailSection` it
/// does NOT hide itself — that belongs to the section widget above it, which
/// is the only thing that knows whether "nothing to show" means "not applicable"
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
  }       ) : assert(
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
  /// the [ProductSectionHeader]. May be content-sized — [TwoColumnMasonry]
  /// measures each cell as it lays it out, so a [FitCard] given no box of its
  /// own simply takes the height its copy comes to, and the grid packs around
  /// it. Null when the caller wants the plain text heading.
  final Widget? tile;

  /// The grid's closing cell, in the right column beside the last product — the
  /// "See more" card that is the way to the rest of the shelf. Like [tile] it
  /// may be content-sized: [TwoColumnMasonry] gives it a box of its own and
  /// sizes it to reach the anchored product's bottom edge.
  final Widget? trailing;

  /// The cards to show, in the order the provider ranked them. Expected
  /// non-empty — see the class doc.
  final List<Map<String, dynamic>> products;

  /// The catalog's column count, stated once so a later grid section cannot
  /// quietly become a 3-column outlier on a page of 2-column feeds.
  static const int crossAxisCount = TwoColumnMasonry.columnCount;

  /// One product cell — the catalog's card, at the catalog's ratio, opening the
  /// catalog's detail page.
  Widget _card(BuildContext context, Map<String, dynamic> product) {
    return SoleProductCard(
      product: product,
      imageAspectRatio: productGridRatio(product),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(product: product),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // The closing card is placed beside the last product, so it needs one to
    // anchor it — the list is expected non-empty either way (class doc).
    assert(
      trailing == null || products.isNotEmpty,
      'the closing pair needs a product to anchor it',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A tiled section's heading IS the grid's first cell, so all it gets up
        // here is the same 4px of air the text heading opens with; a titled
        // section renders that heading as its own row instead.
        if (tile != null)
          const SizedBox(height: 4)
        else
          ProductSectionHeader(title: title!, meta: meta),
        TwoColumnMasonry(
          margin: AppConstants.feedMargin,
          gutter: AppConstants.productGridGutter,
          // The last product and the closing card are placed against their own
          // columns when there IS a card to pair them with; without one the
          // flow packs every product, as the catalog does.
          closingCount: trailing == null ? 0 : 2,
          children: [
            ?tile,
            for (final product in products) _card(context, product),
            ?trailing,
          ],
        ),
        // Owned here, not by the caller: the section hides itself when it has
        // nothing to show, and a caller-side spacer would leave a gap where the
        // grid is not.
        const SizedBox(height: 16),
      ],
    );
  }
}
