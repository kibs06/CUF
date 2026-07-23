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

    // Resolve display label from machine key
    final displayCategory = ReportService.categoryLabel(type, category);

    // For 'other' category, show truncated custom details as subtitle
    final subtitle = category == 'other' && customDetails != null && customDetails.isNotEmpty
        ? 'Other: "${customDetails.length > 50 ? '${customDetails.substring(0, 50)}...' : customDetails}"'
        : displayCategory;

    return Container(
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
    );
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
