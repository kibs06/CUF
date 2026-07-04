import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../constants/app_constants.dart';
import '../../../models/store.dart';

/// Horizontal compact store chips — "More Stores" section.
/// Tapping a chip scrolls the hero carousel to that store.
class StoreCompactRow extends StatelessWidget {
  final List<Store> stores;
  final int focusedIndex;
  final ValueChanged<int> onStoreTapped;

  const StoreCompactRow({
    super.key,
    required this.stores,
    required this.focusedIndex,
    required this.onStoreTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label with left border accent
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: AppConstants.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'More Stores',
                style: AppConstants.bodyStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.secondary,
                ),
              ),
            ],
          ),
        ),

        // Horizontal chip list
        SizedBox(
          height: 88,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: stores.length,
            itemBuilder: (context, index) {
              final store = stores[index];
              final isFocused = index == focusedIndex;

              return GestureDetector(
                onTap: () => onStoreTapped(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 105,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        store.color.withAlpha(isFocused ? 230 : 180),
                        store.color.withAlpha(isFocused ? 180 : 120),
                      ],
                    ),
                    border: isFocused
                        ? Border.all(
                            color: AppConstants.accent,
                            width: 2,
                          )
                        : null,
                    boxShadow: isFocused
                        ? [
                            BoxShadow(
                              color: AppConstants.accent.withAlpha(50),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.white.withAlpha(50),
                        backgroundImage: store.logoUrl != null && store.logoUrl!.isNotEmpty
                            ? CachedNetworkImageProvider(store.logoUrl!)
                            : null,
                        child: store.logoUrl == null || store.logoUrl!.isEmpty
                            ? Text(
                                store.initials,
                                style: AppConstants.headlineStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          store.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppConstants.bodyStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
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
