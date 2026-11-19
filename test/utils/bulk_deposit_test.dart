import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/bulk_deposit.dart';

void main() {
  group('bulkDepositFor', () {
    // The sheet quotes this before the customer commits; the server charges
    // the same rule at approval (`bulk_reservation_deposit_rate()`, rounded
    // up), so the two must agree to the peso.
    test('is the deposit rate of the value, rounded up to a whole peso', () {
      expect(bulkDepositFor(1000), 700);
      expect(bulkDepositFor(950), 665);
      expect(bulkDepositFor(1234), 864); // 863.8 -> 864
    });

    test('prices on the discounted value when a voucher applies', () {
      // 12 pairs at PHP 1,234 less a PHP 500 voucher.
      expect(bulkDepositFor(1234 * 12 - 500), bulkDepositFor(14308));
      expect(bulkDepositFor(14308), 10016); // 10,015.6 -> 10,016
    });

    test('a code that covers the whole value owes nothing, not less', () {
      expect(bulkDepositFor(0), 0);
      expect(bulkDepositFor(-50), 0);
    });
  });
}
