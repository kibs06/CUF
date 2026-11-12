import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../providers/product_provider.dart';
import '../../providers/review_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/product_grid_ratio.dart';
import '../../widgets/sole_product_card.dart';
import '../../widgets/sole_star_rating.dart';
import '../../widgets/two_column_masonry.dart';
import 'seller_product_reviews_screen.dart';

/// Seller-facing reviews, grouped by product and drawn as a masonry grid.
///
/// Shows one customer-style tile per product that has at least one review
/// OR at least one sale. Tapping a tile opens the seller's product page —
/// the same look as the customer's product view, but reviews-only, where
/// the seller answers each review.
class SellerReviewsScreen extends StatefulWidget {
  final String storeId;

  const SellerReviewsScreen({super.key, required this.storeId});

  @override
  State<SellerReviewsScreen> createState() => _SellerReviewsScreenState();
}

class _SellerReviewsScreenState extends State<SellerReviewsScreen> {
  /// product_id → units sold (global aggregation, filtered to this store).
  Map<String, int> _unitsSold = {};
  bool _loadingUnits = true;

  /// 'all' | 'reviewed' | 'unreviewed' (sold but no reviews yet).
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReviewProvider>().loadStoreReviews(widget.storeId);
      context.read<ProductProvider>().loadSellerProducts();
      _loadUnits();
    });
  }

  Future<void> _loadUnits() async {
    try {
      final units = await SupabaseService.instance.fetchUnitsSold();
      if (mounted) setState(() => _unitsSold = units);
    } catch (_) {
      // Counts are enrichment — the list stands without them.
    } finally {
      if (mounted) setState(() => _loadingUnits = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      context.read<ReviewProvider>().loadStoreReviews(widget.storeId),
      context.read<ProductProvider>().loadSellerProducts(),
      _loadUnits(),
    ]);
  }

  void _openProduct(_ProductGroup group, Map<String, dynamic> product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SellerProductReviewsScreen(
          product: product,
          storeId: widget.storeId,
          sold: group.sold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.chrome,
        elevation: 0,
        title: Text(
          'Customer Reviews',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Consumer2<ReviewProvider, ProductProvider>(
        builder: (context, reviews, products, _) {
          if (reviews.isLoadingStoreReviews && reviews.storeReviews.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppConstants.primary),
            );
          }

          final groups = _buildGroups(
            allReviews: reviews.storeReviews,
            catalog: products.products,
          );

          if (groups.isEmpty) {
            // A failed load must never look like "no reviews" — the seller
            // in the screenshot had a review that a failed query hid.
            final loadError = reviews.errorMessage;
            if (loadError != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_outlined,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Could not load reviews',
                        style: AppConstants.bodyStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        loadError,
                        textAlign: TextAlign.center,
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color: AppConstants.secondary.withAlpha(153),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _refreshAll,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.primary,
                        ),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppConstants.primary.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.rate_review_outlined,
                        size: 34,
                        color: AppConstants.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No reviews yet',
                      style: AppConstants.bodyStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Products appear here once they\nsell or receive a review.',
                      textAlign: TextAlign.center,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.secondary.withAlpha(153),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final visible = groups.where((g) {
            if (_filter == 'reviewed') return g.reviews.isNotEmpty;
            if (_filter == 'unreviewed') return g.reviews.isEmpty;
            return true;
          }).toList();

          final totalSold = groups.fold<int>(0, (sum, g) => sum + g.sold);
          final reviewedCount =
              groups.where((g) => g.reviews.isNotEmpty).length;

          return RefreshIndicator(
            color: AppConstants.primary,
            onRefresh: _refreshAll,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                // Summary card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SellerTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SellerTheme.cardBorder),
                    boxShadow: AppConstants.sellerShadow,
                  ),
                  child: Row(
                    children: [
                      Column(
                        children: [
                          Text(
                            _overallAvg(groups).toStringAsFixed(2),
                            style: AppConstants.monoStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.secondary,
                            ),
                          ),
                          SoleStarRating(
                            rating: _overallAvg(groups),
                            size: 16,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${reviews.storeReviews.length} review${reviews.storeReviews.length == 1 ? '' : 's'}',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withAlpha(128),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '$reviewedCount product${reviewedCount == 1 ? '' : 's'} reviewed'
                          '${_loadingUnits ? '' : ' • $totalSold sold'}',
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            color: AppConstants.secondary.withAlpha(179),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Filter chips
                Wrap(
                  spacing: 8,
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: _filter == 'all',
                      onTap: () => setState(() => _filter = 'all'),
                    ),
                    _FilterChip(
                      label: 'With reviews',
                      selected: _filter == 'reviewed',
                      onTap: () => setState(() => _filter = 'reviewed'),
                    ),
                    _FilterChip(
                      label: 'No reviews yet',
                      selected: _filter == 'unreviewed',
                      onTap: () => setState(() => _filter = 'unreviewed'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        _filter == 'unreviewed'
                            ? 'Every selling product has a review. Nice!'
                            : 'No products match this filter.',
                        style: AppConstants.bodyStyle(
                          fontSize: 14,
                          color: AppConstants.secondary.withAlpha(153),
                        ),
                      ),
                    ),
                  )
                else
                  TwoColumnMasonry(
                    margin: 0,
                    gutter: AppConstants.productGridGutter,
                    children: [
                      for (final g in visible)
                        Builder(
                          builder: (context) {
                            final raw =
                                _rawProduct(products.products, g);
                            if (raw == null) {
                              return const SizedBox.shrink();
                            }
                            return _ReviewTile(
                              group: g,
                              rawProduct: raw,
                              onTap: () => _openProduct(g, raw),
                            );
                          },
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The catalog row behind a group, so the detail page gets the full
  /// product map (gallery, price, sale). Orphan groups (deleted products)
  /// carry no row and are not tappable.
  Map<String, dynamic>? _rawProduct(
    List<Map<String, dynamic>> catalog,
    _ProductGroup group,
  ) {
    if (group.productId.isEmpty) return null;
    for (final p in catalog) {
      if (p['id']?.toString() == group.productId) return p;
    }
    return null;
  }

  double _overallAvg(List<_ProductGroup> groups) {
    var total = 0;
    var count = 0;
    for (final g in groups) {
      for (final r in g.reviews) {
        total += ((r['rating'] as num?)?.toInt() ?? 0);
        count++;
      }
    }
    if (count == 0) return 0;
    return total / count;
  }

  /// Join the seller catalog with reviews + sold counts, keeping only
  /// products that have at least one review OR at least one sale.
  /// Reviews for products missing from the catalog (deleted) are kept as
  /// orphan rows so no review is silently lost.
  List<_ProductGroup> _buildGroups({
    required List<Map<String, dynamic>> allReviews,
    required List<Map<String, dynamic>> catalog,
  }) {
    final reviewsByPid = <String, List<Map<String, dynamic>>>{};
    for (final r in allReviews) {
      final pid = r['product_id']?.toString() ?? '';
      if (pid.isEmpty) continue;
      reviewsByPid.putIfAbsent(pid, () => []).add(r);
    }

    final storeProducts = catalog.where((p) {
      final sid = p['store_id']?.toString();
      // The provider may briefly hold another scope (customer catalog);
      // only this store's rows belong here.
      return sid == null || sid.isEmpty || sid == widget.storeId;
    }).toList();

    final groups = <_ProductGroup>[];
    final seen = <String>{};

    for (final p in storeProducts) {
      final pid = p['id']?.toString() ?? '';
      if (pid.isEmpty || !seen.add(pid)) continue;
      final reviews = reviewsByPid[pid] ?? const [];
      final sold = _unitsSold[pid] ?? ((p['units_sold'] as num?)?.toInt() ?? 0);
      // The rule: reviewed OR sold.
      if (reviews.isEmpty && sold <= 0) continue;
      groups.add(_ProductGroup(
        productId: pid,
        reviews: List.of(reviews),
        sold: sold,
      ));
    }

    // Orphan reviews — product gone from the catalog but reviews remain.
    for (final entry in reviewsByPid.entries) {
      if (seen.contains(entry.key)) continue;
      groups.add(_ProductGroup(
        productId: entry.key,
        reviews: List.of(entry.value),
        sold: 0,
      ));
    }

    // Sellers triage by attention: unreplied first, then most reviewed,
    // then best selling.
    int unreplied(List<Map<String, dynamic>> rs) => rs
        .where((r) => (r['seller_reply']?.toString() ?? '').isEmpty)
        .length;
    groups.sort((a, b) {
      final ua = unreplied(a.reviews).compareTo(unreplied(b.reviews));
      if (ua != 0) return -ua;
      final rc = a.reviews.length.compareTo(b.reviews.length);
      if (rc != 0) return -rc;
      return -a.sold.compareTo(b.sold);
    });
    return groups;
  }
}

class _ProductGroup {
  final String productId;
  final List<Map<String, dynamic>> reviews;
  final int sold;

  _ProductGroup({
    required this.productId,
    required this.reviews,
    required this.sold,
  });

  double get avgRating {
    if (reviews.isEmpty) return 0;
    final total = reviews.fold<int>(
      0,
      (sum, r) => sum + (((r['rating'] as num?)?.toInt() ?? 0)),
    );
    return total / reviews.length;
  }

  int get needsReply => reviews
      .where((r) => (r['seller_reply']?.toString() ?? '').isEmpty)
      .length;
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppConstants.primary : SellerTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppConstants.primary : SellerTheme.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : AppConstants.secondary,
          ),
        ),
      ),
    );
  }
}

/// One masonry cell: the customer's own product card (same photo, name,
/// stars, price and sold count the shopper sees) with a slim seller strip
/// underneath — review count plus a "needs reply" pill when the seller
/// has reviews to answer. Tapping opens the seller's reviews-only
/// product page.
class _ReviewTile extends StatelessWidget {
  final _ProductGroup group;
  final Map<String, dynamic> rawProduct;
  final VoidCallback onTap;

  const _ReviewTile({
    required this.group,
    required this.rawProduct,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // The card reads its numbers off the product map, so hand it a copy
    // stamped with this group's review stats and sold count.
    final stamped = Map<String, dynamic>.of(rawProduct)
      ..['avg_rating'] = group.avgRating
      ..['review_count'] = group.reviews.length
      ..['units_sold'] = group.sold;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoleProductCard(
          product: stamped,
          imageAspectRatio: productGridRatio(stamped),
          onTap: onTap,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
          child: group.reviews.isEmpty
              ? Text(
                  'No reviews yet',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withAlpha(128),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${group.reviews.length} review${group.reviews.length == 1 ? '' : 's'}',
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          color:
                              AppConstants.secondary.withAlpha(153),
                        ),
                      ),
                    ),
                    if (group.needsReply > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${group.needsReply} need${group.needsReply == 1 ? 's' : ''} reply',
                          style: AppConstants.bodyStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
