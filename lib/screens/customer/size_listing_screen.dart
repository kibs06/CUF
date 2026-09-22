import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../../constants/app_brightness.dart';
import '../../constants/app_constants.dart';
import '../../constants/app_palette.dart';
import '../../models/foot_measurement.dart';
import '../../providers/auth_provider.dart';
import '../../providers/foot_measurement_provider.dart';
import '../../providers/product_provider.dart';
import '../../utils/product_grid_ratio.dart';
import '../../utils/size_match.dart';
import '../../widgets/product_shelf_toolbar.dart';
import '../../widgets/sole_product_card.dart';
import 'product_detail_screen.dart';

/// The whole shelf behind the home feed's **See more** card: every product that
/// stocks the customer's saved size right now, uncapped.
///
/// The home section it opens from is honest about being a preview — the size
/// poster, ten products, and the arrow — so this page is what that arrow means:
/// the same shelf, same default order (the catalog's own shuffled order, the
/// one the preview also uses), with nothing taken away.
///
/// **It searches, filters and sorts *itself*.** A shelf of forty products is a
/// list a customer wants to narrow — by a word, by a category, by price — and
/// the only thing it may never do is narrow the shelf's *rule*: searching here
/// keeps "stocks my size" intact, just as sorting here keeps the home feed's
/// order intact. The state is local ([_query], [_category], [_sort]) and the
/// work is the provider's ([ProductProvider.shelfProducts], which reuses the
/// catalog's own [matchesSearchQuery] and sort), so this page cannot invent a
/// second meaning for "search" or for "Price: Low to High".
///
/// Why a page rather than growing the preview in place: the feed already
/// carries The Workshop Collection below this section, and a size shelf that
/// grew
/// without limit would either duplicate that grid or push it out of reach.
///
/// **Absent-safe, like every other size surface.** It reads the size the same
/// way the section does ([shoppingEuSizeFrom] — the profile snapshot first, then
/// a scan already in memory) and renders the empty state when there is no size
/// on file or nothing stocks it, never a guessed size. It reads the catalog
/// already in memory: no query, no network.
class SizeListingScreen extends StatefulWidget {
  const SizeListingScreen({super.key});

  @override
  State<SizeListingScreen> createState() => _SizeListingScreenState();
}

class _SizeListingScreenState extends State<SizeListingScreen> {
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

  /// Back to the whole shelf — what the empty-results state offers, since the
  /// shelf itself (which has products in it) is one tap away and its own empty
  /// state is a different thing entirely.
  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _category = null;
    });
  }

  /// Clay as INK, not as a fill — the same role the size card's value uses.
  /// `AppConstants.primary` is pinned (it is a fill other colours are drawn on),
  /// so at #8B5A2B it is only ~3.3:1 on the dark page, short of AA for the small
  /// labels this page draws.
  Color get _accentInk => AppPalette.of(AppBrightness.current).primaryInk;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final measurement = context
        .select<FootMeasurementProvider, FootMeasurement?>(
          (p) => p.latestMeasurement,
        );
    final euSize = shoppingEuSizeFrom(profile, measurement: measurement);

    final shelf = euSize == null
        ? const <Map<String, dynamic>>[]
        : context.select<ProductProvider, List<Map<String, dynamic>>>(
            (p) => p.productsInSize(euSize),
          );
    final provider = context.read<ProductProvider>();

    // The chips are the categories this *shelf* holds — not the catalog's
    // vocabulary, which would offer filters that lead to an empty grid. A
    // category that the shelf no longer holds stops being a chip, so it must
    // stop being the filter too: computed rather than assigned, so no build has
    // to mutate state to stay consistent.
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
                _buildTopBar(context, euSize, products.length, shelf.length),
                // No toolbar over an empty shelf: there is nothing to search,
                // filter or sort, and the empty state says what to do instead.
                if (shelf.isNotEmpty)
                  ProductShelfToolbar(
                    controller: _searchController,
                    hintText: 'Search in your size…',
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
                      : _buildGrid(products),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar: back + the shelf's name, its size and its count ──

  Widget _buildTopBar(
    BuildContext context,
    double? euSize,
    int shown,
    int total,
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
                  'Based on your size',
                  style: AppConstants.headlineStyle(fontSize: 20),
                ),
                const SizedBox(height: 2),
                // The size is named here, not just the count: the whole shelf is
                // a claim about what fits, so the number it was built on stays
                // visible (and correctable in Settings → Size Your Foot). The
                // count follows the grid, not the shelf, once a search or a
                // filter is narrowing it (`3 of 10 pairs`) — a heading that
                // counts products the customer cannot see would be a lie.
                Text(
                  shelfCountLabel(
                    shown: shown,
                    total: total,
                    qualifier: euSize == null ? null : euSizeLabel(euSize),
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
        // The same card and the same per-product ratio as the home grid, so a
        // product looks identical on both sides of the arrow.
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

  /// Shown when the shelf has products but the search or the filter left none
  /// of them. Deliberately *not* the shelf's empty state: nothing is wrong with
  /// the shelf, and the fix is to widen the question rather than to leave the
  /// page — so the action is "Clear filters", the only way back to the full
  /// list besides retyping.
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
                ? 'Nothing in this category'
                : 'Nothing in your size matches "$query"',
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'The shelf still has $shelfSize in it — clear the filters to see '
            'them.',
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

  /// Shown when there is no size on file, or nothing stocks it any more (a
  /// reload can empty the shelf while this page is open). Not a dead end: the
  /// way out is the same "Browse All Styles" the rest of the app uses.
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
              Icons.straighten_outlined,
              size: 34,
              color: _accentInk.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Nothing in your size right now',
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Add or update your size to see what fits, or browse the full '
            'catalog instead.',
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
