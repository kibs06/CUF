import 'package:app/constants/seller_theme_constants.dart';
import 'package:app/models/sales_trend_data.dart';
import 'package:app/widgets/seller/seller_revenue_columns_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The trend cards (dashboard Blocks 5 & 6) used to draw two translucent area
/// bands with a line through each. They now draw one stacked column per bucket.
///
/// What this file guards is the *contract* of that swap, which is easiest to
/// read straight off fl_chart's own data model rather than from pixels:
/// a column's height is the period's **total**, the seam inside it sits at the
/// period's **online** figure, and the two segment colours are the same channel
/// tokens the revenue doughnut uses — so the two cards can never disagree about
/// which channel is rust. Reading `BarChartData` also keeps the test off the
/// font/glyph path that makes pixel captures flaky.
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

SalesDataPoint _point(int day, double online, double inStore) => SalesDataPoint(
  date: DateTime(2026, 9, day),
  onlineRevenue: online,
  inStoreRevenue: inStore,
  revenue: online + inStore,
);

BarChartData _dataOf(WidgetTester tester) =>
    tester.widget<BarChart>(find.byType(BarChart)).data;

void main() {
  final week = [
    _point(1, 120, 0), // online-only day
    _point(2, 0, 90), // in-store-only day
    _point(3, 40, 60),
    _point(4, 300, 150),
  ];

  testWidgets('each bucket is one column, stacked to the period total', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SellerRevenueColumnsChart(
          title: 'Revenue — This Week',
          subtitle: 'Sep 1 – Sep 4, 2026',
          points: week,
          labels: const ['Mon', 'Tue', 'Wed', 'Thu'],
        ),
      ),
    );

    final groups = _dataOf(tester).barGroups;
    expect(groups.length, week.length, reason: 'one column per bucket');

    for (var i = 0; i < week.length; i++) {
      expect(groups[i].barRods.length, 1, reason: 'a bucket is one column');
      final rod = groups[i].barRods.single;
      // Height is the period total — not either channel alone.
      expect(rod.toY, week[i].revenue);
      expect(rod.rodStackItems.length, 2, reason: 'two channels stacked');

      // Bottom segment is online, growing from the baseline to the online
      // figure; the top segment is in-store, carrying it up to the total.
      final online = rod.rodStackItems[0];
      final inStore = rod.rodStackItems[1];
      expect(online.fromY, 0);
      expect(online.toY, week[i].onlineRevenue);
      expect(online.color, SellerTheme.channelOnline);
      expect(inStore.fromY, week[i].onlineRevenue);
      expect(inStore.toY, week[i].revenue);
      expect(inStore.color, SellerTheme.channelInStore);
    }
  });

  testWidgets('a single-channel bucket is a solid column of that channel', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SellerRevenueColumnsChart(
          title: 'Revenue — This Week',
          subtitle: 'Sep 1 – Sep 4, 2026',
          points: week,
        ),
      ),
    );

    final groups = _dataOf(tester).barGroups;
    // The zero-height segment still exists (fl_chart needs both to stack), so
    // the test is that it occupies no *length* — the column reads as one
    // solid colour rather than a seam halfway up.
    final onlineOnly = groups[0].barRods.single.rodStackItems;
    expect(onlineOnly[1].toY - onlineOnly[1].fromY, 0);
    expect(onlineOnly[0].toY - onlineOnly[0].fromY, week[0].revenue);

    final inStoreOnly = groups[1].barRods.single.rodStackItems;
    expect(inStoreOnly[0].toY - inStoreOnly[0].fromY, 0);
    expect(inStoreOnly[1].toY - inStoreOnly[1].fromY, week[1].revenue);
  });

  testWidgets('the y-axis tops out above the tallest column', (tester) async {
    await tester.pumpWidget(
      _host(
        SellerRevenueColumnsChart(
          title: 'Revenue — Monthly Trend',
          subtitle: 'September 2026',
          points: week,
          isWeekly: false,
        ),
      ),
    );

    final data = _dataOf(tester);
    final peak = week.map((p) => p.revenue).reduce((a, b) => a > b ? a : b);
    expect(data.maxY, greaterThan(peak));
    // Headroom is 20% over the peak, rounded up to a whole tick so the top
    // gridline is labelled exactly once.
    expect(data.maxY, closeTo(peak * 1.2, data.gridData.horizontalInterval!));
  });

  testWidgets('the chart shares the doughnut\'s channel colours', (
    tester,
  ) async {
    // Both cards split the same two channels; if these ever diverge the
    // dashboard tells two stories about the same money.
    expect(SellerRevenueColumnsChart.onlineColor, SellerTheme.channelOnline);
    expect(SellerRevenueColumnsChart.inStoreColor, SellerTheme.channelInStore);
    expect(
      SellerRevenueColumnsChart.onlineColor,
      isNot(SellerRevenueColumnsChart.inStoreColor),
    );
  });

  testWidgets('an empty period keeps the plot\'s height', (tester) async {
    await tester.pumpWidget(
      _host(
        SellerRevenueColumnsChart(
          title: 'Revenue — Monthly Trend',
          subtitle: 'September 2026',
          points: const [],
        ),
      ),
    );

    expect(find.text('No sales yet this period'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
    // Same box as the chart state, so the card doesn't resize as sales land.
    final plot = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .map((s) => s.height)
        .toList();
    expect(plot, contains(220.0));
  });
}
