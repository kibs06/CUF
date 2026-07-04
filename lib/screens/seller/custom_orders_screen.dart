import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/order_provider.dart';
import '../../widgets/seller/seller_status_chip.dart';

class CustomOrdersScreen extends StatefulWidget {
  const CustomOrdersScreen({super.key});

  @override
  State<CustomOrdersScreen> createState() => _CustomOrdersScreenState();
}

class _CustomOrdersScreenState extends State<CustomOrdersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<OrderProvider>(context, listen: false).loadCustomizations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final customs = orderProvider.customizations;

    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          'Custom Orders',
          style: AppConstants.bodyStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: orderProvider.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppConstants.primary))
          : customs.isEmpty
              ? Center(
                  child: Text(
                    'No custom requests yet',
                    style: AppConstants.bodyStyle(color: Colors.grey.shade400),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: customs.length,
                  itemBuilder: (context, index) {
                    final c = customs[index];
                    final status = c['status'] ?? 'pending';
                    final isPending = status == 'pending';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppConstants.sellerCardBg,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppConstants.sellerShadow,
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                c['base_name'] ?? 'Custom Design',
                                style: AppConstants.bodyStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppConstants.secondary,
                                ),
                              ),
                              SellerStatusChip(status: status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _detailRow('Color', c['color'] ?? ''),
                          _detailRow('Material', c['material'] ?? ''),
                          if (c['special_request'] != null && (c['special_request'] as String).isNotEmpty)
                            _detailRow('Request', c['special_request']),
                          if (isPending) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 36,
                                    child: FilledButton(
                                      onPressed: () async {
                                        // Approve
                                        await Provider.of<OrderProvider>(context, listen: false)
                                            .updateOrderStatus(c['id'], 'confirmed');
                                      },
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppConstants.accent,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: Text(
                                        'Approve',
                                        style: AppConstants.bodyStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SizedBox(
                                    height: 36,
                                    child: OutlinedButton(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Reject request?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                                              FilledButton(
                                                onPressed: () {
                                                  Navigator.of(ctx).pop();
                                                },
                                                style: FilledButton.styleFrom(backgroundColor: AppConstants.error),
                                                child: const Text('Reject'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: AppConstants.error),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: Text(
                                        'Reject',
                                        style: AppConstants.bodyStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppConstants.error,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: AppConstants.bodyStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppConstants.bodyStyle(fontSize: 12, color: AppConstants.secondary),
            ),
          ),
        ],
      ),
    );
  }
}
