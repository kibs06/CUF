import 'package:app/utils/pos_history_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seller's side of POS History search: whatever they have in hand — the
/// code the customer read back, the amount they remember, who was at the
/// counter — has to find the sale.
void main() {
  Map<String, dynamic> sale({
    String id = '16c13ea7-1234-5678-9abc-def012345678',
    double total = 2550.0,
  }) =>
      {'id': id, 'total_amount': total};

  group('receipt code', () {
    test('the code on the card matches, with or without the hash', () {
      expect(
        matchesPosHistoryQuery(
          order: sale(),
          query: '16c13ea7',
          cashierName: 'Keith',
        ),
        isTrue,
      );
      expect(
        matchesPosHistoryQuery(
          order: sale(),
          query: '#16C13EA7',
          cashierName: 'Keith',
        ),
        isTrue,
      );
    });

    test('a partial code matches too, since the card shows only 8 characters',
        () {
      expect(
        matchesPosHistoryQuery(
          order: sale(),
          query: 'c13e',
          cashierName: '',
        ),
        isTrue,
      );
    });

    test('an unrelated string finds nothing', () {
      expect(
        matchesPosHistoryQuery(
          order: sale(),
          query: 'zzzz',
          cashierName: 'Keith',
        ),
        isFalse,
      );
    });
  });

  group('amount', () {
    test('digits, grouped digits and a peso sign all work', () {
      for (final query in ['2550', '2,550', '₱2,550.00', '2550.00']) {
        expect(
          matchesPosHistoryQuery(
            order: sale(),
            query: query,
            cashierName: '',
          ),
          isTrue,
          reason: query,
        );
      }
    });

    test('a centavo total matches its two-decimal form', () {
      expect(
        matchesPosHistoryQuery(
          order: sale(total: 1250.5),
          query: '1250.50',
          cashierName: '',
        ),
        isTrue,
      );
    });

    test('a wrong amount does not match', () {
      expect(
        matchesPosHistoryQuery(
          order: sale(),
          query: '999',
          cashierName: '',
        ),
        isFalse,
      );
    });
  });

  group('cashier', () {
    test('matches the name printed on the receipt, case-insensitively', () {
      expect(
        matchesPosHistoryQuery(
          order: sale(),
          query: 'keith vincent',
          cashierName: 'Keith Vincent D. Abalo',
        ),
        isTrue,
      );
    });

    test('does not match another name', () {
      expect(
        matchesPosHistoryQuery(
          order: sale(),
          query: 'maria',
          cashierName: 'Keith Vincent D. Abalo',
        ),
        isFalse,
      );
    });
  });

  test('an empty or blank query matches everything', () {
    expect(
      matchesPosHistoryQuery(order: sale(), query: '', cashierName: ''),
      isTrue,
    );
    expect(
      matchesPosHistoryQuery(order: sale(), query: '   ', cashierName: ''),
      isTrue,
    );
  });
}
