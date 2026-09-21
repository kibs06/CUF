import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../../constants/app_brightness.dart';
import '../../constants/app_constants.dart';
import '../../constants/app_palette.dart';
import '../../providers/product_provider.dart';
import '../../utils/product_grid_ratio.dart';
import '../../utils/sale_price.dart';
import '../../widgets/product_shelf_toolbar.dart';
import '../../widgets/sole_product_card.dart';
import 'product_detail_screen.dart';

/// The whole sale shelf behind the home feed's **ON SALE** card: every product
/// that is on sale right now, uncapped.
///
/// The section it opens from is honest about being a preview — the poster, the
/// discount, and however many sale cards fit in the two columns beside it — so
/// this page is what that card means: the same shelf, the same rule
/// ([isOnSale]), the same card, with nothing taken away.
///
/// **Why a page and not the `'On Sale'` chip.** The chip narrows the Home feed
/// in place, which is right for "show me only these in the catalog I am already
/// reading". This is the other question — *what is on sale, all of it* — and a
/// customer who tapped a card that names the sale is asking to leave the feed
/// for the sale, not to have the feed silently rewritten under them with the
/// section they tapped now hidden. It is also the pattern the rest of the app
/// already uses: "See more" opens [SizeListingScreen], an audience chip opens
/// the audience shelf, and both come back to the same Home.
///
/// **It searches, filters and sorts *itself*.** A sale shelf is a list a
/// customer wants to narrow — a word, a category, the cheapest first — and the
/// one thing it may never do is narrow the shelf's *rule*: searching here keeps
/// "is on sale right now" intact, exactly as sorting here keeps the home feed's
/// order intact. The state is local ([_query], [_category], [_sort]) and the
/// work is the provider's ([ProductProvider.shelfProducts], which reuses the
/// catalog's own [matchesSearchQuery] and sort), so this page cannot invent a
/// second meaning for "search" or for "Price: Low to High". Its default order
/// is the shelf's own (the catalog order the home feed shows), which is what
/// "Featured" means on every listing page.
///
/// **Absent-safe.** A sale can end while this page is open, so an empty list is
/// a real state and it explains itself ("Nothing on sale right now") rather than
/// rendering a blank page, with a pop back to the feed as the way out. The page
/// reads the catalog already in memory — no query, no network — so it can never
/// be the reason a sale surface waits. A search that matches nothing on the
/// shelf is a *different* state from that, and says so.
class OnSaleListingScreen extends StatefulWidget {
  const OnSaleListingScreen({super.key});

  @override
  State<OnSaleListingScreen> createState() => _OnSaleListingScreenState();
}

class _OnSaleListingScreenState extends State<OnSaleListingScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// What the customer typed into the shelf's own field. Empty = the whole
  /// shelf.
  String _query = '';

  /// The category filter in force, or null for every category. Local, like the
  /// search page's — see the class doc.
  String? _category;

  /// The order this page is using. Starts at the shelf's own (catalog) order.
  SortMode _sort = SortMode.featured;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Back to the whole shelf — what the no-matches state offers, since a sale
  /// that *has* products is one tap away (and its own empty state, for a sale
  /// that ended, is a different thing entirely).
  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _category = null;
    });
  }

  /// Clay as INK, rather than [AppConstants.primary] as a fill.
  ///
  /// The brand clay is pinned (it is a fill other colours are drawn on), so at
  /// #8B5A2B it is only ~3.3:1 on the dark page — under AA for the small text
  /// it labels here. `AppPalette.primaryInk` is the role token for exactly this
  /// case (it is the lighter clay on dark), the same choice the size shelf makes.
  Color get _accentInk => AppPalette.of(AppBrightness.current).primaryInk;

  @override
  Widget build(BuildContext context) {
    final shelf = context.select<ProductProvider, List<Map<String, dynamic>>>(
      (p) => p.products.where(isOnSale).toList(),
    );
    final provider = context.read<ProductProvider>();

    // Derived from the same list the grid draws, so the headline can never
    // disagree with the cards under it — and from the WHOLE shelf, so narrowing
    // the list does not quietly change the "up to N% off" the page is named
    // for.
    final discount = maxDiscountPercent(shelf);

    final categories = provider.shelfCategories(shelf);
    final selectedCategory = _category != null && categories.contains(_category)
        ? _category
        : null;

    final products = provider.shelfProducts(
      shelf,
      query: _query,
      category: selectedCategory,
      sort: _sort,
    );

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
                _buildTopBar(context, products.length, shelf.length, discount),
                // No toolbar over an empty shelf: there is nothing to search,
                // filter or sort, and the empty state says what to do instead.
                if (shelf.isNotEmpty)
                  ProductShelfToolbar(
                    controller: _searchController,
                    hintText: 'Search on sale…',
                    categories: categories,
                    selectedCategory: selectedCategory,
                    onCategorySelected: (category) =>
                        setState(() => _category = category),
                    onQueryChanged: (query) => setState(() => _query = query),
                    sort: _sort,
                    onSortSelected: (mode) => setState(() => _sort = mode),
                  ),
                Expanded(
                  child: shelf.isEmpty
                      ? _buildEmptyState(context)
                      : products.isEmpty
                      ? _buildNoMatchesState(context, shelf.length)
                      : _buildGrid(context, products),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar: back + the shelf's name, its count and its best discount ──

  Widget _buildTopBar(
    BuildContext context,
    int shown,
    int total,
    int? discount,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppConstants.secondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'On Sale',
                  style: AppConstants.headlineStyle(fontSize: 20),
                ),
                const SizedBox(height: 2),
                // The discount is named here, not only on the card: the whole
                // shelf is a claim about how much is off, so the number it was
                // built on stays visible — and it is the same derivation the
                // home poster uses. The count follows the grid instead, once a
                // search or a filter is narrowing it (`3 of 10 pairs`), because
                // a heading that counts cards the customer cannot see would be
                // a lie.
                Text(
                  shelfCountLabel(
                    shown: shown,
                    total: total,
                    qualifier: discount == null ? null : 'up to $discount% off',
                  ),
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── The shelf ──

  Widget _buildGrid(BuildContext context, List<Map<String, dynamic>> products) {
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
        // The same card and the same per-product ratio as the home grid, so a
        // product looks identical on both sides of the card.
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

  /// Shown when the sale shelf has products but the search or the filter left
  /// none of them. Deliberately *not* [OnSaleListingScreenState._buildEmptyState]:
  /// the sale is fine, the question was just too narrow — so the action is
  /// "Clear filters", the only way back to the whole shelf besides retyping.
  Widget _buildNoMatchesState(BuildContext context, int shelfSize) {
    final query = _query.trim();
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
              Icons.search_off,
              size: 34,
              color: _accentInk.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            query.isEmpty
                ? 'Nothing on sale in this category'
                : 'Nothing on sale matches "$query"',
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            '$shelfSize ${shelfSize == 1 ? 'pair is' : 'pairs are'} on sale '
            'right now — clear the filters to see them.',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _clearFilters,
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
                  Icon(
                    Icons.filter_alt_off_outlined,
                    size: 15,
                    color: _accentInk,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Clear filters',
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

  /// Shown when the last sale ends while this page is open (or nothing was on
  /// sale to begin with). Not a dead end: the way out is back to the feed.
  Widget _buildEmptyState(BuildContext context) {
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
              Icons.local_offer_outlined,
              size: 34,
              color: _accentInk.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Nothing on sale right now',
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Sales come and go — check back soon, or browse the full catalog '
            'in the meantime.',
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
