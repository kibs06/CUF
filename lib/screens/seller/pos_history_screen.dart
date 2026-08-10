import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../widgets/shimmer_box.dart';
import '../../services/order_service.dart';
import '../../services/product_service.dart';
import '../../services/connectivity_service.dart';
import 'pos_receipt_detail_screen.dart';

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Screen showing past POS (in-person) transactions for the current seller.
///
/// Queries orders with `source='pos'` scoped to the seller's store,
/// ordered most-recent-first. Cards styled as digital receipts.
class PosHistoryScreen extends StatefulWidget {
  const PosHistoryScreen({super.key});

  @override
  State<PosHistoryScreen> createState() => _PosHistoryScreenState();
}

/// Date range presets for filtering POS history.
enum _DateRange {
  all,
  today,
  thisWeek,
  thisMonth,
}

class _PosHistoryScreenState extends State<PosHistoryScreen> {
  final OrderService _orderService = OrderService();
  List<Map<String, dynamic>> _allTransactions = [];
  bool _isLoading = true;
  String? _error;
  _DateRange _selectedRange = _DateRange.all;
  StreamSubscription<bool>? _connectivitySub;
  bool _wasOffline = false;
  String _storeName = 'Store';
  String _storeLocation = '';
  String _sellerName = '';
  bool _storeDetailsFetched = false;

  @override
  void initState() {
    super.initState();
    _wasOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.isOnlineStream.listen((isOnline) {
      if (isOnline && _wasOffline && mounted) {
        _loadHistory();
      }
      _wasOffline = !isOnline;
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final storeId = await ProductService.instance.getSellerStoreId();
      if (storeId == null) {
        setState(() {
          _allTransactions = [];
          _isLoading = false;
        });
        return;
      }

      // Fetch store details + seller name once (cached across refreshes)
      if (!_storeDetailsFetched) {
        try {
          final storeData = await Supabase.instance.client
              .from('stores')
              .select('name, location, owner_id')
              .eq('id', storeId)
              .maybeSingle();
          if (storeData != null && mounted) {
            _storeName = storeData['name']?.toString() ?? 'Store';
            _storeLocation = storeData['location']?.toString() ?? '';

            // Fetch seller name from profiles
            final ownerId = storeData['owner_id']?.toString();
            if (ownerId != null) {
              try {
                final profile = await Supabase.instance.client
                    .from('profiles')
                    .select('full_name')
                    .eq('id', ownerId)
                    .maybeSingle();
                if (profile != null && mounted) {
                  _sellerName = profile['full_name']?.toString() ?? '';
                }
              } catch (_) {
                // Ignore profile fetch failure
              }
            }
            if (mounted) _storeDetailsFetched = true;
          }
        } catch (_) {
          // Use defaults on failure
        }
      }

      final transactions = await _orderService.fetchPosHistory(storeId);
      if (mounted) {
        setState(() {
          _allTransactions = transactions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return '';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    // Older than a week — show date
    return '${_kMonths[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return '';
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  /// Compute the filtered list based on the selected date range.
  List<Map<String, dynamic>> get _filteredTransactions {
    if (_selectedRange == _DateRange.all) return _allTransactions;

    final now = DateTime.now();
    final from = switch (_selectedRange) {
      _DateRange.today => DateTime(now.year, now.month, now.day),
      _DateRange.thisWeek => DateTime(
        now.subtract(Duration(days: now.weekday - 1)).year,
        now.subtract(Duration(days: now.weekday - 1)).month,
        now.subtract(Duration(days: now.weekday - 1)).day,
      ),
      _DateRange.thisMonth => DateTime(now.year, now.month, 1),
      _ => DateTime(now.year, now.month, now.day), // unreachable
    };

    return _allTransactions.where((order) {
      final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '');
      if (createdAt == null) return false;
      return !createdAt.isBefore(from);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          'POS History',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date range filter chips
          if (!_isLoading && _allTransactions.isNotEmpty)
            _buildFilterBar(),
          // Transaction list or empty/error state
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      color: Colors.white,
      child: Column(
        children: [
          // Filter chips row
          Row(
            children: _DateRange.values.map((range) {
              final selected = _selectedRange == range;
              final label = switch (range) {
                _DateRange.all => 'All',
                _DateRange.today => 'Today',
                _DateRange.thisWeek => 'This Week',
                _DateRange.thisMonth => 'This Month',
              };
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: AppConstants.primary,
                  backgroundColor: AppConstants.sellerSurface,
                  labelStyle: AppConstants.bodyStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppConstants.secondary,
                  ),
                  onSelected: (_) => setState(() => _selectedRange = range),
                ),
              );
            }).toList(),
          ),
          // Revenue summary for filtered range
          if (_selectedRange != _DateRange.all) ...[
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final filtered = _filteredTransactions;
                final total = filtered.fold<double>(
                  0,
                  (sum, o) => sum + ((o['total_amount'] as num?)?.toDouble() ?? 0),
                );
                return Row(
                  children: [
                    Text(
                      '${filtered.length} transaction${filtered.length == 1 ? '' : 's'}',
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '₱${total.toStringAsFixed(0)}',
                      style: AppConstants.monoStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primary,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      // Skeleton receipt cards while history loads.
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: List.generate(
          4,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SellerTheme.cardBorder),
              boxShadow: AppConstants.sellerShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: 90, height: 10, borderRadius: 5),
                SizedBox(height: 16),
                ShimmerBox(
                  width: double.infinity,
                  height: 12,
                  borderRadius: 5,
                ),
                SizedBox(height: 10),
                ShimmerBox(width: 160, height: 12, borderRadius: 5),
                SizedBox(height: 16),
                Row(
                  children: [
                    ShimmerBox(width: 70, height: 16, borderRadius: 8),
                    Spacer(),
                    ShimmerBox(width: 70, height: 18, borderRadius: 5),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return _buildError();
    }

    final filtered = _filteredTransactions;
    if (filtered.isEmpty) {
      return _buildEmpty();
    }

    // Build flat list with date section headers
    final widgets = <Widget>[];
    String? lastDateKey;
    
    for (final order in filtered) {
      final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '');
      String dateKey;
      if (createdAt != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final orderDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
        
        if (orderDate == today) {
          dateKey = 'Today';
        } else if (orderDate == today.subtract(const Duration(days: 1))) {
          dateKey = 'Yesterday';
        } else {
          dateKey = '${_kMonths[createdAt.month - 1]} ${createdAt.day}, ${createdAt.year}';
        }
      } else {
        dateKey = 'Unknown Date';
      }
      
      // Add date section header when date changes
      if (dateKey != lastDateKey) {
        widgets.add(_buildDateSectionHeader(dateKey));
        lastDateKey = dateKey;
      }
      
      widgets.add(_buildReceiptCard(order));
    }
    
    return RefreshIndicator(
      color: AppConstants.primary,
      onRefresh: _loadHistory,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: widgets,
      ),
    );
  }

  /// Build the receipt tear-off dashed divider.
  Widget _buildReceiptDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: List.generate(
          60,
          (i) => Expanded(
            child: Container(
              height: 1,
              color: i.isOdd
                  ? Colors.transparent
                  : AppConstants.primary.withValues(alpha: 0.15),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Receipt-style transaction card
  // ---------------------------------------------------------------------------
  Widget _buildReceiptCard(Map<String, dynamic> order) {
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final paymentMethod = (order['payment_method'] ?? 'cash').toString();
    final items = order['order_items'] as List? ?? [];
    final itemsCount = order['items_count'] ?? items.length;
    final createdAt = order['created_at']?.toString();
    final shortId = order['id'].toString();
    final displayId = shortId.length >= 8 ? shortId.substring(0, 8) : shortId;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PosReceiptDetailScreen(
              order: order,
              storeName: _storeName,
              storeLocation: _storeLocation,
              sellerName: _sellerName,
            ),
          ),
        );
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Receipt header: order ID + timestamp ──
            Row(
              children: [
                Text(
                  '#$displayId',
                  style: AppConstants.monoStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_formatDate(createdAt)}  ${_formatTime(createdAt)}',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Itemized line items ──
            ...items.map<Widget>((item) {
              final name = item['product_name'] ?? 'Product';
              final size = item['size'] ?? '';
              final qty = item['quantity'] ?? 1;
              final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
              final lineTotal = unitPrice * qty;
              final imageUrl = item['product_image']?.toString() ?? '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product thumbnail (or quantity badge fallback)
                    if (imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          children: [
                            Image.network(
                              imageUrl,
                              width: 32,
                              height: 28,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => Container(
                                width: 32,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppConstants.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.inventory_2_outlined, size: 14, color: AppConstants.primary),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppConstants.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '$qty',
                                  style: AppConstants.monoStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      // Quantity badge fallback
                      Container(
                        width: 26,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppConstants.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$qty',
                          style: AppConstants.monoStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.primary,
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    // Item name + size
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: AppConstants.bodyStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppConstants.secondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (size.toString().isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              'Size $size',
                              style: AppConstants.bodyStyle(
                                fontSize: 11,
                                color: AppConstants.secondary.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Line subtotal
                    Text(
                      '₱${lineTotal.toStringAsFixed(0)}',
                      style: AppConstants.monoStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppConstants.secondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              );
            }),

            if (items.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$itemsCount item${itemsCount == 1 ? '' : 's'}',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],

            // ── Receipt divider (dashed tear-off) ──
            _buildReceiptDivider(),

            const SizedBox(height: 10),

            // ── Footer: payment method + total ──
            Row(
              children: [
                // Payment method pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                            : Icons.qr_code_2,
                        size: 12,
                        color: paymentMethod.toLowerCase() == 'cash'
                            ? AppConstants.okStockColor
                            : AppConstants.statusConfirmedColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        paymentMethod,
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: paymentMethod.toLowerCase() == 'cash'
                              ? AppConstants.okStockColor
                              : AppConstants.statusConfirmedColor,
                        ),
                      ),
                    ],
                  ),
                ),
                // GCash reference number (if present)
                if (paymentMethod.toLowerCase() == 'gcash' &&
                    (order['gcash_reference_number']?.toString().isNotEmpty ?? false)) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppConstants.statusConfirmedColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Ref: ${order['gcash_reference_number']}',
                      style: AppConstants.monoStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.statusConfirmedColor,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Total — the hero number
                Text(
                  '₱${total.toStringAsFixed(0)}',
                  style: AppConstants.monoStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildDateSectionHeader(String dateLabel) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(
        dateLabel.toUpperCase(),
        style: AppConstants.bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppConstants.secondary.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppConstants.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load history',
              style: AppConstants.bodyStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadHistory,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final hasFilter = _selectedRange != _DateRange.all;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppConstants.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 36,
                color: AppConstants.primary.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasFilter ? 'No transactions in this period' : 'No POS transactions yet',
              style: AppConstants.bodyStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Try a different time range or check All.'
                  : 'Completed in-store sales will appear here.',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
