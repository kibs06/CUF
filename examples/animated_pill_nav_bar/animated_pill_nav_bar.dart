import 'package:flutter/material.dart';

/// One destination in an [AnimatedPillNavBar].
///
/// [badgeCount] is optional; when non-null and greater than zero a small
/// red count badge is pinned to the top-right of the icon.
class NavItem {
  final IconData icon;
  final String label;
  final int? badgeCount;

  const NavItem({
    required this.icon,
    required this.label,
    this.badgeCount,
  });
}

/// Sliding-pill bottom navigation bar.
///
/// - A single rounded "pill" slides horizontally behind the active tab
///   ([AnimatedAlign], 320ms, [Curves.easeOutCubic]).
/// - The active icon tints to the accent brown and scales up 1.0 → 1.1;
///   inactive icons stay gray at 1.0.
/// - Inactive tabs show only an icon; the [NavItem.label] is used for
///   accessibility (semantics) — the bar itself is icon-only.
///
/// `currentIndex` is controlled by the parent (no internal state), so it
/// drops straight into `Scaffold.bottomNavigationBar` next to an
/// `IndexedStack`.
class AnimatedPillNavBar extends StatefulWidget {
  /// The tabs to display, in order.
  final List<NavItem> items;

  /// Index of the currently active tab (controlled by the parent).
  final int currentIndex;

  /// Called with the index of the tapped tab.
  final ValueChanged<int> onTap;

  /// Bar background. Defaults to warm cream.
  final Color backgroundColor;

  /// Accent color for the pill tint and the active icon. Defaults to brown.
  final Color activeColor;

  /// Color of inactive icons. Defaults to muted gray.
  final Color inactiveColor;

  /// How long the pill slide / color / scale animations take.
  final Duration animationDuration;

  /// Animation curve for the pill slide (try `Curves.elasticOut` for a
  /// subtle spring — the default stays calm).
  final Curve curve;

  /// Pill width — roughly hugs the icon, not the full tab width.
  final double pillWidth;

  /// Pill height.
  final double pillHeight;

  /// Bar height.
  final double barHeight;

  const AnimatedPillNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.backgroundColor = const Color(0xFFF3EDE3),
    this.activeColor = const Color(0xFF6B4A2B),
    this.inactiveColor = const Color(0xFF9E9E9E),
    this.animationDuration = const Duration(milliseconds: 320),
    this.curve = Curves.easeOutCubic,
    this.pillWidth = 56,
    this.pillHeight = 44,
    this.barHeight = 68,
  });

  @override
  State<AnimatedPillNavBar> createState() => _AnimatedPillNavBarState();
}

class _AnimatedPillNavBarState extends State<AnimatedPillNavBar> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.barHeight,
      color: widget.backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = widget.items.length;
          if (count == 0) return const SizedBox.shrink();

          // Convert the active tab's center (fraction of the width) into an
          // Alignment x coordinate: -1 = far left, +1 = far right.
          final alignX = ((widget.currentIndex + 0.5) / count) * 2 - 1;

          return Stack(
            children: [
              // ── Sliding pill ─────────────────────────────────
              // AnimatedAlign tweens the alignment from the old tab to the
              // new one, so the pill glides horizontally (ease-out cubic).
              AnimatedAlign(
                alignment: Alignment(alignX, 0),
                duration: widget.animationDuration,
                curve: widget.curve,
                child: Container(
                  width: widget.pillWidth,
                  height: widget.pillHeight,
                  decoration: BoxDecoration(
                    color: widget.activeColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(widget.pillHeight / 2),
                  ),
                ),
              ),

              // ── Tabs ─────────────────────────────────────────
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: _buildTab(context, widget.items[i], i),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTab(BuildContext context, NavItem item, int index) {
    final isActive = index == widget.currentIndex;

    return Semantics(
      label: item.label,
      button: true,
      selected: isActive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(index),
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Icon: color tweens gray ↔ accent brown; scale 1.0 ↔ 1.1.
              // Both use the same duration as the pill so everything feels
              // synced when the tab switches.
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(
                  end: isActive ? widget.activeColor : widget.inactiveColor,
                ),
                duration: widget.animationDuration,
                curve: widget.curve,
                builder: (context, color, _) => AnimatedScale(
                  scale: isActive ? 1.1 : 1.0,
                  duration: widget.animationDuration,
                  curve: widget.curve,
                  child: Icon(item.icon, size: 24, color: color),
                ),
              ),
              if (item.badgeCount != null && item.badgeCount! > 0)
                Positioned(
                  top: -6,
                  right: -8,
                  child: _Badge(count: item.badgeCount!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small red circular count badge (white text), anchored to the icon's
/// top-right corner. Caps at "99+".
class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFD32F2F),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Center(
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}
