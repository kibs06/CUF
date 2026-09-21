import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../providers/product_provider.dart';
import 'product_sort_chip.dart';
import 'underline_category_chip.dart';

/// The search + filter + sort bar a shelf listing page puts under its heading —
/// the size shelf, the sale shelf, and whatever shelf comes next.
///
/// **One widget on purpose.** A customer who learns these three controls on one
/// shelf must not meet a differently-shaped version of them on the next, and
/// the alternative — each page growing its own row — is how two pages that mean
/// the same thing end up looking like two products. The chips and the sort
/// control are the shared widgets the search page uses ([UnderlineCategoryChip],
/// [ProductSortChip]), so the *controls* are shared as well as the band they sit
/// in.
///
/// **State lives in the page, not here.** The screen owns the query, the
/// category and the sort, because the same three are what its grid is filtered
/// and sorted by, and its empty state may have to clear them. This widget draws
/// them and reports changes back — it never holds or derives a product list, so
/// it cannot disagree with the grid it labels.
///
/// **The field is a filter, not a destination.** It narrows the shelf under it
/// as the customer types, which is what a shelf of ten or fifty products wants:
/// nothing to submit, no page to leave, and the count above it says how much of
/// the shelf is left. The app's search *page* is the other kind of thing — a
/// query against the whole catalog, its own back stack, suggestions and
/// history — and it keeps its own bar.
///
/// The chips come from the shelf itself ([ProductProvider.shelfCategories]), so
/// a chip can never lead to an empty grid, and they are hidden when the shelf
/// holds no categories at all — a lone "All" above a grid that cannot be
/// narrowed is noise. (The search results page's row follows the same rule off
/// [ProductProvider.searchCategories], so the two pages' chips behave alike: a
/// category is offered whenever the list under it has one.) The sort control
/// always shows, because it always does something.
class ProductShelfToolbar extends StatelessWidget {
  const ProductShelfToolbar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.onQueryChanged,
    required this.sort,
    required this.onSortSelected,
  });

  /// The page's controller, so the page's empty state can clear the field as
  /// well as the filtering it caused.
  final TextEditingController controller;

  /// The field's hint, in the shelf's own words — "Search in your size…",
  /// "Search on sale…".
  final String hintText;

  /// The categories the shelf holds, alphabetical; empty renders no chip row.
  final List<String> categories;

  /// The filter in force, or null for every category.
  final String? selectedCategory;

  final ValueChanged<String?> onCategorySelected;

  /// Called with the field's text as it changes, and with `''` when the field
  /// is cleared.
  final ValueChanged<String> onQueryChanged;

  final SortMode sort;
  final ValueChanged<SortMode> onSortSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: _searchField(context),
        ),
        SizedBox(
          height: 42,
          child: Row(
            children: [
              // One 'All' chip ahead of the shelf's own — the same shape the
              // search results page's chips have, off the same provider helper.
              if (categories.isNotEmpty)
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    // 12 + the chip's own 8 keeps the first label aligned with
                    // the shelf's count line above it (both at 20).
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      UnderlineCategoryChip(
                        label: 'All',
                        selected: selectedCategory == null,
                        indicatorKey: const ValueKey('shelf-underline-All'),
                        onTap: () => onCategorySelected(null),
                      ),
                      for (final category in categories)
                        UnderlineCategoryChip(
                          label: category,
                          selected: selectedCategory == category,
                          indicatorKey: ValueKey('shelf-underline-$category'),
                          onTap: () => onCategorySelected(category),
                        ),
                    ],
                  ),
                )
              else
                const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 16, left: 8),
                child: ProductSortChip(sort: sort, onSelected: onSortSelected),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The shelf's search field: the app's search-bar shape (the same 44px box,
  /// hairline and radius the search page's field uses) with a leading magnifier
  /// and a trailing clear instead of a submit button — because this one filters
  /// where the customer is standing.
  Widget _searchField(BuildContext context) {
    final hasText = controller.text.trim().isNotEmpty;
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppConstants.secondary, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 18,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onChanged: onQueryChanged,
              onSubmitted: onQueryChanged,
              style: AppConstants.bodyStyle(
                fontSize: 15,
                color: AppConstants.secondary,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: AppConstants.bodyStyle(
                  fontSize: 15,
                  color: AppConstants.secondary.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
              ),
            ),
          ),
          // Clear — empties the field AND the filtering, so a customer is never
          // left staring at a narrowed shelf wondering what narrowed it.
          if (hasText)
            GestureDetector(
              onTap: () {
                controller.clear();
                onQueryChanged('');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The count line a shelf page puts under its heading — `10 pairs · EU 39`, or
/// `3 of 10 pairs · EU 39` while a search or a filter is narrowing it, so the
/// heading can never count products the grid is not showing.
///
/// Shared by the shelf pages rather than written into each: the line is the
/// same sentence on all of them, and the `of` form only exists because these
/// pages can now be narrowed in place.
String shelfCountLabel({
  required int shown,
  required int total,
  String? qualifier,
}) {
  final pairs = shown == 1 ? '1 pair' : '$shown pairs';
  return [
    shown == total ? pairs : '$shown of $total pairs',
    ?qualifier,
  ].join(' · ');
}
