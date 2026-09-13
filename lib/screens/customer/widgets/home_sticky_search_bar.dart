import 'package:flutter/material.dart';
import '../../../constants/app_constants.dart';
import '../../../services/search_history_service.dart';
import '../../../widgets/cart_icon_button.dart';
import 'search_history_overlay.dart';

/// A compact search bar + cart icon that pins to the top of the viewport
/// once the hero has scrolled out of view.
///
/// Solid background matching the bottom nav bar's cream tone, with a white
/// search pill and white cart circle — consistent with the sticky_header_preview.html.
///
/// Uses the same [TextEditingController] and [FocusNode] as the hero's
/// search field so typing in either stays in sync.
class HomeStickySearchBar extends StatefulWidget {
  const HomeStickySearchBar({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    this.onTap,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String>? onSearchChanged;

  /// When provided, tapping the field opens the full-screen search page
  /// instead of focusing inline (read-only tap-through field).
  final VoidCallback? onTap;

  @override
  State<HomeStickySearchBar> createState() => _HomeStickySearchBarState();
}

class _HomeStickySearchBarState extends State<HomeStickySearchBar> {
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    widget.searchFocusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant HomeStickySearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchFocusNode != widget.searchFocusNode) {
      oldWidget.searchFocusNode.removeListener(_onFocusChange);
      widget.searchFocusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.searchFocusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    final focused = widget.searchFocusNode.hasFocus;
    if (focused != _isSearchFocused) {
      setState(() => _isSearchFocused = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final focused = _isSearchFocused;
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
          // Search pill — white background, subtle border
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: focused
                      ? AppConstants.primary
                      : lineColor.withValues(alpha: 0.6),
                  width: focused ? 1.5 : 1,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: AppConstants.primary.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: TextField(
                controller: widget.searchController,
                focusNode: widget.onTap != null ? null : widget.searchFocusNode,
                onTap: widget.onTap,
                readOnly: widget.onTap != null,
                showCursor: widget.onTap == null,
                onChanged: widget.onSearchChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (term) {
                  SearchHistoryService.instance.record(term);
                  widget.searchFocusNode.unfocus();
                },
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

          // Recent-search history dropdown — floats over the page content
          // (takes no layout space, so the pinned bar never grows).
          if (_isSearchFocused && widget.searchController.text.isEmpty)
            Positioned(
              top: 48, // search row (38px) + 6px top padding + small gap
              left: 16,
              right: 62, // aligns with the search pill (cart icon takes the rest)
              child: SearchHistoryOverlay(
                horizontalMargin: 0,
                onSelect: (term) {
                  widget.searchController.text = term;
                  widget.onSearchChanged?.call(term);
                  SearchHistoryService.instance.record(term);
                  widget.searchFocusNode.unfocus();
                },
              ),
            ),
        ],
      ),
    );
  }
}
