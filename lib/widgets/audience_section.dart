import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../providers/product_provider.dart';
import '../screens/customer/audience_listing_screen.dart';
import '../screens/customer/product_detail_screen.dart';
import '../utils/product_audience.dart';
import '../utils/product_images.dart';
import 'press_sink.dart';
import 'product_image_pager.dart';
import 'product_section_header.dart';
import 'sole_product_card.dart';

/// How many cells an audience section previews.
///
/// Four, because this section is a **door rather than a shelf**: it is the
/// feed's way of saying *this is what we make for men* and then getting out of
/// the way, where the shelf itself is one tap behind the last tile.
///
/// Four is exactly one 2x2 grid: two rows of two. A block of pictures is read as
/// a *block*, so a short last row would make it look broken rather than small.
///
/// Deliberately not [kAudienceRailLimit] (12): that number sizes the provider's
/// own default cap, which other callers and their tests rely on. This is the
/// home section's editorial count and nothing else reads it.
const int kAudiencePreviewCount = 4;

/// How many of the preview cells open a product page.
///
/// Three: the first three tiles are the products themselves, and the fourth
/// cell is a stacked-cards door to the whole shelf. A short shelf
/// (three or fewer) has no door — the listing behind it would be the same
/// products already on screen — so every tile is a product.
const int kAudienceProductTileCount = 3;

/// Test seam for the stacked-cards fourth cell (the shelf door, not a product).
const Key kAudienceSeeMoreKey = Key('audience-see-more');

/// One audience section on the customer home — Men's, Women's or Kids': a
/// heading over **four photos**, the first three opening those products and
/// the last opening that audience's shelf.
///
/// **Photos only, and that is the section's point.** Each product tile is the
/// catalog's own card in its `imageOnly` mode — the product's picture, its
/// corner radius and its hairline, and nothing else: no name, no rating, no
/// price. Three names and three prices repeated under a heading that already
/// says who they are for is a second catalog above the real one; the shelf
/// behind the tiles names and prices all of them, with room to read them.
/// What this section has to say is *what this audience looks like*, and a
/// photograph says that faster than a list of lines can.
///
/// **A product tile is a product.** Tapping one of the first three opens
/// [ProductDetailScreen] for that product, with the audience's ranked shelf as
/// its swipe list — so swiping walks the shelf the tile came from. The fourth
/// cell is the shelf's door: the fourth photo as the top of a small stacked
/// deck, with the count of what sits behind it, opening [AudienceListingScreen]
/// for that audience — the same page the Home hero's audience chip opens.
///
/// **Edge to edge, and that is deliberate.** This widget adds no side margin of
/// its own — its heading is inset 0 and its tiles run to the edges of its box —
/// because the page margin belongs to whatever is laying sections out. Alone on
/// the feed that is one audience across the page; in [AudienceSections] it is two
/// or three narrower columns with the page gutters between them. A section that
/// inset itself could be both.
///
/// **Its tiles are a 2x2 grid of squares.** Two rows of two at any column width,
/// so the same four cells read the same whether the section sits alone on the
/// feed or in the audience row on a phone. The squares let the grid line up: a
/// product's own photo shape is cropped to fit rather than letting a tall one
/// push its row out of line. That is why this does not reuse `ProductGridSection`,
/// whose masonry staggers the cell heights.
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

    // The whole ranked shelf, so the product tiles can swipe through it and
    // the door can say how much sits behind it. Sliced below to the 2x2
    // preview — the section is the only thing that knows how long a preview
    // should be.
    final shelf =
        context.select<ProductProvider, List<Map<String, dynamic>>>(
      (p) => p.productsForAudience(canonical, limit: 0),
    );
    if (shelf.isEmpty) return const SizedBox.shrink();

    final showSeeMore = shelf.length > kAudienceProductTileCount;
    final productTiles = showSeeMore
        ? shelf.sublist(0, kAudienceProductTileCount)
        : shelf.take(kAudiencePreviewCount).toList();

    void openShelf() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AudienceListingScreen(audience: canonical),
        ),
      );
    }

    // The 2x2 cells in reading order: up to three product doors, then the
    // stacked-cards shelf door. A short shelf ends on its products — a door
    // that opened the same products would be a promise onto nothing.
    final cells = <Widget>[
      for (final (index, product) in productTiles.indexed)
        SoleProductCard(
          product: product,
          imageAspectRatio: 1.0,
          imageOnly: true,
          semanticsLabel: product['name']?.toString() ?? 'Product ${index + 1}',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ProductDetailScreen(
                product: product,
                // The shelf in the preview's own ranked order, so swiping
                // walks the shelf behind the tap.
                browseList: shelf,
                browseIndex: index,
              ),
            ),
          ),
        ),
      if (showSeeMore)
        _AudienceSeeMoreTile(
          // The next photos on the shelf, fanned as a stacked deck — a hint
          // of what sits behind the door rather than a fourth product tile.
          product: shelf[kAudienceProductTileCount],
          middleProduct: shelf.length > kAudienceProductTileCount + 1
              ? shelf[kAudienceProductTileCount + 1]
              : null,
          backProduct: shelf.length > kAudienceProductTileCount + 2
              ? shelf[kAudienceProductTileCount + 2]
              : null,
          label: label,
          remaining: shelf.length - kAudienceProductTileCount,
          onTap: openShelf,
        ),
    ];

    // Two rows of two, the same gutter between the columns as between the rows.
    final rows = <Widget>[
      for (var start = 0; start < cells.length; start += 2) ...[
        if (start > 0) const SizedBox(height: AppConstants.productGridGutter),
        Row(
          children: [
            Expanded(child: cells[start]),
            const SizedBox(width: AppConstants.productGridGutter),
            Expanded(
              child: start + 1 < cells.length
                  ? cells[start + 1]
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Inset 0: the page margin is the caller's (see the class doc).
        ProductSectionHeader(title: label, sideInset: 0),
        ...rows,
        // Owned here, not by the caller: this section hides itself when it
        // has nothing to show, and a caller-side spacer would leave a gap
        // where the tiles are not.
        const SizedBox(height: 16),
      ],
    );
  }
}

/// The fourth cell of an audience preview: the next photo as the top of a
/// small stacked deck, with the count of what sits behind it, opening the
/// whole shelf.
///
/// It is the same size and shape as the three product tiles beside it (a
/// square with the product family's corner and hairline), so the 2x2 block
/// stays a block. The top card shows the shelf's next photo with the count of
/// what sits behind it, over two stepped cards showing the shelf's next
/// photos — the cell reads as a stack to flip through, not a fourth product.
class _AudienceSeeMoreTile extends StatelessWidget {
  const _AudienceSeeMoreTile({
    required this.product,
    this.middleProduct,
    this.backProduct,
    required this.label,
    required this.remaining,
    required this.onTap,
  });

  /// The photo topping the stack — the shelf's next product.
  final Map<String, dynamic> product;

  /// The photos fanned behind it — the 5th and 6th shelf products, when the
  /// shelf runs that deep. Null renders a plain fill instead.
  final Map<String, dynamic>? middleProduct;
  final Map<String, dynamic>? backProduct;

  /// The audience heading (`Men's`), for the accessible name.
  final String label;

  /// How many shelf products sit behind this door (shelf minus the three
  /// product tiles). Named on the tile only when more than one hides there.
  final int remaining;

  final VoidCallback onTap;

  /// How far each card of the stack steps up-right from the one in front of
  /// it. Two steps, so the peek reads at a glance without eating the photo.
  static const double _stackStep = 8;

  /// The photo when the product carries none of its own.
  static const String _fallbackProductImage =
      'https://images.unsplash.com/photo-1549298916-b41d501d7722?q=80&w=600&auto=format&fit=crop';

  /// The shelf photo a stack layer shows: the product's first photo, or the
  /// stand-in when it carries none of its own.
  static List<String> _photoOf(Map<String, dynamic> product) {
    final urls = productImageUrls(product);
    return urls.isEmpty ? const [_fallbackProductImage] : [urls.first];
  }

  /// One card fanned behind the top photo — the product's own photo when the
  /// shelf runs that deep, a plain fill otherwise. Pointer-transparent (like
  /// the top photo): the whole cell stays one tap target.
  static Widget _behindCard(Map<String, dynamic>? product) {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: AppConstants.productCardRadius,
      ),
      child: product == null
          ? null
          : ClipRRect(
              borderRadius: AppConstants.productCardRadius,
              child: IgnorePointer(
                child: ProductImagePager(images: _photoOf(product)),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photoOf(product);
    // One label for the whole cell (the FitCard shape): the stacked cards and
    // the count badge say nothing on their own — the door announces the shelf
    // it opens, once.
    return Semantics(
      container: true,
      button: true,
      label: 'See all $label products',
      child: ExcludeSemantics(
        child: PressSink(
          key: kAudienceSeeMoreKey,
          onTap: onTap,
          idle: AppConstants.productCardShadow,
          pressed: AppConstants.productCardShadowPressed,
          borderRadius: AppConstants.productCardRadius,
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                color: AppConstants.surfaceLight,
                borderRadius: AppConstants.productCardRadius,
                border: Border.all(color: AppConstants.cardEdge, width: 1),
              ),
              child: ClipRRect(
                borderRadius: AppConstants.productCardImageRadius,
                child: Stack(
                  fit: StackFit.expand,                  children: [
                    // The deck behind the top photo — the shelf's 6th and
                    // 5th photos stepped up-right, so the cell reads as a
                    // stack to flip through rather than one more tile.
                    // Borderless: only the top card carries the hairline, so
                    // the peek reads as photos, not an outline grid.
                    Positioned(
                      left: _stackStep * 2,
                      top: 0,
                      right: 0,
                      bottom: _stackStep * 2,
                      child: _behindCard(backProduct),
                    ),
                    Positioned(
                      left: _stackStep,
                      top: _stackStep,
                      right: _stackStep,
                      bottom: _stackStep,
                      child: _behindCard(middleProduct),
                    ),
                    // The top card: the shelf's next photo and the count of
                    // what sits behind it.
                    Positioned(
                      left: 0,
                      top: _stackStep * 2,
                      right: _stackStep * 2,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppConstants.surfaceLight,
                          borderRadius: AppConstants.productCardRadius,
                          border: Border.all(
                            color: AppConstants.cardEdge,
                            width: 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius:
                              AppConstants.productCardImageRadius,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Pointer-transparent so the whole cell stays
                              // the one tap target above.
                              IgnorePointer(
                                child: ProductImagePager(
                                  images: photos,
                                ),
                              ),
                              if (remaining > 1)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 6,
                                  child: Center(
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.65,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '+$remaining more',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
              ),
            ),
          ),
        ),
        ),
      ),
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
/// **Side by side is an arrangement, not a shape.** Each column is the same 2x2
/// grid whatever its width, so on a phone the audiences sit side by side as two
/// small grids.
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
            if (index > 0) const SizedBox(width: AppConstants.audienceColumnGap),
            Expanded(
              child: AudienceSection(audience: audience, enabled: enabled),
            ),
          ],
        ],
      ),
    );
  }
}
