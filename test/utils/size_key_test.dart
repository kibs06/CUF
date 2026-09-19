import 'dart:io';

import 'package:app/utils/size_key.dart';
import 'package:flutter_test/flutter_test.dart';

/// P0 characterization suite for `lib/utils/size_key.dart`.
///
/// See `docs/AI/SIZE_AWARE_SHOPPING_PLAN.md` §4–5: this pins the one rule for
/// what a stored size means before any size-aware UI ships.
void main() {
  group('sizeSystem', () {
    test('prefers an explicit prefix', () {
      expect(sizeSystem('EU 40'), 'EU');
      expect(sizeSystem('EU40'), 'EU');
      expect(sizeSystem('eu 40'), 'EU');
      expect(sizeSystem('US 8'), 'US');
      expect(sizeSystem('UK 3.5'), 'UK');
      expect(sizeSystem('JP 25'), 'JP');
    });

    test('bare numbers fall back to the default system (decision #1: EU)', () {
      expect(kDefaultSizeSystem, 'EU');
      expect(sizeSystem('40'), 'EU');
      expect(sizeSystem(' 40'), 'EU');
      expect(sizeSystem('9.5'), 'EU');
    });

    test('no number → default, never a guessed prefix', () {
      expect(sizeSystem(''), 'EU');
      expect(sizeSystem('Other'), 'EU');
      expect(sizeSystem('garbage'), 'EU');
    });
  });

  group('sizeNumber', () {
    test('parses prefixed and bare sizes', () {
      expect(sizeNumber('EU 40'), 40);
      expect(sizeNumber('40'), 40);
      expect(sizeNumber(' 40'), 40);
      expect(sizeNumber('EU40'), 40);
      expect(sizeNumber('US 8'), 8);
      expect(sizeNumber('UK 3.5'), 3.5);
      expect(sizeNumber('JP 25'), 25);
      expect(sizeNumber('9.5'), 9.5);
    });

    test('returns null when there is no number', () {
      expect(sizeNumber(''), isNull);
      expect(sizeNumber('EU'), isNull);
      expect(sizeNumber('Other'), isNull);
      expect(sizeNumber('garbage'), isNull);
    });
  });

  group('sizeKey — the DB mirror', () {
    test("mirrors regexp_replace(size, '\\D', '', 'g')", () {
      // The database matches sizes digits-only, everywhere (§4.1).
      expect(sizeKey('EU 40'), '40');
      expect(sizeKey('40'), '40');
      expect(sizeKey(' 40'), '40');
      expect(sizeKey('US 8'), '8');
      // The dot goes too — `\D` is exactly non-digit, not "non-digit-or-dot".
      expect(sizeKey('UK 3.5'), '35');
      expect(sizeKey('JP 25'), '25');
      expect(sizeKey('9.5'), '95');
      expect(sizeKey(''), '');
      expect(sizeKey('Other'), '');
    });

    test('the DB-mirror invariant: EU 40 and 40 are one size', () {
      expect(sizeKey('EU 40'), sizeKey('40'));
      expect(sizeKey(' 40'), sizeKey('EU 40'));
    });

    test('sizeKeyForEu keys a profile EU size the same way', () {
      expect(sizeKeyForEu(40), '40');
      expect(sizeKeyForEu(42), '42');
      expect(sizeKeyForEu(41.5), '415');
    });
  });

  group('sizeNumberInEu', () {
    test('is identity for EU and for bare (default) sizes', () {
      expect(sizeNumberInEu('EU 40'), 40);
      expect(sizeNumberInEu('40'), 40);
      expect(sizeNumberInEu('41.5'), 41.5);
    });

    test('converts the known systems', () {
      expect(sizeNumberInEu('US 7'), 40);
      expect(sizeNumberInEu('UK 6.5'), 40);
    });

    test('unknown systems keep their raw value — the band check rejects them',
        () {
      // 'JP 25' is not EU 25; it is simply outside [kEuMin, kEuMax], which is
      // what stops P1's match rule from claiming it (R1).
      expect(sizeNumberInEu('JP 25'), 25);
      expect(kEuMin, 35);
      expect(kEuMax, 48);
      expect(kNearSizeToleranceEu, 0.5);
    });

    test('returns null when there is no number', () {
      expect(sizeNumberInEu(''), isNull);
      expect(sizeNumberInEu('Other'), isNull);
    });
  });

  group('formatSize — the one label formatter', () {
    test('names the system instead of assuming one', () {
      expect(formatSize('EU 40'), 'EU 40');
      expect(formatSize('40'), 'EU 40');
      expect(formatSize(' 40'), 'EU 40');
      expect(formatSize('EU40'), 'EU 40');
      expect(formatSize('US 8'), 'US 8');
      expect(formatSize('UK 3.5'), 'UK 3.5');
      expect(formatSize('JP 25'), 'JP 25');
      expect(formatSize('9.5'), 'EU 9.5');
    });

    test('converts when asked for a target unit', () {
      expect(formatSize('EU 40', unit: 'US'), 'US 7');
      expect(formatSize('EU 40', unit: 'EU'), 'EU 40');
      expect(formatSize('US 8', unit: 'EU'), 'EU 41');
      // The §4.2 fix: a bare stored EU 40 no longer renders as 'US 40'.
      expect(formatSize('40', unit: 'US'), 'US 7');
    });

    test('falls back to the raw string when it cannot parse', () {
      expect(formatSize(''), '');
      expect(formatSize('Other'), 'Other');
      expect(formatSize('garbage'), 'garbage');
    });
  });

  group('compareSizes — half sizes sort numerically', () {
    test('orders by numeric value, not by string or int.tryParse', () {
      expect(compareSizes('40', '42'), lessThan(0));
      expect(compareSizes('42', '40'), greaterThan(0));
      expect(compareSizes('42.5', '42'), greaterThan(0));
      expect(compareSizes('9.5', '10.5'), lessThan(0));
      expect(compareSizes('EU 40', 'EU 41.5'), lessThan(0));
      expect(compareSizes('40', '40'), 0);
    });

    test('unparseable sizes sort last, never to the front', () {
      expect(compareSizes('Other', 'EU 40'), greaterThan(0));
      expect(compareSizes('EU 40', 'Other'), lessThan(0));
      expect(compareSizes('Other', 'garbage'), isNot(0));
    });

    test('the §4.3 regression: half sizes sort in place', () {
      final sizes = ['42.5', '40', '41.5', '9.5', '39'];
      sizes.sort(compareSizes);
      expect(sizes, ['9.5', '39', '40', '41.5', '42.5']);
    });
  });

  group('the shopping scale — US labels are chart-dependent', () {
    test('men\'s offsets are the default and the only fallback', () {
      expect(kDefaultSizeCategory, 'men');
      expect(euToUsChartOffset(null), 33);
      expect(euToUsChartOffset('men'), 33);
      expect(euToUsChartOffset('kids'), 33);
      expect(euToUsChartOffset('women'), 31.5);
      // An unrecognised scale is NOT read as women's.
      expect(euToUsChartOffset('unisex'), 33);
    });

    test('the same EU size reads differently per scale', () {
      expect(usSizeFromEu(42), 9);
      expect(usSizeFromEu(42, category: 'women'), 10.5);
      expect(usSizeFromEu(42, category: 'kids'), 9);
      expect(euSizeFromUs(10.5, category: 'women'), 42);
    });

    test('formatSize labels US on the scale it is given', () {
      expect(formatSize('EU 42', unit: 'US'), 'US 9');
      expect(formatSize('EU 42', unit: 'US', category: 'women'), 'US 10.5');
      expect(formatSize('EU 42', unit: 'US', category: 'kids'), 'US 9');
      // Bare (EU) sizes take the same path — this is the product-page grid.
      expect(formatSize('42', unit: 'US', category: 'women'), 'US 10.5');
      expect(formatSize('42.5', unit: 'US', category: 'women'), 'US 11');
      // Round-tripping stays exact, so a tapped label maps back to one size.
      expect(
        formatSize(formatSize('EU 41.5', unit: 'US', category: 'women'),
            unit: 'EU', category: 'women'),
        'EU 41.5',
      );
    });

    test('UK stays on its single chart — the scale must not move it', () {
      // The app owns a women's offset for the US chart only. Inventing one for
      // UK here would disagree with euToUk() on the scan screens, so the UK
      // label is deliberately unchanged by the category.
      expect(formatSize('EU 42', unit: 'UK'), 'UK 8.5');
      expect(formatSize('EU 42', unit: 'UK', category: 'women'), 'UK 8.5');
      expect(convertSizeNumber(42, 'EU', 'UK', category: 'women'), 8.5);
    });

    test('convertSizeNumber is unchanged for the men\'s default', () {
      expect(convertSizeNumber(40, 'EU', 'US'), 7);
      expect(convertSizeNumber(7, 'US', 'EU'), 40);
      expect(convertSizeNumber(40, 'EU', 'UK'), 6.5);
      expect(convertSizeNumber(6.5, 'UK', 'EU'), 40);
      expect(convertSizeNumber(7, 'US', 'UK'), 6.5);
      expect(convertSizeNumber(6.5, 'UK', 'US'), 7);
      expect(convertSizeNumber(40, 'EU', 'EU'), 40);
    });

    test('units are EU + US + UK — except on the kids chart', () {
      expect(kSizeUnits, ['EU', 'US', 'UK']);
      expect(sizeUnitsForCategory(null), kSizeUnits);
      expect(sizeUnitsForCategory('men'), kSizeUnits);
      expect(sizeUnitsForCategory('women'), kSizeUnits);
      // Kids' US/UK is a separate, non-linear chart this app does not own: the
      // men's-derived step would label a child's EU 22 as US -11.
      expect(sizeUnitsForCategory('kids'), ['EU']);
      expect(usSizeFromEu(22, category: 'kids'), -11);
    });

    test('an unknown system is still returned unchanged', () {
      expect(convertSizeNumber(25, 'JP', 'EU'), 25);
      expect(convertSizeNumber(40, 'EU', 'JP'), 40);
      expect(formatSize('JP 25', unit: 'US'), 'US 25');
    });
  });

  group('guard', () {
    test('no lib file hardcodes an "EU " size label', () {
      // Whole-line comments are skipped; code lines are scanned in full.
      final pattern = RegExp(r"""['"]EU \$""");
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (pattern.hasMatch(lines[i])) offenders.add('${entity.path}:${i + 1}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Route size labels through formatSize() from '
            'lib/utils/size_key.dart instead of a hardcoded EU literal.',
      );
    });

    test('every displaySizeInUnit call site names the shopping scale', () {
      // A US label without the shopper's saved scale silently falls back to the
      // men's chart — the mislabelling this wiring removed. Kept as a guard so
      // a new call site cannot quietly reintroduce it.
      final pattern = RegExp(r'displaySizeInUnit\(');
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final match in pattern.allMatches(source)) {
          final call = source.substring(
              match.start, (match.start + 160).clamp(0, source.length));
          if (!call.contains('category:')) {
            final line = source.substring(0, match.start).split('\n').length;
            offenders.add('${entity.path}:$line');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Pass category: savedFootSizeCategory(profile) to '
            'displaySizeInUnit so US labels use the shopper\'s own chart.',
      );
    });
  });
}
