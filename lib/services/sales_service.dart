import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/seller_report_data.dart';
import '../models/sales_trend_data.dart';

class SalesService {
  final SupabaseClient _client;

  SalesService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// The sale belongs to the handover, not the placement: every date
  /// filter and every bucket below reads `delivered_at` (stamped when the
  /// seller marks the order delivered — see stamp_delivered_at), falling
  /// back to `created_at` only for rows that predate the stamp.
  /// Rows with no handover yet (NULL `delivered_at`) have no sale date,
  /// so the `delivered_at` range filters leave them out.
  static DateTime _saleDate(dynamic row) {
    final map = row as Map;
    return DateTime.parse(
      ((map['delivered_at'] ?? map['created_at']) as String),
    );
  }

  // ─── QUERY SAFETY HELPERS ─────────────────────────────────────

  /// PostgREST `in` lists ride in the request URL — an unbounded id list
  /// risks HTTP 414s (or silent server-side truncation), which would drop
  /// revenue without a trace. Every `inFilter` call below goes through
  /// here so large stores stay correct.
  static const int inFilterChunkSize = 200;

  Future<List<dynamic>> _selectByIdChunks(
    List<dynamic> ids,
    Future<List<dynamic>> Function(List<dynamic> chunk) run,
  ) async {
    final rows = <dynamic>[];
    for (var i = 0; i < ids.length; i += inFilterChunkSize) {
      final end = (i + inFilterChunkSize).clamp(0, ids.length);
      rows.addAll(await run(ids.sublist(i, end)));
    }
    return rows;
  }

  /// Sale-date range predicate: a row counts when its handover
  /// (`delivered_at`) falls in [start, end); legacy rows with NULL
  /// `delivered_at` count on `created_at` instead — mirroring [_saleDate].
  /// A plain `.gte('delivered_at', …)` filter silently drops the legacy
  /// rows, so every sale-date filter below goes through here.
  static String saleRangeFilter(DateTime start, DateTime end) {
    final s = start.toIso8601String();
    final e = end.toIso8601String();
    return 'and(delivered_at.gte.$s,delivered_at.lt.$e),'
        'and(delivered_at.is.null,created_at.gte.$s,created_at.lt.$e)';
  }

  /// Open-ended variant of [saleRangeFilter] for "since" queries.
  static String saleSinceFilter(DateTime start) {
    final s = start.toIso8601String();
    return 'delivered_at.gte.$s,and(delivered_at.is.null,created_at.gte.$s)';
  }

  /// Fold helper shared by the previous-period totals.
  static double _sumAmounts(List rows) => rows.fold<double>(
        0,
        (s, r) => s + (((r as Map)['total_amount'] as num?)?.toDouble() ?? 0),
      );

  // ─── LIGHT CACHE ──────────────────────────────────────────────
  // Short-TTL memo for the expensive report/trend queries: the dashboard
  // and Reports screens each fan out to ~10 queries, and tab switches /
  // pull-to-refresh would otherwise re-run all of them every time.
  // Service instances are created per call (`SalesService()`), so the
  // cache is static. The TTL is deliberately short — sales data must
  // stay near-live.
  static const Duration salesCacheTtl = Duration(minutes: 2);
  static final Map<String, _SalesCacheEntry> _salesCache = {};

  static String _cacheKey(String method, List<Object?> parts) =>
      '$method:${parts.map((p) => p.toString()).join('|')}';

  T? _readCache<T>(String key) {
    final entry = _salesCache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.storedAt) > salesCacheTtl) {
      _salesCache.remove(key);
      return null;
    }
    return entry.value as T?;
  }

  void _writeCache(String key, Object value) {
    _salesCache.removeWhere(
      (k, e) => DateTime.now().difference(e.storedAt) > salesCacheTtl,
    );
    _salesCache[key] = _SalesCacheEntry(value, DateTime.now());
  }

  /// Test hook: drop all cached sales results.
  static void clearSalesCache() => _salesCache.clear();

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
    return data.map((r) => (r as Map)['id']).toList();
  }

  Future<double> fetchTodaySales(String storeId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final posOrderIds = await _getPosOrderIds(storeId);
    if (posOrderIds.isEmpty) return 0;

    final data = await _selectByIdChunks(posOrderIds, (chunk) async {
      final rows = await _client
          .from('orders')
          .select('total_amount')
          .inFilter('id', chunk)
          .eq('payment_status', 'paid')
          .or(saleSinceFilter(start));
      return List<dynamic>.from(rows as List);
    });

    return data.fold<double>(
      0,
      (sum, row) => sum + ((row['total_amount'] as num?)?.toDouble() ?? 0),
    );
  }

  Future<List<Map<String, dynamic>>> fetchWeeklySales(String storeId) async {
    final from = DateTime.now().subtract(const Duration(days: 6));
    final posOrderIds = await _getPosOrderIds(storeId);
    if (posOrderIds.isEmpty) return [];

    final data = await _selectByIdChunks(posOrderIds, (chunk) async {
      final rows = await _client
          .from('orders')
          .select('total_amount, delivered_at, created_at')
          .inFilter('id', chunk)
          .eq('payment_status', 'paid')
          .or(saleSinceFilter(from))
          .order('delivered_at');
      return List<dynamic>.from(rows as List);
    });
    return data
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
    return data
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  // ─── ONLINE ORDERS REVENUE ────────────────────────────────────

  Future<double> getOnlineTodayRevenue(String storeId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final orderIds = await _getOrderIds(storeId);
    if (orderIds.isEmpty) return 0;

    final data = await _selectByIdChunks(orderIds, (chunk) async {
      final rows = await _client
          .from('orders')
          .select('total_amount')
          .inFilter('id', chunk)
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .or(saleSinceFilter(startOfDay));
      return List<dynamic>.from(rows as List);
    });

    return data.fold<double>(
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
    final data = await _selectByIdChunks(orderIds, (chunk) async {
      final rows = await _client
          .from('orders')
          .select('total_amount, delivered_at, created_at')
          .inFilter('id', chunk)
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .or(saleSinceFilter(sevenDaysAgo))
          .order('delivered_at');
      return List<dynamic>.from(rows as List);
    });

    return data
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
      final createdAt = _saleDate(row);
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
      final createdAt = _saleDate(row);
      daily[createdAt.weekday - 1] +=
          ((row['total_amount'] as num?)?.toDouble() ?? 0);
    }
    return daily;
  }

  Future<double> getMonthlyRevenue(String storeId) async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final orderIds = await _getOrderIds(storeId);

    // Revenue definition (consistent app-wide): exclude cancelled orders,
    // require payment_status = 'paid' (money actually received), and count
    // each sale on its handover date (`delivered_at`), not on placement.
    // POS now reads the LIVE orders.source='pos' path — the legacy
    // sales_transactions table is no longer written by the POS screen.
    final onlineFuture = orderIds.isEmpty
        ? Future.value(<dynamic>[])
        : _selectByIdChunks(orderIds, (chunk) async {
            final rows = await _client
                .from('orders')
                .select('total_amount')
                .inFilter('id', chunk)
                .neq('status', 'cancelled')
                .eq('payment_status', 'paid')
                .or(saleSinceFilter(startOfMonth));
            return List<dynamic>.from(rows as List);
          });
    final posFuture = _client
        .from('orders')
        .select('total_amount')
        .eq('store_id', storeId)
        .eq('source', 'pos')
        .neq('status', 'cancelled')
        .eq('payment_status', 'paid')
        .or(saleSinceFilter(startOfMonth))
        .then((d) => List.from(d as List));

    final results = await Future.wait([onlineFuture, posFuture]);

    double total = 0;
    for (final row in results[0]) {
      total += (((row as Map)['total_amount'] as num?)?.toDouble() ?? 0);
    }
    for (final row in results[1]) {
      total += (((row as Map)['total_amount'] as num?)?.toDouble() ?? 0);
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

    final rows = await _selectByIdChunks(orderIds, (chunk) async {
      final chunkRows = await _client
          .from('orders')
          .select('total_amount, delivered_at, created_at')
          .inFilter('id', chunk)
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .or(saleSinceFilter(sixMonthsAgo));
      return List<dynamic>.from(chunkRows as List);
    });

    return _aggregateMonthly(rows, now);
  }

  /// POS-only monthly revenue trend (6 months).
  Future<List<double>> getPosMonthlyRevenueTrend(String storeId) async {
    final now = DateTime.now();
    final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
    final posOrderIds = await _getPosOrderIds(storeId);
    if (posOrderIds.isEmpty) return List<double>.filled(6, 0);

    final rows = await _selectByIdChunks(posOrderIds, (chunk) async {
      final chunkRows = await _client
          .from('orders')
          .select('total_amount, delivered_at, created_at')
          .inFilter('id', chunk)
          .eq('payment_status', 'paid')
          .or(saleSinceFilter(sixMonthsAgo));
      return List<dynamic>.from(chunkRows as List);
    });

    return _aggregateMonthly(rows, now);
  }

  /// Shared helper: aggregate rows into a 6-month revenue list.
  List<double> _aggregateMonthly(List rows, DateTime now) {
    final monthly = List<double>.filled(6, 0);
    for (final row in rows) {
      final createdAt = _saleDate(row);
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

    // Compute previous period range
    final duration = end.difference(start);
    final prevStart = start.subtract(duration);
    final prevEnd = start;

    final cacheKey = _cacheKey('weeklyReport', [
      storeId,
      start.toIso8601String(),
      end.toIso8601String(),
      monthly,
    ]);
    final cached = _readCache<SellerReportData>(cacheKey);
    if (cached != null) return cached;

    // Fetch online orders in range (via products→order_items chain)
    final orderIds = await _getOrderIds(storeId);
    final rangeFilter = saleRangeFilter(start, end);
    Future<List<dynamic>> fetchOnlineCurrent(List<dynamic> chunk) async {
      final rows = await _client
          .from('orders')
          .select('id, total_amount, delivered_at, created_at')
          .inFilter('id', chunk)
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .or(rangeFilter);
      return List<dynamic>.from(rows as List);
    }

    final onlineFuture = orderIds.isEmpty
        ? Future.value(<dynamic>[])
        : _selectByIdChunks(orderIds, fetchOnlineCurrent);
    // POS orders in range — LIVE path (orders WHERE source='pos').
    // The legacy sales_transactions table is no longer written by the
    // POS screen, so reading it here silently dropped all POS revenue.
    final posFuture = _client
        .from('orders')
        .select('id, total_amount, delivered_at, created_at')
        .eq('store_id', storeId)
        .eq('source', 'pos')
        .neq('status', 'cancelled')
        .eq('payment_status', 'paid')
        .or(rangeFilter)
        .then((d) => List.from(d as List));

    final results = await Future.wait([onlineFuture, posFuture]);
    final onlineOrders = results[0];
    final posTransactions = results[1];

    // Fetch previous period totals (online + POS)
    final prevRangeFilter = saleRangeFilter(prevStart, prevEnd);
    final prevOnlineRows = orderIds.isEmpty
        ? <dynamic>[]
        : await _selectByIdChunks(orderIds, (chunk) async {
            final rows = await _client
                .from('orders')
                .select('total_amount')
                .inFilter('id', chunk)
                .neq('status', 'cancelled')
                .eq('payment_status', 'paid')
                .or(prevRangeFilter);
            return List<dynamic>.from(rows as List);
          });
    final prevPosRows = await _client
        .from('orders')
        .select('total_amount')
        .eq('store_id', storeId)
        .eq('source', 'pos')
        .neq('status', 'cancelled')
        .eq('payment_status', 'paid')
        .or(prevRangeFilter);
    final previousPeriodTotal =
        _sumAmounts(prevOnlineRows) + _sumAmounts(prevPosRows as List);

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
      final createdAt = _saleDate(row);
      if (monthly) {
        dailyRevenue[createdAt.day - 1] += amount;
      } else {
        dailyRevenue[createdAt.weekday - 1] += amount;
      }
    }
    for (final row in posTransactions) {
      final amount = (row['total_amount'] as num?)?.toDouble() ?? 0;
      weeklyTotal += amount;
      final createdAt = _saleDate(row);
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
          .map((o) => (o as Map)['id'])
          .toList();
      final onlineItems = await _selectByIdChunks(
        onlineOrderIds,
        (chunk) async {
          final rows = await _client
              .from('order_items')
              .select('product_id, quantity, unit_price')
              .inFilter('order_id', chunk);
          return List<dynamic>.from(rows as List);
        },
      );
      for (final item in onlineItems) {
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
          .map((t) => (t as Map)['id'])
          .toList();
      final posItems = await _selectByIdChunks(posTxIds, (chunk) async {
        final rows = await _client
            .from('order_items')
            .select('product_id, quantity, unit_price')
            .inFilter('order_id', chunk);
        return List<dynamic>.from(rows as List);
      });
      for (final item in posItems) {
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

    final report = SellerReportData(
      weeklyTotal: weeklyTotal,
      previousPeriodTotal: previousPeriodTotal,
      dailyRevenue: dailyRevenue,
      topProducts: topProducts,
      weekStart: start,
      weekEnd: end,
    );
    _writeCache(cacheKey, report);
    return report;
  }

  Future<int> getTotalOrderCount(String storeId) async {
    final orderIds = await _getOrderIds(storeId);
    if (orderIds.isEmpty) return 0;

    final data = await _selectByIdChunks(orderIds, (chunk) async {
      final rows = await _client
          .from('orders')
          .select('id')
          .inFilter('id', chunk)
          .neq('status', 'cancelled');
      return List<dynamic>.from(rows as List);
    });
    return data.length;
  }

  Future<int> getPendingOrderCount(String storeId) async {
    final orderIds = await _getOrderIds(storeId);
    if (orderIds.isEmpty) return 0;

    final data = await _selectByIdChunks(orderIds, (chunk) async {
      final rows = await _client
          .from('orders')
          .select('id')
          .inFilter('id', chunk)
          .inFilter('status', ['placed', 'preparing']);
      return List<dynamic>.from(rows as List);
    });
    return data.length;
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

    final cacheKey = _cacheKey('weeklyTrend', [
      storeId,
      channel.name,
      weekStart?.toIso8601String() ?? 'auto',
    ]);
    final cached = _readCache<SalesTrendResult>(cacheKey);
    if (cached != null) return cached;

    final result = await _fetchTrend(
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
    _writeCache(cacheKey, result);
    return result;
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

    final cacheKey = _cacheKey('monthlyTrend', [
      storeId,
      channel.name,
      monthsBack,
    ]);
    final cached = _readCache<SalesTrendResult>(cacheKey);
    if (cached != null) return cached;

    final result = await _fetchTrend(
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
    _writeCache(cacheKey, result);
    return result;
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
    final rangeFilter = saleRangeFilter(start, end);
    final prevRangeFilter = saleRangeFilter(prevStart, prevEnd);

    // Fetch current period data
    final orderIds = await _getOrderIds(storeId);
    Future<List<dynamic>> fetchTrendOnline(List<dynamic> chunk, String columns, String range) async {
      final rows = await _client
          .from('orders')
          .select(columns)
          .inFilter('id', chunk)
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .or(range);
      return List<dynamic>.from(rows as List);
    }

    final futures = <Future<List<dynamic>>>[];

    // Online orders
    if (channel != SalesChannelFilter.inStore && orderIds.isNotEmpty) {
      futures.add(_selectByIdChunks(
        orderIds,
        (chunk) => fetchTrendOnline(
          chunk,
          'total_amount, delivered_at, created_at',
          rangeFilter,
        ),
      ));
    } else {
      futures.add(Future.value(<dynamic>[]));
    }

    // POS orders
    if (channel != SalesChannelFilter.online) {
      futures.add(_client
          .from('orders')
          .select('total_amount, delivered_at, created_at')
          .eq('store_id', storeId)
          .eq('source', 'pos')
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .or(rangeFilter)
          .then((d) => List.from(d as List)));
    } else {
      futures.add(Future.value(<dynamic>[]));
    }

    // Previous period data
    final prevFutures = <Future<List<dynamic>>>[];
    if (channel != SalesChannelFilter.inStore && orderIds.isNotEmpty) {
      prevFutures.add(_selectByIdChunks(
        orderIds,
        (chunk) => fetchTrendOnline(chunk, 'total_amount', prevRangeFilter),
      ));
    } else {
      prevFutures.add(Future.value(<dynamic>[]));
    }
    if (channel != SalesChannelFilter.online) {
      prevFutures.add(_client
          .from('orders')
          .select('total_amount')
          .eq('store_id', storeId)
          .eq('source', 'pos')
          .neq('status', 'cancelled')
          .eq('payment_status', 'paid')
          .or(prevRangeFilter)
          .then((d) => List.from(d as List)));
    } else {
      prevFutures.add(Future.value(<dynamic>[]));
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
      final createdAt = _saleDate(row);
      final slot = slotByDate(createdAt);
      if (slot >= 0 && slot < slotCount) {
        onlineDaily[slot] += amount;
      }
    }
    // POS / in-store orders (results[1])
    for (final row in results[1]) {
      final amount = (row['total_amount'] as num?)?.toDouble() ?? 0;
      totalRevenue += amount;
      final createdAt = _saleDate(row);
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

/// One cached sales result with its write time (drives the TTL eviction).
class _SalesCacheEntry {
  final Object value;
  final DateTime storedAt;
  const _SalesCacheEntry(this.value, this.storedAt);
}
