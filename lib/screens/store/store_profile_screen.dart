import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import '../../models/store.dart';
import '../../providers/follow_provider.dart';
import '../../providers/product_provider.dart';
import '../../services/message_service.dart';
import '../../services/store_service.dart';
import '../../widgets/chat/chat_view.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/sole_product_card.dart';
import '../customer/product_detail_screen.dart';
import '../customer/ar_fitting_screen.dart';
import 'collection_screen.dart';
import 'widgets/stitch_painter.dart';

/// Full profile page for a single store.
/// Reached via "Enter Store" from the carousel.
class StoreProfileScreen extends StatefulWidget {
  final String storeId;

  const StoreProfileScreen({super.key, required this.storeId});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final StoreService _storeService = StoreService.instance;

  Store? _store;
  List<Map<String, dynamic>> _storeProducts = [];
  List<Map<String, dynamic>> _storyEntries = [];
  bool _isLoading = true;
  String _sortMode = 'Newest';
  int _followerCount = 0;

  /// Deterministic image aspect ratio per card keyed off product id.
  double _imageAspectRatioFor(dynamic product) {
    const ratios = [1.0, 0.78, 1.22, 0.95];
    final id = product['id']?.toString() ?? '';
    final key = id.isEmpty ? 0 : id.hashCode;
    return ratios[key.abs() % ratios.length];
  }

  final PageController _featuredController = PageController(
    viewportFraction: 0.88,
  );
  int _featuredIndex = 0;

  // Collections derived from the store's products
  List<String> get _collections {
    final cats = <String>{};
    for (final p in _storeProducts) {
      cats.add(p['category'] as String);
    }
    return cats.toList();
  }

  List<Map<String, dynamic>> get _featuredProducts {
    return _storeProducts.where((p) => p['is_featured'] == true).toList();
  }

  List<Map<String, dynamic>> get _sortedProducts {
    final list = List<Map<String, dynamic>>.from(_storeProducts);
    switch (_sortMode) {
      case 'Price: Low–High':
        list.sort(
          (a, b) => (a['price'] as double).compareTo(b['price'] as double),
        );
        break;
      case 'Price: High–Low':
        list.sort(
          (a, b) => (b['price'] as double).compareTo(a['price'] as double),
        );
        break;
      case 'Newest':
      default:
        list.sort((a, b) => '${b['id']}'.compareTo('${a['id']}'));
        break;
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _messageSeller() async {
    final customerId = Supabase.instance.client.auth.currentUser?.id;
    if (customerId == null) return;

    // Get or create conversation
    final conversation = await MessageService.instance.getOrCreateConversation(
      storeId: widget.storeId,
      customerId: customerId,
    );

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatView(
          conversationId: conversation.id,
          viewerRole: 'customer',
          otherPartyName: _store?.name ?? 'Store',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _featuredController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Refresh products from server so new/removed products appear on pull
    await Provider.of<ProductProvider>(context, listen: false).loadProducts();
    final store = await _storeService.fetchStoreById(widget.storeId);
    final stories = await _storeService.getStoryEntriesForStore(widget.storeId);
    // Fetch the DB-truth follower count
    final followerCount = await _storeService.getFollowerCount(widget.storeId);
    if (!mounted) return;
    final allProducts = Provider.of<ProductProvider>(
      context,
      listen: false,
    ).products;
    final storeProducts = allProducts
        .where((p) => p['store_id'] == widget.storeId)
        .toList();

    setState(() {
      _store = store;
      _storeProducts = storeProducts;
      _storyEntries = stories;
      _followerCount = followerCount;
      _isLoading = false;
    });

    // Save last visited store for "Continue Browsing" (Change 6b)
    if (store != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_visited_store_id', widget.storeId);
      await prefs.setString('last_visited_store_name', store.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _store == null) {
      return Scaffold(
        backgroundColor: AppConstants.surfaceLight,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppConstants.secondary,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppConstants.primary),
        ),
      );
    }

    final store = _store!;
    final sorted = _sortedProducts;

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: RefreshIndicator(
        color: AppConstants.primary,
        onRefresh: _loadData,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Sliver 1: Store Hero Header ──
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: store.color,
              foregroundColor: AppConstants.surfaceLight,
              actions: const [CartIconButton()],
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  store.name,
                  style: AppConstants.headlineStyle(
                    fontSize: 15,
                    color: AppConstants.surfaceLight,
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Banner image or brand gradient background
                    if (store.bannerUrl != null && store.bannerUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: store.bannerUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          decoration: BoxDecoration(
                            gradient: store.cardGradient,
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          decoration: BoxDecoration(
                            gradient: store.cardGradient,
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(gradient: store.cardGradient),
                      ),

                    // Dark gradient overlay for text readability
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withAlpha(20),
                              Colors.black.withAlpha(140),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Stitch overlay
                    CustomPaint(painter: const StitchPainter()),

                    // Content overlay
                    Positioned(
                      bottom: 56,
                      left: 20,
                      right: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (store.tagline != null)
                            Text(
                              store.tagline!,
                              style: AppConstants.bodyStyle(
                                fontSize: 13,
                                color: Colors.white.withAlpha(190),
                              ),
                            ),
                          const SizedBox(height: 12),
                          // Stats row — horizontally scrollable, never overflows
                          _buildStatsRow(store),
                          const SizedBox(height: 10),
                          // Actions row — Message Seller + Follow, always visible
                          _buildActionsRow(store),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Sliver 2: Collection Shelf ──
            if (_collections.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Row(
                    children: [
                      Text(
                        'Shop by Collection',
                        style: AppConstants.headlineStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '— ${store.name}',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: AppConstants.secondary.withAlpha(127),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      for (var i = 0; i < _collections.length; i++) ...[
                        if (i > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              '·',
                              style: AppConstants.bodyStyle(
                                fontSize: 16,
                                color: AppConstants.secondary.withAlpha(90),
                              ),
                            ),
                          ),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CollectionScreen(
                                  collectionName: _collections[i],
                                  categoryFilter: _collections[i],
                                  storeId: widget.storeId,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 2,
                            ),
                            child: Text(
                              _collections[i],
                              style: AppConstants.bodyStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppConstants.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            // ── Sliver 3: Featured Products ──
            if (_featuredProducts.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Text(
                    'Featured Picks',
                    style: AppConstants.headlineStyle(fontSize: 18),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 190,
                  child: PageView.builder(
                    controller: _featuredController,
                    onPageChanged: (i) => setState(() => _featuredIndex = i),
                    itemCount: _featuredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _featuredProducts[index];
                      final images = product['images'] as List;
                      return GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductDetailScreen(product: product),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            borderRadius: AppConstants.cardRadius,
                            boxShadow: _featuredIndex == index
                                ? AppConstants.warmShadow
                                : [],
                          ),
                          child: ClipRRect(
                            borderRadius: AppConstants.cardRadius,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  images.isNotEmpty ? images[0] as String : '',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        color: AppConstants.borderGray,
                                        child: const Icon(
                                          Icons.image_not_supported,
                                        ),
                                      ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withAlpha(180),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 14,
                                  left: 16,
                                  right: 16,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product['name'] ?? '',
                                        style: AppConstants.headlineStyle(
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '₱${(product['price'] as double).toStringAsFixed(0)}',
                                        style: AppConstants.monoStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppConstants.accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Featured dots
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_featuredProducts.length, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: _featuredIndex == i ? 16 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: _featuredIndex == i
                              ? AppConstants.primary
                              : AppConstants.borderGray,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],

            // ── Sliver 4: Our Story ──
            if (_storyEntries.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                  child: Text(
                    'Our Story',
                    style: AppConstants.headlineStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final story = _storyEntries[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: AppConstants.cardRadius,
                        boxShadow: AppConstants.warmShadow,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              story['title'] ?? '',
                              style: AppConstants.headlineStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              story['body_text'] ?? '',
                              style: AppConstants.bodyStyle(
                                fontSize: 13,
                                color: AppConstants.secondary.withAlpha(180),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }, childCount: _storyEntries.length),
              ),
            ],

            // ── Sliver 5: All Products Grid ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
                child: Text(
                  'All Products',
                  style: AppConstants.headlineStyle(fontSize: 18),
                ),
              ),
            ),
            // Sort chips
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: ['Newest', 'Price: Low–High', 'Price: High–Low']
                      .map((mode) {
                        final isSelected = _sortMode == mode;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FilterChip(
                            label: Text(
                              mode,
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? AppConstants.surfaceLight
                                    : AppConstants.secondary,
                              ),
                            ),
                            selected: isSelected,
                            onSelected: (_) {
                              setState(() => _sortMode = mode);
                            },
                            selectedColor: AppConstants.primary,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: isSelected
                                  ? Colors.transparent
                                  : AppConstants.borderGray.withAlpha(100),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        );
                      })
                      .toList(),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // Product grid
            if (sorted.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      'No products in this store yet.',
                      style: AppConstants.bodyStyle(
                        color: AppConstants.secondary.withAlpha(153),
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.55,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final prod = sorted[index];
                      return SoleProductCard(
                        product: prod,
                        imageAspectRatio: _imageAspectRatioFor(prod),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProductDetailScreen(product: prod),
                            ),
                          );
                        },
                        onTryOnTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ARVirtualFitScreen(preselectedProduct: prod),
                            ),
                          );
                        },
                      );
                    },
                    childCount: sorted.length,
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // STORE BANNER — Stats + Actions rows
  // ════════════════════════════════════════════════════════════════

  /// Horizontally scrollable stats row — never overflows.
  Widget _buildStatsRow(Store store) {
    final followProvider = context.watch<FollowProvider>();
    final displayCount = followProvider.followerCountFor(
      widget.storeId,
      fallback: _followerCount,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _statChip(
            '$displayCount ${displayCount == 1 ? 'follower' : 'followers'}',
          ),
          _statDivider(),
          _statChip('${_storeProducts.length} products'),
          _statDivider(),
          _statChip('★ ${store.rating}'),
          if (store.hoursLabel != null) ...[
            _statDivider(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.access_time,
                    size: 14,
                    color: AppConstants.surfaceLight,
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      store.hoursLabel!,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: AppConstants.monoStyle(
                        fontSize: 11,
                        color: Colors.white.withAlpha(200),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _statDivider(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_on,
                  size: 14,
                  color: AppConstants.surfaceLight,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    store.location,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: AppConstants.monoStyle(
                      fontSize: 11,
                      color: Colors.white.withAlpha(200),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Actions row — Message Seller + Follow button, always fully visible.
  Widget _buildActionsRow(Store store) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => _messageSeller(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppConstants.surfaceLight, width: 1.5),
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              color: AppConstants.surfaceLight,
              size: 16,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _FollowButton(
          storeId: widget.storeId,
          brandColor: AppConstants.parseBrandColor(store.color),
          onFollowChanged: (isFollowing) {
            // Issue 2: count is now owned by FollowProvider.toggle()
            // — just read the reconciled value from the provider.
          },
        ),
      ],
    );
  }

  Widget _statChip(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: AppConstants.monoStyle(
          fontSize: 11,
          color: Colors.white.withAlpha(200),
        ),
      ),
    );
  }

  Widget _statDivider() {
    return Text(
      '·',
      style: AppConstants.monoStyle(
        fontSize: 14,
        color: Colors.white.withAlpha(120),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Animated Follow Button
// ══════════════════════════════════════════════════════════════════

class _FollowButton extends StatefulWidget {
  final String storeId;
  final Color brandColor;
  final void Function(bool isFollowing) onFollowChanged;

  const _FollowButton({
    required this.storeId,
    required this.brandColor,
    required this.onFollowChanged,
  });

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    lowerBound: 0.0,
    upperBound: 0.12,
  );
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap(FollowProvider followProvider) async {
    if (_isLoading) return;
    HapticFeedback.lightImpact();

    // Bounce: scale up then settle back down
    await _controller.forward();
    _controller.reverse();

    final wasFollowing = followProvider.isFollowing(widget.storeId);
    setState(() => _isLoading = true);
    try {
      await followProvider.toggle(widget.storeId);
      if (mounted) widget.onFollowChanged(!wasFollowing);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update follow status'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final followProvider = context.watch<FollowProvider>();
    final isFollowing = followProvider.isFollowing(widget.storeId);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + _controller.value;
        return Transform.scale(scale: scale, child: child);
      },
      child: GestureDetector(
        onTap: () => _handleTap(followProvider),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isFollowing ? AppConstants.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppConstants.surfaceLight, width: 1.5),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Row(
              key: ValueKey(isFollowing),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFollowing) ...[
                  Icon(Icons.check, size: 13, color: widget.brandColor),
                  const SizedBox(width: 4),
                ],
                Text(
                  isFollowing ? 'Following' : 'Follow',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isFollowing
                        ? widget.brandColor
                        : AppConstants.surfaceLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
