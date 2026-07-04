import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_timeline.dart';

class OrderTrackingScreen extends StatelessWidget {
  final Map<String, dynamic> order;

  const OrderTrackingScreen({
    super.key,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    final orderId = order['id'];
    final status = (order['status'] as String).toLowerCase();
    
    // Map status string to index
    int activeIndex = 0;
    if (status == AppConstants.statusPreparing) {
      activeIndex = 1;
    } else if (status == AppConstants.statusReady) {
      activeIndex = 2;
    } else if (status == AppConstants.statusReceived) {
      activeIndex = 3;
    }

    final timelineItems = [
      const SoleTimelineItem(
        title: 'Order Placed',
        description: 'Artisan shop received your craft request.',
        time: 'June 15, 10:30 AM',
      ),
      const SoleTimelineItem(
        title: 'Being Prepared',
        description: 'Leather cutting & welt stitching active at Carcar studio.',
        time: 'June 15, 2:00 PM',
      ),
      const SoleTimelineItem(
        title: 'Ready for Pickup / Delivery',
        description: 'Shoe finished, polished, and boxed for handover.',
        time: '',
      ),
      const SoleTimelineItem(
        title: 'Received',
        description: 'Order handed over. Wear it in style!',
        time: '',
      ),
    ];

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Track Order #$orderId',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order header details card
                SoleCard(
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Carcar Craft Collection',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Size: EU ${order['size']}',
                            style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      Text(
                        '₱${(order['total_amount'] as double).toStringAsFixed(2)}',
                        style: AppConstants.monoStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                Text(
                  'Production Progress',
                  style: AppConstants.headlineStyle(fontSize: 18),
                ),
                const SizedBox(height: 20),

                // Vertical Timeline
                SoleCard(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: SoleTimeline(
                    items: timelineItems,
                    activeIndex: activeIndex,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
