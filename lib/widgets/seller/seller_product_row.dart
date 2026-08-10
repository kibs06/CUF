import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../utils/sale_price.dart';

class SellerProductRow extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleFeatured;
  final VoidCallback? onTogglePublished;
  final VoidCallback? onDuplicate;
  final VoidCallback? onArchive;

  const SellerProductRow({
    super.key,
    required this.product,
    this.onEdit,
    this.onToggleFeatured,
    this.onTogglePublished,
    this.onDuplicate,
    this.onArchive,
  });

  int _getTotalStock(Map<String, dynamic> sizes) {
    int total = 0;
    sizes.forEach((_, qty) {
      if (qty is int) total += qty;
    });
    return total;
  }

  double _getStockPercent(int current, int total) {
    if (total == 0) return 0;
    return current / total;
  }

  @override
  Widget build(BuildContext context) {
    final id = product['id']?.toString() ?? '';
    final String img = (product['images'] as List?)?.isNotEmpty == true
        ? product['images'][0]
        : '';
    final double price = (product['price'] is int)
        ? (product['price'] as int).toDouble()
        : (product['price'] ?? 0.0).toDouble();
    final bool onSale = isOnSale(product);
    final double displayPrice = onSale ? effectivePrice(product) : price;
    final sku =
        product['sku'] ?? 'SKU-${id.length > 8 ? id.substring(0, 8) : id}';
    final totalStock = _getTotalStock(product['sizes'] ?? {});
    final maxStock = 20;
    final stockPercent = _getStockPercent(totalStock, maxStock).clamp(0.0, 1.0);
    final isLow = totalStock <= 5;
    final isPublished = product['is_published'] != false;
    final isFeatured = product['is_featured'] == true;

    Color progressColor;
    if (stockPercent > 0.5) {
      progressColor = AppConstants.okStockColor;
    } else if (stockPercent > 0.1) {
      progressColor = AppConstants.statusPendingColor;
    } else {
      progressColor = AppConstants.lowStockColor;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppConstants.sellerCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SellerTheme.cardBorder),
        boxShadow: AppConstants.sellerShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: img.isNotEmpty
                ? Image.network(
                    img,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      width: 56,
                      height: 56,
                      color: AppConstants.borderGray.withValues(alpha: 0.3),
                      child: const Icon(
                        Icons.image,
                        color: AppConstants.primary,
                      ),
                    ),
                  )
                : Container(
                    width: 56,
                    height: 56,
                    color: AppConstants.borderGray.withValues(alpha: 0.3),
                    child: const Icon(Icons.image, color: AppConstants.primary),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name'] ?? '',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (onSale) ...[
                      Text(
                        '₱${displayPrice.toStringAsFixed(0)}',
                        style: AppConstants.monoStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.error,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '₱${price.toStringAsFixed(0)}',
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          color: SellerTheme.textMuted,
                        ).copyWith(decoration: TextDecoration.lineThrough),
                      ),
                      const SizedBox(width: 5),
                    ] else
                      Text(
                        '₱${price.toStringAsFixed(0)}',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: SellerTheme.textMuted,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        '· SKU: $sku',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: SellerTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: stockPercent,
                        backgroundColor: Colors.grey.shade200,
                        color: progressColor,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'Stock: $totalStock / $maxStock',
                          style: AppConstants.bodyStyle(
                            fontSize: 11,
                            color: SellerTheme.textMuted,
                          ),
                        ),
                        if (isLow) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppConstants.lowStockColor.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'LOW',
                              style: AppConstants.monoStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.lowStockColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildStatusChip(
                      isPublished ? 'PUBLISHED' : 'DRAFT',
                      isPublished
                          ? AppConstants.okStockColor
                          : AppConstants.statusPendingColor,
                    ),
                    if (isFeatured) ...[
                      const SizedBox(width: 6),
                      _buildStatusChip('FEATURED', AppConstants.accent),
                    ],
                    if (onSale) ...[
                      const SizedBox(width: 6),
                      _buildStatusChip('ON SALE', AppConstants.error),
                    ],
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: AppConstants.secondary),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit?.call();
                  break;
                case 'feature':
                  onToggleFeatured?.call();
                  break;
                case 'publish':
                  onTogglePublished?.call();
                  break;
                case 'duplicate':
                  onDuplicate?.call();
                  break;
                case 'archive':
                  onArchive?.call();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'feature',
                child: Text(isFeatured ? 'Remove Featured' : 'Mark Featured'),
              ),
              PopupMenuItem(
                value: 'publish',
                child: Text(isPublished ? 'Set as Draft' : 'Publish'),
              ),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              const PopupMenuItem(value: 'archive', child: Text('Archive')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppConstants.monoStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
