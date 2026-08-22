import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/sale_price.dart';
import '../../utils/product_grid_ratio.dart';
import '../../constants/app_constants.dart';
import '../../providers/cart_provider.dart';
import '../../providers/message_provider.dart';
import '../../providers/product_provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/floating_message_button.dart';
import '../../widgets/no_internet_view.dart';
import '../../widgets/sole_product_card.dart';
import '../../widgets/shimmer_group.dart';
import '../../widgets/customer_foot_profile_banner.dart';
import '../../widgets/chat/chat_view.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';
import 'tracking_screen.dart';
import 'my_reports_screen.dart';
import 'widgets/home_hero.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final GlobalKey _catalogKey = GlobalKey();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchKeyword = '';
  StreamSubscription? _connectivitySub;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductProvider>(context, listen: false)
          .loadProducts(hideOutOfStock: true);
      // Load conversations for the floating message button badge
      _loadConversations();
      // Set up push notification deep link handler
      _initPushNotifications();
    });

    // Auto-refresh products when connection is restored after being offline
    _wasOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub =
        ConnectivityService.instance.isOnlineStream.listen((isOnline) {
      if (isOnline && _wasOffline && mounted) {
        Provider.of<ProductProvider>(context, listen: false)
            .loadProducts(hideOutOfStock: true);
      }
      _wasOffline = !isOnline;
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || !mounted) return;
    final msgProvider = context.read<MessageProvider>();
    // Always set up the realtime subscription first, even if the initial
    // load fails — so the badge updates when messages arrive.
    msgProvider.subscribeToInbox(customerId: userId);
    try {
      await msgProvider.loadConversationsForCustomer(userId);
    } catch (e) {
      debugPrint('[CustomerHome] Failed to load conversations: $e');
    }
  }

  /// Set up the push notification deep-link handlers.
  void _initPushNotifications() {
    PushNotificationService.instance.onNavigateToChat =
        (conversationId, storeName) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatView(
            conversationId: conversationId,
            viewerRole: 'customer',
            otherPartyName: storeName,
          ),
        ),
      );
    };

    PushNotificationService.instance.onNavigateToScreen =
        (screen, referenceId) {
      if (!mounted) return;
      switch (screen) {
        case 'order_tracking':
          if (referenceId == null) return;
          // orders.id is UUID — use string directly, with int fallback for legacy data.
          final orderIdValue = int.tryParse(referenceId) ?? referenceId;
          Supabase.instance.client
              .from('orders')
              .select('*, order_items(*, products(name))')
              .eq('id', orderIdValue)
              .single()
              .then((data) {
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrderTrackingScreen(order: data),
                ),
              );
            }
          }).catchError((e) {
            debugPrint('[Push] Failed to fetch order for deep-link: $e');
          });
          break;
        case 'my_reports':
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const MyReportsScreen(),
            ),
          );
          break;
      }
    };
  }

  void _showSortSheet(BuildContext context) {
    final productProvider = context.read<ProductProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppConstants.borderGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sort by',
              style: AppConstants.headlineStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            ...SortMode.values.map((mode) {
              final isActive = productProvider.sortMode == mode;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      isActive
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color:
                          isActive ? AppConstants.primary : AppConstants.borderGray,
                      size: 20,
                    ),
                    title: Text(
                      sortModeLabel(mode),
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                        color: isActive
                            ? AppConstants.primary
                            : AppConstants.secondary,
                      ),
                    ),
                    onTap: () {
                      productProvider.setSortMode(mode);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final cartCount = context.select<CartProvider, int>((p) => p.itemCount);
    final allProducts = productProvider.products;
    final filteredProducts =
        productProvider.getFilteredProducts(_searchKeyword);
    // Products currently on sale — powers the dedicated "On Sale" sliver.
    final saleProducts =
        allProducts.where(isOnSale).toList();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      // No AppBar — the HomeHero provides its own icon row that bleeds
      // behind the status bar for the full-bleed effect.
      body: Stack(
        children: [
          // Noise texture overlay (base layer)
          AppConstants.noiseOverlay(opacity: 0.03),

          // Main scrollable content: hero behind, sheet overlapping on top
          RefreshIndicator(
            color: AppConstants.primary,
            onRefresh: () async {
              await Provider.of<ProductProvider>(context, listen: false)
                  .loadProducts(hideOutOfStock: true);
            },              child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Hero (full-bleed, extends behind status bar) ──
                SliverToBoxAdapter(
                  child: HomeHero(
                    cartCount: cartCount,
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    onSearchChanged: (val) {
                      setState(() => _searchKeyword = val);
                    },
                    onCartTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CartScreen(),
                        ),
                      );
                    },
                    onCtaTap: () {
                      // Scroll down to the product catalog
                      final ctx = _catalogKey.currentContext;
                      if (ctx != null) {
                        Scrollable.ensureVisible(
                          ctx,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    onProductTap: (product) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductDetailScreen(product: product),
                        ),
                      );
                    },
                  ),
                ),

                // ── Sheet (overlaps hero bottom, rounded top corners) ──
                SliverToBoxAdapter(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    child: ColoredBox(
                      color: AppConstants.surfaceLight,
                      child: Column(
                        children: [
                          const SizedBox(height: 6),

                          // Foot-profile reminder (conditional)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                            child: CustomerFootProfileBanner(),
                          ),

                          // ── On Sale section ──
                          if (_searchKeyword.isEmpty &&
                              saleProducts.isNotEmpty &&
                              (productProvider.selectedCategory == null ||
                                  productProvider.selectedCategory ==
                                      'All')) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 4, 20, 10),
                              child: Row(
                                children: [
                                  Text(
                                    'On Sale',
                                    style: AppConstants.headlineStyle(
                                        fontSize: 16),
                                  ),
                                  const SizedBox(width: 10),
                                  const _PriceTagBadge(label: 'HOT DEALS'),
                                ],
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              // NOTE: deliberately a plain SliverGrid, NOT masonry.
                              // Two SliverMasonryGrids in one CustomScrollView trigger a
                              // scroll-offset-correction loop in flutter_staggered_grid_view
                              // 0.7.0 that yanks the viewport back partway down the page
                              // — making the bottom of a long catalog unreachable. The
                              // catalog grid below keeps masonry; this small section uses
                              // a deterministic grid (exact extent, no estimation).
                              child: GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: 0.58,
                                ),
                                itemCount: saleProducts.length,
                                itemBuilder: (context, index) {
                                  final prod = saleProducts[index];
                                  return SoleProductCard(
                                    product: prod,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ProductDetailScreen(
                                                  product: prod),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // ── Catalog header + sort ──
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child:                                  Text(
                                    'Artisan Catalog',
                                    style: AppConstants.headlineStyle(
                                        fontSize: 20),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _showSortSheet(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppConstants.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppConstants.primary
                                            .withValues(alpha: 0.15),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.sort_outlined,
                                          size: 14,
                                          color: AppConstants.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          sortModeLabel(
                                              productProvider.sortMode),
                                          style: AppConstants.bodyStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppConstants.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ── Product grid ──
                          if (productProvider.isLoading)
                            ConnectivityService.instance.isOnline
                                ? const _CatalogSkeletonGrid()
                                : NoInternetView(
                                    onRetry: () =>
                                        Provider.of<ProductProvider>(
                                            context,
                                            listen: false)
                                            .loadProducts(
                                                hideOutOfStock: true),
                                  )
                          else if (allProducts.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 48),
                              child: Column(
                                children: [
                                  Icon(Icons.search_off,
                                      size: 48,
                                      color: AppConstants.primary
                                          .withValues(alpha: 0.5)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No shoes match your criteria.',
                                    style: AppConstants.bodyStyle(
                                        color: AppConstants.secondary
                                            .withValues(alpha: 0.6)),
                                  ),
                                ],
                              ),
                            )
                          else
                            MasonryGridView.count(
                              key: _catalogKey,
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              physics: const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              itemCount: filteredProducts.length,
                              itemBuilder: (context, index) {
                                final prod = filteredProducts[index];
                                return SoleProductCard(
                                  product: prod,
                                  imageAspectRatio: productGridRatio(prod),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            ProductDetailScreen(
                                                product: prod),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),

                          // Bottom spacing for nav bar
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Floating chat button — only on Home tab
          const FloatingMessageButton(),
        ],
      ),
    );
  }

}

/// A price-tag shaped badge (punched hole + pointed right edge) used to
/// emphasize section labels like "HOT DEALS".
class _PriceTagBadge extends StatelessWidget {
  const _PriceTagBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _PriceTagPainter(color: Color(0xFFFFC107)),
      child: Padding(
        padding: const EdgeInsets.only(left: 22, right: 18, top: 5, bottom: 5),
        child: Text(
          label,
          style: AppConstants.monoStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Color(0xFF3B2314),
          ).copyWith(letterSpacing: 0.5),
        ),
      ),
    );
  }
}

class _PriceTagPainter extends CustomPainter {
  const _PriceTagPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const pointWidth = 12.0;
    const holeRadius = 6.0;
    final holeCenter = Offset(14, size.height / 2);

    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width - pointWidth, size.height),
          const Radius.circular(4),
        ),
      )
      ..moveTo(size.width - pointWidth, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width - pointWidth, size.height)
      ..close()
      ..addOval(Rect.fromCircle(center: holeCenter, radius: holeRadius));

    canvas.drawShadow(
      path,
      Colors.black.withValues(alpha: 0.25),
      2,
      false,
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PriceTagPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Skeleton placeholder for a single catalog product card (loading state).
class _ProductCardSkeleton extends StatelessWidget {
  const _ProductCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: double.infinity, height: 150, borderRadius: 8),
          SizedBox(height: 10),
          SkeletonBox(width: double.infinity, height: 14),
          SizedBox(height: 6),
          SkeletonBox(width: 90, height: 12),
          SizedBox(height: 8),
          SkeletonBox(width: 70, height: 16),
        ],
      ),
    );
  }
}

/// 2-column grid of skeleton product cards under one shimmer wave.
class _CatalogSkeletonGrid extends StatelessWidget {
  const _CatalogSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return ShimmerGroup(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            for (int row = 0; row < 3; row++) ...[
              const Row(
                children: [
                  Expanded(child: _ProductCardSkeleton()),
                  SizedBox(width: 16),
                  Expanded(child: _ProductCardSkeleton()),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}
