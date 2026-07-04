import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../providers/cart_provider.dart';
import '../screens/customer/cart_screen.dart';

/// Persistent cart icon button for the AppBar.
/// Displays a shopping bag icon with an animated badge showing the
/// current number of items in the cart. Tapping navigates to CartScreen.
///
/// Enhanced with a bounce animation that fires when the cart count increases,
/// providing visual feedback for the fly-to-cart overlay arrival.
///
/// [iconKey] is an optional GlobalKey assigned to the IconButton so that
/// external code can obtain its screen-space position via RenderBox.
class CartIconButton extends StatefulWidget {
  /// Optional GlobalKey for position detection (fly-to-cart target).
  final GlobalKey? iconKey;

  const CartIconButton({super.key, this.iconKey});

  @override
  State<CartIconButton> createState() => _CartIconButtonState();
}

class _CartIconButtonState extends State<CartIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnimation;
  int _previousCount = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // Bouncy scale sequence: 1.0 → 1.3 → 0.9 → 1.0
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.9), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final count = cart.itemCount;
    final hasItems = count > 0;

    // Trigger bounce when cart count increases (skip initial build)
    if (_initialized && count > _previousCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bounceController.forward(from: 0.0);
      });
    }
    _previousCount = count;
    _initialized = true;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: IconButton(
        key: widget.iconKey,
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const CartScreen()),
          );
        },
        icon: AnimatedBuilder(
          animation: _bounceAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _bounceAnimation.value,
              child: child,
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Icon(
                  hasItems
                      ? Icons.shopping_bag
                      : Icons.shopping_bag_outlined,
                  key: ValueKey<bool>(hasItems),
                  color: AppConstants.secondary,
                  size: 26,
                ),
              ),
              // Badge overlay
              if (hasItems)
                Positioned(
                  right: -6,
                  top: -4,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: child,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      decoration: BoxDecoration(
                        color: AppConstants.accent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppConstants.accent.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        textAlign: TextAlign.center,
                        style: AppConstants.monoStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
