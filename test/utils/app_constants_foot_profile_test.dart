import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_constants.dart';

void main() {
  group('needsFootProfile (source only)', () {
    test('NULL / empty / skipped all count as missing', () {
      expect(AppConstants.needsFootProfile(null), isTrue);
      expect(AppConstants.needsFootProfile(''), isTrue);
      expect(AppConstants.needsFootProfile('skipped'), isTrue);
    });

    test('scanned and manually-picked sources count as present', () {
      expect(AppConstants.needsFootProfile('ar_scan'), isFalse);
      expect(AppConstants.needsFootProfile('manual'), isFalse);
    });
  });

  group('hasFootSize', () {
    test('null profile has no size', () {
      expect(AppConstants.hasFootSize(null), isFalse);
    });

    test('no signal at all → banner should show', () {
      expect(AppConstants.hasFootSize(const {}), isFalse);
      expect(
        AppConstants.hasFootSize({
          'foot_profile_source': null,
          'foot_size_ph': null,
        }),
        isFalse,
      );
      expect(
        AppConstants.hasFootSize({
          'foot_profile_source': 'skipped',
          'foot_size_ph': null,
        }),
        isFalse,
      );
    });

    test('a completed source alone is enough', () {
      expect(
        AppConstants.hasFootSize({'foot_profile_source': 'ar_scan'}),
        isTrue,
      );
      expect(
        AppConstants.hasFootSize({'foot_profile_source': 'manual'}),
        isTrue,
      );
    });

    test('a stored EU size alone is enough (snapshot write lost the source)',
        () {
      expect(AppConstants.hasFootSize({'foot_size_ph': 40.5}), isTrue);
      expect(AppConstants.hasFootSize({'foot_size_ph': 40}), isTrue);
      expect(AppConstants.hasFootSize({'foot_size_ph': '40.5'}), isTrue);
    });

    test('a size wins over a skipped source', () {
      expect(
        AppConstants.hasFootSize({
          'foot_profile_source': 'skipped',
          'foot_size_ph': 39.0,
        }),
        isTrue,
      );
    });

    test('a blank size is not a size', () {
      expect(AppConstants.hasFootSize({'foot_size_ph': ''}), isFalse);
      expect(AppConstants.hasFootSize({'foot_size_ph': '  '}), isFalse);
    });
  });
}
