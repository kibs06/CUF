import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../../constants/app_brightness.dart';
import '../../constants/app_constants.dart';
import '../../constants/app_palette.dart';
import '../../providers/product_provider.dart';
import '../../utils/product_audience.dart';
import '../../utils/product_grid_ratio.dart';
import '../../widgets/product_shelf_toolbar.dart';
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
///  * its **own search, category filter and sort** ([_query], [_category],
///    [_sort], all local), so opening this page can never narrow, re-filter or
///    re-sort the Home feed underneath it;
///  * the **whole** list for that audience — uncapped, unlike the 12-card rail;
///  * its empty state, because an audience can lose its last product while the
///    page is open (a reload) and a blank page would read as a bug.
///
/// **It searches, filters and sorts *itself*, and never its rule.** A shelf of
/// forty pairs is a list a customer wants to narrow — by a word, by a category,
/// by price — but searching here must keep "sellers tagged this Men's" intact.
/// The state is local and the work is the provider's
/// ([ProductProvider.shelfProducts], which reuses the catalog's own
/// [matchesSearchQuery] and sort), so this page cannot invent a second meaning
/// for "search" — and it is the same toolbar the size and sale shelves put up
/// ([ProductShelfToolbar]), so the three controls a customer learns on one
/// shelf are the three they meet on the next.
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
  final TextEditingController _searchController = TextEditingController();

  /// What the customer typed into the shelf's own field. Empty = the whole
  /// shelf.
  String _query = '';

  /// The category filter in force, or null for every category. Local, like the
  /// search page's — see the class doc.
  String? _category;

  /// The order this page is using. Starts at the shelf's own ranking, so the
  /// list a customer tapped is the list they get until they ask otherwise.
  SortMode _sort = SortMode.featured;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Back to the whole shelf — what the no-matches state offers, since the
  /// shelf itself (which has products in it) is one tap away and its own empty
  /// state is a different thing entirely.
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
  /// #8B5A2B it is only ~3.3:1 on the dark page — under AA for the 11–13px text
  /// it labels here. `AppPalette.primaryInk` is the role token for exactly this
  /// case (it is the lighter clay on dark), and the palette's own notes call it
  /// the ink role for the brand; `AppConstants.primary` stays for the fills and
  /// hairline tints below, where it is decoration rather than something to read.
  Color get _accentInk => AppPalette.of(AppBrightness.current).primaryInk;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ProductProvider>();
    final label = productAudienceLabel(widget.audience) ?? 'Shelf';

    final shelf = context.select<ProductProvider, List<Map<String, dynamic>>>(
      (p) => p.productsInAudience(widget.audience),
    );

    // The chips are the categories this *shelf* holds — not the catalog's
    // vocabulary, which would offer filters that lead to an empty grid. A
    // category the shelf no longer holds stops being a chip, so it must stop
    // being the filter too: computed rather than assigned, so no build has to
    // mutate state to stay consistent.
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
                _buildTopBar(label, products.length, shelf.length),
                // No toolbar over an empty shelf: there is nothing to search,
                // filter or sort, and the empty state says what to do instead.
                if (shelf.isNotEmpty)
                  ProductShelfToolbar(
                    controller: _searchController,
                    hintText: 'Search in $label…',
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
                      ? _buildEmptyState(label)
                      : products.isEmpty
                          ? _buildNoMatchesState(label, shelf.length)
                          : _buildGrid(products),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar: back + the shelf's name and its count ──
  //
  // The count follows the GRID, not the shelf, once a search or a filter is
  // narrowing it (`3 of 10 pairs`) — a heading that counts products the
  // customer cannot see would be a lie. The sort control is not here any more;
  // it lives in the toolbar with the search field and the chips, which is where
  // the other shelf pages have it.
  Widget _buildTopBar(String label, int shown, int total) {
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
                Text(label, style: AppConstants.headlineStyle(fontSize: 20)),
                const SizedBox(height: 2),
                Text(
                  shelfCountLabel(shown: shown, total: total),
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

  /// Shown when the shelf has products but the search or the category filter
  /// left none of them. Deliberately *not* the shelf's empty state: nothing is
  /// wrong with the shelf, and the fix is to widen the question rather than to
  /// leave the page — so the action is "Clear filters", the only way back to
  /// the full list besides retyping.
  Widget _buildNoMatchesState(String label, int shelfSize) {
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
                ? 'Nothing in this category'
                : 'Nothing in $label matches "$query"',
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'The shelf still has '
            '${shelfSize == 1 ? '1 pair' : '$shelfSize pairs'} in it — clear '
            'the filters to see them.',
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
                  Icon(Icons.filter_alt_off_outlined,
                      size: 15, color: _accentInk),
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
}
