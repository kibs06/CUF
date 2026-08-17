import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import '../../widgets/sole_card.dart';
import 'admin_helpers.dart';

/// Admin Orders — port of admin-portal/src/pages/Orders.jsx.
///
/// Full order list with search, status + date filters, pagination, and a
/// detail sheet that shows items and lets the admin update the status.
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  static const _pageSize = 20;
  static const _orderStatuses = [
    'pending', 'placed', 'confirmed', 'preparing', 'ready',
    'shipped', 'received', 'delivered', 'cancelled',
  ];

  final _searchCtrl = TextEditingController();
  String _search = '';
  String _statusFilter = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int _page = 1;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Supabase.instance.client
          .from('orders')
          .select(
            '*, profiles!orders_customer_id_fkey(full_name, email), '
            'stores(name), '
            'order_items(*, products(name))',
          )
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _orders = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _orders.where((o) {
      final id = (o['id'] ?? '').toString().toLowerCase();
      final customer =
          ((o['profiles'] as Map<String, dynamic>?)?['full_name'] ?? '')
              .toString()
              .toLowerCase();
      if (q.isNotEmpty && !id.contains(q) && !customer.contains(q)) return false;
      if (_statusFilter != 'all' && o['status'] != _statusFilter) return false;
      final created = adminParseTime(o['created_at']);
      if (_dateFrom != null && (created == null || created.isBefore(_dateFrom!))) {
        return false;
      }
      if (_dateTo != null) {
        final endOfDay = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
        if (created == null || created.isAfter(endOfDay)) return false;
      }
      return true;
    }).toList();
  }

  String _customerName(Map<String, dynamic> order) =>
      (order['profiles'] as Map<String, dynamic>?)?['full_name'] ?? 'Unknown';

  String _customerEmail(Map<String, dynamic> order) =>
      (order['profiles'] as Map<String, dynamic>?)?['email'] ?? '';

  String _storeName(Map<String, dynamic> order) =>
      (order['stores'] as Map<String, dynamic>?)?['name'] ?? '—';

  int _itemsCount(Map<String, dynamic> order) {
    final items = (order['order_items'] as List?) ?? [];
    return items
        .fold<int>(0, (sum, it) => sum + ((it?['quantity'] as num?)?.toInt() ?? 0));
  }

  void _openOrder(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppConstants.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _OrderDetailSheet(order: order, onUpdated: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 1 << 31);
    final pageRows = filtered.length <= _pageSize
        ? filtered
        : filtered.sublist(
            ((_page - 1) * _pageSize).clamp(0, filtered.length),
            (_page * _pageSize).clamp(0, filtered.length),
          );

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text('Orders', style: AppConstants.headlineStyle(fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          Column(
            children: [
              // Search + filters
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() {
                        _search = v;
                        _page = 1;
                      }),
                      style: AppConstants.bodyStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search order ID or customer…',
                        hintStyle: AppConstants.bodyStyle(fontSize: 13, color: Colors.black38),
                        prefixIcon: const Icon(Icons.search, color: AppConstants.primary),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Status + date filters
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _filterChip(
                            label: 'All statuses',
                            active: _statusFilter == 'all',
                            onTap: () => setState(() {
                              _statusFilter = 'all';
                              _page = 1;
                            }),
                          ),
                          for (final s in _orderStatuses)
                            _filterChip(
                              label: s.toUpperCase(),
                              active: _statusFilter == s,
                              onTap: () => setState(() {
                                _statusFilter = s;
                                _page = 1;
                              }),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _dateField(
                            label: _dateFrom == null ? 'From' : adminDate(_dateFrom),
                            onTap: () => _pickDate(selectFrom: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _dateField(
                            label: _dateTo == null ? 'To' : adminDate(_dateTo),
                            onTap: () => _pickDate(selectFrom: false),
                          ),
                        ),
                        if (_dateFrom != null || _dateTo != null)
                          TextButton(
                            onPressed: () => setState(() {
                              _dateFrom = null;
                              _dateTo = null;
                              _page = 1;
                            }),
                            child: Text('Clear', style: AppConstants.bodyStyle(fontSize: 12, color: AppConstants.primary)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppConstants.primary))
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: AppConstants.bodyStyle(color: AppConstants.error),
                              ),
                            ),
                          )
                        : pageRows.isEmpty
                            ? Center(
                                child: Text(
                                  'No orders found.\nTry adjusting your search or filters.',
                                  textAlign: TextAlign.center,
                                  style: AppConstants.bodyStyle(color: Colors.black45),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                itemCount: pageRows.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == pageRows.length) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            onPressed: _page <= 1 ? null : () => setState(() => _page--),
                                            icon: const Icon(Icons.chevron_left, color: AppConstants.primary),
                                          ),
                                          Text(
                                            'Page $_page of $totalPages · ${filtered.length} orders',
                                            style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black45),
                                          ),
                                          IconButton(
                                            onPressed: _page >= totalPages ? null : () => setState(() => _page++),
                                            icon: const Icon(Icons.chevron_right, color: AppConstants.primary),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  final order = pageRows[index];
                                  final status = (order['status'] ?? '').toString();
                                  final total = (order['total_amount'] as num?) ?? 0;
                                  return GestureDetector(
                                    onTap: () => _openOrder(order),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      child: SoleCard(
                                        color: Colors.white,
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    _customerName(order),
                                                    style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                  ),
                                                ),
                                                AdminStatusChip(label: status, status: status),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${_customerEmail(order)} · ${_storeName(order)}',
                                              style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black45),
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  '#${adminShortId((order['id'] ?? '').toString())} · ${_itemsCount(order)} items',
                                                  style: AppConstants.monoStyle(fontSize: 11, color: Colors.black45),
                                                ),
                                                Text(
                                                  adminCurrency(total),
                                                  style: AppConstants.monoStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppConstants.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              adminDateTime(adminParseTime(order['created_at'])),
                                              style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black45),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip({required String label, required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppConstants.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppConstants.primary : AppConstants.borderGray,
          ),
        ),
        child: Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppConstants.secondary.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _dateField({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppConstants.borderGray),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 14, color: AppConstants.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool selectFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (selectFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
        _page = 1;
      });
    }
  }
}

/// Detail bottom sheet: customer info, item lines, total + status updater.
class _OrderDetailSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onUpdated;

  const _OrderDetailSheet({required this.order, required this.onUpdated});

  @override
  State<_OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends State<_OrderDetailSheet> {
  static const _orderStatuses = [
    'pending', 'placed', 'confirmed', 'preparing', 'ready',
    'shipped', 'received', 'delivered', 'cancelled',
  ];

  late String _newStatus = (widget.order['status'] ?? '').toString();
  bool _saving = false;

  Future<void> _updateStatus() async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('orders')
          .update({'status': _newStatus})
          .eq('id', widget.order['id']);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onUpdated();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order status updated'), backgroundColor: AppConstants.success),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e'), backgroundColor: AppConstants.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final items = (order['order_items'] as List?) ?? [];
    final total = (order['total_amount'] as num?) ?? 0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppConstants.borderGray,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Order #${adminShortId((order['id'] ?? '').toString())}',
                style: AppConstants.headlineStyle(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                adminDateTime(adminParseTime(order['created_at'])),
                style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black45),
              ),
              const SizedBox(height: 16),
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order['profiles']?['full_name'] ?? 'Unknown',
                      style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      order['profiles']?['email'] ?? '',
                      style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black45),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order['stores']?['name'] ?? '—',
                      style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Items', style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              AdminCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(
                  children: [
                    for (final item in items) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item?['products']?['name'] ?? 'Product'} × ${item?['quantity'] ?? 0}',
                                style: AppConstants.bodyStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              adminCurrency(((item?['unit_price'] as num?) ?? 0) * ((item?['quantity'] as num?) ?? 0)),
                              style: AppConstants.monoStyle(fontSize: 12, color: AppConstants.secondary),
                            ),
                          ],
                        ),
                      ),
                      if (item != items.last) const Divider(height: 1, color: AppConstants.borderGray),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(
                    adminCurrency(total),
                    style: AppConstants.monoStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppConstants.primary),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Update Status', style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _newStatus,
                isExpanded: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                items: [
                  for (final s in _orderStatuses)
                    DropdownMenuItem(value: s, child: Text(s, style: AppConstants.bodyStyle(fontSize: 13))),
                ],
                onChanged: (v) => setState(() => _newStatus = v ?? _newStatus),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : _updateStatus,
                  child: Text(
                    _saving ? 'Updating…' : 'Update Status',
                    style: AppConstants.bodyStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
