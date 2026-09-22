import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/product_provider.dart';
import '../../services/search_history_service.dart';
import '../../utils/product_grid_ratio.dart';
import '../../widgets/product_rail_section.dart';
import '../../widgets/product_sort_chip.dart';
import '../../widgets/sole_product_card.dart';
import '../../widgets/underline_category_chip.dart';
import 'product_detail_screen.dart';

/// The search results page — where the customer's query actually lands.
///
/// Why a page and not an inline filter of the Home feed: filtering Home in
/// place left the customer *in* the search with no way out. The feed was
/// narrowed, the search bar was read-only, neither bar had a clear button, and
/// backing out of the search page silently kept the old keyword — so a query
/// that matched nothing (e.g. "Formal Shoes", which matched no product *name*
/// or *tag*) was a dead end. A destination you can pop is the fix, and it is
/// also the pattern every shop app uses.
///
/// What it owns:
///
///  * its **own query** — editable, with a clear button, re-running in place;
///  * its **own category filter and sort**, held locally and passed to
///    [ProductProvider.searchResults], so opening a search can never re-sort or
///    re-filter the Home feed underneath it;
///  * the **no-match panel**: a "Popular right now" rail rather than an empty
///    page, so no query is a dead end ([ProductProvider.relatedProducts]).
///
/// The matching rule is not local — it is [matchesSearchQuery] via the
/// provider, so this page and the search suggestion panel agree by
/// construction about what a term means.
class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({super.key, required this.initialQuery});

  /// The term the customer committed. Empty is allowed (the page then invites
  /// a search rather than claiming nothing matched).
  final String initialQuery;

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  late final TextEditingController _controller;

  late String _query;

  /// null = every category. Local on purpose — see the class doc.
  String? _category;

  SortMode _sort = SortMode.featured;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
    _controller = TextEditingController(text: _query);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Run [raw] as the active query. Recorded in history only when it is a real
  /// term, so clearing the field does not log an empty search.
  void _submit(String raw) {
    final term = raw.trim();
    if (term.isNotEmpty) SearchHistoryService.instance.record(term);
    setState(() => _query = term);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();

    // The chips are the categories this query actually found — not the whole
    // catalog's vocabulary. `provider.categories` starts with 'All' (which this
    // page renders itself, so using it printed two All chips) and includes
    // categories with nothing in them, each a chip leading to "0 results".
    final categories = provider.searchCategories(_query);
    // A category that no longer matches the query stops being a chip, so it
    // must stop being the filter too — computed rather than assigned, so no
    // build has to mutate state to stay consistent.
    final selectedCategory = _category != null && categories.contains(_category)
        ? _category
        : null;

    final results = _query.isEmpty
        ? const <Map<String, dynamic>>[]
        : provider.searchResults(
            _query,
            category: selectedCategory,
            sort: _sort,
          );
    // Fetched unconditionally but only rendered in the empty case — it is a
    // sort of the already-loaded catalog, so this costs no request.
    final related = provider.relatedProducts();

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
                _buildTopBar(),
                Divider(height: 1, color: AppConstants.borderGray),
                if (_query.isNotEmpty)
                  _buildFilterBar(categories, results.length, selectedCategory),
                Expanded(
                  child: _query.isEmpty
                      ? _buildPanel(
                          related,
                          title: 'Search the collection',
                          subtitle:
                              'A style, a material or a color — like '
                              '“loafers” or “handmade”.',
                        )
                      : results.isEmpty
                      ? _buildPanel(
                          related,
                          title: 'No matches for "$_query"',
                          subtitle:
                              'Try a shorter word, or start from '
                              "what's selling.",
                        )
                      : _buildGrid(results),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar: back + editable field (with clear) + search button ──

  Widget _buildTopBar() {
    final hasText = _controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppConstants.secondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: AppConstants.surfaceLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppConstants.secondary, width: 1.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: false,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _submit,
                      onChanged: (_) => setState(() {}),
                      style: AppConstants.bodyStyle(
                        fontSize: 15,
                        color: AppConstants.secondary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search leather shoes…',
                        hintStyle: AppConstants.bodyStyle(
                          fontSize: 15,
                          color: AppConstants.secondary.withValues(alpha: 0.4),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  // Clear — the one affordance the old inline search never had.
                  // It empties the field AND the results, so the customer is
                  // never left staring at a page they cannot leave.
                  if (hasText)
                    GestureDetector(
                      onTap: () {
                        _controller.clear();
                        _submit('');
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: AppConstants.secondary.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: () => _submit(_controller.text),
                    child: Container(
                      width: 52,
                      height: double.infinity,
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppConstants.chrome,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.search,
                        color: Colors.white,
                        size: 22,
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

  // ── Filter bar: category chips + sort ──

  Widget _buildFilterBar(
    List<String> categories,
    int resultCount,
    String? selectedCategory,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 42,
          child: Row(
            children: [
              // One 'All' chip, and only when there is something to choose
              // between: with a single category (or none) a lone 'All' is noise.
              if (categories.isNotEmpty)
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    // 12 + the chip's own 8 keeps the first label aligned with
                    // the result count below it (both at 20).
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      UnderlineCategoryChip(
                        label: 'All',
                        selected: selectedCategory == null,
                        indicatorKey: const ValueKey('search-underline-All'),
                        onTap: () => setState(() => _category = null),
                      ),
                      for (final category in categories)
                        UnderlineCategoryChip(
                          label: category,
                          selected: selectedCategory == category,
                          indicatorKey: ValueKey('search-underline-$category'),
                          onTap: () => setState(() => _category = category),
                        ),
                    ],
                  ),
                )
              else
                const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 16, left: 8),
                child: _sortChip(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
          child: Text(
            resultCount == 1
                ? '1 result for "$_query"'
                : '$resultCount results for "$_query"',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.55),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sortChip() => ProductSortChip(
    sort: _sort,
    onSelected: (mode) => setState(() => _sort = mode),
  );

  // ── Results ──

  Widget _buildGrid(List<Map<String, dynamic>> results) {
    return MasonryGridView.count(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppConstants.feedMargin,
        12,
        AppConstants.feedMargin,
        32,
      ),
      crossAxisCount: 2,
      crossAxisSpacing: AppConstants.productGridGutter,
      mainAxisSpacing: AppConstants.productGridGutter,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final prod = results[index];
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

  /// The panel shown when there is nothing to list — either nothing matched or
  /// nothing has been typed. It always carries products, so the page never ends
  /// in blank space.
  Widget _buildPanel(
    List<Map<String, dynamic>> related, {
    required String title,
    required String subtitle,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
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
              size: 36,
              color: AppConstants.primary.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              // Back to the feed: close the search pages entirely rather than
              // leaving the customer inside a search they abandoned.
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
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
                    Icons.category_outlined,
                    size: 15,
                    color: AppConstants.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Browse All Styles',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (related.isNotEmpty) ...[
            const SizedBox(height: 8),
            // The shared rail: header + cards + its own trailing spacing, so
            // this panel is one widget rather than a bespoke carousel.
            ProductRailSection(title: 'Popular right now', products: related),
          ],
        ],
      ),
    );
  }
}
