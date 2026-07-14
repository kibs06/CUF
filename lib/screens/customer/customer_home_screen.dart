import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/message_provider.dart';
import '../../providers/product_provider.dart';
import '../../services/connectivity_service.dart';
import '../../widgets/floating_message_button.dart';
import '../../widgets/no_internet_view.dart';
import '../../widgets/sole_product_card.dart';
import '../../widgets/cart_icon_button.dart';
import '../store/store_profile_screen.dart';
import 'product_detail_screen.dart';
import 'ar_fitting_screen.dart';

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

  // Resume browsing state (Change 6b)
  String? _lastStoreId;
  String? _lastStoreName;

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
    _loadLastVisitedStore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductProvider>(context, listen: false).loadProducts();
      // Load conversations for the floating message button badge
      _loadConversations();
    });

    // Auto-refresh products when connection is restored after being offline
    _wasOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.isOnlineStream.listen((isOnline) {
      if (isOnline && _wasOffline && mounted) {
        Provider.of<ProductProvider>(context, listen: false).loadProducts();
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

  Future<void> _loadLastVisitedStore() async {
    final prefs = await SharedPreferences.getInstance();
    final storeId = prefs.getString('last_visited_store_id');
    final storeName = prefs.getString('last_visited_store_name');
    if (mounted && storeId != null && storeName != null) {
      setState(() {
        _lastStoreId = storeId;
        _lastStoreName = storeName;
      });
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final productProvider = context.watch<ProductProvider>();
    final filteredProducts = productProvider.getFilteredProducts(_searchKeyword);

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'SoleVision Studio',
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
                await Provider.of<ProductProvider>(context, listen: false).loadProducts();
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
                        if (_lastStoreId != null && _lastStoreName != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => StoreProfileScreen(
                                      storeId: _lastStoreId!,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppConstants.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppConstants.primary.withValues(
                                      alpha: 0.18,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.storefront_outlined,
                                      color: AppConstants.primary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Pick up where you left off → $_lastStoreName',
                                        style: AppConstants.bodyStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppConstants.primary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: AppConstants.primary,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Text(
                          'Good morning, ${auth.displayName.split(" ").first} 👋',
                          style: AppConstants.bodyStyle(
                            fontSize: 14,
                            color: AppConstants.secondary.withOpacity(0.6),
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
                            hintText: 'Search artisan boots, oxfords, loafers...',
                            hintStyle: AppConstants.bodyStyle(
                              fontSize: 14,
                              color: AppConstants.secondary.withOpacity(0.4),
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
                            onSelected: (selected) {
                              if (selected) {
                                productProvider.selectCategory(cat);
                              }
                            },
                            selectedColor: AppConstants.primary,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: isSelected ? Colors.transparent : AppConstants.borderGray.withOpacity(0.4),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 12)),

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
                                                  Colors.black.withOpacity(0.6),
                                                  Colors.black.withOpacity(0.1),
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
                                                    color: AppConstants.surfaceLight.withOpacity(0.8),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _searchKeyword.isEmpty ? 'Artisan Catalog' : 'Search Results',
                          style: AppConstants.headlineStyle(fontSize: 20),
                        ),
                        Text(
                          '${filteredProducts.length} items',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: AppConstants.secondary.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // Catalog Grid
                if (productProvider.isLoading)
                  SliverFillRemaining(
                    child: Center(
                      child: ConnectivityService.instance.isOnline
                          ? const CircularProgressIndicator(color: AppConstants.primary)
                          : NoInternetView(
                              onRetry: () => Provider.of<ProductProvider>(context, listen: false).loadProducts(),
                            ),
                    ),
                  )
                else if (filteredProducts.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 48, color: AppConstants.primary.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No shoes match your criteria.',
                            style: AppConstants.bodyStyle(color: AppConstants.secondary.withOpacity(0.6)),
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
                          onTryOnTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ARVirtualFitScreen(preselectedProduct: prod),
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
