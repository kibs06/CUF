import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../providers/product_provider.dart';
import '../screens/customer/product_detail_screen.dart';
import '../screens/customer/recently_viewed_screen.dart';
import '../utils/product_grid_ratio.dart';
import 'sole_product_card.dart';

/// "Recently Viewed" grid on the customer profile — same masonry card style
/// as the Artisan Catalog on the home screen.
///
/// When more than four items exist (two full rows), the grid is capped at
/// that height, the bottom of the cut-off area fades into the page
/// background, and a centered "See more" pill sits in the fade. Tapping it
/// pushes the full [RecentlyViewedScreen] (the same "View all"-style
/// navigation the My Orders panel uses). With four or fewer items the grid
/// renders uncapped with no fade and no pill.
///
/// Cap and fade geometry are computed from the REAL rendered card heights:
/// the first four cards are measured offstage (same width, same widgets as
/// the grid) and a masonry column simulation derives the exact two-row
/// extent — no hardcoded per-device number. A generous provisional estimate
/// keeps the first frame stable until the probes are laid out.
class RecentlyViewedSection extends StatefulWidget {
  const RecentlyViewedSection({
    super.key,
    required this.items,
    this.onProductOpened,
  });

  final List<Map<String, dynamic>> items;
  final Future<void> Function()? onProductOpened;

  @override
  State<RecentlyViewedSection> createState() => _RecentlyViewedSectionState();
}

class _RecentlyViewedSectionState extends State<RecentlyViewedSection> {
  /// Number of cards kept visible before the fade — exactly two full rows.
  static const int _visibleItems = 4;
  static const double _spacing = 16;

  /// The fade band always covers the partial-card "poke" and never exceeds
  /// these bounds.
  static const double _minFadeHeight = 100;
  static const double _maxFadeHeight = 240;

  /// Generous first-frame estimate of one card's height (before the probes
  /// measure the real cards): image at the tallest ratio + text block.
  static double _provisionalCardHeight(double cellWidth) =>
      cellWidth / 0.78 + 140;

  final List<GlobalKey> _probeKeys =
      List.generate(_visibleItems, (_) => GlobalKey());

  /// Number of probes actually in the tree this build (min(4, item count)).
  int _probeCount = 0;

  /// Measured heights of the first up-to-4 cards at the current cell width,
  /// or null until the probes have been laid out once.
  List<double>? _probeHeights;
  bool _measurePending = false;
  bool _delayedMeasureScheduled = false;

  // ── Probe measurement ───────────────────────────────────────────

  void _scheduleMeasure() {
    if (_measurePending) return;
    _measurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurePending = false;
      if (mounted) _measureProbes();
    });
  }

  void _measureProbes() {
    final heights = <double>[];
    for (var i = 0; i < _probeCount; i++) {
      final size = _probeKeys[i].currentContext?.size;
      if (size == null) return; // not laid out yet — retry on next build
      heights.add(size.height);
    }
    if (_probeHeights == null ||
        _probeHeights!.length != heights.length ||
        !_heightsEqual(_probeHeights!, heights)) {
      setState(() => _probeHeights = heights);
      _scheduleDelayedReMeasures();
    }
  }

  /// GoogleFonts fetches the DM Sans / Playfair / Sora fonts at runtime, so
  /// text metrics can change a frame or two after first layout. Re-measure
  /// a couple of times so the cap settles on the real font metrics.
  void _scheduleDelayedReMeasures() {
    if (_delayedMeasureScheduled) return;
    _delayedMeasureScheduled = true;
    for (final delay in const [
      Duration(milliseconds: 400),
      Duration(milliseconds: 1400),
    ]) {
      Future.delayed(delay, () {
        if (mounted) _measureProbes();
      });
    }
  }

  bool _heightsEqual(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.5) return false;
    }
    return true;
  }

  // ── Cap + fade geometry (masonry column simulation) ────────────

  /// Total capped grid height (bottom of the 4th card) and the fade band
  /// height, derived from the measured card heights. Each card lands in the
  /// shortest column, exactly like the masonry delegate.
  (double cap, double fadeHeight) _capAndFade(List<double> heights) {
    double colA = 0, colB = 0;
    int countA = 0, countB = 0;
    for (final h in heights) {
      if (colA <= colB) {
        colA += h;
        countA++;
      } else {
        colB += h;
        countB++;
      }
    }
    final extA = colA + _spacing * (countA - 1);
    final extB = colB + _spacing * (countB - 1);
    final cap = math.max(extA, extB);

    // How far the 5th item pokes above the cap line (the gap between the two
    // columns). The fade always covers this poke so cut-off cards dissolve
    // into the background instead of being hard-clipped.
    final poke = math.max(0.0, cap - math.min(extA, extB));
    final fadeHeight = (poke + 60).clamp(_minFadeHeight, _maxFadeHeight);
    return (cap, fadeHeight);
  }

  // ── Build ──────────────────────────────────────────────────────

  Map<String, dynamic>? _liveProduct(
    ProductProvider provider,
    Map<String, dynamic> item,
  ) {
    return provider.products.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p?['id']?.toString() == item['id'],
          orElse: () => null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();

    // Only items that are still in the live catalog. Out-of-stock (now
    // hidden from browse) and deleted products are excluded so the grid
    // never shows a stale price with a dead tap.
    final liveItems = widget.items
        .where((item) => productProvider.products
            .any((p) => p['id']?.toString() == item['id']))
        .toList();

    if (liveItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.history_outlined,
              size: 14,
              color: AppConstants.secondary.withValues(alpha: 0.3),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Products you view will show up here',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = (constraints.maxWidth - _spacing) / 2;
        _probeCount = math.min(_visibleItems, liveItems.length);
        _scheduleMeasure();

        final needsCap = liveItems.length > _visibleItems;
        final heights = _probeHeights ??
            List.generate(
              _probeCount,
              (_) => _provisionalCardHeight(cellWidth),
            );
        final (cap, fadeHeight) = _capAndFade(heights);

        final grid = MasonryGridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: _spacing,
          mainAxisSpacing: _spacing,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: liveItems.length,
          itemBuilder: (context, index) {
            final item = liveItems[index];
            // Cards beyond the first four are partially hidden under the
            // fade — block their taps (card + sale tape) so a half-visible
            // card never responds to a tap.
            final tappable = !needsCap || index < _visibleItems;
            return _buildCard(productProvider, item, tappable: tappable);
          },
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recently Viewed',
              style: AppConstants.bodyStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (!needsCap)
              grid
            else
              SizedBox(
                height: cap,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(child: grid),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: fadeHeight,
                      child: _FadeFooter(
                        height: fadeHeight,
                        onSeeMore: _openAll,
                      ),
                    ),
                  ],
                ),
              ),
            // Offstage probes of the first cards — measured to size the cap.
            // Lays out but paints nothing and takes no room in the column.
            Offstage(
              offstage: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _probeCount; i++)
                    SizedBox(
                      width: cellWidth,
                      key: _probeKeys[i],
                      child: SoleProductCard(
                        product:
                            _liveProduct(productProvider, liveItems[i]) ??
                                const {},
                        imageAspectRatio: productGridRatio(liveItems[i]),
                        onTap: () {},
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCard(
    ProductProvider productProvider,
    Map<String, dynamic> item, {
    required bool tappable,
  }) {
    final fullProduct = _liveProduct(productProvider, item);
    final card = SoleProductCard(
      product: fullProduct ?? const {},
      imageAspectRatio: productGridRatio(fullProduct ?? item),
      onTap: () async {
        final resolved = _liveProduct(productProvider, item);
        if (resolved != null) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: resolved),
            ),
          );
        }
        // The tapped product moved to the front — let the owner reload.
        await widget.onProductOpened?.call();
      },
    );
    return tappable ? card : IgnorePointer(child: card);
  }

  Future<void> _openAll() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RecentlyViewedScreen(onProductOpened: widget.onProductOpened),
      ),
    );
    // The list order may have changed while away — re-measure next frame.
    if (mounted) _scheduleMeasure();
  }
}

/// The fade band at the bottom of the capped grid: a gradient from
/// transparent to the page background, with the centered "See more" pill.
/// The decorated container absorbs taps over the faded cards underneath.
class _FadeFooter extends StatelessWidget {
  const _FadeFooter({required this.height, required this.onSeeMore});

  final double height;
  final VoidCallback onSeeMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppConstants.surfaceLight.withValues(alpha: 0),
            AppConstants.surfaceLight,
          ],
        ),
      ),
      child: Center(child: _SeeMorePill(onTap: onSeeMore)),
    );
  }
}

class _SeeMorePill extends StatelessWidget {
  const _SeeMorePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppConstants.stadiumRadius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppConstants.stadiumRadius,
            boxShadow: AppConstants.warmShadow,
            border: Border.all(
              color: AppConstants.borderGray.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See more',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.secondary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.expand_more,
                size: 18,
                color: AppConstants.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}