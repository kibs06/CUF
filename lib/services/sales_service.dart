import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/seller_report_data.dart';
import '../models/sales_trend_data.dart';

class SalesService {
  final SupabaseClient _client;

  SalesService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// Helper: get order IDs for a store via products → order_items chain.
  Future<List<dynamic>> _getOrderIds(String storeId) async {
    final productRows = await _client
        .from('products')
        .select('id')
        .eq('store_id', storeId);
    final productIds = (productRows as List)
        .map((r) => (r as Map)['id'])
        .toList();
    if (productIds.isEmpty) return [];

    final itemRows = await _client
        .from('order_items')
        .select('order_id')
        .inFilter('product_id', productIds);
    return (itemRows as List)
        .map((r) => (r as Map)['order_id'])
        .toSet()
        .toList();
  }

  Future<String> recordSale(Map<String, dynamic> dto) async {
    final transaction = await _client
        .from('sales_transactions')
        .insert({
          'store_id': dto['store_id'],
          'seller_id': dto['seller_id'],
          'total_amount': dto['total_amount'],
          'payment_method': dto['payment_method'],
          'amount_tendered': dto['amount_tendered'],
          'change_amount': dto['change_amount'],
        })
        .select()
        .single();

    final transactionId = transaction['id'].toString();

    // Batch-fetch inventory for all products to resolve sizes that
    // match what the decrement_inventory_on_sale trigger expects.
    final productIds = (dto['items'] as List? ?? [])
        .map((item) => (item as Map)['product_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final Map<String, List<String>> invSizesByProduct = {};
    if (productIds.isNotEmpty) {
      final invRows = await _client
          .from('inventory')
          .select('product_id, size')
          .inFilter('product_id', productIds)
          .gt('stock', 0);
      for (final row in (invRows as List)) {
        final pid = row['product_id'].toString();
        invSizesByProduct.putIfAbsent(pid, () => [])
            .add(row['size']?.toString() ?? '');
      }
    }

    final items = (dto['items'] as List? ?? []).map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final productId = map['product_id']?.toString() ?? '';
      final cartSize = map['size']?.toString() ?? '';

      // Resolve size from inventory (same logic as createOrder)
      String size = cartSize;
      final invSizes = invSizesByProduct[productId] ?? [];
      if (invSizes.isNotEmpty) {
        // 1) Exact match
        if (!invSizes.contains(cartSize)) {
          // 2) Numeric match (strip prefix)
          final numeric = cartSize.replaceAll(RegExp(r'^[A-Za-z]+'), '');
          if (invSizes.contains(numeric)) {
            size = numeric;
          } else {
            // 3) Fallback: first available
            size = invSizes.first;
          }
        }
      }

      return {
        'transaction_id': transactionId,
        'product_id': productId,
        'size': size,
        'quantity': map['quantity'],
        'unit_price': map['unit_price'],
      };
    }).toList();

    if (items.isNotEmpty) {
      await _client.from('sales_transaction_items').insert(items);
    }
    return transactionId;
  }

  // ─── POS SALES (orders table WHERE source='pos') ─────────────

  /// Helper: get POS order IDs for a store (orders with source='pos').
  Future<List<dynamic>> _getPosOrderIds(String storeId) async {
    final data = await _client
        .from('orders')
        .select('id')
        .eq('store_id', storeId)
        .eq('source', 'pos')
        .neq('status', 'cancelled');
    return (data as List).map((r) => (r as Map)['id']).toList();
  }

  Future<double> fetchTodaySales(String storeId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final posOrderIds = await _getPosOrderIds(storeId);
    if (posOrderIds.isEmpty) return 0;

    final data = await _client
        .from('orders')
        .select('total_amount')
        .inFilter('id', posOrderIds)
        .eq('payment_status', 'paid')
        .gte('created_at', start);

    return (data as List).fold<double>(
      0,
      (sum, row) => sum + ((row['total_amount'] as num?)?.toDouble() ?? 0),
    );
  }

  Future<List<Map<String, dynamic>>> fetchWeeklySales(String storeId) async {
    final from = DateTime.now()
        .subtract(const Duration(days: 6))
        .toIso8601String();
    final posOrderIds = await _getPosOrderIds(storeId);
    if (posOrderIds.isEmpty) return [];

    final data = await _client
        .from('orders')
        .select('total_amount, created_at')
        .inFilter('id', posOrderIds)
        .eq('payment_status', 'paid')
        .gte('created_at', from)
        .order('created_at');
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchTransactions(
    String storeId, {
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _client
        .from('sales_transactions')
        .select()
        .eq('store_id', storeId);
    if (from != null) query = query.gte('created_at', from.toIso8601String());
    if (to != null) query = query.lte('created_at', to.toIso8601String());
    // Filters before .order()
    final data = await query.order('created_at', ascending: false);
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  // ─── ONLINE ORDERS REVENUE ────────────────────────────────────

  Future<double> getOnlineTodayRevenue(String storeId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day)
        .toIso8601String();

    final orderIds = await _getOrderIds(storeId);
    if (orderIds.isEmpty) return 0;

    final data = await _client
        .from('orders')
        .select('total_amount')
        .inFilter('id', orderIds)
        .neq('status', 'cancelled')
        .eq('payment_status', 'paid')
        .gte('created_at', startOfDay);

    return (data as List).fold<double>(
      0,
      (sum, row) => sum + ((row['total_amount'] as num?)?.toDouble() ?? 0),
    );
  }

  Future<double> getTodayRevenue(String storeId) async {
    final results = await Future.wait([
      getOnlineTodayRevenue(storeId),
      fetchTodaySales(storeId),
    ]);
    return results[0] + results[1];
  }

  Future<List<Map<String, dynamic>>> getOnlineWeeklySales(
    String storeId,
  ) async {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 6));
    final orderIds = await _getOrderIds(storeId);
    if (orderIds.isEmpty) return [];

    // Filters before .order()
    final data = await _client
        .from('orders')
        .select('total_amount, created_at')
        .inFilter('id', orderIds)
        .neq('status', 'cancelled')
        .eq('payment_status', 'paid')
        .gte('created_at', sevenDaysAgo.toIso8601String())
        .order('created_at');

    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<double>> getWeeklyRevenue(String storeId) async {
    final results = await Future.wait([
      getOnlineWeeklyRevenue(storeId),
      getPosWeeklyRevenue(storeId),
    ]);
    return List.generate(7, (i) => results[0][i] + results[1][i]);
  }

  /// Online-only weekly revenue per day (Mon=0 … Sun=6).
  Future<List<double>> getOnlineWeeklyRevenue(String storeId) async {
    final rows = await getOnlineWeeklySales(storeId);
    final daily = List<double>.filled(7, 0);
    for (final row in rows) {
      final createdAt = DateTime.parse(row['created_at'] as String);
      daily[createdAt.weekday - 1] +=
          ((row['total_amount'] as num?)?.toDouble() ?? 0);
    }
    return daily;
  }

  /// POS-only weekly revenue per day (Mon=0 … Sun=6).
  Future<List<double>> getPosWeeklyRevenue(String storeId) async {
    final rows = await fetchWeeklySales(storeId);
    final daily = List<double>.filled(7, 0);
    for (final row in rows) {
      final createdAt = DateTime.parse(row['created_at'] as String);
      daily[createdAt.weekday - 1] +=
          ((row['total_amount'] as num?)?.toDouble() ?? 0);
    }
    return daily;
  }

  Future<double> getMonthlyRevenue(String storeId) async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
    final orderIds = await _getOrderIds(storeId);

    // Revenue definition (consistent app-wide): exclude cancelled orders
    // and require payment_status = 'paid' (money actually received).
    // POS now reads the LIVE orders.source='pos' path — the legacy
    // sales_transactions table is no longer written by the POS screen.
    final futures = <Future<List>>[
      _client
          .from('orders')
          .select('total_amount')
          .eq('store_id', storeId)
          .eq('source', 'pos')
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .gte('created_at', startOfMonth)
          .then((d) => List.from(d as List)),
    ];

    if (orderIds.isNotEmpty) {
      futures.insert(
        0,
        _client
            .from('orders')
            .select('total_amount')
            .inFilter('id', orderIds)
            .neq('status', 'cancelled')
            .eq('payment_status', 'paid')
            .gte('created_at', startOfMonth)
            .then((d) => List.from(d as List)),
      );
    } else {
      futures.insert(0, Future.value([]));
    }

    final results = await Future.wait(futures);

    double total = 0;
    for (final row in results[0]) {
      total += ((row['total_amount'] as num?)?.toDouble() ?? 0);
    }
    for (final row in results[1]) {
      total += ((row['total_amount'] as num?)?.toDouble() ?? 0);
    }
    return total;
  }

  /// Monthly revenue trend for the past 6 months (combined).
  /// Returns a list of 6 doubles (index 0 = 5 months ago, index 5 = current month).
  Future<List<double>> getMonthlyRevenueTrend(String storeId) async {
    final results = await Future.wait([
      getOnlineMonthlyRevenueTrend(storeId),
      getPosMonthlyRevenueTrend(storeId),
    ]);
    return List.generate(6, (i) => results[0][i] + results[1][i]);
  }

  /// Online-only monthly revenue trend (6 months).
  Future<List<double>> getOnlineMonthlyRevenueTrend(String storeId) async {
    final now = DateTime.now();
    final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
    final orderIds = await _getOrderIds(storeId);
    if (orderIds.isEmpty) return List<double>.filled(6, 0);

    final rows = await _client
        .from('orders')
        .select('total_amount, created_at')
        .inFilter('id', orderIds)
        .neq('status', 'cancelled')
        .eq('payment_status', 'paid')
        .gte('created_at', sixMonthsAgo.toIso8601String());

    return _aggregateMonthly(rows as List, now);
  }

  /// POS-only monthly revenue trend (6 months).
  Future<List<double>> getPosMonthlyRevenueTrend(String storeId) async {
    final now = DateTime.now();
    final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
    final posOrderIds = await _getPosOrderIds(storeId);
    if (posOrderIds.isEmpty) return List<double>.filled(6, 0);

    final rows = await _client
        .from('orders')
        .select('total_amount, created_at')
        .inFilter('id', posOrderIds)
        .eq('payment_status', 'paid')
        .gte('created_at', sixMonthsAgo.toIso8601String());

    return _aggregateMonthly(rows as List, now);
  }

  /// Shared helper: aggregate rows into a 6-month revenue list.
  List<double> _aggregateMonthly(List rows, DateTime now) {
    final monthly = List<double>.filled(6, 0);
    for (final row in rows) {
      final createdAt = DateTime.parse(row['created_at'] as String);
      final monthDiff =
          (now.year - createdAt.year) * 12 + (now.month - createdAt.month);
      final index = 5 - monthDiff;
      if (index >= 0 && index < 6) {
        monthly[index] += ((row['total_amount'] as num?)?.toDouble() ?? 0);
      }
    }
    return monthly;
  }

  /// Generates abbreviated month labels for the trend chart (e.g. ['Jan','Feb',…]).
  static List<String> monthlyLabels() {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return List.generate(6, (i) {
      // Safe double-modulo to handle negative values in Dart
      final idx = ((now.month - 6 + i) % 12 + 12) % 12;
      return months[idx];
    });
  }

  /// Full month labels with year for chart tooltips
  /// (e.g. ['February 2026', …, 'July 2026']).
  static List<String> monthlyFullLabels() {
    final now = DateTime.now();
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return List.generate(6, (i) {
      final offset = now.month - 6 + i;
      final month = ((offset % 12) + 12) % 12 + 1;
      final year = now.year + (offset ~/ 12);
      return '${names[month - 1]} $year';
    });
  }

  /// Combined report: online orders + POS sales for a date range.
  /// When [monthly] is true, aggregates revenue by day-of-month (1-indexed)
  /// instead of weekday. The returned [SellerReportData.dailyRevenue] list
  /// length will match the number of days in the range.
  Future<SellerReportData> getWeeklyReport(
    String storeId, {
    DateTime? weekStart,
    DateTime? weekEnd,
    bool monthly = false,
  }) async {
    final now = DateTime.now();
    final start = weekStart ??
        DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final end = weekEnd ?? start.add(const Duration(days: 7));
    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();

    // Compute previous period range
    final duration = end.difference(start);
    final prevStart = start.subtract(duration);
    final prevEnd = start;
    final prevStartStr = prevStart.toIso8601String();
    final prevEndStr = prevEnd.toIso8601String();

    // Fetch online orders in range (via products→order_items chain)
    final orderIds = await _getOrderIds(storeId);
    final futures = <Future<List>>[
      orderIds.isNotEmpty
          ? _client
              .from('orders')
              .select('id, total_amount, created_at')
              .inFilter('id', orderIds)
              .neq('status', 'cancelled')
              .eq('payment_status', 'paid')
              .gte('created_at', startStr)
              .lt('created_at', endStr)
              .then((d) => List.from(d as List))
          : Future.value([]),
      // POS orders in range — LIVE path (orders WHERE source='pos').
      // The legacy sales_transactions table is no longer written by the
      // POS screen, so reading it here silently dropped all POS revenue.
      _client
          .from('orders')
          .select('id, total_amount, created_at')
          .eq('store_id', storeId)
          .eq('source', 'pos')
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .gte('created_at', startStr)
          .lt('created_at', endStr)
          .then((d) => List.from(d as List)),
    ];

    // Fetch previous period totals (online + POS) in parallel
    final prevFutures = <Future<double>>[
      orderIds.isNotEmpty
          ? _client
              .from('orders')
              .select('total_amount')
              .inFilter('id', orderIds)
              .neq('status', 'cancelled')
              .eq('payment_status', 'paid')
              .gte('created_at', prevStartStr)
              .lt('created_at', prevEndStr)
              .then((d) => (d as List).fold<double>(0, (s, r) => s + ((r['total_amount'] as num?)?.toDouble() ?? 0)))
          : Future.value(0.0),
      _client
          .from('orders')
          .select('total_amount')
          .eq('store_id', storeId)
          .eq('source', 'pos')
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .gte('created_at', prevStartStr)
          .lt('created_at', prevEndStr)
          .then((d) => (d as List).fold<double>(0, (s, r) => s + ((r['total_amount'] as num?)?.toDouble() ?? 0))),
    ];

    final results = await Future.wait(futures);
    final prevResults = await Future.wait(prevFutures);
    final onlineOrders = results[0];
    final posTransactions = results[1];
    final previousPeriodTotal = prevResults[0] + prevResults[1];

    // Aggregate daily revenue
    // Weekly: 7 slots indexed by weekday (Mon=0 Sun=6)
    // Monthly: one slot per day-of-month (index 0 = day 1)
    final slotCount = monthly
        ? DateTime(now.year, now.month + 1, 0).day
        : 7;
    final dailyRevenue = List<double>.filled(slotCount, 0);
    double weeklyTotal = 0;
    for (final row in onlineOrders) {
      final amount = (row['total_amount'] as num?)?.toDouble() ?? 0;
      weeklyTotal += amount;
      final createdAt = DateTime.parse(row['created_at'] as String);
      if (monthly) {
        dailyRevenue[createdAt.day - 1] += amount;
      } else {
        dailyRevenue[createdAt.weekday - 1] += amount;
      }
    }
    for (final row in posTransactions) {
      final amount = (row['total_amount'] as num?)?.toDouble() ?? 0;
      weeklyTotal += amount;
      final createdAt = DateTime.parse(row['created_at'] as String);
      if (monthly) {
        dailyRevenue[createdAt.day - 1] += amount;
      } else {
        dailyRevenue[createdAt.weekday - 1] += amount;
      }
    }

    // Aggregate top products from order_items + sales_transaction_items
    final productTotals = <String, Map<String, dynamic>>{};

    void addItem(String productId, int quantity, double unitPrice) {
      productTotals.putIfAbsent(
        productId,
        () => {'units': 0, 'revenue': 0.0},
      );
      productTotals[productId]!['units'] += quantity;
      productTotals[productId]!['revenue'] += quantity * unitPrice;
    }

    // Fetch online order items
    if (onlineOrders.isNotEmpty) {
      final onlineOrderIds = onlineOrders
          .map((o) => o['id'])
          .toList();
      final onlineItems = await _client
          .from('order_items')
          .select('product_id, quantity, unit_price')
          .inFilter('order_id', onlineOrderIds);
      for (final item in onlineItems as List) {
        addItem(
          item['product_id'] as String,
          (item['quantity'] as num?)?.toInt() ?? 0,
          (item['unit_price'] as num?)?.toDouble() ?? 0,
        );
      }
    }

    // Fetch POS order items (order_items on the POS order ids — the
    // sales_transaction_items table is legacy and no longer written).
    if (posTransactions.isNotEmpty) {
      final posTxIds = posTransactions
          .map((t) => t['id'])
          .toList();
      final posItems = await _client
          .from('order_items')
          .select('product_id, quantity, unit_price')
          .inFilter('order_id', posTxIds);
      for (final item in posItems as List) {
        addItem(
          item['product_id'] as String,
          (item['quantity'] as num?)?.toInt() ?? 0,
          (item['unit_price'] as num?)?.toDouble() ?? 0,
        );
      }
    }

    // Sort by units sold, take top 5
    final sorted = productTotals.entries.toList()
      ..sort((a, b) =>
          (b.value['units'] as int).compareTo(a.value['units'] as int));
    final top5 = sorted.take(5).toList();

    // Fetch product names
    List<Map<String, dynamic>> topProducts = [];
    if (top5.isNotEmpty) {
      final productIds = top5.map((e) => e.key).toList();
      final productData = await _client
          .from('products')
          .select('id, name')
          .inFilter('id', productIds);
      final nameMap = <String, String>{};
      for (final p in productData as List) {
        nameMap[p['id'] as String] = p['name'] as String? ?? 'Unknown';
      }
      topProducts = top5
          .map((entry) => {
                'name': nameMap[entry.key] ?? 'Unknown Product',
                'units': entry.value['units'] as int,
                'revenue': entry.value['revenue'] as double,
              })
          .toList();
    }

    return SellerReportData(
      weeklyTotal: weeklyTotal,
      previousPeriodTotal: previousPeriodTotal,
      dailyRevenue: dailyRevenue,
      topProducts: topProducts,
      weekStart: start,
      weekEnd: end,
    );
  }

  Future<int> getTotalOrderCount(String storeId) async {
    final orderIds = await _getOrderIds(storeId);
    if (orderIds.isEmpty) return 0;

    final data = await _client
        .from('orders')
        .select('id')
        .inFilter('id', orderIds)
        .neq('status', 'cancelled');
    return (data as List).length;
  }

  Future<int> getPendingOrderCount(String storeId) async {
    final orderIds = await _getOrderIds(storeId);
    if (orderIds.isEmpty) return 0;

    final data = await _client
        .from('orders')
        .select('id')
        .inFilter('id', orderIds)
        .inFilter('status', ['placed', 'preparing']);
    return (data as List).length;
  }

  // ─── TREND DATA (for dashboard charts) ────────────────────────

  /// Fetches daily revenue for the last 7 days, combined online + POS.
  /// Returns a [SalesTrendResult] with points, totals, and comparison.
  Future<SalesTrendResult> getWeeklyTrend({
    required String storeId,
    required SalesChannelFilter channel,
    DateTime? weekStart,
  }) async {
    final now = DateTime.now();
    final start = weekStart ?? DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final end = start.add(const Duration(days: 7));

    // Previous period (same length, immediately prior)
    final prevStart = start.subtract(const Duration(days: 7));
    final prevEnd = start;

    return _fetchTrend(
      storeId: storeId,
      channel: channel,
      start: start,
      end: end,
      prevStart: prevStart,
      prevEnd: prevEnd,
      slotCount: 7,
      slotByDate: (date) => date.weekday - 1, // Mon=0, Sun=6
      labelBuilder: (i) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i],
      periodLabel: 'This Week',
    );
  }

  /// Fetches monthly revenue for the last 6 months, combined online + POS.
  Future<SalesTrendResult> getMonthlyTrend({
    required String storeId,
    required SalesChannelFilter channel,
    int monthsBack = 6,
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - (monthsBack - 1), 1);
    final end = DateTime(now.year, now.month + 1, 1);

    // Previous period
    final prevStart = DateTime(now.year, now.month - (monthsBack * 2 - 1), 1);
    final prevEnd = start;

    return _fetchTrend(
      storeId: storeId,
      channel: channel,
      start: start,
      end: end,
      prevStart: prevStart,
      prevEnd: prevEnd,
      slotCount: monthsBack,
      slotByDate: (date) {
        final monthDiff = (date.year - start.year) * 12 + (date.month - start.month);
        return monthDiff.clamp(0, monthsBack - 1);
      },
      // Each point's date must be a DISTINCT month, rolled forward from the
      // window start — otherwise the chart's month-abbrev x-labels repeat.
      pointDateBuilder: (i) => DateTime(start.year, start.month + i, 1),
      labelBuilder: (i) {
        final offset = now.month - monthsBack + 1 + i;
        final month = ((offset % 12) + 12) % 12;
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return months[month];
      },
      fullLabelBuilder: (i) {
        final offset = now.month - monthsBack + 1 + i;
        final month = ((offset % 12) + 12) % 12;
        final year = now.year + (offset ~/ 12);
        const names = ['January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December'];
        return '${names[month]} $year';
      },
      periodLabel: 'Last $monthsBack Months',
    );
  }

  /// Internal: fetch trend data for any period.
  Future<SalesTrendResult> _fetchTrend({
    required String storeId,
    required SalesChannelFilter channel,
    required DateTime start,
    required DateTime end,
    required DateTime prevStart,
    required DateTime prevEnd,
    required int slotCount,
    required int Function(DateTime) slotByDate,
    required String Function(int) labelBuilder,
    String Function(int)? fullLabelBuilder,
    required String periodLabel,
    DateTime Function(int)? pointDateBuilder,
  }) async {
    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();
    final prevStartStr = prevStart.toIso8601String();
    final prevEndStr = prevEnd.toIso8601String();

    // Fetch current period data
    final orderIds = await _getOrderIds(storeId);
    final futures = <Future<List>>[];

    // Online orders
    if (channel != SalesChannelFilter.inStore && orderIds.isNotEmpty) {
      futures.add(_client
          .from('orders')
          .select('total_amount, created_at')
          .inFilter('id', orderIds)
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .gte('created_at', startStr)
          .lt('created_at', endStr)
          .then((d) => List.from(d as List)));
    } else {
      futures.add(Future.value([]));
    }

    // POS orders
    if (channel != SalesChannelFilter.online) {
      futures.add(_client
          .from('orders')
          .select('total_amount, created_at')
          .eq('store_id', storeId)
          .eq('source', 'pos')
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .gte('created_at', startStr)
          .lt('created_at', endStr)
          .then((d) => List.from(d as List)));
    } else {
      futures.add(Future.value([]));
    }

    // Previous period data
    final prevFutures = <Future<List>>[];
    if (channel != SalesChannelFilter.inStore && orderIds.isNotEmpty) {
      prevFutures.add(_client
          .from('orders')
          .select('total_amount')
          .inFilter('id', orderIds)
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .gte('created_at', prevStartStr)
          .lt('created_at', prevEndStr)
          .then((d) => List.from(d as List)));
    } else {
      prevFutures.add(Future.value([]));
    }
    if (channel != SalesChannelFilter.online) {
      prevFutures.add(_client
          .from('orders')
          .select('total_amount')
          .eq('store_id', storeId)
          .eq('source', 'pos')
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .gte('created_at', prevStartStr)
          .lt('created_at', prevEndStr)
          .then((d) => List.from(d as List)));
    } else {
      prevFutures.add(Future.value([]));
    }

    final results = await Future.wait(futures);
    final prevResults = await Future.wait(prevFutures);

    // Merge current period by date — separate online and inStore
    final onlineDaily = List<double>.filled(slotCount, 0);
    final inStoreDaily = List<double>.filled(slotCount, 0);
    double totalRevenue = 0;

    // Online orders (results[0])
    for (final row in results[0]) {
      final amount = (row['total_amount'] as num?)?.toDouble() ?? 0;
      totalRevenue += amount;
      final createdAt = DateTime.parse(row['created_at'] as String);
      final slot = slotByDate(createdAt);
      if (slot >= 0 && slot < slotCount) {
        onlineDaily[slot] += amount;
      }
    }
    // POS / in-store orders (results[1])
    for (final row in results[1]) {
      final amount = (row['total_amount'] as num?)?.toDouble() ?? 0;
      totalRevenue += amount;
      final createdAt = DateTime.parse(row['created_at'] as String);
      final slot = slotByDate(createdAt);
      if (slot >= 0 && slot < slotCount) {
        inStoreDaily[slot] += amount;
      }
    }

    // Previous period total
    double previousPeriodRevenue = 0;
    for (final row in [...prevResults[0], ...prevResults[1]]) {
      previousPeriodRevenue += (row['total_amount'] as num?)?.toDouble() ?? 0;
    }

    // Percent change
    final percentChange = previousPeriodRevenue > 0
        ? ((totalRevenue - previousPeriodRevenue) / previousPeriodRevenue) * 100
        : 0.0;

    // Build points with channel-separated revenue.
    // ⚠️ pointDateBuilder must produce DISTINCT dates per slot — the
    // weekly default advances by day, while monthly rolls by month.
    // (Bug: previously all monthly points shared the window-start month,
    // making every x-axis label read the same month abbreviation.)
    final now = DateTime.now();
    final points = List.generate(slotCount, (i) {
      final online = onlineDaily[i];
      final inStore = inStoreDaily[i];
      return SalesDataPoint(
        date: pointDateBuilder?.call(i) ?? start.add(Duration(days: i)),
        onlineRevenue: online,
        inStoreRevenue: inStore,
        revenue: online + inStore,
        isProjected: i == slotCount - 1 && now.hour < 18,
      );
    });

    return SalesTrendResult(
      points: points,
      totalRevenue: totalRevenue,
      previousPeriodRevenue: previousPeriodRevenue,
      percentChange: percentChange,
      periodLabel: periodLabel,
    );
  }
}
