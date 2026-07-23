import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Result type from the quick message sheet.
enum QuickMessageAction {
  sendMessage, // Options 1-4: auto-send the message
  requestChange, // Option 5: open Request a Change flow
  typeCustom, // Option 6: open empty thread for custom message
}

/// Result data returned from the quick message flow.
class QuickMessageResult {
  final QuickMessageAction action;
  final String? message; // The pre-filled message text (for sendMessage action)

  const QuickMessageResult({
    required this.action,
    this.message,
  });
}

/// A quick message option.
class QuickMessageOption {
  final String message;
  final IconData icon;
  final bool isDestructive;

  const QuickMessageOption({
    required this.message,
    required this.icon,
    this.isDestructive = false,
  });
}

/// Default quick message options for active orders.
const _activeOrderOptions = [
  QuickMessageOption(
    message: 'When will my order ship?',
    icon: Icons.local_shipping_outlined,
  ),
  QuickMessageOption(
    message: 'Can I still change the size/color?',
    icon: Icons.swap_horiz,
  ),
  QuickMessageOption(
    message: 'Can I update my delivery address?',
    icon: Icons.location_on_outlined,
  ),
  QuickMessageOption(
    message: 'Is my order still on track?',
    icon: Icons.track_changes,
  ),
];

/// Quick message options for completed/cancelled orders.
const _completedOrderOptions = [
  QuickMessageOption(
    message: 'I have an issue with my order',
    icon: Icons.warning_amber_outlined,
    isDestructive: true,
  ),
  QuickMessageOption(
    message: "I'd like to leave feedback",
    icon: Icons.star_outline,
  ),
];

/// Bottom sheet for quick message options when starting an order chat.
///
/// Returns a [QuickMessageResult] if the user selects an option, or null if dismissed.
Future<QuickMessageResult?> showQuickMessageSheet({
  required BuildContext context,
  required String orderId,
  required String productName,
  String? imageUrl,
  required String storeName,
  required String orderStatus,
}) {
  return showModalBottomSheet<QuickMessageResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuickMessageSheet(
      orderId: orderId,
      productName: productName,
      imageUrl: imageUrl,
      storeName: storeName,
      orderStatus: orderStatus,
    ),
  );
}

class _QuickMessageSheet extends StatelessWidget {
  final String orderId;
  final String productName;
  final String? imageUrl;
  final String storeName;
  final String orderStatus;

  const _QuickMessageSheet({
    required this.orderId,
    required this.productName,
    this.imageUrl,
    required this.storeName,
    required this.orderStatus,
  });

  bool get _isCompletedOrder =>
      orderStatus == 'cancelled' || orderStatus == 'delivered' || orderStatus == 'received';

  @override
  Widget build(BuildContext context) {
    final options = _isCompletedOrder ? _completedOrderOptions : _activeOrderOptions;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppConstants.surfaceLight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppConstants.borderGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header with context
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    // Product thumbnail
                    if (imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          imageUrl!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => Container(
                            width: 40,
                            height: 40,
                            color: AppConstants.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.shopping_bag_outlined, size: 20, color: AppConstants.primary),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Message $storeName',
                            style: AppConstants.bodyStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'About Order #${orderId.length >= 8 ? orderId.substring(0, 8) : orderId}',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Quick options list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: options.length + 2, // +2 for "Other question" and "Request a Change"
                  itemBuilder: (context, index) {
                    if (index < options.length) {
                      // Regular quick message option
                      final option = options[index];
                      return _QuickOptionTile(
                        option: option,
                        onTap: () {
                          Navigator.of(context).pop(
                            QuickMessageResult(
                              action: QuickMessageAction.sendMessage,
                              message: option.message,
                            ),
                          );
                        },
                      );
                    } else if (index == options.length) {
                      // "I have another question" option
                      return _QuickOptionTile(
                        option: const QuickMessageOption(
                          message: 'I have another question',
                          icon: Icons.chat_bubble_outline,
                        ),
                        onTap: () {
                          Navigator.of(context).pop(
                            const QuickMessageResult(
                              action: QuickMessageAction.typeCustom,
                            ),
                          );
                        },
                      );
                    } else {
                      // "Request a Change" option (at the bottom)
                      return _QuickOptionTile(
                        option: const QuickMessageOption(
                          message: "I'd like to request a change to my order",
                          icon: Icons.edit_note,
                        ),
                        onTap: () {
                          Navigator.of(context).pop(
                            const QuickMessageResult(
                              action: QuickMessageAction.requestChange,
                            ),
                          );
                        },
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A single quick option tile.
class _QuickOptionTile extends StatelessWidget {
  final QuickMessageOption option;
  final VoidCallback onTap;

  const _QuickOptionTile({
    required this.option,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: option.isDestructive
                          ? AppConstants.error.withValues(alpha: 0.1)
                          : AppConstants.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      option.icon,
                      size: 18,
                      color: option.isDestructive ? AppConstants.error : AppConstants.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Message text
                  Expanded(
                    child: Text(
                      option.message,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: option.isDestructive ? AppConstants.error : AppConstants.secondary,
                      ),
                    ),
                  ),
                  // Chevron
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppConstants.secondary.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(
          height: 1,
          color: AppConstants.borderGray.withValues(alpha: 0.3),
          indent: 60,
        ),
      ],
    );
  }
}
