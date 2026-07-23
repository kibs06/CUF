import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/report_service.dart';

/// Screen showing the user's submitted reports with status tracking.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Future<List<Map<String, dynamic>>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = ReportService.instance.getMyReports();
  }

  Future<void> _refresh() async {
    setState(() {
      _reportsFuture = ReportService.instance.getMyReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFF5EDE4), size: 24),
        title: Text(
          'My Reports',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFF5EDE4),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppConstants.primary,
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _reportsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppConstants.primary),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48,
                          color: AppConstants.error.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text('Failed to load reports',
                          style: AppConstants.bodyStyle(
                              fontSize: 15, color: AppConstants.secondary)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final reports = snapshot.data ?? [];
            if (reports.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag_outlined, size: 48,
                              color: AppConstants.primary.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          Text('No reports yet',
                              style: AppConstants.bodyStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppConstants.secondary)),
                          const SizedBox(height: 8),
                          Text(
                            'If you encounter any issues, you can report them from chat, orders, or settings.',
                            style: AppConstants.bodyStyle(
                                fontSize: 13,
                                color: AppConstants.secondary.withValues(alpha: 0.6)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              itemBuilder: (context, index) => _buildReportCard(reports[index]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final status = report['status'] as String? ?? 'pending';
    final type = report['type'] as String? ?? 'other';
    final category = report['category'] as String? ?? '';
    final createdAt = report['created_at'] as String?;
    final isHighPriority = report['priority'] == 'high';
    final customDetails = report['custom_details'] as String?;
    final reporterNotified = report['reporter_notified'] as bool? ?? false;
    final reporterNotificationText = report['reporter_notification_text'] as String?;

    // Resolve display label from machine key
    final displayCategory = ReportService.categoryLabel(type, category);

    // For 'other' category, show truncated custom details as subtitle
    final subtitle = category == 'other' && customDetails != null && customDetails.isNotEmpty
        ? 'Other: "${customDetails.length > 50 ? '${customDetails.substring(0, 50)}...' : customDetails}"'
        : displayCategory;

    return GestureDetector(
      onTap: () => _showReportDetail(report),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: type badge + priority + status
            Row(
              children: [
                // Type icon
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _typeColor(type).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(_typeIcon(type), size: 16, color: _typeColor(type)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _typeLabel(type),
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Priority badge
                if (isHighPriority)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppConstants.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'HIGH',
                      style: AppConstants.bodyStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.error,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                // Status badge
                _StatusBadge(status: status),
              ],
            ),

            // Admin response indicator (if notified)
            if (reporterNotified && reporterNotificationText != null && reporterNotificationText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppConstants.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppConstants.success.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.support_agent, size: 16, color: AppConstants.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Support responded',
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.success,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            reporterNotificationText.length > 80
                                ? '${reporterNotificationText.substring(0, 80)}...'
                                : reporterNotificationText,
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              color: AppConstants.secondary.withValues(alpha: 0.7),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: AppConstants.secondary.withValues(alpha: 0.4)),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            // Date
            if (createdAt != null)
              Text(
                'Submitted ${_formatDate(createdAt)}',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showReportDetail(Map<String, dynamic> report) {
    final status = report['status'] as String? ?? 'pending';
    final type = report['type'] as String? ?? 'other';
    final category = report['category'] as String? ?? '';
    final createdAt = report['created_at'] as String?;
    final customDetails = report['custom_details'] as String?;
    final actionTaken = report['action_taken'] as String?;
    final reporterNotified = report['reporter_notified'] as bool? ?? false;
    final reporterNotificationText = report['reporter_notification_text'] as String?;
    final displayCategory = ReportService.categoryLabel(type, category);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppConstants.secondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _typeLabel(type),
                            style: AppConstants.bodyStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.secondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayCategory,
                            style: AppConstants.bodyStyle(
                              fontSize: 13,
                              color: AppConstants.secondary.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(status: status),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Submitted date
                    _buildDetailRow('Submitted', createdAt != null ? _formatDate(createdAt) : '—'),

                    // Custom details (for 'other' category)
                    if (category == 'other' && customDetails != null && customDetails.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Your Description',
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.secondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppConstants.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          customDetails,
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            color: AppConstants.secondary,
                          ),
                        ),
                      ),
                    ],

                    // Action taken
                    if (actionTaken != null && actionTaken != 'none') ...[
                      const SizedBox(height: 16),
                      _buildDetailRow('Action Taken', _formatAction(actionTaken)),
                    ],

                    // Admin response
                    if (reporterNotified && reporterNotificationText != null && reporterNotificationText.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppConstants.success.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppConstants.success.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.support_agent, size: 18, color: AppConstants.success),
                                const SizedBox(width: 8),
                                Text(
                                  'Response from Support',
                                  style: AppConstants.bodyStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppConstants.success,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              reporterNotificationText,
                              style: AppConstants.bodyStyle(
                                fontSize: 13,
                                color: AppConstants.secondary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // No response yet hint
                    if (!reporterNotified && (status == 'under_review' || status == 'pending')) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppConstants.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.hourglass_empty, size: 18, color: AppConstants.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Your report is being reviewed. You\'ll receive a notification when there\'s an update.',
                                style: AppConstants.bodyStyle(
                                  fontSize: 12,
                                  color: AppConstants.secondary.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
          Text(
            value,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppConstants.secondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatAction(String action) {
    switch (action) {
      case 'warning_issued': return 'Warning issued';
      case 'content_removed': return 'Content removed';
      case 'seller_suspended': return 'Seller suspended';
      case 'refund_issued': return 'Refund issued';
      case 'other': return 'Other action taken';
      default: return action;
    }
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'message': return 'Message Report';
      case 'product': return 'Product Report';
      case 'seller': return 'Seller Report';
      case 'other': return 'General Report';
      default: return 'Report';
    }
  }

  static IconData _typeIcon(String type) {
    switch (type) {
      case 'message': return Icons.chat_bubble_outline;
      case 'product': return Icons.shopping_bag_outlined;
      case 'seller': return Icons.storefront_outlined;
      case 'other': return Icons.help_outline;
      default: return Icons.flag_outlined;
    }
  }

  static Color _typeColor(String type) {
    switch (type) {
      case 'message': return const Color(0xFF5C6BC0);
      case 'product': return AppConstants.primary;
      case 'seller': return const Color(0xFFE8A020);
      case 'other': return const Color(0xFF78909C);
      default: return AppConstants.secondary;
    }
  }

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (_) {
      return iso;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'pending' => ('Pending', const Color(0xFFE8A020)),
      'under_review' => ('Under Review', const Color(0xFF5C6BC0)),
      'resolved' => ('Resolved', AppConstants.success),
      'dismissed' => ('Dismissed', const Color(0xFF78909C)),
      _ => (status, AppConstants.secondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: AppConstants.bodyStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
