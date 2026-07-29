import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_constants.dart';

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Full-screen receipt view for a single POS transaction.
///
/// Shows store name, order ID, timestamp, itemized line items,
/// dashed tear-off divider, and total/payment summary.
/// Designed to be ready for future share/export as image or PDF.
class PosReceiptDetailScreen extends StatelessWidget {
  final Map<String, dynamic> order;
  final String storeName;
  final String storeLocation;
  final String sellerName;

  const PosReceiptDetailScreen({
    super.key,
    required this.order,
    required this.storeName,
    this.storeLocation = '',
    this.sellerName = '',
  });

  @override
  Widget build(BuildContext context) {
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final paymentMethod = (order['payment_method'] ?? 'cash').toString();
    final items = order['order_items'] as List? ?? [];
    final createdAt = order['created_at']?.toString();
    final shortId = order['id'].toString();
    final displayId = shortId.length >= 8 ? shortId.substring(0, 8) : shortId;
    final dt = createdAt != null ? DateTime.tryParse(createdAt) : null;

    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Receipt',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy Order ID',
            icon: const Icon(Icons.copy, color: Colors.white, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '#$displayId'));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Order ID copied',
                    style: AppConstants.bodyStyle(color: Colors.white, fontSize: 13),
                  ),
                  backgroundColor: AppConstants.secondary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppConstants.primary.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── Success checkmark ──
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppConstants.okStockColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        size: 28,
                        color: AppConstants.okStockColor,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Store name ──
                    Text(
                      storeName,
                      style: AppConstants.bodyStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.secondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (storeLocation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        storeLocation,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary.withValues(alpha: 0.45),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 4),

                    // ── "POS Sale" badge ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppConstants.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'POS Sale',
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Dashed divider (top) ──
                    _buildDashedDivider(),

                    const SizedBox(height: 16),

                    // ── Order ID + timestamp ──
                    _buildReceiptInfoRow('Order ID', '#$displayId'),
                    const SizedBox(height: 8),
                    _buildReceiptInfoRow(
                      'Date',
                      dt != null
                          ? '${_kMonths[dt.month - 1]} ${dt.day}, ${dt.year}'
                          : '—',
                    ),
                    const SizedBox(height: 8),
                    _buildReceiptInfoRow(
                      'Time',
                      dt != null ? _formatTime(dt) : '—',
                    ),
                    if (sellerName.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildReceiptInfoRow('Cashier', sellerName),
                    ],
                    const SizedBox(height: 16),

                    // ── Dashed divider (between info and items) ──
                    _buildDashedDivider(),

                    const SizedBox(height: 16),

                    // ── Item count summary ──
                    if (items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${items.length} item${items.length == 1 ? '' : 's'}',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppConstants.secondary.withValues(alpha: 0.4),
                          ),
                        ),
                      ),

                    // ── Items ──
                    ...items.map<Widget>((item) {
                      final name = item['product_name'] ?? 'Product';
                      final size = item['size'] ?? '';
                      final qty = item['quantity'] ?? 1;
                      final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
                      final lineTotal = unitPrice * qty;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Quantity
                            Container(
                              width: 28,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppConstants.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$qty',
                                style: AppConstants.monoStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppConstants.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Name + size
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: AppConstants.bodyStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppConstants.secondary,
                                    ),
                                  ),
                                  if (size.toString().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Size $size',
                                      style: AppConstants.bodyStyle(
                                        fontSize: 12,
                                        color: AppConstants.secondary.withValues(alpha: 0.45),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Price
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₱${lineTotal.toStringAsFixed(0)}',
                                  style: AppConstants.monoStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppConstants.secondary,
                                  ),
                                ),
                                if (qty > 1) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    '₱${unitPrice.toStringAsFixed(0)} × $qty',
                                    style: AppConstants.bodyStyle(
                                      fontSize: 10,
                                      color: AppConstants.secondary.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    }),

                    // ── Dashed divider (between items and total) ──
                    _buildDashedDivider(),

                    const SizedBox(height: 16),

                    // ── VAT Breakdown (VAT-inclusive, 12%) ──
                    _buildVATBreakdown(total),
                    const SizedBox(height: 12),

                    // ── Payment method ──
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: paymentMethod.toLowerCase() == 'cash'
                                ? AppConstants.okStockColor.withValues(alpha: 0.10)
                                : AppConstants.statusConfirmedColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                paymentMethod.toLowerCase() == 'cash'
                                    ? Icons.payments_outlined
                                    : Icons.phone_android,
                                size: 14,
                                color: paymentMethod.toLowerCase() == 'cash'
                                    ? AppConstants.okStockColor
                                    : AppConstants.statusConfirmedColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                paymentMethod.toUpperCase(),
                                style: AppConstants.bodyStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: paymentMethod.toLowerCase() == 'cash'
                                      ? AppConstants.okStockColor
                                      : AppConstants.statusConfirmedColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'TOTAL',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.secondary.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // ── Total ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '₱${total.toStringAsFixed(0)}',
                          style: AppConstants.monoStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.secondary,
                          ),
                        ),
                      ],
                    ),

                    // ── Tendered / Change (cash only) ──
                    if (paymentMethod.toLowerCase() == 'cash' &&
                        (order['amount_tendered'] != null)) ...[
                      const SizedBox(height: 12),
                      _buildDashedDivider(),
                      const SizedBox(height: 12),
                      _buildReceiptInfoRow(
                        'Amount Tendered',
                        '₱${((order['amount_tendered'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                      ),
                      const SizedBox(height: 6),
                      _buildReceiptInfoRow(
                        'Change',
                        '₱${((order['change_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                      ),
                    ],
                    // ── GCash Reference Number ──
                    if (paymentMethod.toLowerCase() == 'gcash' &&
                        (order['gcash_reference_number']?.toString().isNotEmpty ?? false)) ...[
                      const SizedBox(height: 12),
                      _buildDashedDivider(),
                      const SizedBox(height: 12),
                      _buildReceiptInfoRow(
                        'GCash Ref #',
                        order['gcash_reference_number'].toString(),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Bottom dashed divider (tear-off) ──
                    _buildDashedDivider(),

                    const SizedBox(height: 12),

                    // ── Footer text ──
                    Text(
                      'Thank you for your purchase!',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.35),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashedDivider() {
    return Row(
      children: List.generate(
        50,
        (i) => Expanded(
          child: Container(
            height: 1,
            color: i.isOdd
                ? Colors.transparent
                : AppConstants.primary.withValues(alpha: 0.18),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
        ),
        Text(
          value,
          style: AppConstants.monoStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppConstants.secondary,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  /// VAT-inclusive breakdown (Philippine retail convention).
  /// Listed prices already include 12% VAT.
  Widget _buildVATBreakdown(double total) {
    final vatableSales = total / 1.12;
    final vatAmount = total - vatableSales;

    return Column(
      children: [
        _buildReceiptInfoRow(
          'VATable Sales',
          '₱${vatableSales.toStringAsFixed(2)}',
        ),
        const SizedBox(height: 6),
        _buildReceiptInfoRow(
          'VAT (12%)',
          '₱${vatAmount.toStringAsFixed(2)}',
        ),
      ],
    );
  }
}
