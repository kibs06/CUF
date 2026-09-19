import 'package:flutter/material.dart';
import '../../../constants/app_constants.dart';
import '../../../widgets/cart_icon_button.dart';

/// A compact search bar + cart icon that pins to the top of the viewport
/// once the hero has scrolled out of view.
///
/// Solid background matching the bottom nav bar's cream tone, with a white
/// search pill and white cart circle — consistent with the sticky_header_preview.html.
///
/// **Tap-to-search, not type-in-place.** The field is a read-only stand-in that
/// opens the search page, where the real field, its suggestion panel and its
/// results live. Typing here used to filter the Home feed in place, which is
/// what left a customer stuck inside a query with no clear button and no way
/// back out (`search_results_screen.dart` documents that fix).
class HomeStickySearchBar extends StatelessWidget {
  const HomeStickySearchBar({super.key, this.onTap});

  /// Opens the full-screen search page.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lineColor = AppConstants.borderGray;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 6,
        12,
        10,
      ),
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: const Color(0x2E140F0A).withValues(alpha: 0.18),
            offset: const Offset(0, 6),
            blurRadius: 14,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Row(
        children: [
          // Search pill — white background, subtle border
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: AppConstants.surfaceLight,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: lineColor.withValues(alpha: 0.6),
                ),
              ),
              child: TextField(
                onTap: onTap,
                readOnly: true,
                showCursor: false,
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search leather shoes…',
                  hintStyle: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(left: 8, right: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF3D2817),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.search,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 38,
                    minHeight: 38,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Cart icon — no background circle, matches hero's style
          const CartIconButton(),
        ],
      ),
    );
  }
}
