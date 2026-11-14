import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app/models/sales_trend_data.dart';
import 'package:app/services/sales_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockSupabaseTable extends Mock implements SupabaseQueryBuilder {}

/// A real [PostgrestFilterBuilder] whose chain methods build a throwaway URL
/// (no network) while [then] serves canned responses in call order.
///
/// Rationale: [SalesService] chains `select → inFilter/eq → neq → or → then`
/// (or awaits the builder directly). Stubbing every link with mocktail would
/// need a dozen stubs per test and still couldn't serve a *sequence* of
/// different results — the queue does that, and [orFilters] records every
/// sale-date predicate the service actually sent.
class CannedBuilder
    extends PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  CannedBuilder()
      : super(
          PostgrestBuilder<List<Map<String, dynamic>>,
              List<Map<String, dynamic>>, List<Map<String, dynamic>>>(
            url: Uri.parse('https://test.local'),
            headers: const <String, String>{},
          ),
        );

  final Queue<List<dynamic>> _results = Queue();
  final List<String> orFilters = [];
  final List<String> tables = [];

  void enqueue(List<dynamic> rows) => _results.add(rows);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> or(String filters,
      {String? referencedTable}) {
    orFilters.add(filters);
    return this;
  }

  // Every chain link below returns `this`: the real implementations hand
  // back base-class copies, which would lose the canned [then] and attempt
  // a real HTTP request. Argument matching is intentionally loose
  // (`dynamic`) — only the recorded `or` predicates are asserted.
  @override
  CannedBuilder eq(String column, dynamic value) => this;
  @override
  CannedBuilder neq(String column, dynamic value) => this;
  @override
  CannedBuilder inFilter(String column, dynamic values) => this;
  @override
  CannedBuilder gte(String column, dynamic value) => this;
  @override
  CannedBuilder lt(String column, dynamic value) => this;
  @override
  CannedBuilder order(String column,
          {bool ascending = false,
          bool nullsFirst = false,
          String? referencedTable}) =>
      this;

  @override
  Future<R> then<R>(
      FutureOr<R> Function(List<Map<String, dynamic>> value) onValue,
      {Function? onError}) async {
    final List<dynamic> rows =
        _results.isNotEmpty ? _results.removeFirst() : <dynamic>[];
    return onValue(rows.cast<Map<String, dynamic>>());
  }
}

void main() {
  late MockSupabaseClient mockClient;
  late MockSupabaseTable mockTable;
  late CannedBuilder canned;
  late SalesService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockTable = MockSupabaseTable();
    canned = CannedBuilder();
    when(() => mockClient.from(any())).thenAnswer((inv) {
      canned.tables.add(inv.positionalArguments[0] as String);
      return mockTable;
    });
    when(() => mockTable.select(any())).thenAnswer((_) => canned);
    service = SalesService(client: mockClient);
    SalesService.clearSalesCache();
  });

  Map<String, dynamic> order(
    String id,
    double amount, {
    String? deliveredAt,
    String? createdAt,
  }) =>
      {
        'id': id,
        'total_amount': amount,
        'delivered_at': deliveredAt,
        'created_at': createdAt ?? deliveredAt,
      };

  group('getWeeklyReport', () {
    test('combines online + POS into slot buckets with prev comparison',
        () async {
      final weekStart = DateTime(2026, 11, 9); // Mon
      final weekEnd = DateTime(2026, 11, 16);

      // products → order_items chain
      canned.enqueue([
        {'id': 'p1'}
      ]);
      canned.enqueue([
        {'order_id': 'o1'}
      ]);
      // current: one online (Wed) + one POS (Thu)
      canned.enqueue([order('o1', 100, deliveredAt: '2026-11-11T10:00:00.000')]);
      canned.enqueue([order('pos1', 50, deliveredAt: '2026-11-12T10:00:00.000')]);
      // previous period totals
      canned.enqueue([
        {'total_amount': 40}
      ]);
      canned.enqueue([
        {'total_amount': 10}
      ]);
      // order items + product names for top products
      canned.enqueue([
        {'product_id': 'p1', 'quantity': 2, 'unit_price': 50}
      ]);
      canned.enqueue([]);
      canned.enqueue([
        {'id': 'p1', 'name': 'Shoe'}
      ]);

      final report = await service.getWeeklyReport(
        'store-1',
        weekStart: weekStart,
        weekEnd: weekEnd,
      );

      expect(report.weeklyTotal, 150);
      expect(report.previousPeriodTotal, 50);
      expect(report.percentChange, 200);
      expect(report.dailyRevenue.length, 7);
      expect(report.dailyRevenue[2], 100); // Wed = online
      expect(report.dailyRevenue[3], 50); // Thu = POS
      expect(report.topProducts.single['name'], 'Shoe');
      expect(report.topProducts.single['units'], 2);
    });

    test('legacy rows with NULL delivered_at count via created_at', () async {
      final weekStart = DateTime(2026, 11, 9);
      final weekEnd = DateTime(2026, 11, 16);

      canned.enqueue([
        {'id': 'p1'}
      ]);
      canned.enqueue([
        {'order_id': 'o1'}
      ]);
      // Pre-stamp row: no handover yet recorded, created in-range.
      canned.enqueue([
        order('o1', 75,
            deliveredAt: null, createdAt: '2026-11-10T10:00:00.000'),
      ]);
      canned.enqueue([]);
      canned.enqueue([]);
      canned.enqueue([]);
      canned.enqueue([]);
      canned.enqueue([]);
      canned.enqueue([]);

      final report = await service.getWeeklyReport(
        'store-1',
        weekStart: weekStart,
        weekEnd: weekEnd,
      );

      // The sale-date predicate must carry the NULL fallback — a plain
      // `gte(delivered_at)` filter would drop this row in production.
      expect(
        canned.orFilters.any((f) => f.contains('delivered_at.is.null')),
        isTrue,
        reason: 'sale-range filter must include the delivered_at NULL fallback',
      );
      expect(report.weeklyTotal, 75);
      expect(report.dailyRevenue[1], 75); // Tue bucket via created_at
    });

    test('empty store returns zeros with null percent change', () async {
      canned.enqueue(<dynamic>[]); // no products
      canned.enqueue([]); // no POS rows
      canned.enqueue([]); // no prev POS rows

      final report = await service.getWeeklyReport('store-empty');

      expect(report.weeklyTotal, 0);
      expect(report.previousPeriodTotal, 0);
      expect(report.percentChange, isNull);
      expect(report.dailyRevenue, everyElement(0));
      expect(report.topProducts, isEmpty);
    });

    test('second identical call is served from cache', () async {
      canned.enqueue([
        {'id': 'p1'}
      ]);
      canned.enqueue([
        {'order_id': 'o1'}
      ]);
      canned.enqueue([order('o1', 100, deliveredAt: '2026-11-11T10:00:00.000')]);
      canned.enqueue([]);
      canned.enqueue([]);
      canned.enqueue([]);
      canned.enqueue([]);
      canned.enqueue([]);
      canned.enqueue([]);

      final weekStart = DateTime(2026, 11, 9);
      final first = await service.getWeeklyReport('store-1',
          weekStart: weekStart, weekEnd: DateTime(2026, 11, 16));
      clearInteractions(mockClient);
      final second = await service.getWeeklyReport('store-1',
          weekStart: weekStart, weekEnd: DateTime(2026, 11, 16));

      verifyNever(() => mockClient.from(any()));
      expect(second.weeklyTotal, first.weeklyTotal);
    });
  });

  group('getWeeklyTrend', () {
    test('splits online vs in-store per weekday with comparison', () async {
      final weekStart = DateTime(2026, 11, 9); // Mon
      canned.enqueue([
        {'id': 'p1'}
      ]);
      canned.enqueue([
        {'order_id': 'o1'}
      ]);
      canned.enqueue([order('o1', 100, deliveredAt: '2026-11-11T10:00:00.000')]);
      canned.enqueue([order('pos1', 50, deliveredAt: '2026-11-12T10:00:00.000')]);
      canned.enqueue([
        {'total_amount': 40}
      ]);
      canned.enqueue([
        {'total_amount': 10}
      ]);

      final trend = await service.getWeeklyTrend(
        storeId: 'store-1',
        channel: SalesChannelFilter.all,
        weekStart: weekStart,
      );

      expect(trend.totalRevenue, 150);
      expect(trend.previousPeriodRevenue, 50);
      expect(trend.percentChange, 200);
      expect(trend.points.length, 7);
      expect(trend.points[2].onlineRevenue, 100);
      expect(trend.points[2].inStoreRevenue, 0);
      expect(trend.points[3].inStoreRevenue, 50);
      expect(trend.periodLabel, 'This Week');
    });
  });

  group('query safety', () {
    test('order counts chunk inFilter lists for large stores', () async {
      // 250 products → 250 order ids → orders lookup must run in 2 chunks.
      canned.enqueue(List.generate(250, (i) => {'id': 'p$i'}));
      canned.enqueue(List.generate(250, (i) => {'order_id': 'o$i'}));
      canned.enqueue(List.generate(200, (i) => {'id': 'o$i'}));
      canned.enqueue(List.generate(50, (i) => {'id': 'o${200 + i}'}));

      final count = await service.getTotalOrderCount('big-store');

      expect(count, 250);
      final orderLookups =
          canned.tables.where((t) => t == 'orders').length;
      expect(orderLookups, 2,
          reason: '250 ids must be fetched in 2 chunks, never one URL');
    });
  });
}
