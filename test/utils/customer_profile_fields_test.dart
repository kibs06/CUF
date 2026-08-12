import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/customer_profile_fields.dart';

void main() {
  group('validateBirthday', () {
    test('rejects null (field is required)', () {
      expect(validateBirthday(null), isNotNull);
    });

    test('rejects a future date', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(validateBirthday(tomorrow), 'Birthday can\'t be in the future');
    });

    test('rejects someone under 13', () {
      final today = DateTime.now();
      final eleven = DateTime(today.year - 11, today.month, today.day);
      expect(
        validateBirthday(eleven),
        'You must be at least 13 years old to sign up',
      );
    });

    test('accepts someone exactly 13 (year-wise)', () {
      final today = DateTime.now();
      final thirteen = DateTime(today.year - 13, today.month, today.day);
      expect(validateBirthday(thirteen), isNull);
    });

    test('accepts a normal adult birthday', () {
      expect(validateBirthday(DateTime(1998, 3, 4)), isNull);
    });

  });

  group('gender self-describe', () {
    test('any non-self-describe selection passes without text', () {
      expect(validateGenderSelfDescribe('Woman', null), isNull);
      expect(validateGenderSelfDescribe('Man', 'ignored'), isNull);
      expect(validateGenderSelfDescribe('Prefer not to say', null), isNull);
      expect(validateGenderSelfDescribe(null, null), isNull);
    });

    test('self-describe requires non-blank free text', () {
      expect(validateGenderSelfDescribe('Self-describe', null), isNotNull);
      expect(validateGenderSelfDescribe('Self-describe', '   '), isNotNull);
      expect(validateGenderSelfDescribe('Self-describe', 'Agender'), isNull);
    });

    test('resolveGenderValue maps presets and free text', () {
      expect(resolveGenderValue(null, null), isNull);
      expect(resolveGenderValue('Woman', 'whatever'), 'Woman');
      expect(resolveGenderValue('Self-describe', ' Agender '), 'Agender');
      expect(resolveGenderValue('Self-describe', '   '), isNull);
    });
  });

  group('formatBirthdayForDb', () {
    test('formats as local YYYY-MM-DD (no time component)', () {
      expect(formatBirthdayForDb(DateTime(1998, 3, 4)), '1998-03-04');
      expect(formatBirthdayForDb(DateTime(2000, 12, 1)), '2000-12-01');
      expect(formatBirthdayForDb(null), isNull);
    });
  });

  group('manual entry lists', () {
    test('EU sizes run 35 → 48 in half steps, matching the scan results range', () {
      expect(customerEuSizes.first, '35');
      expect(customerEuSizes.last, '48');
      expect(customerEuSizes, contains('40.5'));
      // 27 values: (48 - 35) * 2 + 1
      expect(customerEuSizes.length, 27);
    });

    test('width options mirror the canonical list', () {
      expect(customerFootWidths, ['Narrow', 'Regular', 'Wide']);
    });
  });
}
