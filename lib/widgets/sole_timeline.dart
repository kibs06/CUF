import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SoleTimelineItem {
  final String title;
  final String description;
  final String time;

  const SoleTimelineItem({
    required this.title,
    required this.description,
    required this.time,
  });
}

class SoleTimeline extends StatelessWidget {
  final List<SoleTimelineItem> items;
  final int activeIndex;

  const SoleTimeline({
    super.key,
    required this.items,
    required this.activeIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(items.length, (index) {
        final item = items[index];
        final isPast = index < activeIndex;
        final isActive = index == activeIndex;
        final isFuture = index > activeIndex;
        final isLast = index == items.length - 1;

        Color dotColor;
        Widget dotChild;

        if (isPast) {
          dotColor = AppConstants.success;
          dotChild = const Icon(Icons.check, size: 12, color: AppConstants.surfaceLight);
        } else if (isActive) {
          dotColor = AppConstants.accent;
          dotChild = Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppConstants.secondary,
              shape: BoxShape.circle,
            ),
          );
        } else {
          dotColor = AppConstants.borderGray;
          dotChild = const SizedBox.shrink();
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left indicator column
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    // Node circle
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isActive ? AppConstants.primary : Colors.transparent,
                          width: isActive ? 2 : 0,
                        ),
                      ),
                      child: Center(child: dotChild),
                    ),
                    // Vertical connector line
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: isPast ? AppConstants.success : AppConstants.borderGray.withOpacity(0.5),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Content block
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  key: ValueKey('timeline_item_$index'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: AppConstants.bodyStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isActive
                              ? AppConstants.primary
                              : (isPast ? AppConstants.secondary : AppConstants.secondary.withOpacity(0.5)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.description,
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color: AppConstants.secondary.withOpacity(isFuture ? 0.4 : 0.7),
                        ),
                      ),
                      if (item.time.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.time,
                          style: AppConstants.monoStyle(
                            fontSize: 11,
                            color: AppConstants.primary.withOpacity(isFuture ? 0.4 : 0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
