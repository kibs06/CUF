import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/order_provider.dart';
import '../../widgets/sole_card.dart';

class SellerApprovalScreen extends StatefulWidget {
  final bool isStandalonePage;

  const SellerApprovalScreen({super.key, this.isStandalonePage = false});

  @override
  State<SellerApprovalScreen> createState() => _SellerApprovalScreenState();
}

class _SellerApprovalScreenState extends State<SellerApprovalScreen> {
  String? _busyUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<OrderProvider>(context, listen: false).loadProfiles();
    });
  }

  void _handleApproval(String userId, String name, bool approve) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceLight,
        title: Text(
          approve ? 'Approve Seller?' : 'Reject Request?',
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
        content: Text(
          approve
              ? 'Authorize "$name" to upload products and execute register POS sales?'
              : 'Reject seller registration application for "$name"?',
          style: AppConstants.bodyStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppConstants.bodyStyle(color: AppConstants.secondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: approve
                  ? AppConstants.success
                  : AppConstants.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              approve ? 'Approve' : 'Reject',
              style: AppConstants.bodyStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);
      setState(() => _busyUserId = userId);
      final success = approve
          ? await orderProvider.approveSeller(userId)
          : await orderProvider.rejectSeller(userId);
      if (mounted) setState(() => _busyUserId = null);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? approve
                      ? '$name is now an authorized Seller!'
                      : 'Application rejected.'
                : 'Unable to update seller application.',
          ),
          backgroundColor: success ? AppConstants.success : AppConstants.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final pendingSellers = orderProvider.profiles
        .where((p) => p['seller_status'] == AppConstants.statusPending)
        .toList();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Seller Authorization Queue',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.isStandalonePage
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: AppConstants.secondary,
                ),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          orderProvider.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppConstants.primary),
                )
              : pendingSellers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 48,
                        color: AppConstants.success.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'All seller applications are settled.',
                        style: AppConstants.bodyStyle(
                          color: AppConstants.secondary.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  itemCount: pendingSellers.length,
                  itemBuilder: (context, index) {
                    final applicant = pendingSellers[index];
                    final name = applicant['full_name'] ?? 'Unnamed Artisan';
                    final email = applicant['email'] ?? '';
                    final userId = applicant['id'];
                    final isBusy = _busyUserId == userId;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: SoleCard(
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppConstants.primary
                                      .withValues(alpha: 0.1),
                                  child: const Icon(
                                    Icons.workspace_premium,
                                    color: AppConstants.primary,
                                  ), // Leather / seller icon
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: AppConstants.bodyStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        email,
                                        style: AppConstants.bodyStyle(
                                          fontSize: 12,
                                          color: Colors.black45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Reject Outlined
                                OutlinedButton(
                                  onPressed: isBusy
                                      ? null
                                      : () => _handleApproval(
                                          userId,
                                          name,
                                          false,
                                        ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: AppConstants.error,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    'Reject',
                                    style: AppConstants.bodyStyle(
                                      color: AppConstants.error,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Approve Outlined/Filled
                                OutlinedButton(
                                  onPressed: isBusy
                                      ? null
                                      : () =>
                                            _handleApproval(userId, name, true),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: AppConstants.success,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    'Approve',
                                    style: AppConstants.bodyStyle(
                                      color: AppConstants.success,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
