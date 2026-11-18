import 'package:app/utils/payout_account.dart';
import 'package:flutter_test/flutter_test.dart';

// The value these helpers produce is the destination of real money: the admin
// copies it into GCash. So the tests care most about two things — the number
// survives a trip through storage unchanged, and anything that is not an
// 11-digit 09… number is refused rather than saved.
void main() {
  group('normalizeGcashNumber', () {
    test('keeps an already-clean local number', () {
      expect(normalizeGcashNumber('09171234567'), '09171234567');
    });

    test('strips spaces, dashes and parentheses', () {
      expect(normalizeGcashNumber('0917 123-4567'), '09171234567');
      expect(normalizeGcashNumber('(0917) 123 4567'), '09171234567');
    });

    test('turns +63 into the local 09 form', () {
      expect(normalizeGcashNumber('+63 917 123 4567'), '09171234567');
      expect(normalizeGcashNumber('639171234567'), '09171234567');
    });

    test('leaves a wrong-length number short, for the validator to refuse', () {
      expect(normalizeGcashNumber('091712345'), '091712345');
    });
  });

  group('encode / parse round-trip', () {
    test('stores the number first and the name after the separator', () {
      expect(
        encodePayoutDetails(number: '0917 123 4567', name: '  Juan Cruz '),
        '09171234567 · Juan Cruz',
      );
    });

    test('parses what it wrote', () {
      final account = parsePayoutAccount('gcash', '09171234567 · Juan Cruz');
      expect(account, isNotNull);
      expect(account!.number, '09171234567');
      expect(account.name, 'Juan Cruz');
      expect(account.isSet, isTrue);
    });

    test('reads a bare number as a number with no name', () {
      final account = parsePayoutAccount('gcash', '09171234567');
      expect(account!.number, '09171234567');
      expect(account.name, '');
    });

    test('reads a +63 number that was saved before this field existed', () {
      final account = parsePayoutAccount(null, '+639171234567');
      expect(account!.number, '09171234567');
    });

    test('keeps a bank rail verbatim instead of digit-stripping it', () {
      final account = parsePayoutAccount('bank', 'BDO 1234567890');
      expect(account!.number, 'BDO 1234567890');
      expect(account.name, '');
    });

    test('returns null for nothing on file', () {
      expect(parsePayoutAccount('gcash', null), isNull);
      expect(parsePayoutAccount('gcash', '   '), isNull);
    });
  });

  group('payoutDestinationLabel', () {
    test('says GCash and the number once set', () {
      expect(
        payoutDestinationLabel(const PayoutAccount(
          number: '09171234567',
          name: 'Juan Cruz',
        )),
        'GCash · 09171234567',
      );
    });

    test('says so plainly when nothing is on file', () {
      expect(payoutDestinationLabel(null), 'No payout details on file');
    });

    test('names the bank rail when that is the method', () {
      expect(
        payoutDestinationLabel(
          const PayoutAccount(number: 'BDO 1234567890', name: ''),
          method: 'bank',
        ),
        'Bank · BDO 1234567890',
      );
    });
  });

  group('validation', () {
    test('accepts a well-formed number and name', () {
      expect(
        payoutAccountError(number: '09171234567', name: 'Juan Cruz'),
        isNull,
      );
    });

    test('refuses a number that is not 11 digits', () {
      expect(
        payoutAccountError(number: '091712345', name: 'Juan Cruz'),
        contains('11-digit'),
      );
    });

    test('refuses a number that does not start with 09', () {
      expect(
        payoutAccountError(number: '12345678901', name: 'Juan Cruz'),
        contains('09'),
      );
    });

    test('refuses an empty name', () {
      expect(
        payoutAccountError(number: '09171234567', name: ' '),
        contains('name'),
      );
    });

    test('points at the field that is wrong', () {
      expect(gcashNumberError('09171234567'), isNull);
      expect(gcashNumberError('12345'), isNotNull);
      expect(payoutAccountNameError('Juan Cruz'), isNull);
      expect(payoutAccountNameError('J'), isNotNull);
    });
  });
}
