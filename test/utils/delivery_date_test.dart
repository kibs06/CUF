/// Unit tests for the delivery date estimation utility.
///
/// Covers:
/// - Calculation entirely within one week (no weekend crossing)
/// - Crossing a single weekend
/// - Crossing two weekends (e.g. starting on a Friday)
/// - Year-end / month-end rollover (e.g. starting Dec 30)
/// - Date formatting
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/delivery_date.dart';

void main() {
  group('getEstimatedDeliveryDate', () {
    test('within one week, no weekend crossing (Mon + 4 = Fri)', () {
      // Monday Aug 3, 2026
      final start = DateTime(2026, 8, 3);
      expect(getEstimatedDeliveryDate(start), DateTime(2026, 8, 7));
    });

    test('crosses one weekend (Wed + 4 = Tue next week)', () {
      // Wednesday Aug 5, 2026 → Thu, Fri, Mon, Tue
      final start = DateTime(2026, 8, 5);
      expect(getEstimatedDeliveryDate(start), DateTime(2026, 8, 11));
    });

    test('crosses two weekends (Friday + 4 = Thu next week)', () {
      // Friday Aug 7, 2026 → Mon, Tue, Wed, Thu
      final start = DateTime(2026, 8, 7);
      expect(getEstimatedDeliveryDate(start), DateTime(2026, 8, 13));
    });

    test('crosses two weekends when starting Saturday (Sat + 4 = Thu next week)', () {
      // Saturday Aug 8, 2026 → Mon, Tue, Wed, Thu
      final start = DateTime(2026, 8, 8);
      expect(getEstimatedDeliveryDate(start), DateTime(2026, 8, 13));
    });

    test('year-end rollover (Wed Dec 30, 2026 + 4 = Tue Jan 5, 2027)', () {
      // Wed Dec 30 → Thu, Fri, Mon, Tue (New Year's weekend skipped)
      final start = DateTime(2026, 12, 30);
      expect(getEstimatedDeliveryDate(start), DateTime(2027, 1, 5));
    });

    test('month-end rollover (Thu Jan 29 + 4 = Wed Feb 4)', () {
      // Thu Jan 29 → Fri, Mon, Tue, Wed
      final start = DateTime(2026, 1, 29);
      expect(getEstimatedDeliveryDate(start), DateTime(2026, 2, 4));
    });

    test('returns start date when businessDays is 0', () {
      final start = DateTime(2026, 8, 3);
      expect(getEstimatedDeliveryDate(start, businessDays: 0), start);
    });

    test('custom business day count works (2 days)', () {
      final start = DateTime(2026, 8, 3); // Monday
      expect(
        getEstimatedDeliveryDate(start, businessDays: 2),
        DateTime(2026, 8, 5),
      );
    });

    test('never returns a weekend', () {
      // Start on a Thursday; 4 business days out must land on a weekday.
      final start = DateTime(2026, 8, 6); // Thursday
      final result = getEstimatedDeliveryDate(start);
      expect(result.weekday, lessThanOrEqualTo(DateTime.friday));
    });
  });

  group('formatDeliveryDate', () {
    test('formats as "Weekday, Mon D, YYYY"', () {
      expect(
        formatDeliveryDate(DateTime(2026, 8, 12)),
        'Wednesday, Aug 12, 2026',
      );
    });

    test('uses full weekday name', () {
      expect(
        formatDeliveryDate(DateTime(2026, 8, 3)),
        'Monday, Aug 3, 2026',
      );
    });
  });
}
