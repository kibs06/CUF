import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/order_provider.dart';
import '../../providers/product_provider.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_metric_card.dart';
import 'seller_approval_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<OrderProvider>(context, listen: false).loadProfiles();
      Provider.of<OrderProvider>(context, listen: false).loadOrders();
      Provider.of<ProductProvider>(context, listen: false).loadProducts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final productProvider = context.watch<ProductProvider>();

    final totalUsers = orderProvider.profiles.length;
    final activeSellers = orderProvider.profiles.where((p) => p['role'] == AppConstants.roleSeller).length;
    final totalProducts = productProvider.products.length;
    final double systemRevenue = orderProvider.orders.fold(0.0, (sum, o) => sum + (o['total_amount'] as double));

    final pendingApplications = orderProvider.profiles.where(
      (p) => p['seller_status'] == AppConstants.statusPending && p['role'] == AppConstants.roleCustomer,
    ).toList();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text('Admin Operations Control', style: AppConstants.headlineStyle(fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pending Applications warning banner
                if (pendingApplications.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () {
                      // Navigate to Approval screen (could switch tabs or push)
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SellerApprovalScreen(isStandalonePage: true),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active, color: Color(0xFFC47D00)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pending Seller Requests',
                                  style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, color: const Color(0xFFC47D00)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'There are ${pendingApplications.length} artisans waiting for seller profile authorization.',
                                  style: AppConstants.bodyStyle(fontSize: 12, color: const Color(0xFFC47D00)),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Color(0xFFC47D00)),
                        ],
                      ),
                    ),
                  ),
                ],

                // Grid 2x2 stats
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.3,
                  children: [
                    SoleMetricCard(
                      title: "Total Accounts",
                      value: "$totalUsers",
                      trend: "+3.5% registration",
                      isPositiveTrend: true,
                      icon: Icons.people_alt_outlined,
                      iconColor: AppConstants.primary,
                    ),
                    SoleMetricCard(
                      title: "Authorized Sellers",
                      value: "$activeSellers",
                      trend: "Active workshops",
                      isPositiveTrend: true,
                      icon: Icons.storefront_outlined,
                      iconColor: AppConstants.primary,
                    ),
                    SoleMetricCard(
                      title: "System Products",
                      value: "$totalProducts",
                      trend: "Unique designs",
                      isPositiveTrend: true,
                      icon: Icons.grid_view_outlined,
                      iconColor: AppConstants.accent,
                    ),
                    SoleMetricCard(
                      title: "Gross Sales Value",
                      value: "₱${systemRevenue.toStringAsFixed(0)}",
                      trend: "+24.8% growth",
                      isPositiveTrend: true,
                      icon: Icons.analytics_outlined,
                      iconColor: AppConstants.success,
                    ),
                  ],
                ),
                
                const SizedBox(height: 28),

                // System info card
                Text('Workshop Health', style: AppConstants.headlineStyle(fontSize: 18)),
                const SizedBox(height: 12),
                SoleCard(
                  color: Colors.white,
                  child: Column(
                    children: [
                      _buildHealthIndicator('AR Foundation Pipeline', 'Healthy (Unity Ready)', AppConstants.success),
                      const Divider(color: AppConstants.borderGray, height: 16),
                      _buildHealthIndicator('Supabase DB Synced', 'Active Connection Mocked', AppConstants.primary),
                      const Divider(color: AppConstants.borderGray, height: 16),
                      _buildHealthIndicator('Cebu Delivery API', 'Nominal Latency', AppConstants.success),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthIndicator(String name, String desc, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: AppConstants.bodyStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(desc, style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black45)),
          ],
        ),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ],
    );
  }
}
