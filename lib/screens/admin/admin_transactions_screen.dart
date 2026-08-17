import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import 'admin_helpers.dart';

/// Admin Transactions — port of admin-portal/src/pages/Transactions.jsx.
///
/// Payment intents list with summary cards, status/store/date filters,
/// search, CSV export, and a detail sheet with fee breakdown + webhook
/// event timeline.
class AdminTransactionsScreen extends StatefulWidget {
  const AdminTransactionsScreen({super.key});

  @override
  State<AdminTransactionsScreen> createState() => _AdminTransactionsScreenState();
}

class _AdminTransactionsScreenState extends State<AdminTransactionsScreen> {
  static const _pageSize = 20;

  static const _intentColumns =
      'id, order_id, customer_id, paymongo_payment_intent_id, checkout_session_id, '
      'amount, fee_amount, paymongo_fee_amount, net_amount, gcash_reference_number, '
      'status, currency, livemode, expires_at, paid_at, created_at, updated_at, '
      'orders!inner(id, status, payment_status, total_amount, gcash_fee_amount, '
      'gcash_transaction_id, payment_verified_at, created_at, store_id, '
      'stores(name), profiles!orders_customer_id_fkey(full_name, email))';

  static const _baseColumns =
      'id, order_id, customer_id, paymongo_payment_intent_id, checkout_session_id, '
      'amount, fee_amount, status, currency, livemode, expires_at, paid_at, '
      'created_at, updated_at, '
      'orders!inner(id, status, payment_status, total_amount, gcash_fee_amount, '
      'gcash_transaction_id, payment_verified_at, created_at, store_id, '
      'stores(name), profiles!orders_customer_id_fkey(full_name, email))';

  static const _eventColumns =
      'id, event_type, status, payment_intent_id, order_id, '
      'amount, redacted_payload, received_at, processed_at';

  static const _statusSegments = [
    ('all', 'All'),
    ('succeeded', 'Paid'),
    ('pending', 'Pending'),
    ('failed', 'Failed'),
    ('expired', 'Expired'),
    ('cancelled', 'Cancelled'),
  ];

  final _searchCtrl = TextEditingController();
  String _search = '';
  String _statusFilter = 'all';
  String _storeFilter = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int _page = 1;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  bool _feeColumnsAvailable = false;
  List<Map<String, dynamic>> _stores = [];

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
      final client = Supabase.instance.client;

      // Prefer the full column set (needs the admin-transactions migration);
      // fall back to base columns so the page still works when not applied.
      Map<String, dynamic> intents;
      try {
        intents = await _fetchIntents(client, _intentColumns, true);
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('paymongo_fee_amount') ||
            msg.contains('net_amount') ||
            msg.contains('gcash_reference_number')) {
          intents = await _fetchIntents(client, _baseColumns, false);
        } else {
          rethrow;
        }
      }

      final eventsRes = await client
          .from('payment_webhook_events')
          .select(_eventColumns)
          .order('received_at', ascending: true);
      final storesRes = await client
          .from('stores')
          .select('id, name')
          .eq('is_active', true)
          .order('name', ascending: true);

      final eventsByOrder = <String, List<dynamic>>{};
      final eventsByPi = <String, List<dynamic>>{};
      for (final e in (eventsRes as List?) ?? []) {
        final orderId = e?['order_id']?.toString();
        final piId = e?['payment_intent_id']?.toString();
        if (orderId != null) {
          eventsByOrder.putIfAbsent(orderId, () => []).add(e);
        }
        if (piId != null) {
          eventsByPi.putIfAbsent(piId, () => []).add(e);
        }
      }

      final rows = <Map<String, dynamic>>[];
      for (final r in intents['rows'] as List) {
        final orderEvents = eventsByOrder[(r['order_id'] ?? '').toString()] ?? [];
        final piId = (r['paymongo_payment_intent_id'] as String?);
        final piEvents = piId != null ? (eventsByPi[piId] ?? <dynamic>[]) : <dynamic>[];
        final merged = <String, dynamic>{};
        for (final e in [...orderEvents, ...piEvents]) {
          merged[e['id'].toString()] = e;
        }
        final events = merged.values.toList()
          ..sort((a, b) {
            final da = adminParseTime(a['received_at']);
            final db = adminParseTime(b['received_at']);
            return (da ?? DateTime(0)).compareTo(db ?? DateTime(0));
          });
        rows.add({...r, 'events': events, 'events_count': events.length});
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _feeColumnsAvailable = intents['feeColumnsAvailable'] as bool;
        _stores = List<Map<String, dynamic>>.from(storesRes);
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

  Future<Map<String, dynamic>> _fetchIntents(
    SupabaseClient client,
    String columns,
    bool feeColumnsAvailable,
  ) async {
    final query = client.from('payment_intents').select(columns);

    if (_statusFilter != 'all') {
      query.eq('status', _statusFilter);
    }
    if (_dateFrom != null) {
      final from = DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day);
      query.gte('created_at', from.toUtc().toIso8601String());
    }
    if (_dateTo != null) {
      final to = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
      query.lte('created_at', to.toUtc().toIso8601String());
    }
    query.order('created_at', ascending: false);

    final data = await query;
    return {
      'rows': List<Map<String, dynamic>>.from(data),
      'feeColumnsAvailable': feeColumnsAvailable,
    };
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _rows.where((t) {
      final orderId = (t['order_id'] ?? '').toString().toLowerCase();
      final customer = (t['customer_name'] ?? '').toString().toLowerCase();
      final store = (t['store_name'] ?? '').toString().toLowerCase();
      final session =
          ((t['checkout_session_id'] as String?) ?? '').toLowerCase();
      final ref =
          ((t['gcash_reference_number'] as String?) ?? '').toLowerCase();
      if (q.isNotEmpty &&
          !orderId.contains(q) &&
          !customer.contains(q) &&
          !store.contains(q) &&
          !session.contains(q) &&
          !ref.contains(q)) {
        return false;
      }
      if (_storeFilter != 'all' && (t['store_id'] ?? '').toString() != _storeFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  // ── Derived stats (matches the web's useMemo) ───────────────────
  ({int total, double totalPaid, double? fees, int attention}) get _stats {
    final filtered = _filtered;
    var totalPaid = 0.0;
    var feeData = 0.0;
    var feeCount = 0;
    for (final t in filtered) {
      if (t['status'] == 'succeeded') {
        totalPaid += (t['amount'] as num?)?.toDouble() ?? 0;
      }
      final fee = t['paymongo_fee_amount'];
      if (fee != null) {
        feeData += (fee as num).toDouble();
        feeCount++;
      }
    }
    final attention = filtered
        .where((t) => t['status'] == 'failed' || t['status'] == 'expired')
        .length;
    return (
      total: filtered.length,
      totalPaid: totalPaid,
      fees: feeCount > 0 ? feeData : null,
      attention: attention,
    );
  }

  String _customerName(Map<String, dynamic> t) =>
      (t['customer_name'] ?? 'Unknown').toString();

  String _storeName(Map<String, dynamic> t) =>
      (t['store_name'] ?? '—').toString();

  void _openDetail(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppConstants.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _TransactionDetailSheet(
        transaction: t,
        feeColumnsAvailable: _feeColumnsAvailable,
        onClose: () {},
      ),
    );
  }

  String _escCsv(Object? value) {
    final s = value?.toString() ?? '';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  Future<void> _exportCsv() async {
    final filtered = _filtered;
    if (filtered.isEmpty) return;
    const header = [
      'Order ID', 'Store', 'Customer', 'Amount (PHP)', 'Model B Fee (PHP)',
      'PayMongo Fee (PHP)', 'Net (PHP)', 'Status', 'GCash Ref',
      'Checkout Session', 'PayMongo Payment ID', 'Created At', 'Updated At',
    ];
    final lines = filtered.map((r) => [
          r['order_id'],
          r['store_name'],
          r['customer_name'],
          r['amount'],
          r['fee_amount'],
          r['paymongo_fee_amount'] ?? '',
          r['net_amount'] ?? '',
          r['status'],
          r['gcash_reference_number'] ?? '',
          r['checkout_session_id'] ?? '',
          r['paymongo_payment_intent_id'] ?? '',
          r['created_at'],
          r['updated_at'],
        ].map(_escCsv).join(','));
    final csv = '\uFEFF${[header.join(','), ...lines].join('\n')}';

    try {
      final dir = await Directory.systemTemp.createTemp('transactions');
      final file = File('${dir.path}/transactions-${DateTime.now().toIso8601String().substring(0, 10)}.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Transactions export',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: AppConstants.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final stats = _stats;
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
        title: Text('Transactions', style: AppConstants.headlineStyle(fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: filtered.isEmpty ? null : _exportCsv,
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download_outlined, color: AppConstants.primary),
          ),
        ],
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          Column(
            children: [
              // Stat cards
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    _statCard(
                      label: 'Transactions',
                      value: '${stats.total}',
                      icon: Icons.account_balance_wallet_outlined,
                      color: AppConstants.primary,
                    ),
                    const SizedBox(width: 10),
                    _statCard(
                      label: 'Total paid',
                      value: adminCurrencyWhole(stats.totalPaid),
                      icon: Icons.payments_outlined,
                      color: AppConstants.accent,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    _statCard(
                      label: 'PayMongo fees',
                      value: stats.fees == null ? '—' : adminCurrencyWhole(stats.fees),
                      icon: Icons.account_balance_outlined,
                      color: AppConstants.borderGray,
                    ),
                    const SizedBox(width: 10),
                    _statCard(
                      label: 'Failed / expired',
                      value: '${stats.attention}',
                      icon: Icons.warning_amber_outlined,
                      color: AppConstants.error,
                      highlight: stats.attention > 0,
                    ),
                  ],
                ),
              ),
              // Filters
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (value, label) in _statusSegments)
                            GestureDetector(
                              onTap: () => setState(() {
                                _statusFilter = value;
                                _page = 1;
                                _load();
                              }),
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _statusFilter == value
                                      ? AppConstants.primary
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _statusFilter == value
                                        ? AppConstants.primary
                                        : AppConstants.borderGray,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: AppConstants.bodyStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _statusFilter == value
                                        ? Colors.white
                                        : AppConstants.secondary.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() {
                        _search = v;
                        _page = 1;
                      }),
                      style: AppConstants.bodyStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search order, customer, store, ref…',
                        hintStyle: AppConstants.bodyStyle(fontSize: 13, color: Colors.black38),
                        prefixIcon: const Icon(Icons.search, color: AppConstants.primary),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _search = '';
                                    _page = 1;
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _storeDropdown(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _pickDate(selectFrom: true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppConstants.borderGray),
                              ),
                              child: Text(
                                _dateFrom == null ? 'From' : adminDate(_dateFrom),
                                style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black54),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _pickDate(selectFrom: false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppConstants.borderGray),
                              ),
                              child: Text(
                                _dateTo == null ? 'To' : adminDate(_dateTo),
                                style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black54),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // List
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
                                  filtered.isEmpty && _rows.isEmpty
                                      ? 'No transactions yet.\nGCash payments will show up here as customers place orders online.'
                                      : 'No matches.\nTry adjusting your search and filters.',
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
                                            'Page $_page of $totalPages · ${filtered.length} transactions',
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
                                  final t = pageRows[index];
                                  final status = (t['status'] ?? '').toString();
                                  return GestureDetector(
                                    onTap: () => _openDetail(t),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      child: AdminCard(
                                        padding: const EdgeInsets.all(14),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: AppConstants.primary.withValues(alpha: 0.1),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.person_outline,
                                                size: 18,
                                                color: AppConstants.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _customerName(t),
                                                    style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                  ),
                                                  Text(
                                                    '${_storeName(t)} · #${adminShortId((t['order_id'] ?? '').toString())}',
                                                    style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black45),
                                                  ),
                                                  Text(
                                                    adminDateTime(adminParseTime(t['created_at'])),
                                                    style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black45),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  adminCurrency((t['amount'] as num?) ?? 0),
                                                  style: AppConstants.monoStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppConstants.secondary,
                                                  ),
                                                ),
                                                if (t['paymongo_fee_amount'] != null)
                                                  Text(
                                                    'net ${adminCurrency((t['net_amount'] as num?) ?? 0)}',
                                                    style: AppConstants.bodyStyle(fontSize: 10, color: Colors.black45),
                                                  ),
                                                const SizedBox(height: 4),
                                                AdminStatusChip(label: status, status: status),
                                              ],
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

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool highlight = false,
  }) {
    return Expanded(
      child: AdminCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppConstants.bodyStyle(fontSize: 10, color: Colors.black45),
                  ),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: AppConstants.monoStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: highlight ? AppConstants.error : AppConstants.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _storeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppConstants.borderGray),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _storeFilter,
          isExpanded: true,
          dropdownColor: Colors.white,
          style: AppConstants.bodyStyle(fontSize: 12),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('All stores')),
            for (final s in _stores)
              DropdownMenuItem(
                value: (s['id'] ?? '').toString(),
                child: Text(
                  (s['name'] ?? '').toString(),
                  overflow: TextOverflow.ellipsis,
                  style: AppConstants.bodyStyle(fontSize: 12),
                ),
              ),
          ],
          onChanged: (v) => setState(() {
            _storeFilter = v ?? 'all';
            _page = 1;
          }),
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
        _load();
      });
    }
  }
}

/// Detail bottom sheet: amount/fee cards, order context, references,
/// and the webhook event timeline.
class _TransactionDetailSheet extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final bool feeColumnsAvailable;
  final VoidCallback onClose;

  const _TransactionDetailSheet({
    required this.transaction,
    required this.feeColumnsAvailable,
    required this.onClose,
  });

  String _humanize(String? value) {
    final s = value ?? '';
    if (s.isEmpty) return '';
    return s
        .split(RegExp(r'[._]'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final order = t['orders'];
    final events = (t['events'] as List?) ?? [];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Transaction #${adminShortId((t['id'] ?? '').toString())}',
                      style: AppConstants.headlineStyle(fontSize: 18),
                    ),
                  ),
                  AdminStatusChip(label: (t['status'] ?? '').toString()),
                ],
              ),
              const SizedBox(height: 16),
              // Amount cards
              Row(
                children: [
                  Expanded(
                    child: _amountCard('Amount charged', adminCurrency(t['amount'])),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _amountCard('Model B fee', adminCurrency(t['fee_amount'])),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _amountCard(
                      'PayMongo fee',
                      t['paymongo_fee_amount'] != null
                          ? adminCurrency(t['paymongo_fee_amount'])
                          : '—',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _amountCard(
                      'Net',
                      t['net_amount'] != null ? adminCurrency(t['net_amount']) : '—',
                    ),
                  ),
                ],
              ),
              if (!feeColumnsAvailable) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8A020).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE8A020).withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Fee and net columns are not in the database yet — apply the '
                    'admin-transactions migration (20260810000000_admin_transactions_view.sql) '
                    'to populate them.',
                    style: AppConstants.bodyStyle(fontSize: 11, color: const Color(0xFF8A6100)),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              // Order context
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (t['customer_name'] ?? 'Unknown').toString(),
                      style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      (t['customer_email'] ?? '').toString(),
                      style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black45),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${t['store_name']} · Order #${adminShortId((t['order_id'] ?? '').toString())}',
                      style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black45),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        AdminStatusChip(
                          label: 'order: ${order?['status'] ?? '—'}',
                          status: (order?['status'] ?? '').toString(),
                        ),
                        const SizedBox(width: 8),
                        AdminStatusChip(
                          label: 'payment: ${order?['payment_status'] ?? '—'}',
                          status: (order?['payment_status'] ?? '').toString(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _infoRow('Order total', adminCurrency(order?['total_amount'])),
                    _infoRow('Order GCash fee', adminCurrency(order?['gcash_fee_amount'])),
                    _infoRow('Expires', adminDateTime(adminParseTime(t['expires_at']))),
                    _infoRow('Paid at', adminDateTime(adminParseTime(t['paid_at']))),
                    _infoRow('Verified at', adminDateTime(adminParseTime(t['payment_verified_at']))),
                    _infoRow('Livemode', t['livemode'] == true ? 'yes' : 'no'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // References
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'References',
                      style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    _infoRow('PayMongo payment', t['paymongo_payment_intent_id']?.toString() ?? '—'),
                    _infoRow('Checkout session', t['checkout_session_id']?.toString() ?? '—'),
                    _infoRow('GCash reference', t['gcash_reference_number']?.toString() ?? '—'),
                    _infoRow('GCash transaction id', order?['gcash_transaction_id']?.toString() ?? '—'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Event timeline
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Webhook event timeline (${t['events_count'] ?? 0})',
                      style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (events.isEmpty)
                      Text(
                        'No webhook events recorded for this transaction.',
                        style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black45),
                      )
                    else
                      for (final e in events) _eventRow(e),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountCard(String label, String value) {
    return AdminCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppConstants.bodyStyle(fontSize: 10, color: Colors.black45),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppConstants.monoStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black45),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppConstants.monoStyle(fontSize: 11, color: AppConstants.secondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventRow(dynamic e) {
    final status = (e?['status'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppConstants.borderGray.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppConstants.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _humanize((e?['event_type'] ?? '').toString()),
                        style: AppConstants.bodyStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                    AdminStatusChip(label: status, status: status),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  adminDateTime(adminParseTime(e?['received_at'])),
                  style: AppConstants.bodyStyle(fontSize: 10, color: Colors.black45),
                ),
                if (e?['processed_at'] != null)
                  Text(
                    'processed ${adminDateTime(adminParseTime(e?['processed_at']))}',
                    style: AppConstants.bodyStyle(fontSize: 10, color: Colors.black45),
                  ),
                if (e?['amount'] != null)
                  Text(
                    adminCurrency((e?['amount'] as num?) ?? 0),
                    style: AppConstants.monoStyle(fontSize: 11, color: AppConstants.secondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
