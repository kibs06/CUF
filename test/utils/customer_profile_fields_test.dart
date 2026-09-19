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

    test('the band follows the shopping scale', () {
      // Adults keep the 35 → 48 list the scan results screen uses.
      expect(customerEuSizesFor('men'), customerEuSizes);
      expect(customerEuSizesFor('women'), customerEuSizes);
      expect(customerEuSizesFor(null), customerEuSizes);

      // Kids mirrors euSizeChart's children's band (22 → 35) — before this a
      // child wearing EU 28 could not enter their size at all.
      expect(customerEuSizesFor('kids'), customerKidsEuSizes);
      expect(customerEuSizesFor('kids').first, '22');
      expect(customerEuSizesFor('kids').last, '35');
      expect(customerEuSizesFor('kids'), contains('28.5'));
      expect(customerEuSizesFor('kids'), isNot(contains('42')));
    });

    test('width options mirror the canonical list', () {
      expect(customerFootWidths, ['Narrow', 'Regular', 'Wide']);
    });

    test('shopping scales match what the scan stores', () {
      // These strings are load-bearing: they are written to
      // profiles.foot_size_category and foot_measurements.shoe_category, and
      // FootMeasurement.euToUs switches on them.
      expect(customerFootSizeCategories.map((c) => c.$1).toList(),
          ['men', 'women', 'kids']);
      expect(footSizeCategoryLabel('women'), "Women's");
      expect(footSizeCategoryLabel('men'), "Men's");
      expect(footSizeCategoryLabel('kids'), "Kids'");
    });

    test('an absent or unknown scale has no label — never a guess', () {
      expect(footSizeCategoryLabel(null), isNull);
      expect(footSizeCategoryLabel(''), isNull);
      expect(footSizeCategoryLabel('unisex'), isNull);
    });
  });

  group('footProfileSummary', () {
    test('says nothing is saved for an absent or empty profile', () {
      expect(footProfileSummary(null), 'Not set yet');
      expect(footProfileSummary(const {}), 'Not set yet');
      expect(
        footProfileSummary(const {'foot_profile_source': 'skipped'}),
        'Not set yet',
      );
      expect(footProfileSummary(const {'foot_size_ph': '   '}), 'Not set yet');
    });

    test('names the size and where it came from', () {
      expect(
        footProfileSummary(
          const {'foot_size_ph': 42.0, 'foot_profile_source': 'manual'},
        ),
        'EU 42 · set manually',
      );
      expect(
        footProfileSummary(
          const {'foot_size_ph': 42.5, 'foot_profile_source': 'ar_scan'},
        ),
        'EU 42.5 · from your AR scan',
      );
    });

    test('a size with no known source still reads as the size', () {
      // Pre-feature rows have the size but predate the source column.
      expect(footProfileSummary(const {'foot_size_ph': '40'}), 'EU 40');
      expect(
        footProfileSummary(const {'foot_size_ph': 40, 'foot_profile_source': null}),
        'EU 40',
      );
    });

    test('names the shopping scale when one is saved', () {
      expect(
        footProfileSummary(const {
          'foot_size_ph': 42,
          'foot_size_category': 'women',
          'foot_profile_source': 'manual',
        }),
        "EU 42 · Women's · set manually",
      );
      // Unset or unrecognised → the size alone, exactly as before.
      expect(
        footProfileSummary(const {'foot_size_ph': 40, 'foot_size_category': null}),
        'EU 40',
      );
      expect(
        footProfileSummary(const {'foot_size_ph': 40, 'foot_size_category': 'x'}),
        'EU 40',
      );
    });
  });

  group('savedFootSizeCategory', () {
    test('returns the saved scale key', () {
      expect(
        savedFootSizeCategory(const {'foot_size_category': 'women'}),
        'women',
      );
      expect(savedFootSizeCategory(const {'foot_size_category': 'men'}), 'men');
      expect(
        savedFootSizeCategory(const {'foot_size_category': 'kids'}),
        'kids',
      );
    });

    test('null for an absent profile, an unset column, or a bad value', () {
      expect(savedFootSizeCategory(null), isNull);
      expect(savedFootSizeCategory(const {}), isNull);
      expect(savedFootSizeCategory(const {'foot_size_category': null}), isNull);
      expect(savedFootSizeCategory(const {'foot_size_category': ''}), isNull);
      expect(
        savedFootSizeCategory(const {'foot_size_category': 'unisex'}),
        isNull,
      );
      // Identity gender is not a sizing scale.
      expect(
        savedFootSizeCategory(const {'gender': 'Woman'}),
        isNull,
      );
    });
  });
}
