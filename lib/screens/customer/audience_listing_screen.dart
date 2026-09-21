import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../../constants/app_brightness.dart';
import '../../constants/app_constants.dart';
import '../../constants/app_palette.dart';
import '../../providers/product_provider.dart';
import '../../utils/product_audience.dart';
import '../../utils/product_grid_ratio.dart';
import '../../widgets/product_sort_chip.dart';
import '../../widgets/sole_product_card.dart';
import 'product_detail_screen.dart';

/// Everything the seller tagged for one audience — Men's, Women's, Kids' or
/// Unisex — reached by tapping that audience's chip in the Home category row.
///
/// Why a page rather than a filter chip that narrows Home in place: the
/// audience chips sit in a row of *categories*, and a category chip narrowing
/// the feed is fine, but an audience is a shelving decision, not a keyword. A
/// customer who taps "Women's" is asking to see the Women's shelf — with its
/// own order, its own count, and a Back button that returns them to the same
/// Home they left. That also keeps the rails' rule intact: the rails stay
/// curated strips, and `unisex` (deliberately absent from them, §4 R4) is
/// reachable as a group here instead of in three rails at once.
///
/// What it owns:
///
///  * its **own sort** ([SortMode.featured] to start), held locally and passed
///    into [ProductProvider.productsInAudience] — opening this page can never
///    re-sort the Home feed underneath it;
///  * the **whole** list for that audience — uncapped, unlike the 12-card rail;
///  * its empty state, because an audience can lose its last product while the
///    page is open (a reload) and a blank page would read as a bug.
///
/// It reads the catalog already in memory — no query, no network — and only
/// `unisex`/`men`/`women`/`kids` are valid here; an unrecognised value renders
/// the empty state rather than guessing an audience.
///
/// Reachable only through an audience chip, which itself only exists while
/// `AppConstants.productAudienceEnabled` is on AND the catalog holds at least
/// one product for that audience (see [ProductProvider.audiencesInCatalog]) —
/// so this page itself needs no kill switch, its entry point is the gate.
class AudienceListingScreen extends StatefulWidget {
  const AudienceListingScreen({super.key, required this.audience});

  /// A canonical audience value from `product_audience.dart`'s vocabulary.
  final String audience;

  @override
  State<AudienceListingScreen> createState() => _AudienceListingScreenState();
}

class _AudienceListingScreenState extends State<AudienceListingScreen> {
  SortMode _sort = SortMode.featured;

  /// Clay as INK, rather than [AppConstants.primary] as a fill.
  ///
  /// The brand clay is pinned (it is a fill other colours are drawn on), so at
  /// #8B5A2B it is only ~3.3:1 on the dark page — under AA for the 11–13px text
  /// it labels here. `AppPalette.primaryInk` is the role token for exactly this
  /// case (it is the lighter clay on dark), and the palette's own notes call it
  /// the ink role for the brand; `AppConstants.primary` stays for the fills and
  /// hairline tints below, where it is decoration rather than something to read.
  Color get _accentInk => AppPalette.of(AppBrightness.current).primaryInk;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();
    final label = productAudienceLabel(widget.audience) ?? 'Shelf';
    final products = provider.productsInAudience(widget.audience, sort: _sort);

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            AppConstants.noiseOverlay(opacity: 0.03),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(label, products.length),
                Expanded(
                  child: products.isEmpty
                      ? _buildEmptyState(label)
                      : _buildGrid(products),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar: back + the shelf's name and size + its own sort ──
  //
  // The sort control drops to its own line once the text is large enough that
  // it no longer fits beside the title on a narrow phone. There is no honest
  // way to squeeze it instead: the label is a *word* ('Price: Low to High'), so
  // shrinking it means either ellipsising it ("Price: Lo…", which is what a
  // sort sheet's option is — not decoration) or truncating a control the
  // customer needs to read. Stacking keeps both readable, costs one line of
  // height, and leaves the normal case byte-for-byte unchanged.
  static const double _sortLabelFontSize = 11;

  /// True when the scaled label no longer fits the header's spare width — the
  /// threshold is expressed in scaled pixels rather than a raw scale factor so
  /// it stays tied to the label it is about.
  bool _stacksAtLargeText(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(_sortLabelFontSize);
    return scaled > 15.5;
  }

  Widget _buildTopBar(String label, int count) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppConstants.headlineStyle(fontSize: 20)),
        const SizedBox(height: 2),
        Text(
          count == 1 ? '1 pair' : '$count pairs',
          style: AppConstants.bodyStyle(
            fontSize: 12,
            color: AppConstants.secondary.withValues(alpha: 0.55),
          ),
        ),
      ],
    );

    final back = IconButton(
      icon: Icon(Icons.arrow_back, color: AppConstants.secondary),
      onPressed: () => Navigator.of(context).pop(),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 10),
      child: _stacksAtLargeText(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    back,
                    const SizedBox(width: 4),
                    Expanded(child: title),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 4),
                  child: _sortChip(),
                ),
              ],
            )
          : Row(
              children: [
                back,
                const SizedBox(width: 4),
                Expanded(child: title),
                _sortChip(),
              ],
            ),
    );
  }

  /// The shared chip: the sheet is one sheet and the control above it is one
  /// control, so an audience shelf cannot offer a fifth set of orders.
  Widget _sortChip() => ProductSortChip(
    sort: _sort,
    onSelected: (mode) => setState(() => _sort = mode),
  );

  // ── The shelf ──

  Widget _buildGrid(List<Map<String, dynamic>> products) {
    return MasonryGridView.count(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppConstants.feedMargin,
        4,
        AppConstants.feedMargin,
        32,
      ),
      crossAxisCount: 2,
      crossAxisSpacing: AppConstants.productGridGutter,
      mainAxisSpacing: AppConstants.productGridGutter,
      itemCount: products.length,
      itemBuilder: (context, index) {
        final prod = products[index];
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
    );
  }

  /// Shown when this audience currently holds nothing. Not a dead end: the
  /// way out is the same "Browse All Styles" the rest of the app uses, and it
  /// leaves the page rather than offering a filter that would find nothing.
  Widget _buildEmptyState(String label) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 32),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppConstants.primary.withValues(alpha: 0.07),
              border: Border.all(
                color: AppConstants.primary.withValues(alpha: 0.18),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.category_outlined,
              size: 34,
              color: _accentInk.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Nothing in $label yet',
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Sellers are still filling this shelf. The rest of the catalog is '
            'right below it.',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: AppConstants.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppConstants.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.grid_view_outlined, size: 15, color: _accentInk),
                  const SizedBox(width: 6),
                  // Flexible, so the pill wraps its label at a large text scale
                  // rather than overflowing its own row.
                  Flexible(
                    child: Text(
                      'Browse All Styles',
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _accentInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
