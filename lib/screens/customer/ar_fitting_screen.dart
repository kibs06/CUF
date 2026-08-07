import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/product_provider.dart';
import '../../providers/cart_provider.dart';
import '../../utils/cart_helpers.dart';
import '../../widgets/ar_view_placeholder.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/seller/fly_to_order_animation.dart';

class ARVirtualFitScreen extends StatefulWidget {
  final Map<String, dynamic>? preselectedProduct;

  const ARVirtualFitScreen({
    super.key,
    this.preselectedProduct,
  });

  @override
  State<ARVirtualFitScreen> createState() => _ARVirtualFitScreenState();
}

class _ARVirtualFitScreenState extends State<ARVirtualFitScreen> with TickerProviderStateMixin {
  late Map<String, dynamic> _activeProduct;
  late String _activeSize;
  late String _activeColor;
  
  late ValueNotifier<bool> _isTracking;
  bool _showTutorial = true;
  bool _isAddingToCart = false;

  // GlobalKeys for the fly-to-cart overlay animation (Add to Cart → cart icon)
  final GlobalKey _addToCartButtonKey = GlobalKey();
  final GlobalKey _cartIconKey = GlobalKey();
  
  late AnimationController _pulseController;
  late AnimationController _particleController;

  @override
  void initState() {
    super.initState();
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    
    // Fallback if no preselected product
    if (widget.preselectedProduct != null) {
      _activeProduct = widget.preselectedProduct!;
    } else {
      _activeProduct = productProvider.products.isNotEmpty
          ? productProvider.products.first
          : {
              'id': 1,
              'name': 'Carcar Classic Oxford',
              'price': 2499.00,
              'images': ['https://images.unsplash.com/photo-1533867617858-e7b97e060509?q=80&w=600&auto=format&fit=crop'],
              'sizes': {'38': 5, '39': 8, '40': 12, '41': 6, '42': 0},
            };
    }

    // Initialize selections
    _activeColor = 'Burnished Clay';
    final sizesMap = Map<String, dynamic>.from(_activeProduct['sizes'] ?? {});
    _activeSize = sizesMap.keys.firstWhere((s) => sizesMap[s] > 0, orElse: () => '39');

    _isTracking = ValueNotifier<bool>(false);

    // Simulated tracking lock on after 2.5 seconds
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _isTracking.value = true;
      }
    });

    // Pulse animation for tracking dot
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    // Particle/edge overlay animation
    _particleController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _particleController.dispose();
    _isTracking.dispose();
    super.dispose();
  }

  void _switchProduct(Map<String, dynamic> product) {
    setState(() {
      _activeProduct = product;
      final sizesMap = Map<String, dynamic>.from(product['sizes'] ?? {});
      _activeSize = sizesMap.keys.firstWhere((s) => sizesMap[s] > 0, orElse: () => '39');
      
      // Simulate tracking relocking on shoe change
      _isTracking.value = false;
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) {
          _isTracking.value = true;
        }
      });
    });
  }

  void _checkSizeAvailability() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (context) {
        final sizesMap = Map<String, dynamic>.from(_activeProduct['sizes'] ?? {});
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock Level: ${_activeProduct['name']}',
                style: AppConstants.headlineStyle(fontSize: 18, color: AppConstants.surfaceLight),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: sizesMap.entries.map((entry) {
                  final size = entry.key;
                  final qty = entry.value as int;
                  final inStock = qty > 0;
                  return Column(
                    children: [
                      Text(
                        'EU $size',
                        style: AppConstants.monoStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.surfaceLight,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: inStock ? AppConstants.success.withOpacity(0.2) : AppConstants.error.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          inStock ? '$qty left' : 'OUT',
                          style: AppConstants.bodyStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: inStock ? AppConstants.success : AppConstants.error,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _addToCart() {
    // Guard against rapid taps stacking multiple overlay flights (mirrors
    // product detail screen's _isAddingToCart pattern).
    if (_isAddingToCart) return;
    setState(() => _isAddingToCart = true);

    final cart = Provider.of<CartProvider>(context, listen: false);
    final double price = (_activeProduct['price'] is int)
        ? (_activeProduct['price'] as int).toDouble()
        : (_activeProduct['price'] ?? 0.0);
    final List<dynamic> images = _activeProduct['images'] ?? [];

    // Look up variant_id for the selected size (mirrors product_detail_screen)
    final variants = _activeProduct['product_variants'] as List<dynamic>? ?? [];
    final (:variantId, :additionalPrice) = resolveVariant(
      variants: variants,
      size: _activeSize,
      color: _activeColor,
    );

    final String imageUrl = images.isNotEmpty ? images.first : '';

    cart.addToCart(
      productId: _activeProduct['id'].toString(),
      productName: _activeProduct['name'],
      imageUrl: imageUrl,
      price: price,
      size: _activeSize,
      color: _activeColor,
      variantId: variantId,
      additionalPrice: additionalPrice,
    );

    // Pack-the-box fly-to-cart overlay animation (same as the POS): the box
    // GIF draws in around the product, then the solid box flies up to the
    // cart icon and lands with a ring flash.
    FlyToOrderAnimation.show(
      context: context,
      sourceKey: _addToCartButtonKey,
      targetKey: _cartIconKey,
      imageUrl: imageUrl,
    );

    // Re-enable the button after the box-pack animation finishes (~1800 ms)
    // so rapid taps can't stack overlapping flights.
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _isAddingToCart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final otherProducts = productProvider.products;
    final sizesMap = Map<String, dynamic>.from(_activeProduct['sizes'] ?? {});

    return Scaffold(
      backgroundColor: AppConstants.surfaceDark,
      body: Stack(
        children: [
          // Immersive Camera Feed View
          const SizedBox.expand(
            child: ARViewPlaceholder(),
          ),

          // Animated particle scatter effect at borders
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _particleController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _ARParticlePainter(
                      progress: _particleController.value,
                    ),
                  );
                },
              ),
            ),
          ),

          // Top overlay: Glassmorphism back/title panel
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: Colors.black.withOpacity(0.4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.close, color: AppConstants.surfaceLight, size: 18),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _activeProduct['name'] ?? 'Carcar Footwear',
                              style: AppConstants.bodyStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.surfaceLight,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Active Color: $_activeColor',
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                color: AppConstants.surfaceLight.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Cart shortcut — fly-to-cart target for the add-to-cart animation
                      CartIconButton(
                        iconKey: _cartIconKey,
                        iconColor: AppConstants.surfaceLight,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom overlay: Glassmorphism menu box (~210px tall)
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  color: Colors.black.withOpacity(0.55),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status Tracking Indicator + Size Checker Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Pulse dot and status
                          ValueListenableBuilder<bool>(
                            valueListenable: _isTracking,
                            builder: (context, tracking, child) {
                              final statusText = tracking ? 'Fit looks good!' : 'Tracking your feet...';
                              return Row(
                                children: [
                                  // Pulsing Dot
                                  AnimatedBuilder(
                                    animation: _pulseController,
                                    builder: (context, child) {
                                      return Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: tracking ? AppConstants.success : AppConstants.accent,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: (tracking ? AppConstants.success : AppConstants.accent)
                                                  .withOpacity(0.6 * _pulseController.value),
                                              blurRadius: 6,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    statusText,
                                    style: AppConstants.bodyStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: tracking ? AppConstants.success : AppConstants.accent,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          // Size availability button
                          GestureDetector(
                            onTap: _checkSizeAvailability,
                            child: Row(
                              children: [
                                Text(
                                  'Availability',
                                  style: AppConstants.bodyStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppConstants.surfaceLight.withOpacity(0.8),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_up,
                                  color: AppConstants.surfaceLight.withOpacity(0.8),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Horizontal shoe variants/colors list
                      SizedBox(
                        height: 52,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: otherProducts.length,
                          itemBuilder: (context, index) {
                            final prod = otherProducts[index];
                            final isCurrent = prod['id'] == _activeProduct['id'];
                            final String img = (prod['images'] as List).isNotEmpty ? prod['images'][0] : '';
                            
                            return GestureDetector(
                              onTap: () => _switchProduct(prod),
                              child: Container(
                                width: 52,
                                height: 52,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isCurrent ? AppConstants.accent : Colors.white24,
                                    width: isCurrent ? 2 : 1,
                                  ),
                                  image: DecorationImage(
                                    image: NetworkImage(img),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Size Selector row (compact chips)
                      SizedBox(
                        height: 32,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: sizesMap.entries.map((entry) {
                            final size = entry.key;
                            final isAvailable = (entry.value as int) > 0;
                            final isSelected = _activeSize == size;

                            return GestureDetector(
                              onTap: isAvailable
                                  ? () {
                                      setState(() {
                                        _activeSize = size;
                                      });
                                    }
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppConstants.accent
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppConstants.accent
                                        : Colors.white24,
                                    width: 1,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'EU $size',
                                    style: AppConstants.monoStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? AppConstants.secondary
                                          : (isAvailable ? AppConstants.surfaceLight : Colors.white30),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Add to Cart
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: FilledButton(
                          key: _addToCartButtonKey,
                          onPressed: _isAddingToCart ? null : _addToCart,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppConstants.accent,
                            foregroundColor: AppConstants.secondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppConstants.buttonRadius,
                            ),
                          ),
                          child: Text(
                            'Add to Cart (₱${_activeProduct['price']})',
                            style: AppConstants.bodyStyle(
                              fontWeight: FontWeight.bold,
                              color: AppConstants.secondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // First-time "How to use" guide overlay
          if (_showTutorial)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showTutorial = false;
                  });
                },
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Virtual Fit Guide',
                        style: AppConstants.headlineStyle(fontSize: 24, color: AppConstants.surfaceLight),
                      ),
                      const SizedBox(height: 24),
                      _buildTutorialStep(
                        icon: Icons.camera_alt_outlined,
                        title: '1. Point at your feet',
                        desc: 'Hold camera ~3 feet away from your feet with good ambient lighting.',
                      ),
                      const SizedBox(height: 20),
                      _buildTutorialStep(
                        icon: Icons.checkroom_outlined,
                        title: '2. Select a shoe',
                        desc: 'Tap the circular thumbnails below to swap shoe models in real time.',
                      ),
                      const SizedBox(height: 20),
                      _buildTutorialStep(
                        icon: Icons.remove_red_eye_outlined,
                        title: '3. See how it fits',
                        desc: 'Adjust your size and look at the foot alignment on screen.',
                      ),
                      const SizedBox(height: 48),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _showTutorial = false;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppConstants.surfaceLight),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: Text(
                          'Got It',
                          style: AppConstants.bodyStyle(color: AppConstants.surfaceLight, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTutorialStep({required IconData icon, required String title, required String desc}) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: AppConstants.primary.withOpacity(0.2),
          child: Icon(icon, color: AppConstants.accent),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppConstants.bodyStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppConstants.surfaceLight),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: AppConstants.bodyStyle(fontSize: 12, color: AppConstants.surfaceLight.withOpacity(0.7)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Custom painter for ambient scatter edge particles
class _ARParticlePainter extends CustomPainter {
  final double progress;

  _ARParticlePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppConstants.accent.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    // Draw small animated glowing circles near borders
    final double w = size.width;
    final double h = size.height;
    
    // Animate coordinates based on progress
    final double dy1 = 150 + (h * 0.4 * progress);
    final double dy2 = h * 0.7 - (h * 0.3 * progress);
    
    // Left edge
    canvas.drawCircle(Offset(30, dy1), 4, paint);
    canvas.drawCircle(Offset(45, dy2), 6, paint);
    
    // Right edge
    canvas.drawCircle(Offset(w - 30, dy2), 5, paint);
    canvas.drawCircle(Offset(w - 45, dy1), 3, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
