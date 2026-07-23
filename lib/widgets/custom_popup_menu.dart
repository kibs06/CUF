import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// A custom popup menu item.
class CustomPopupMenuItem {
  final String label;
  final IconData icon;
  final Color? iconColor;
  final Color? textColor;
  final VoidCallback onTap;
  final bool showDividerBefore;

  const CustomPopupMenuItem({
    required this.label,
    required this.icon,
    this.iconColor,
    this.textColor,
    required this.onTap,
    this.showDividerBefore = false,
  });
}

/// Shows a custom-styled popup menu anchored to the target widget.
///
/// The menu appears below the target widget with a scrim backdrop.
Future<void> showCustomPopupMenu({
  required BuildContext context,
  required List<CustomPopupMenuItem> items,
  double menuWidth = 260,
}) async {
  final overlay = Overlay.of(context);
  final renderBox = context.findRenderObject() as RenderBox;
  final targetSize = renderBox.size;
  final targetPosition = renderBox.localToGlobal(Offset.zero);

  // Calculate menu position - below the target, right-aligned
  final screenWidth = MediaQuery.of(context).size.width;
  double menuLeft = targetPosition.dx + targetSize.width - menuWidth;
  
  // Ensure menu doesn't go off-screen left
  if (menuLeft < 16) menuLeft = 16;
  
  // Ensure menu doesn't go off-screen right
  if (menuLeft + menuWidth > screenWidth - 16) {
    menuLeft = screenWidth - menuWidth - 16;
  }

  final menuTop = targetPosition.dy + targetSize.height + 4;

  late OverlayEntry overlayEntry;
  
  overlayEntry = OverlayEntry(
    builder: (context) => _PopupMenuOverlay(
      items: items,
      menuLeft: menuLeft,
      menuTop: menuTop,
      menuWidth: menuWidth,
      onDismiss: () => overlayEntry.remove(),
    ),
  );

  overlay.insert(overlayEntry);

  // Wait for tap outside to dismiss
  await Future.delayed(const Duration(milliseconds: 100));
}

class _PopupMenuOverlay extends StatefulWidget {
  final List<CustomPopupMenuItem> items;
  final double menuLeft;
  final double menuTop;
  final double menuWidth;
  final VoidCallback onDismiss;

  const _PopupMenuOverlay({
    required this.items,
    required this.menuLeft,
    required this.menuTop,
    required this.menuWidth,
    required this.onDismiss,
  });

  @override
  State<_PopupMenuOverlay> createState() => _PopupMenuOverlayState();
}

class _PopupMenuOverlayState extends State<_PopupMenuOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Scrim backdrop
        GestureDetector(
          onTap: _dismiss,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: _opacityAnimation,
            builder: (context, child) {
              return Container(
                color: Colors.black.withValues(alpha: 0.2 * _opacityAnimation.value),
              );
            },
          ),
        ),
        // Menu
        Positioned(
          left: widget.menuLeft,
          top: widget.menuTop,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                alignment: Alignment.topRight,
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: widget.menuWidth,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF6F1), // Warm cream background
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppConstants.borderGray.withValues(alpha: 0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                            spreadRadius: 0,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < widget.items.length; i++) ...[
                            if (widget.items[i].showDividerBefore)
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: AppConstants.borderGray.withValues(alpha: 0.3),
                                indent: 16,
                                endIndent: 16,
                              ),
                            _MenuItemTile(
                              item: widget.items[i],
                              onTap: () {
                                widget.items[i].onTap();
                                _dismiss();
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  final CustomPopupMenuItem item;
  final VoidCallback onTap;

  const _MenuItemTile({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = item.iconColor ?? AppConstants.secondary;
    final textColor = item.textColor ?? AppConstants.secondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 20,
              color: iconColor,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.label,
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
