import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../constants/app_constants.dart';
import '../../services/product_service.dart';
import '../../services/store_service.dart';
import '../../widgets/sole_primary_button.dart';
import 'edit_store_screen.dart';

/// Seller-facing store profile screen.
///
/// Shows the store's banner, logo, info, and key stats.
/// Tapping "Edit Store" navigates to [EditStoreScreen].
class StoreProfileScreen extends StatefulWidget {
  final Map<String, dynamic> store;

  const StoreProfileScreen({super.key, required this.store});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final _storeService = StoreService.instance;
  final _productService = ProductService.instance;

  Map<String, dynamic>? _store;
  int _productCount = 0;
  final int _orderCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _store = widget.store;
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      // Refresh store data
      final updatedStore = await _storeService.getMyStore();
      final products = await _productService.getSellerProducts();
      final storeId = _store!['id'].toString();
      final productCount =
          products.where((p) => p['store_id'] == storeId).length;

      if (mounted) {
        setState(() {
          if (updatedStore != null) _store = updatedStore;
          _productCount = productCount;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleOpen() async {
    if (_store == null) return;
    final currentOpen = _store!['is_open'] ?? true;
    final newOpen = !currentOpen;
    try {
      await _storeService.toggleStoreOpen(
          _store!['id'].toString(), newOpen);
      setState(() => _store!['is_open'] = newOpen);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                newOpen ? 'Store is now open' : 'Store is now closed'),
            backgroundColor: AppConstants.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  Future<void> _navigateToEdit() async {
    if (_store == null) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditStoreScreen(store: _store!),
      ),
    );
    if (result == true) {
      // Refresh data after edit
      final updatedStore = await _storeService.getMyStore();
      if (mounted && updatedStore != null) {
        setState(() => _store = updatedStore);
      }
    }
  }

  String? get _bannerUrl => _store?['banner_url']?.toString();
  String? get _logoUrl => _store?['logo_url']?.toString();
  String get _name => _store?['name'] ?? 'My Store';
  String get _tagline => _store?['tagline'] ?? '';
  String get _location => _store?['location'] ?? '';
  bool get _isOpen => _store?['is_open'] ?? true;
  String get _brandColorHex => _store?['brand_color'] ?? '#8B5A2B';
  double get _rating =>
      (_store?['rating'] as num?)?.toDouble() ?? 5.0;

  Color get _brandColor => AppConstants.parseBrandColor(_brandColorHex);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          'Store Profile',
          style: AppConstants.bodyStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Banner & Header ──
                _buildHeaderSection(),
                const SizedBox(height: 16),

                // ── Store Info ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildInfoSection(),
                ),
                const SizedBox(height: 16),

                // ── Stats Row ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildStatsRow(),
                ),
                const SizedBox(height: 20),

                // ── Edit Button ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SolePrimaryButton(
                    label: 'Edit Store',
                    icon: const Icon(Icons.edit_outlined,
                        color: Colors.white, size: 18),
                    onPressed: _navigateToEdit,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header Section (Banner + Logo + Name + Open Toggle) ──

  Widget _buildHeaderSection() {
    return Stack(
      children: [
        // Banner
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _brandColor,
                Color.lerp(
                    _brandColor, const Color(0xFF1A1208), 0.4)!,
              ],
            ),
          ),
          child: _bannerUrl != null
              ? CachedNetworkImage(
                  imageUrl: _bannerUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const SizedBox(),
                )
              : const SizedBox(),
        ),
        // Dark overlay for text readability
        if (_bannerUrl != null)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
            ),
          ),
        // Content
        Positioned(
          bottom: 16,
          left: 20,
          right: 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Logo
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                      color: AppConstants.surfaceLight, width: 2.5),
                  boxShadow: AppConstants.warmShadow,
                ),
                child: _logoUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: CachedNetworkImage(
                          imageUrl: _logoUrl!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(Icons.store_outlined,
                        size: 28,
                        color: AppConstants.primary.withValues(alpha: 0.6)),
              ),
              const SizedBox(width: 14),
              // Name + Open status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _name,
                      style: AppConstants.headlineStyle(
                        fontSize: 20,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isOpen
                                ? AppConstants.success
                                : AppConstants.error,
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          child: Text(_isOpen ? 'Open' : 'Closed'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Info Section ──

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.warmShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tagline
          if (_tagline.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.format_quote,
                    size: 16,
                    color: AppConstants.primary.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _tagline,
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      color: AppConstants.secondary.withValues(alpha: 0.7),
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // Location
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  size: 16, color: AppConstants.primary),
              const SizedBox(width: 8),
              Text(
                _location,
                style: AppConstants.bodyStyle(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Brand Color Swatch
          Row(
            children: [
              const Icon(Icons.palette_outlined,
                  size: 16, color: AppConstants.primary),
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _brandColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: AppConstants.borderGray
                          .withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Brand Color',
                style: AppConstants.bodyStyle(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Open/Closed Toggle
          Row(
            children: [
              Icon(Icons.store_outlined,
                  size: 16, color: AppConstants.primary),
              const SizedBox(width: 8),
              Text(
                'Store Status',
                style: AppConstants.bodyStyle(fontSize: 13),
              ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _isOpen
                      ? AppConstants.success.withValues(alpha: 0.12)
                      : AppConstants.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _isOpen
                        ? AppConstants.success
                        : AppConstants.error,
                  ),
                  child: Text(_isOpen ? 'Open' : 'Closed'),
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _isOpen,
                onChanged: (_) => _toggleOpen(),
                activeColor: AppConstants.success,
                activeThumbColor: AppConstants.success,
                inactiveTrackColor: AppConstants.error.withValues(alpha: 0.3),
                inactiveThumbColor: AppConstants.error,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Stats Row ──

  Widget _buildStatsRow() {
    if (_isLoading) {
      return Shimmer.fromColors(
        baseColor: AppConstants.borderGray.withValues(alpha: 0.3),
        highlightColor: Colors.white,
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppConstants.cardRadius,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.warmShadow,
      ),
      child: Row(
        children: [
          _statItem(
            icon: Icons.inventory_2_outlined,
            value: '$_productCount',
            label: 'Products',
          ),
          _statDivider(),
          _statItem(
            icon: Icons.receipt_long_outlined,
            value: '$_orderCount',
            label: 'Orders',
          ),
          _statDivider(),
          _statItem(
            icon: Icons.star_outline,
            value: _rating.toStringAsFixed(1),
            label: 'Rating',
          ),
        ],
      ),
    );
  }

  Widget _statItem({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppConstants.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppConstants.monoStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 11,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 40,
      color: AppConstants.borderGray.withValues(alpha: 0.3),
    );
  }
}
