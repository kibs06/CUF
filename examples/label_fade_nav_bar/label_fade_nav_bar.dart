import 'package:flutter/material.dart';

/// One destination in a [LabelFadeNavBar].
///
/// [badgeCount] is optional; when non-null and greater than zero a small
/// red count badge is pinned to the top-right of the icon.
class NavBarItem {
  final IconData icon;
  final String label;
  final int? badgeCount;

  const NavBarItem({
    required this.icon,
    required this.label,
    this.badgeCount,
  });
}

/// Custom bottom navigation bar where only the **selected** tab shows its
/// label. The label fades in while sliding up when a tab is selected, and
/// fades out while sliding down when it is deselected. The icon color tweens
/// between muted and accent over the same duration.
///
/// Pure Flutter — no third-party packages:
///  * label animation: [AnimatedSwitcher] + [FadeTransition] +
///    [SlideTransition]
///  * icon color: [TweenAnimationBuilder] + [ColorTween]
///
/// Tabs are equal-width `Expanded` cells and the label lives in a
/// fixed-height slot, so showing/hiding a label never reflows the bar.
class LabelFadeNavBar extends StatefulWidget {
  /// The tabs to display, in order.
  final List<NavBarItem> items;

  /// Index of the currently selected tab.
  final int selectedIndex;

  /// Called with the index of the tapped tab.
  final ValueChanged<int> onTap;

  /// Bar background. Defaults to warm cream.
  final Color backgroundColor;

  /// Color of the selected icon + label. Defaults to warm brown.
  final Color activeColor;

  /// Color of unselected icons. Defaults to muted gray.
  final Color inactiveColor;

  /// Shared duration for the label fade/slide and icon-color animations.
  static const Duration animationDuration = Duration(milliseconds: 250);

  const LabelFadeNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    this.backgroundColor = const Color(0xFFF5F0E8),
    this.activeColor = const Color(0xFF8B4513),
    this.inactiveColor = const Color(0xFF9E9E9E),
  });

  @override
  State<LabelFadeNavBar> createState() => _LabelFadeNavBarState();
}

class _LabelFadeNavBarState extends State<LabelFadeNavBar> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.backgroundColor,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < widget.items.length; i++)
                Expanded(
                  child: _LabelFadeTab(
                    item: widget.items[i],
                    isSelected: i == widget.selectedIndex,
                    duration: LabelFadeNavBar.animationDuration,
                    activeColor: widget.activeColor,
                    inactiveColor: widget.inactiveColor,
                    onTap: () => widget.onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabelFadeTab extends StatelessWidget {
  final NavBarItem item;
  final bool isSelected;
  final Duration duration;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _LabelFadeTab({
    required this.item,
    required this.isSelected,
    required this.duration,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Icon (+ optional badge) ─────────────────────────
              // Fixed 48x24 box keeps the icon centered; the badge may
              // overflow its top-right corner without shifting anything.
              SizedBox(
                width: 48,
                height: 24,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: TweenAnimationBuilder<Color?>(
                          // Only `end` matters: on a selection change the
                          // builder animates from the icon's *current*
                          // color to the new target (ease-out, 250ms).
                          tween: ColorTween(
                            end: isSelected ? activeColor : inactiveColor,
                          ),
                          duration: duration,
                          curve: Curves.easeOut,
                          builder: (context, color, _) => Icon(
                            item.icon,
                            size: 24,
                            color: color,
                          ),
                        ),
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
              const SizedBox(height: 4),

              // ── Label ──────────────────────────────────────────
              // Fixed-height slot prevents vertical reflow. AnimatedSwitcher
              // swaps the label for an empty box: the outgoing label fades
              // out while sliding down (tween runs in reverse), the incoming
              // one fades in while sliding up.
              SizedBox(
                height: 14,
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeOut,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.3),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: isSelected
                      ? Text(
                          item.label,
                          key: ValueKey('label-${item.label}'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: activeColor,
                          ),
                        )
                      : const SizedBox(
                          key: ValueKey('label-hidden'),
                          width: 0,
                          height: 0,
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

/// Small red circular count badge (white text) anchored to an icon's
/// top-right corner. Rendered outside the label animation, so it is always
/// visible regardless of selection state.
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
          // Cap at 99+ so a huge count never blows up the circle.
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
