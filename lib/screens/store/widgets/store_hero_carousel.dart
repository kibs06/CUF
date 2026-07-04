import 'package:flutter/material.dart';
import '../../../models/store.dart';
import '../../../constants/app_constants.dart';
import 'store_hero_card.dart';

/// Hero store carousel with peek effect, scale animation, and page dots.
/// Shows one store card at a time with neighboring cards peeking at the edges.
class StoreHeroCarousel extends StatefulWidget {
  final List<Store> stores;
  final PageController pageController;
  final ValueChanged<int> onStoreChanged;
  final int currentIndex;
  final Map<String, int> productCounts;

  const StoreHeroCarousel({
    super.key,
    required this.stores,
    required this.pageController,
    required this.onStoreChanged,
    required this.currentIndex,
    required this.productCounts,
  });

  @override
  State<StoreHeroCarousel> createState() => _StoreHeroCarouselState();
}

class _StoreHeroCarouselState extends State<StoreHeroCarousel> {
  double _currentPageValue = 0.0;

  @override
  void initState() {
    super.initState();
    widget.pageController.addListener(_onPageScroll);
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_onPageScroll);
    super.dispose();
  }

  void _onPageScroll() {
    if (widget.pageController.hasClients) {
      setState(() {
        _currentPageValue = widget.pageController.page ?? 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Carousel
        SizedBox(
          height: 280,
          child: PageView.builder(
            controller: widget.pageController,
            pageSnapping: true,
            onPageChanged: widget.onStoreChanged,
            itemCount: widget.stores.length,
            itemBuilder: (context, index) {
              final store = widget.stores[index];
              // Calculate scale based on distance from current page
              final distance = (_currentPageValue - index).abs();
              final scale = (1 - (distance * 0.05)).clamp(0.95, 1.0);

              return StoreHeroCard(
                store: store,
                scale: scale,
                productCount:
                    widget.productCounts[store.id] ?? 0,
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        // Page indicator dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.stores.length, (index) {
            final isActive = widget.currentIndex == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isActive ? 20 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isActive
                    ? AppConstants.accent
                    : AppConstants.secondary.withAlpha(76),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}
