import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../utils/notification_formatters.dart';

/// Espresso/cream bottom navigation bar with a sliding indicator pill.
///
/// Keeps the same look as the Material 3 `NavigationBar` it replaces
/// (background bar, tinted indicator pill, filled icon + label for the
/// active tab, unread badge on the bell) but makes the indicator **glide**
/// from tab to tab on selection (~300ms ease-out-cubic) instead of snapping.
///
/// The constructor API is compatible with the old implementation
/// ([role] / [currentIndex] / [onTap] / [notificationUnreadCount]), with
/// optional [backgroundColor] / [activeColor] / [inactiveColor] / [barHeight]
/// so the seller shell can reuse the same widget with its own palette.
class SoleBottomNav extends StatelessWidget {
  final String role;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Number of unread notifications for the bell icon badge.
  /// When 0, no badge is shown. Values > 99 display as "99+".
  final int notificationUnreadCount;

  /// Bar background. Defaults to the app's warm cream.
  final Color? backgroundColor;

  /// Accent color for the indicator pill tint and the selected icon/label.
  /// Defaults to [AppConstants.primary].
  final Color? activeColor;

  /// Color of unselected icons/labels. Defaults to muted espresso.
  final Color? inactiveColor;

  /// Indicator pill color. When null, the pill is a translucent tint of
  /// [activeColor] (customer/admin style). Provide a solid color (e.g. the
  /// seller's amber) to keep a custom pill while it slides.
  final Color? pillColor;

  /// Bar height. Defaults to 80 (Material 3 NavigationBar height).
  final double? barHeight;

  const SoleBottomNav({
    super.key,
    required this.role,
    required this.currentIndex,
    required this.onTap,
    this.notificationUnreadCount = 0,
    this.backgroundColor,
    this.activeColor,
    this.inactiveColor,
    this.pillColor,
    this.barHeight,
  });

  // Geometry — matches Material 3 NavigationBar proportions.
  static const double _defaultBarHeight = 80;
  static const double _pillWidth = 64;
  static const double _pillHeight = 34;
  static const double _iconAreaHeight = 32;
  static const double _labelGap = 2;
  // 11px label with an explicit height: 1.3 → exactly 14.3px line box, so
  // the icon-row math below is deterministic regardless of font metrics.
  static const double _labelHeight = 11 * 1.3;

  /// Vertical center of the icon row within the bar (not the label), derived
  /// from the same layout constants used in [_buildDestination], so the pill
  /// can't silently drift off the icon if one of them changes.
  static double _iconCenterY(double barHeight) =>
      (barHeight - (_iconAreaHeight + _labelGap + _labelHeight)) / 2 +
      _iconAreaHeight / 2;

  @override
  Widget build(BuildContext context) {
    final destinations = _getDestinations();
    final bg = backgroundColor ?? AppConstants.surfaceLight;
    final active = activeColor ?? AppConstants.primary;
    final inactive =
        inactiveColor ?? AppConstants.secondary.withValues(alpha: 0.5);
    final pill =
        pillColor ?? active.withValues(alpha: 0.15); // tint by default
    final height = barHeight ?? _defaultBarHeight;

    return Container(
      color: bg,
      // The bar extends behind the home-indicator / gesture area; only the
      // destinations are inset.
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final count = destinations.length;
              // Exact pixel position of the pill's left edge so its CENTER
              // lands on the active tab's center. (AnimatedAlign's alignment
              // offsets a child by (parent − child), so it can't center a
              // fixed-width pill at an arbitrary tab fraction — we compute
              // the left edge directly instead.)
              final pillLeft =
                  ((currentIndex + 0.5) / count) * width - _pillWidth / 2;

              return Stack(
                children: [
                  // ── Sliding indicator pill ────────────────────
                  // AnimatedPositioned tweens `left` from the old tab to the
                  // new one, so the pill glides horizontally (300ms ease-out).
                  AnimatedPositioned(
                    left: pillLeft,
                    top: _iconCenterY(height) - _pillHeight / 2,
                    width: _pillWidth,
                    height: _pillHeight,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: Container(
                      decoration: BoxDecoration(
                        color: pill,
                        borderRadius: BorderRadius.circular(_pillHeight / 2),
                      ),
                    ),
                  ),

                  // ── Destinations ──────────────────────────────
                  // Positioned.fill makes the Row span the full bar height so
                  // the destination content is vertically centered — otherwise
                  // the Row shrinks to its content and hugs the top of the
                  // Stack, pushing the icon row away from the pill.
                  Positioned.fill(
                    child: Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          Expanded(
                            child: _buildDestination(
                              context,
                              destinations[i],
                              i,
                              active,
                              inactive,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDestination(
    BuildContext context,
    _NavDest dest,
    int index,
    Color active,
    Color inactive,
  ) {
    final isActive = index == currentIndex;

    return Semantics(
      label: dest.label,
      button: true,
      selected: isActive,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(index),
          // No ripple splash and no rectangular highlight — the "box"
          // fading in/out on tap was distracting. Taps still register; the
          // sliding pill provides the selection feedback.
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: _iconAreaHeight,
                child: Center(
                  child: dest.isBell
                      ? _NotificationBadgeIcon(
                          icon: isActive
                              ? Icons.notifications
                              : Icons.notifications_outlined,
                          unreadCount: notificationUnreadCount,
                          selected: isActive,
                          activeColor: active,
                        )
                      : Icon(
                          isActive ? dest.selectedIcon : dest.icon,
                          size: 24,
                          color: isActive ? active : inactive,
                        ),
                ),
              ),
              const SizedBox(height: _labelGap),
              Text(
                dest.label,
                // Single line, ellipsized — a wrapped label would grow the
                // column and shift the icon row away from the pill.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  // Explicit line height keeps the icon-row layout math
                  // (see [_iconCenterY]) exact.
                  height: 1.3,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? active : inactive,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_NavDest> _getDestinations() {
    switch (role) {
      case AppConstants.roleSeller:
        return const [
          _NavDest(
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            label: 'Dashboard',
          ),
          _NavDest(
            icon: Icons.point_of_sale_outlined,
            selectedIcon: Icons.point_of_sale,
            label: 'POS',
          ),
          _NavDest(
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            label: 'Products',
          ),
          _NavDest(
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long,
            label: 'Orders',
          ),
          _NavDest(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: 'Profile',
          ),
        ];
      case AppConstants.roleAdmin:
        return const [
          _NavDest(
            icon: Icons.admin_panel_settings_outlined,
            selectedIcon: Icons.admin_panel_settings,
            label: 'Dashboard',
          ),
          _NavDest(
            icon: Icons.people_alt_outlined,
            selectedIcon: Icons.people_alt,
            label: 'Users',
          ),
          _NavDest(
            icon: Icons.how_to_reg_outlined,
            selectedIcon: Icons.how_to_reg,
            label: 'Requests',
          ),
          _NavDest(
            icon: Icons.monitor_heart_outlined,
            selectedIcon: Icons.monitor_heart,
            label: 'Monitor',
          ),
          _NavDest(
            icon: Icons.flag_outlined,
            selectedIcon: Icons.flag,
            label: 'Intruder',
          ),
          _NavDest(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: 'Profile',
          ),
        ];
      case AppConstants.roleCustomer:
      default:
        return const [
          _NavDest(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: 'Home',
          ),
          _NavDest(
            icon: Icons.storefront_outlined,
            selectedIcon: Icons.storefront,
            label: 'Store',
          ),
          _NavDest(
            icon: Icons.notifications_outlined,
            selectedIcon: Icons.notifications,
            label: 'Notifications',
            isBell: true,
          ),
          _NavDest(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: 'Profile',
          ),
        ];
    }
  }
}

/// One destination definition (icon pair, label, optional bell badge).
class _NavDest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isBell;

  const _NavDest({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.isBell = false,
  });
}

/// Wraps a notification icon with an optional unread-count badge.
///
/// The badge sits at the top-right of the icon and:
/// - Is hidden when [unreadCount] is 0.
/// - Shows the raw number up to 99, then "99+" for higher counts.
/// - Uses a red background consistent with the app's unread-dot color.
class _NotificationBadgeIcon extends StatelessWidget {
  final IconData icon;
  final int unreadCount;
  final bool selected;
  final Color activeColor;

  const _NotificationBadgeIcon({
    required this.icon,
    required this.unreadCount,
    this.selected = false,
    this.activeColor = AppConstants.primary,
  });

  @override
  Widget build(BuildContext context) {
    final hasBadge = unreadCount > 0;
    final badgeText = formatBadgeCount(unreadCount);

    return Semantics(
      label: hasBadge ? 'Notifications, $unreadCount unread' : 'Notifications',
      button: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 24, color: selected ? activeColor : null),
          if (hasBadge)
            Positioned(
              top: -4,
              right: -8,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppConstants.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
