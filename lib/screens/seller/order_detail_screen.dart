import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import '../../providers/order_provider.dart';
import '../../services/message_service.dart';
import '../../widgets/seller/seller_status_chip.dart';
import '../../widgets/chat/chat_view.dart';

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _isUpdating = false;

  Map<String, dynamic> get order => widget.order;

  String get _currentStatus => (order['status'] ?? 'pending').toString();

  String? get _nextStatus {
    // Maps seller-facing status → the value sent to SupabaseService.updateOrderStatus().
    // SupabaseService._mapUiStatusToDb() then translates to DB-legal values.
    switch (_currentStatus.toLowerCase()) {
      case 'pending':
        return 'confirmed';    // → DB: preparing
      case 'preparing':
        return 'ready';        // → DB: ready
      case 'ready':
        return 'delivered';    // → DB: delivered (Part D)
      case 'cancelled':
        return 'pending';
      default:
        return null;
    }
  }

  String get _actionLabel {
    switch (_currentStatus.toLowerCase()) {
      case 'pending':
        return '';
      case 'preparing':
        return 'Mark Ready';
      case 'ready':
        return 'Mark Delivered';
      case 'cancelled':
        return 'Restore';
      default:
        return '';
    }
  }

  Color get _actionColor {
    switch (_currentStatus.toLowerCase()) {
      case 'pending':
        return AppConstants.statusConfirmedColor;
      case 'preparing':
        return AppConstants.statusReadyColor;
      case 'ready':
        return AppConstants.statusDeliveredColor;
      case 'cancelled':
        return AppConstants.statusPendingColor;
      default:
        return AppConstants.accent;
    }
  }

  bool get _canReject => _currentStatus.toLowerCase() == 'pending';

  Future<void> _performReject() async {
    final orderId = order['id'];
    if (orderId == null || _isUpdating) return;

    final shortId = orderId.toString().length >= 8
        ? orderId.toString().substring(0, 8)
        : orderId.toString();

    final customerName = order['customer_name'] ?? 'Customer';
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppConstants.sellerCardBg,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SellerStatusChip(status: _currentStatus),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ),
                SellerStatusChip(status: 'cancelled'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cancel_outlined,
                  size: 22,
                  color: AppConstants.error,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Reject Order #$shortId?',
                    style: AppConstants.bodyStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              customerName,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: 'Reason for rejection (optional)',
                hintStyle: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: Colors.grey.shade400,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppConstants.borderGray),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: AppConstants.bodyStyle(fontSize: 13),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Text(
              'The customer will be notified.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
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
              backgroundColor: AppConstants.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Reject',
              style: AppConstants.bodyStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isUpdating = true);

    try {
      final success = await Provider.of<OrderProvider>(
        context,
        listen: false,
      ).cancelOrder(
        orderId: orderId,
        newStatus: 'cancelled',
        reason: reasonController.text.trim().isEmpty 
            ? 'Rejected by seller' 
            : reasonController.text.trim(),
      );

      if (mounted) {
        setState(() => _isUpdating = false);

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order #$orderId has been rejected'),
              backgroundColor: AppConstants.success,
            ),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to reject order. Please try again.'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting order: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  Future<void> _performStatusUpdate() async {
    final orderId = order['id'];
    final nextStatus = _nextStatus;
    if (orderId == null || nextStatus == null || _isUpdating) return;

    // NOTE: A true race-condition guard would re-fetch status from the server
    // before updating. The provider's error handling will catch stale-status
    // failures gracefully, so we skip the extra round-trip here.

    // Build short order ID for display (first 8 chars)
    final shortId = orderId.toString().length >= 8
        ? orderId.toString().substring(0, 8)
        : orderId.toString();

    // Extract context for dialog
    final customerName = order['customer_name'] ?? 'Customer';
    final itemCount = (order['quantity'] as num?)?.toInt() ?? 0;
    final totalAmount = (order['total_amount'] is double)
        ? order['total_amount'] as double
        : (order['total_amount'] ?? 0).toDouble();

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppConstants.sellerCardBg,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status transition chips
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SellerStatusChip(status: _currentStatus),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ),
                SellerStatusChip(status: nextStatus),
              ],
            ),
            const SizedBox(height: 16),
            // Title with icon
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 22,
                  color: AppConstants.statusConfirmedColor,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Confirm Order #$shortId?',
                    style: AppConstants.bodyStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Compact order context
            Text(
              '$customerName · $itemCount item${itemCount == 1 ? '' : 's'} · ₱${totalAmount.toStringAsFixed(0)}',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Notification note
            Text(
              'The customer will be notified.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
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
              backgroundColor: AppConstants.statusConfirmedColor,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Confirm',
              style: AppConstants.bodyStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Set loading state
    setState(() => _isUpdating = true);

    try {
      final success = await Provider.of<OrderProvider>(
        context,
        listen: false,
      ).updateOrderStatus(order['id'], nextStatus);

      if (mounted) {
        setState(() => _isUpdating = false);

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order #$orderId updated to $nextStatus'),
              backgroundColor: AppConstants.success,
            ),
          );
          // Pop with true so ManageOrdersScreen knows to refresh
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update order. Please try again.'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating order: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  Future<void> _messageCustomer() async {
    final customerId = order['customer_id']?.toString();
    if (customerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer ID not available'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Get store ID
    final store = await Supabase.instance.client
        .from('stores')
        .select('id')
        .eq('owner_id', userId)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();

    if (store == null || !mounted) return;

    final storeId = store['id']?.toString();
    if (storeId == null) return;

    // Get or create conversation
    try {
      final conversation = await MessageService.instance.getOrCreateConversation(
        storeId: storeId,
        customerId: customerId,
      );

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatView(
            conversationId: conversation.id,
            viewerRole: 'seller',
            otherPartyName: order['customer_name'] ?? 'Customer',
            orderReferenceId: order['id']?.toString(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open chat with customer. Please try again.'),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = order['id'] ?? '';
    final status = _currentStatus;
    final customerName = order['customer_name'] ?? 'Customer';
    final phone = order['customer_phone'] ?? '';
    final itemCount = order['quantity'] ?? 0;
    final totalAmount = (order['total_amount'] is double)
        ? order['total_amount'] as double
        : (order['total_amount'] ?? 0).toDouble();
    final deliveryAddress = order['delivery_address'] ?? 'In-Store POS Handover';
    final paymentMethod = order['payment_method'] ?? 'Cash';
    final size = order['size'] ?? '40';
    final color = order['color'] ?? 'Standard Brown';

    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          'Order #$id',
          style: AppConstants.monoStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and summary
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppConstants.sellerCardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppConstants.sellerShadow,
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Order #${id.toString().length >= 8 ? id.toString().substring(0, 8) : id}',
                          style: AppConstants.monoStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.secondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SellerStatusChip(status: status),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _infoRow('Customer', customerName),
                  if (phone.isNotEmpty) _infoRow('Phone', phone),
                  _infoRow('Items', '$itemCount'),
                  _infoRow('Size', size),
                  _infoRow('Color', color),
                  _infoRow('Fulfillment', deliveryAddress),
                  _infoRow('Payment', paymentMethod),
                  const SizedBox(height: 12),
                  // Message Customer button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _messageCustomer(),
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text(
                        'Message Customer',
                        style: AppConstants.bodyStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppConstants.primary,
                        side: const BorderSide(color: AppConstants.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: AppConstants.bodyStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.secondary,
                        ),
                      ),
                      Text(
                        '\u20B1${totalAmount.toStringAsFixed(0)}',
                        style: AppConstants.monoStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Timeline section
            Text(
              'TIMELINE',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppConstants.sellerCardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppConstants.sellerShadow,
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _timelineStep('Order Placed', true),
                  _timelineStep('Confirmed', status != 'pending'),
                  _timelineStep('Ready', status == 'ready' || status == 'delivered' || status == 'received'),
                  _timelineStep('Delivered', status == 'delivered' || status == 'received'),
                  _timelineStep('Received', status == 'received'),
                  if (status == 'cancelled') ...[
                    const Divider(height: 16, color: AppConstants.borderGray),
                    _buildCancellationReason(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      // Action buttons at bottom
      bottomNavigationBar: (_actionLabel.isNotEmpty || _canReject)
          ? Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              decoration: BoxDecoration(
                color: AppConstants.sellerCardBg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: _canReject
                    ? Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: _isUpdating ? null : _performReject,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppConstants.error),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isUpdating
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppConstants.error,
                                        ),
                                      )
                                    : Text(
                                        'Reject',
                                        style: AppConstants.bodyStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppConstants.error,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: FilledButton(
                                onPressed: _isUpdating ? null : _performStatusUpdate,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _actionColor,
                                  disabledBackgroundColor: _actionColor.withValues(alpha: 0.6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isUpdating
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'Confirm',
                                        style: AppConstants.bodyStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _isUpdating ? null : _performStatusUpdate,
                          style: FilledButton.styleFrom(
                            backgroundColor: _actionColor,
                            disabledBackgroundColor: _actionColor.withValues(alpha: 0.6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isUpdating
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _actionLabel,
                                  style: AppConstants.bodyStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
              ),
            )
          : null,
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppConstants.bodyStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppConstants.bodyStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancellationReason() {
    final reason = order['cancellation_reason']?.toString();
    final details = order['cancellation_details']?.toString();
    final cancelledAt = order['cancelled_at']?.toString();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppConstants.error.withValues(alpha: 0.15),
            ),
            child: Icon(
              Icons.cancel_outlined,
              size: 14,
              color: AppConstants.error,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cancelled',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.error,
                  ),
                ),
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppConstants.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reason:',
                          style: AppConstants.bodyStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          reason,
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: AppConstants.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (details != null && details.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Details:',
                          style: AppConstants.bodyStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          details,
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: AppConstants.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (cancelledAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Cancelled ${_formatTimestamp(cancelledAt)}',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String timestamp) {
    final dt = DateTime.tryParse(timestamp);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _timelineStep(String label, bool isComplete) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isComplete ? AppConstants.okStockColor : Colors.grey.shade200,
            ),
            child: Icon(
              isComplete ? Icons.check : Icons.circle_outlined,
              size: 14,
              color: isComplete ? Colors.white : Colors.grey.shade400,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: isComplete ? FontWeight.w600 : FontWeight.normal,
              color: isComplete ? AppConstants.secondary : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}
