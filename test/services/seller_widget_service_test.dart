import 'package:app/services/seller_widget_service.dart';
import 'package:app/widgets/seller/seller_inventory_row.dart'
    show kLowStockThreshold;
import 'package:flutter_test/flutter_test.dart';

/// The widget's low-stock count.
///
/// `countLowStockRows` mirrors `SellerDashboardScreen._getLowStockItems` — the
/// same rule the Manage Products "Low Stock" filter and the inventory sheet's
/// amber state use. It is lifted out as a top-level function precisely so it can
/// be tested here without a database, because **it is the one metric the widget
/// computes rather than asks for**, and a drift between it and the dashboard
/// would show a seller two different low-stock numbers for the same store.
///
/// The rule, restated: `sizes` is a `{size: quantity}` map and only **positive**
/// quantities at or below [kLowStockThreshold] count. Zero is excluded on
/// purpose — it is *out of stock*, which the inventory UI paints as a distinct
/// and worse state, and which "low stock" is not the question for.
void main() {
  group('countLowStockRows', () {
    test('counts a size per row, not a product per row', () {
      // Two products, three low sizes between them — the dashboard's own
      // "LOW STOCK" card counts sizes, and its tap target opens the Low Stock
      // filter, so the two must agree on what the unit is.
      final products = [
        {
          'name': 'Runner',
          'sizes': {'EU 41': 3, 'EU 42': 9, 'EU 43': 1},
        },
        {
          'name': 'Loafer',
          'sizes': {'EU 40': 5},
        },
      ];
      expect(countLowStockRows(products), 3);
    });

    test('includes the threshold itself and excludes zero', () {
      final products = [
        {
          'sizes': {
            'at threshold': kLowStockThreshold,
            'already gone': 0,
          },
        },
      ];
      // Exactly 5 is low; 0 is out of stock, not low.
      expect(countLowStockRows(products), 1);
    });

    test('ignores quantities above the threshold', () {
      final products = [
        {
          'sizes': {'plenty': kLowStockThreshold + 1, 'lots': 80},
        },
      ];
      expect(countLowStockRows(products), 0);
    });

    test('honours an explicit threshold override', () {
      final products = [
        {
          'sizes': {'a': 2, 'b': 4, 'c': 8},
        },
      ];
      expect(countLowStockRows(products, threshold: 3), 1);
      expect(countLowStockRows(products, threshold: 8), 3);
    });

    test('is 0 for a store with no products', () {
      expect(countLowStockRows(const []), 0);
    });

    test('reads a missing or non-map `sizes` as no sizes, never as a crash', () {
      // These are rows straight off Supabase, where a column can be null, absent
      // or (from a legacy row) not the shape expected. A background worker that
      // threw here would leave the whole tile stale, so an unreadable row must
      // count as nothing rather than fail the refresh.
      final products = <Map<String, dynamic>>[
        {'name': 'no sizes key at all'},
        {'name': 'null sizes', 'sizes': null},
        {'name': 'sizes is a list', 'sizes': [1, 2, 3]},
        {'name': 'sizes is a string', 'sizes': 'not a map'},
      ];
      expect(countLowStockRows(products), 0);
    });

    test('ignores non-integer quantities', () {
      // A JSON number can arrive as a double, and a double is not a stock count.
      // Reading 4.0 as 4 would be guessing; skipping it is the conservative half
      // of the trade, and the dashboard does the same.
      final products = [
        {
          'sizes': {'double': 4.0, 'string': '3', 'int': 2},
        },
      ];
      expect(countLowStockRows(products), 1);
    });

    test('an empty sizes map counts as nothing', () {
      expect(countLowStockRows([
        {'sizes': <String, dynamic>{}},
      ]), 0);
    });
  });
}
