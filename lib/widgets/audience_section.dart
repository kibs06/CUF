import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../providers/product_provider.dart';
import '../screens/customer/audience_listing_screen.dart';
import '../utils/product_audience.dart';
import '../utils/product_grid_ratio.dart';
import 'product_section_header.dart';
import 'sole_product_card.dart';
import 'two_column_masonry.dart';

/// How many products an audience section previews.
///
/// Four, because this section is a **door rather than a shelf**: it is the
/// feed's way of saying *this is what we make for men* and then getting out of
/// the way, where the shelf itself is one tap behind every tile.
///
/// Four is also the one count that fills **every** shape this section can take
/// without a stump: two clean rows where the column is wide enough for two tiles
/// side by side, four clean rows where it is not. That matters more here than
/// anywhere else on the feed, because a block of pictures is read as a *block* —
/// a short last row makes it look broken rather than merely short.
///
/// Deliberately not [kAudienceRailLimit] (12): that number sizes the provider's
/// own default cap, which other callers and their tests rely on. This is the
/// home section's editorial count and nothing else reads it.
const int kAudiencePreviewCount = 4;

/// The narrowest a tile may be before an audience section stops trying to fit
/// two of them side by side.
///
/// The breakpoint is this doubled plus one [AppConstants.productGridGutter], so
/// the rule is stated in terms of the thing it protects rather than as a bare
/// number. 150 is roughly where a catalogue card stops reading as a card and
/// starts reading as a thumbnail — below it, two tiles beside each other are
/// worse than one tile per row, which is the shape the audience row uses.
const double kAudienceTileMinWidth = 150;

/// The number of tile columns an audience section fits in [width] pixels.
///
/// Two when two tiles of at least [kAudienceTileMinWidth] fit across it, one
/// otherwise. Exposed as a function so the one rule can be tested directly
/// rather than only through a rendered box.
int audienceTileColumnsFor(double width) =>
    width >= kAudienceTileMinWidth * 2 + AppConstants.productGridGutter ? 2 : 1;

/// One audience section on the customer home — Men's, Women's or Kids': a
/// heading over **four photos**, every one of them opening that audience's shelf.
///
/// **Photos only, and that is the section's point.** Each tile is the catalog's
/// own card in its `imageOnly` mode — the product's picture, its corner radius
/// and its hairline, and nothing else: no name, no rating, no price. Four names
/// and four prices repeated under a heading that already says who they are for
/// is a second catalog above the real one; the shelf behind the tiles names and
/// prices all of them, with room to read them. What this section has to say is
/// *what this audience looks like*, and a photograph says that faster than a
/// list of four lines can.
///
/// **A tile is a door, not a product.** Tapping any of the four opens
/// [AudienceListingScreen] for that audience — the same page the Home category
/// row's audience chip opens, and the same move `SeeMoreCard` makes for the size
/// shelf. It is deliberately NOT this product's detail page: the four tiles are
/// one block, so the tap answers "show me the Men's shelf", and opening one
/// arbitrary product out of a set the customer never chose between is the
/// opposite of what the picture was asking. Nothing on a tile is labelled with a
/// name or a price, so nothing on it promises a product page.
///
/// **Edge to edge, and that is deliberate.** This widget adds no side margin of
/// its own — its heading is inset 0 and its tiles run to the edges of its box —
/// because the page margin belongs to whatever is laying sections out. Alone on
/// the feed that is one audience across the page; in [AudienceSections] it is two
/// or three narrower columns with the page gutters between them. A section that
/// inset itself could not be both.
///
/// **Its tiles take the shape its column can afford.** One photo per row when
/// the column is narrow (as it is in the audience row on a phone), two when the
/// column is wide enough for them to still read as cards
/// ([audienceTileColumnsFor]). That is why this does not simply reuse
/// `ProductGridSection`: that widget is the feed's own 2-column masonry and
/// cannot stack a single column, which is exactly what a third of a phone's
/// width needs.
///
/// **This is the first customer-facing pixel of the product-audience feature**,
/// and it is gated behind [AppConstants.productAudienceEnabled].
///
/// **Stated, never inferred.** A product with `audience = null` belongs in the
/// catalog grid, in search and in every category; it is only absent from these
/// sections. That is the whole point of the column existing separately from the
/// size band — EU sizing is unisex, so Men's and Women's share one band and a
/// size could never decide this. [ProductProvider.productsForAudience] owns the
/// rule, including the hard exclusion of `unisex` (a unisex product in all three
/// sections would put one card three times down the feed, plan §4 R4).
///
/// **Absent-safe:** kill switch off, an audience that is not section-eligible,
/// or nothing in the catalog carrying it → renders nothing at all, with no
/// header and no residual gap.
class AudienceSection extends StatelessWidget {
  const AudienceSection({
    super.key,
    required this.audience,
    this.enabled = AppConstants.productAudienceEnabled,
  });

  /// One of [productRailAudiences]. Anything else (including `'unisex'`, which
  /// is a valid audience but never a section) renders nothing.
  final String audience;

  /// The kill switch, resolved once per build.
  ///
  /// Defaults to [AppConstants.productAudienceEnabled] — no production call
  /// site passes this. It exists so the feature's own behaviour stays testable
  /// while that constant is off, which is how it shipped dark.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Switch first: with the feature off this widget must behave as though it
    // does not exist, so it never even asks the provider for a list.
    if (!enabled) return const SizedBox.shrink();

    final canonical = productAudienceFrom(audience);
    if (canonical == null || canonical == kUnisexAudience) {
      return const SizedBox.shrink();
    }
    final label = productAudienceLabel(canonical);
    if (label == null) return const SizedBox.shrink();

    final products =
        context.select<ProductProvider, List<Map<String, dynamic>>>(
      (p) => p.productsForAudience(canonical, limit: kAudiencePreviewCount),
    );
    if (products.isEmpty) return const SizedBox.shrink();

    // Every tile opens the same shelf, so each one names that destination out
    // loud and says which of the four it is — a tile draws no words, and four
    // buttons under one identical label are four buttons a screen reader cannot
    // choose between.
    final tiles = <Widget>[
      for (final (index, product) in products.indexed)
        SoleProductCard(
          product: product,
          imageAspectRatio: productGridRatio(product),
          imageOnly: true,
          semanticsLabel:
              'See the $label shelf, ${index + 1} of ${products.length}',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AudienceListingScreen(audience: canonical),
            ),
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = audienceTileColumnsFor(constraints.maxWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Inset 0: the page margin is the caller's (see the class doc).
            ProductSectionHeader(title: label, sideInset: 0),
            if (columns == 2)
              TwoColumnMasonry(
                margin: 0,
                gutter: AppConstants.productGridGutter,
                children: tiles,
              )
            else
              // One photo per row, the same gutter the two-column form uses
              // between its cells — one seam, whichever shape the column takes.
              Column(
                children: [
                  for (final (index, tile) in tiles.indexed) ...[
                    if (index > 0)
                      const SizedBox(height: AppConstants.productGridGutter),
                    tile,
                  ],
                ],
              ),
            // Owned here, not by the caller: this section hides itself when it
            // has nothing to show, and a caller-side spacer would leave a gap
            // where the tiles are not.
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

/// The Men's / Women's / Kids' sections **side by side**, in one row.
///
/// The home screen renders this instead of iterating [productRailAudiences]
/// itself, so the fixed order, the `unisex` exclusion and the row's own geometry
/// are all decided in one place — and so the feed is one widget rather than a
/// loop plus a layout it would otherwise have to own.
///
/// **Only the audiences that have something get a column.** A reserved empty
/// column is not neutral: with Kids' untagged (its state in the live catalog
/// today) two filled columns and a deliberate hole reads as a broken layout, and
/// a hole in the feed is exactly what every other section here avoids by hiding
/// itself. So the row is two columns today and three the moment a seller tags a
/// Kid's product — the columns resizing is the visible cost of never showing a
/// blank one. A section that renders nothing still contributes nothing, header
/// included.
///
/// **Equal columns, capped at [kAudienceMaxColumns].** Up to that many audiences
/// share the width evenly. The cap is what stops a future vocabulary from
/// squeezing five audiences into a phone's width; anything past it is dropped
/// rather than shrunk, because an unreadable column is not a section.
///
/// **Side by side is an arrangement, not a shape.** Each column asks for its own
/// tile count based on the width it is handed ([audienceTileColumnsFor]), so on a
/// phone — where a column is roughly a third of the page — each one stacks its
/// photos, and on a tablet the same widgets lay out two to a row.
class AudienceSections extends StatelessWidget {
  const AudienceSections({
    super.key,
    this.enabled = AppConstants.productAudienceEnabled,
  });

  /// The kill switch, forwarded to every column. Resolved once per build.
  final bool enabled;

  /// The most columns this row will ever draw.
  static const int kAudienceMaxColumns = 3;

  /// The audiences that currently hold at least one product, in the fixed
  /// [productRailAudiences] order, capped at [kAudienceMaxColumns].
  ///
  /// Built from [ProductProvider.audiencesInCatalog] — the provider's own
  /// single pass over the catalog — rather than from a `productsForAudience`
  /// call per audience, which would filter *and sort* the matches three times
  /// over to answer a question that is only "is this audience here at all?".
  /// Intersecting with [productRailAudiences] is also what keeps the order fixed
  /// and what excludes `unisex`, which is a real audience but never a section.
  ///
  /// Read as a string rather than a list so `select` can compare it by value: a
  /// fresh `List` is never equal to the previous one and would rebuild on every
  /// provider notification.
  static String visibleKey(ProductProvider provider) {
    final present = provider.audiencesInCatalog;
    return productRailAudiences
        .where(present.contains)
        .take(kAudienceMaxColumns)
        .join(',');
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();

    final visible = context.select<ProductProvider, String>(visibleKey);
    if (visible.isEmpty) return const SizedBox.shrink();

    final audiences = visible.split(',');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.feedMargin),
      child: Row(
        // Top-aligned: two audiences rarely hold the same number of photos, and
        // stretching the shorter column would only pad it with nothing.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, audience) in audiences.indexed) ...[
            if (index > 0) const SizedBox(width: AppConstants.productGridGutter),
            Expanded(
              child: AudienceSection(audience: audience, enabled: enabled),
            ),
          ],
        ],
      ),
    );
  }
}
