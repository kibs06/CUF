import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// The product card's photo area: every image the product has, one per page,
/// swiped sideways, with the dots that say there is more than one.
///
/// **It is not a second tap target.** The pager claims horizontal drags (it is
/// a [PageView], so the feed's vertical scroll and the card's own tap both keep
/// working the way they did: a [PageView] answers drags only, so a tap on the
/// photo still reaches the card's `PressSink` and opens the product).
///
/// **The dots and the sale band share one edge.** Both are pinned to the bottom
/// of the photo, so they are stacked here rather than positioned over each
/// other: the dots sit *above* the countdown band when a sale has an end date,
/// and on the image's own bottom edge when it does not — no magic number for
/// the band's height, and the two can never overlap.
class ProductImagePager extends StatefulWidget {
  const ProductImagePager({
    super.key,
    required this.images,
    this.bottomOverlay,
  });

  /// The photos to page through, in the seller's order — see
  /// `productImageUrls`. Expected non-empty; an empty list renders nothing (the
  /// card falls back to its own placeholder photo before getting here).
  final List<String> images;

  /// A band pinned to the photo's bottom edge — the sale countdown. The dots
  /// stack above it.
  final Widget? bottomOverlay;

  /// The dot row, for tests that need to find it (or prove it is absent on a
  /// product with a single photo).
  static const Key dotsKey = Key('product-image-dots');

  /// The size of a resting dot, and the width of the one for the current photo.
  static const double dotSize = 4;
  static const double activeDotWidth = 12;

  /// How far the dots sit off the photo's bottom edge when nothing else is
  /// pinned there.
  static const double dotsInset = 6;

  @override
  State<ProductImagePager> createState() => _ProductImagePagerState();
}

class _ProductImagePagerState extends State<ProductImagePager> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void didUpdateWidget(covariant ProductImagePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(oldWidget.images, widget.images)) return;

    // The grids rebuild cells in place, so this State can be handed a different
    // product mid-swipe — the offset would carry over and the card would open
    // on image 3 of a product that has one. Reset after the frame, when the new
    // page is laid out (jumping to a page before the new itemCount exists is
    // clamped away, and the dots would then describe the wrong photo).
    if (_page == 0) return;
    _page = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) _controller.jumpToPage(0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return const SizedBox.shrink();

    final bool swipeable = widget.images.length > 1;
    final overlay = widget.bottomOverlay;

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.images.length,
          onPageChanged: (page) => setState(() => _page = page),
          itemBuilder: (context, index) => CachedNetworkImage(
            imageUrl: widget.images[index],
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (context, url) => Container(
              color: AppConstants.borderGray.withValues(alpha: 0.3),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppConstants.primary),
                  ),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: AppConstants.borderGray.withValues(alpha: 0.3),
              child: const Icon(
                Icons.broken_image_outlined,
                color: AppConstants.primary,
              ),
            ),
          ),
        ),
        if (swipeable || overlay != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [if (swipeable) _dots(), ?overlay],
            ),
          ),
      ],
    );
  }

  /// One mark per photo: a small dot each, with the current one widened into a
  /// pill. On a photograph they need their own edge, so each carries a soft
  /// shadow — plain white on a pale shot would simply disappear.
  Widget _dots() {
    return Padding(
      padding: const EdgeInsets.only(bottom: ProductImagePager.dotsInset),
      child: Row(
        key: ProductImagePager.dotsKey,
        mainAxisAlignment: MainAxisAlignment.center,
        // Space between the dots, rather than a margin on each of them: a
        // margin would be part of the Container's own box.
        spacing: 4,
        children: [
          for (var index = 0; index < widget.images.length; index++)
            Container(
              key: ValueKey('product-image-dot-$index'),
              width: index == _page
                  ? ProductImagePager.activeDotWidth
                  : ProductImagePager.dotSize,
              height: ProductImagePager.dotSize,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: index == _page ? 0.95 : 0.5,
                ),
                borderRadius: BorderRadius.circular(
                  ProductImagePager.dotSize / 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
