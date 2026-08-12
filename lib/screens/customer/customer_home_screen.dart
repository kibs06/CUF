import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/recently_viewed.dart';
import '../../utils/sale_price.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/message_provider.dart';
import '../../providers/product_provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/floating_message_button.dart';
import '../../widgets/no_internet_view.dart';
import '../../widgets/sole_product_card.dart';
import '../../widgets/sale_price_tape.dart';
import '../../widgets/sale_countdown_overlay.dart';
import '../../widgets/shimmer_group.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/customer_foot_profile_banner.dart';
import '../../widgets/chat/chat_view.dart';
import 'product_detail_screen.dart';
import 'tracking_screen.dart';
import 'my_reports_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final PageController _bannerController = PageController();
  int _bannerIndex = 0;
  Timer? _bannerTimer;
  String _searchKeyword = '';
  StreamSubscription? _connectivitySub;
  bool _wasOffline = false;

  // Recently viewed products
  List<Map<String, dynamic>> _recentlyViewed = [];

  // Featured items mock data for the banner PageView
  final List<Map<String, String>> _featuredArrivals = [
    {
      'title': 'The Carcar Craft Revolution',
      'subtitle': 'Discover vegetable-tanned custom designs',
      'image': 'https://images.unsplash.com/photo-1549298916-b41d501d3772?q=80&w=800&auto=format&fit=crop',
    },
    {
      'title': 'Signature Cordwainer Series',
      'subtitle': 'Double welted artisan soles built for steps',
      'image': 'https://images.unsplash.com/photo-1533867617858-e7b97e060509?q=80&w=800&auto=format&fit=crop',
    },
    {
      'title': 'Summertime Leather Sandals',
      'subtitle': 'Crafted using sustainable leather cuts',
      'image': 'https://images.unsplash.com/photo-1543163521-1bf539c55dd2?q=80&w=800&auto=format&fit=crop',
    }
  ];

  @override
  void initState() {
    super.initState();
    _loadRecentlyViewed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductProvider>(context, listen: false).loadProducts(hideOutOfStock: true);
      // Load conversations for the floating message button badge
      _loadConversations();
      // Set up push notification deep link handler
      _initPushNotifications();
    });

    // Auto-refresh products when connection is restored after being offline
    _wasOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.isOnlineStream.listen((isOnline) {
      if (isOnline && _wasOffline && mounted) {
        Provider.of<ProductProvider>(context, listen: false).loadProducts(hideOutOfStock: true);
      }
      _wasOffline = !isOnline;
    });

    // Auto-scroll PageView banner every 4 seconds
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_bannerController.hasClients) {
        setState(() {
          _bannerIndex = (_bannerIndex + 1) % _featuredArrivals.length;
        });
        _bannerController.animateToPage(
          _bannerIndex,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadRecentlyViewed() async {
    final items = await RecentlyViewedService.instance.load();
    if (mounted) {
      setState(() => _recentlyViewed = items);
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _searchController.dispose();
    _bannerController.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  /// Deterministic image aspect ratio per card keyed off product id
  /// so a card's height stays stable across filtering/re-sorting.
  double _imageAspectRatioFor(dynamic product) {
    const ratios = [1.0, 0.78, 1.22, 0.95];
    final id = product['id']?.toString() ?? '';
    final key = id.isEmpty ? 0 : id.hashCode;
    return ratios[key.abs() % ratios.length];
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
    PushNotificationService.instance.onNavigateToChat = (conversationId, storeName) {
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

    PushNotificationService.instance.onNavigateToScreen = (screen, referenceId) {
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
                      isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: isActive ? AppConstants.primary : AppConstants.borderGray,
                      size: 20,
                    ),
                    title: Text(
                      sortModeLabel(mode),
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        color: isActive ? AppConstants.primary : AppConstants.secondary,
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
    final auth = context.watch<AuthProvider>();
    final productProvider = context.watch<ProductProvider>();
    final filteredProducts = productProvider.getFilteredProducts(_searchKeyword);
    // Products currently on sale — powers the dedicated "On Sale" sliver.
    final saleProducts = productProvider.products.where(isOnSale).toList();
    // Recently-viewed items still in the live catalog. Out-of-stock (now
    // hidden from browse) and deleted products are excluded so the strip
    // never shows a stale price with a dead tap.
    final recentlyViewedItems = _recentlyViewed
        .where((item) => productProvider.products.any(
            (p) => p['id']?.toString() == item['id']))
        .toList();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'CUFMAI',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: const [CartIconButton()],
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SafeArea(
            child: RefreshIndicator(
              color: AppConstants.primary,
              onRefresh: () async {
                await Provider.of<ProductProvider>(context, listen: false).loadProducts(hideOutOfStock: true);
              },              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                // Top section: Greeting + Search Pinned
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Continue Browsing chip (Change 6b)
                        Text(
                          'Good morning, ${auth.displayName.split(" ").first} 👋',
                          style: AppConstants.bodyStyle(
                            fontSize: 14,
                            color: AppConstants.secondary.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Search bar
                        TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            setState(() {
                              _searchKeyword = val;
                            });
                          },
                          style: AppConstants.bodyStyle(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Search products or tags — handmade, leather, boots…',
                            hintStyle: AppConstants.bodyStyle(
                              fontSize: 14,
                              color: AppConstants.secondary.withValues(alpha: 0.4),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon: const Icon(Icons.search, color: AppConstants.primary, size: 20),
                            suffixIcon: _searchKeyword.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _searchKeyword = '';
                                      });
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: const BorderSide(color: AppConstants.primary, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Foot-profile reminder (skipped/incomplete profiles only).
                // Quiet, dismissible-for-session, never a pop-up — one
                // placement on the home screen.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: const CustomerFootProfileBanner(),
                  ),
                ),

                // Category selection scrollbar
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: productProvider.categories.map((cat) {
                        final isSelected = productProvider.selectedCategory == cat;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: ChoiceChip(
                            label: Text(
                              cat,
                              style: AppConstants.bodyStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? AppConstants.surfaceLight : AppConstants.secondary,
                              ),
                            ),
                            selected: isSelected,
                            showCheckmark: false,
                            onSelected: (selected) {
                              if (selected) {
                                productProvider.selectCategory(cat);
                              }
                            },
                            selectedColor: AppConstants.primary,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: isSelected ? Colors.transparent : AppConstants.borderGray.withValues(alpha: 0.4),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // Recently viewed (only when search is empty)
                if (_searchKeyword.isEmpty && recentlyViewedItems.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
                      child: Column(
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
                          SizedBox(
                            height: 180,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: recentlyViewedItems.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final item = recentlyViewedItems[index];
                                // Resolve the live product (if it's still in
                                // the catalog) so the strip shows the current
                                // effective (sale-aware) price.
                                final fullProduct = productProvider.products
                                    .cast<Map<String, dynamic>?>()
                                    .firstWhere(
                                  (p) => p?['id']?.toString() == item['id'],
                                  orElse: () => null,
                                );
                                final DateTime? stripEnd = fullProduct == null
                                    ? null
                                    : DateTime.tryParse(
                                        fullProduct['sale_ends_at']
                                                ?.toString() ??
                                            '');
                                // The expiry watcher re-renders this strip
                                // item with a `now` past the sale end, so the
                                // compact countdown and the sale price fall
                                // back to non-sale together when it expires.
                                return SaleEndWatcher(
                                  product: fullProduct ?? const {},
                                  builder: (context, now) {
                                    final bool stripOnSale =
                                        fullProduct != null &&
                                            isOnSale(fullProduct, now: now);
                                    final double liveStripPrice =
                                        fullProduct != null
                                            ? effectivePrice(fullProduct,
                                                now: now)
                                            : ((item['price'] is num)
                                                    ? (item['price'] as num)
                                                    : 0)
                                                .toDouble();
                                    final double originalPrice =
                                        fullProduct != null
                                            ? ((fullProduct['price'] is num)
                                                    ? (fullProduct['price']
                                                        as num)
                                                    : 0)
                                                .toDouble()
                                            : 0;
                                    return SizedBox(
                                      width: 130,
                                      child: GestureDetector(
                                    onTap: () {
                                      // Use the full product from the loaded list
                                      final productProvider = context.read<ProductProvider>();
                                      final fullProduct = productProvider.products.cast<Map<String, dynamic>?>().firstWhere(
                                        (p) => p?['id']?.toString() == item['id'],
                                        orElse: () => null,
                                      );
                                      if (fullProduct != null) {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ProductDetailScreen(product: fullProduct),
                                          ),
                                        );
                                      }
                                    },
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Thumbnail + compact countdown band
                                        // across its bottom edge (only for
                                        // sales that actually end).
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Stack(
                                            fit: StackFit.passthrough,
                                            children: [
                                              Image.network(
                                                item['imageUrl'] ?? '',
                                                width: 130,
                                                height: 124,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) => Container(
                                                  width: 130,
                                                  height: 124,
                                                  color: AppConstants.borderGray.withValues(alpha: 0.2),
                                                  child: Icon(
                                                    Icons.image_outlined,
                                                    color: AppConstants.borderGray,
                                                  ),
                                                ),
                                              ),
                                              if (stripOnSale &&
                                                  stripEnd != null)
                                                Positioned(
                                                  left: 0,
                                                  right: 0,
                                                  bottom: 0,
                                                  child: SaleCountdownOverlay(
                                                    saleEndsAt: stripEnd,
                                                    compact: true,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        // Text block — Expanded + FittedBox
                                        // (scaleDown) guarantees the card never
                                        // overflows the 180px strip, even when
                                        // an on-sale item renders two price
                                        // lines or the device text scale is
                                        // large.
                                        Expanded(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.topLeft,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item['name'] ?? '',
                                                  style: AppConstants.bodyStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                if (stripOnSale) ...[
                                                  // Sale price hides behind a
                                                  // peel-away tape (same reveal
                                                  // state as the cards' tags).
                                                  SalePriceTape(
                                                    productId: item['id']
                                                            ?.toString() ??
                                                        '',
                                                    // 11px text → slightly
                                                    // more padding to keep
                                                    // the ~40px tap target.
                                                    hitPadding: const EdgeInsets
                                                        .fromLTRB(
                                                            10, 20, 10, 9),
                                                    child: Text(
                                                      '₱${liveStripPrice.toStringAsFixed(2)}',
                                                      style:
                                                          AppConstants.monoStyle(
                                                        fontSize: 11,
                                                        color: AppConstants
                                                            .primary,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '₱${originalPrice.toStringAsFixed(2)}',
                                                    style: AppConstants.monoStyle(
                                                      fontSize: 9,
                                                      color: AppConstants.secondary
                                                          .withValues(alpha: 0.5),
                                                    ).copyWith(
                                                        decoration: TextDecoration
                                                            .lineThrough),
                                                  ),
                                                ] else
                                                  Text(
                                                    '₱${liveStripPrice.toStringAsFixed(2)}',
                                                    style: AppConstants.monoStyle(
                                                      fontSize: 11,
                                                      color: AppConstants.primary,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // Recently Viewed empty state (first-time users)
                if (_searchKeyword.isEmpty && _recentlyViewed.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.history_outlined,
                            size: 14,
                            color: AppConstants.secondary.withValues(alpha: 0.3),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Products you view will show up here',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // On Sale section — dedicated masonry sliver. Shown only in
                // the default browse state (no search, no category filter):
                // when the 'On Sale' chip is selected the grid below already
                // shows all sale items, so the sliver would duplicate it.
                if (_searchKeyword.isEmpty &&
                    saleProducts.isNotEmpty &&
                    (productProvider.selectedCategory == null ||
                        productProvider.selectedCategory == 'All')) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                      child: Row(
                        children: [
                          Text(
                            'On Sale',
                            style: AppConstants.headlineStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 10),
                          const _PriceTagBadge(label: 'HOT DEALS'),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    // NOTE: deliberately a plain SliverGrid, NOT masonry.
                    // Two SliverMasonryGrids in one CustomScrollView trigger a
                    // scroll-offset-correction loop in flutter_staggered_grid_view
                    // 0.7.0 that yanks the viewport back partway down the page
                    // — making the bottom of a long catalog unreachable. The
                    // catalog grid below keeps masonry; this small section uses
                    // a deterministic grid (exact extent, no estimation).
                    // Cards omit imageAspectRatio so the image is an Expanded
                    // fill — the card adapts to any cell height without
                    // overflowing.
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        // 0.58 ≈ the catalog masonry cards' average image
                        // height, so the two sections read similarly.
                        childAspectRatio: 0.58,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final prod = saleProducts[index];
                          return SoleProductCard(
                            product: prod,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ProductDetailScreen(product: prod),
                                ),
                              );
                            },
                          );
                        },
                        childCount: saleProducts.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],

                // Featured PageView Banner (when search query is empty)
                if (_searchKeyword.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Column(
                        children: [
                          Container(
                            height: 160,
                            decoration: BoxDecoration(
                              borderRadius: AppConstants.cardRadius,
                              boxShadow: AppConstants.warmShadow,
                            ),
                            child: ClipRRect(
                              borderRadius: AppConstants.cardRadius,
                              child: Stack(
                                children: [
                                  PageView.builder(
                                    controller: _bannerController,
                                    onPageChanged: (index) {
                                      setState(() {
                                        _bannerIndex = index;
                                      });
                                    },
                                    itemCount: _featuredArrivals.length,
                                    itemBuilder: (context, index) {
                                      final item = _featuredArrivals[index];
                                      return Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.network(
                                            item['image']!,
                                            fit: BoxFit.cover,
                                          ),
                                          // Dark gradient overlay
                                          Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.black.withValues(alpha: 0.6),
                                                  Colors.black.withValues(alpha: 0.1),
                                                ],
                                                begin: Alignment.bottomCenter,
                                                end: Alignment.topCenter,
                                              ),
                                            ),
                                          ),
                                          // Banner texts
                                          Positioned(
                                            bottom: 16,
                                            left: 20,
                                            right: 20,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item['title']!,
                                                  style: AppConstants.headlineStyle(
                                                    fontSize: 20,
                                                    color: AppConstants.surfaceLight,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  item['subtitle']!,
                                                  style: AppConstants.bodyStyle(
                                                    fontSize: 12,
                                                    color: AppConstants.surfaceLight.withValues(alpha: 0.8),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Dots Indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(_featuredArrivals.length, (index) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: _bannerIndex == index ? 16 : 6,
                                height: 6,
                                margin: const EdgeInsets.symmetric(horizontal: 2.0),
                                decoration: BoxDecoration(
                                  color: _bannerIndex == index
                                      ? AppConstants.primary
                                      : AppConstants.borderGray,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // Product Grid header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _searchKeyword.isEmpty ? 'Artisan Catalog' : 'Search Results',
                            style: AppConstants.headlineStyle(fontSize: 20),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _showSortSheet(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppConstants.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppConstants.primary.withValues(alpha: 0.15),
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
                                  sortModeLabel(productProvider.sortMode),
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
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // Catalog Grid — skeleton product cards while loading
                if (productProvider.isLoading)
                  ConnectivityService.instance.isOnline
                      ? const SliverToBoxAdapter(
                          child: _CatalogSkeletonGrid(),
                        )
                      : SliverFillRemaining(
                          hasScrollBody: false,
                          child: NoInternetView(
                            onRetry: () => Provider.of<ProductProvider>(
                                context,
                                listen: false)
                                .loadProducts(hideOutOfStock: true),
                          ),
                        )
                else if (filteredProducts.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 48, color: AppConstants.primary.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No shoes match your criteria.',
                            style: AppConstants.bodyStyle(color: AppConstants.secondary.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverMasonryGrid.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final prod = filteredProducts[index];
                        return SoleProductCard(
                          product: prod,
                          imageAspectRatio: _imageAspectRatioFor(prod),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ProductDetailScreen(product: prod),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                // Spacing bottom
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
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

