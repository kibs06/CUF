import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../providers/product_provider.dart';

/// The "Sort by" bottom sheet — one sheet for every list of products, so Home's
/// catalog and the search results page cannot drift into offering different
/// orders (or the same order under different names).
///
/// Deliberately takes the current mode and a callback rather than reading
/// [ProductProvider]: the search results page sorts its own list and must not
/// silently re-sort the Home feed underneath it.
Future<void> showProductSortSheet(
  BuildContext context, {
  required SortMode current,
  required ValueChanged<SortMode> onSelected,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    // The option list is taller than 9/16 of a short screen, which is the
    // default cap for a modal sheet — so the lower options used to be laid out
    // off the bottom of the screen instead of being scrollable. With
    // isScrollControlled the sheet gets the room, and the constraint below
    // keeps it a sheet rather than a full-screen page.
    isScrollControlled: true,
    builder: (ctx) => Container(
      margin: const EdgeInsets.all(16),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(ctx).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      // SingleChildScrollView so the option list scrolls instead of
      // overflowing on shorter screens (7 options now, maybe more later).
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppConstants.borderGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sort by',
              style: AppConstants.headlineStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            ...SortMode.values.map((mode) {
              final isActive = current == mode;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      isActive
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isActive
                          ? AppConstants.primary
                          : AppConstants.borderGray,
                      size: 20,
                    ),
                    title: Text(
                      sortModeLabel(mode),
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                        color: isActive
                            ? AppConstants.primary
                            : AppConstants.secondary,
                      ),
                    ),
                    onTap: () {
                      onSelected(mode);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    ),
  );
}
