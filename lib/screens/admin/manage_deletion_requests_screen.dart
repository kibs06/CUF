import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';

/// Admin screen for reviewing and processing user account deletion requests.
///
/// Shows a tabbed view (Pending / Approved / Rejected) of all deletion
/// requests. Admins can approve (which permanently deletes the user) or
/// reject a pending request.
class ManageDeletionRequestsScreen extends StatefulWidget {
  const ManageDeletionRequestsScreen({super.key});

  @override
  State<ManageDeletionRequestsScreen> createState() =>
      _ManageDeletionRequestsScreenState();
}

class _ManageDeletionRequestsScreenState
    extends State<ManageDeletionRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _approved = [];
  List<Map<String, dynamic>> _rejected = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      final pendingRes = await client
          .from('deletion_requests')
          .select('*, profiles!deletion_requests_user_id_fkey(full_name, email)')
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final approvedRes = await client
          .from('deletion_requests')
          .select('*, profiles!deletion_requests_user_id_fkey(full_name, email)')
          .eq('status', 'approved')
          .order('reviewed_at', ascending: false);

      final rejectedRes = await client
          .from('deletion_requests')
          .select('*, profiles!deletion_requests_user_id_fkey(full_name, email)')
          .eq('status', 'rejected')
          .order('reviewed_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _pending = List<Map<String, dynamic>>.from(pendingRes);
        _approved = List<Map<String, dynamic>>.from(approvedRes);
        _rejected = List<Map<String, dynamic>>.from(rejectedRes);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load requests: $e';
        _loading = false;
      });
    }
  }

  Future<void> _approveRequest(Map<String, dynamic> request) async {
    final profile = request['profiles'] as Map<String, dynamic>?;
    final userName = profile?['full_name'] as String? ?? 'Unknown';

    // First confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceLight,
        title: Text(
          'Approve Deletion?',
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
        content: Text(
          'This will permanently delete "$userName" — their account, store, '
          'and all data. This cannot be undone.\n\n'
          'Customer orders placed at their store will be kept but detached.',
          style: AppConstants.bodyStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppConstants.bodyStyle(color: AppConstants.secondary)),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete Forever',
                style: AppConstants.bodyStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Second confirmation: type DELETE
    final deleteController = TextEditingController();
    final typedCorrectly = ValueNotifier<bool>(false);
    final doubleCheck = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppConstants.surfaceLight,
          title: Text('Are you absolutely sure?',
              style: AppConstants.headlineStyle(fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently removes the account and cannot be undone. '
                'Type DELETE to confirm.',
                style: AppConstants.bodyStyle(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: deleteController,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Type DELETE',
                  hintStyle: AppConstants.bodyStyle(
                      fontSize: 14, color: Colors.grey.shade400),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (v) {
                  typedCorrectly.value = v == 'DELETE';
                  setDialogState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style:
                      AppConstants.bodyStyle(color: AppConstants.secondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: typedCorrectly.value
                    ? AppConstants.error
                    : Colors.grey.shade300,
              ),
              onPressed: typedCorrectly.value
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: Text('Delete Forever',
                  style: AppConstants.bodyStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (doubleCheck != true || !mounted) return;

    // Process the deletion
    try {
      final result = await Supabase.instance.client
          .rpc('approve_deletion_request', params: {
        'p_request_id': request['id'],
      });

      if (!mounted) return;

      final data = result.data;
      if (data is Map && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$userName has been permanently deleted.'),
            backgroundColor: AppConstants.success,
          ),
        );
        _loadRequests(); // Refresh list
      } else {
        final msg = data is Map ? data['message'] : 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $msg'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    final profile = request['profiles'] as Map<String, dynamic>?;
    final userName = profile?['full_name'] as String? ?? 'Unknown';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceLight,
        title: Text(
          'Reject Deletion Request?',
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
        content: Text(
          'Reject the deletion request from "$userName"? Their account '
          'will remain active.',
          style: AppConstants.bodyStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppConstants.bodyStyle(color: AppConstants.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppConstants.secondary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Reject',
                style: AppConstants.bodyStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final result = await Supabase.instance.client
          .rpc('reject_deletion_request', params: {
        'p_request_id': request['id'],
      });

      if (!mounted) return;

      final data = result.data;
      if (data is Map && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deletion request from "$userName" rejected.'),
            backgroundColor: AppConstants.success,
          ),
        );
        _loadRequests();
      } else {
        final msg = data is Map ? data['message'] : 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $msg'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Deletion Requests',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRequests,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppConstants.primary,
          unselectedLabelColor: AppConstants.secondary,
          indicatorColor: AppConstants.primary,
          tabs: [
            Tab(text: 'Pending (${_pending.length})'),
            Tab(text: 'Approved (${_approved.length})'),
            Tab(text: 'Rejected (${_rejected.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: AppConstants.error),
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: AppConstants.bodyStyle(
                                color: AppConstants.error),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadRequests,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRequestList(_pending, isPending: true),
                    _buildRequestList(_approved, isPending: false),
                    _buildRequestList(_rejected, isPending: false),
                  ],
                ),
    );
  }

  Widget _buildRequestList(List<Map<String, dynamic>> requests,
      {required bool isPending}) {
    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPending ? Icons.inbox_outlined : Icons.check_circle_outline,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              isPending ? 'No pending requests' : 'No requests in this category',
              style: AppConstants.bodyStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) =>
            _buildRequestCard(requests[index], isPending: isPending),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request,
      {required bool isPending}) {
    final profile = request['profiles'] as Map<String, dynamic>?;
    final userName = profile?['full_name'] as String? ?? 'Unknown';
    final userEmail = profile?['email'] as String? ?? 'No email';
    final reason = request['reason'] as String?;
    final createdAt = request['created_at'] as String?;
    final reviewedAt = request['reviewed_at'] as String?;

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPending
              ? Colors.amber.withValues(alpha: 0.3)
              : AppConstants.borderGray,
          width: isPending ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      AppConstants.primary.withValues(alpha: 0.1),
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: AppConstants.bodyStyle(
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: AppConstants.bodyStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        userEmail,
                        style: AppConstants.bodyStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                if (isPending)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Pending',
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFC47D00),
                      ),
                    ),
                  ),
              ],
            ),

            // Reason
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Reason: $reason',
                  style: AppConstants.bodyStyle(
                      fontSize: 13, color: Colors.grey.shade600),
                ),
              ),
            ],

            // Timestamps
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.access_time,
                    size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  'Requested: ${_formatDate(createdAt)}',
                  style: AppConstants.bodyStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
                if (reviewedAt != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.check,
                      size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text(
                    'Reviewed: ${_formatDate(reviewedAt)}',
                    style: AppConstants.bodyStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),

            // Action buttons (only for pending)
            if (isPending) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(
                        'Reject',
                        style: AppConstants.bodyStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppConstants.secondary),
                        foregroundColor: AppConstants.secondary,
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _rejectRequest(request),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(
                        'Approve & Delete',
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.error,
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _approveRequest(request),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '—';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final month = dt.month.toString().padLeft(2, '0');
      final day = dt.day.toString().padLeft(2, '0');
      final hour = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$month/$day/${dt.year} $hour:$min';
    } catch (_) {
      return isoDate;
    }
  }
}
