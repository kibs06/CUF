import 'package:flutter/material.dart';
import '../../../constants/app_constants.dart';
import '../../../models/store.dart';
import '../store_profile_screen.dart';

/// Info strip below the carousel showing focused store details.
/// Animates content with fade+slide when the focused store changes.
class StoreFocusedInfo extends StatelessWidget {
  final Store store;
  final int productCount;

  const StoreFocusedInfo({
    super.key,
    required this.store,
    required this.productCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: Column(
          key: ValueKey(store.id),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Store name
            Text(
              store.name,
              style: AppConstants.bodyStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppConstants.secondary,
              ),
            ),
            const SizedBox(height: 4),
            // Location + open status
            Row(
              children: [
                Flexible(
                  child: Text(
                    store.location,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary.withAlpha(127),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '  ·  ',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withAlpha(76),
                  ),
                ),
                Text(
                  store.isOpen ? '🟢 Open Now' : '⚫ Closed',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: store.isOpen
                        ? AppConstants.success
                        : AppConstants.secondary.withAlpha(127),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Store hours
            if (store.hoursLabel != null) ...[
              Text(
                'Hours: ${store.hoursLabel}',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withAlpha(127),
                ),
              ),
              const SizedBox(height: 4),
            ],
            // Rating + product count (star hidden until the store has
            // reviews — stores.rating is NULL with review_count = 0)
            Text(
              store.rating != null
                  ? '⭐ ${store.rating!.toStringAsFixed(1)}  ·  $productCount products'
                  : '$productCount products',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            // Enter Store button
            _EnterStoreButton(store: store),
          ],
        ),
      ),
    );
  }
}

/// "Enter Store →" button with micro-interaction arrow nudge.
class _EnterStoreButton extends StatefulWidget {
  final Store store;
  const _EnterStoreButton({required this.store});

  @override
  State<_EnterStoreButton> createState() => _EnterStoreButtonState();
}

class _EnterStoreButtonState extends State<_EnterStoreButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StoreProfileScreen(storeId: widget.store.id),
            ),
          );
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Container(
          decoration: BoxDecoration(
            color: AppConstants.primary,
            borderRadius: AppConstants.buttonRadius,
            boxShadow: [
              BoxShadow(
                color: AppConstants.primary.withAlpha(60),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Enter Store',
                style: AppConstants.bodyStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.surfaceLight,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                transform: Matrix4.translationValues(
                  _isPressed ? 2.0 : 0.0,
                  0,
                  0,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppConstants.surfaceLight,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
