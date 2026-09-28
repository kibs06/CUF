import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/foot_measurement.dart';
import 'package:app/utils/fit_shadow.dart';
import 'package:app/utils/fit_verdict_state.dart';

/// Shadow mode's one line (roadmap V1.7).
///
/// The record is what the V1 accuracy bar is judged on — *does the verdict
/// match an artisan's opinion on 10 real products* — so what matters here is
/// that a reviewer can act on a line without opening a debugger: the identity
/// and the size are there, the band and the millimetres behind it are there,
/// the reasons are there, and when there is no verdict the rule that said so is
/// named. The log is line-based, so a line stays one line.

/// A men's EU 42 product: 275 mm internal last, 98 mm wide, measured at 42.
Map<String, dynamic> product({
  Object? id = 'product-1',
  Object? length = 275,
  Object? width = 98,
  Object? ref = 42,
}) => {
  'id': id,
  'last_length_mm': length,
  'last_width_mm': width,
  'fit_ref_size_eu': ref,
};

/// A 265 mm foot, 95 mm wide — 10 mm of toe room in the EU 42 above.
FootMeasurement scannedFoot({double? lengthMm = 265, double? widthMm = 95}) =>
    FootMeasurement(
      userId: 'user-1',
      sizingFootSide: 'right',
      footLengthRightMm: lengthMm,
      footWidthRightMm: widthMm,
      paperSizeUsed: 'ar',
      scanDate: DateTime(2026, 9, 27),
    );

String? line({
  Map<String, dynamic>? productRow,
  String? selectedSize = '42',
  FootMeasurement? measurement,
  FitScanProbe probe = FitScanProbe.done,
}) => fitShadowLine(
  product: productRow ?? product(),
  selectedSize: selectedSize,
  measurement: measurement,
  probe: probe,
);

void main() {
  group('a recorded verdict', () {
    test('carries the identity, the size, the band and the numbers', () {
      final record = line(measurement: scannedFoot())!;

      expect(record, startsWith(kFitShadowTag));
      expect(record, contains('product=product-1'));
      expect(record, contains('size=EU 42'));
      expect(record, contains('band=trueToSize'));
      expect(record, contains('toe=10'));
      expect(record, contains('width=3'));
      // 0.75 (a scan with no recorded quality) × 0.85 (both widths known).
      // Printed to two places so a reviewer can discount a thin record.
      expect(record, contains('conf=0.64'));
      expect(record, contains('foot=265'));
      expect(record, contains('last=275'));
    });

    test('prints the engine reasons, quoted, so a review can read them', () {
      final record = line(measurement: scannedFoot())!;

      expect(record, contains('why="'));
      expect(record, contains('10 mm of toe room — true to size'));
      expect(record, contains(' | '));
    });

    test('omits the width rather than calling an unmeasured one zero', () {
      final record = line(
        productRow: product(width: null),
        measurement: scannedFoot(),
      )!;

      expect(record, contains('band=trueToSize'));
      expect(record, isNot(contains('width=')));
      // …and the reasons say so, which is the honest half of the same rule.
      expect(record, contains('no last width recorded'));
    });

    test('a half size is recorded with its value intact', () {
      final record = line(selectedSize: '42.5', measurement: scannedFoot())!;

      // Half a size up is 3.3 mm more toe room — still the target band, and
      // the record says so rather than rounding the size away.
      expect(record, contains('size=EU 42.5'));
      expect(record, contains('band=trueToSize'));
      expect(record, contains('toe=13'));

      expect(
        line(selectedSize: '41', measurement: scannedFoot()),
        contains('band=snug'),
      );
    });

    test('the record is what the card would say with the switch ON', () {
      // The formatter takes no `enabled` argument at all: shadow mode asks the
      // engine's question, which is the only reason it can collect a sample
      // while `AppConstants.virtualFitEnabled` is off.
      final record = line(measurement: scannedFoot())!;

      expect(record, contains('band='));
      expect(record, isNot(contains('would=disabled')));
    });
  });

  group('a page with no verdict records why', () {
    test('no spec names the rule', () {
      final record = line(
        productRow: product(length: null, width: null, ref: null),
        measurement: scannedFoot(),
      )!;

      expect(record, contains('product=product-1'));
      expect(record, contains('would=noSpecs'));
      expect(record, contains('foot=265'));
      expect(record, isNot(contains('band=')));
    });

    test('a size that does not resolve prints the stored string', () {
      final record = line(selectedSize: 'JP 25', measurement: scannedFoot())!;

      // `ungradeable`, not `noSize`: the raw value is carried as `25` and the
      // engine refuses it for being 17 EU steps from the measured sample —
      // which is exactly the case the reviewer needs to see spelled out.
      expect(record, contains('would=ungradeable'));
      expect(record, contains('raw="JP 25"'));
    });

    test('an unselected size says so', () {
      final record = line(selectedSize: null, measurement: scannedFoot())!;

      expect(record, contains('would=noSize'));
    });

    test('no scan on file is a record, not a silence', () {
      final record = line(measurement: null, probe: FitScanProbe.done)!;

      expect(record, contains('would=needsScan'));
      expect(record, isNot(contains('foot=')));
    });

    test('a failed read is recorded', () {
      final record = line(measurement: null, probe: FitScanProbe.failed)!;

      expect(record, contains('would=unavailable'));
    });

    test('a read still in flight is not a record at all', () {
      // The loading beat is not an outcome: the record that follows it (or its
      // failure) is what belongs in the log, and logging the beat would double
      // every returning customer's lines with a state nobody can judge.
      expect(line(measurement: null, probe: FitScanProbe.pending), isNull);
    });
  });

  group('the line stays a line', () {
    test('a stored size with breaks in it is flattened, not split', () {
      // The log is line-based and read by eye, so a value carrying a newline
      // would silently turn one record into two — and a stored size is a
      // database string this app only interprets, never guarantees. `_quoted`
      // flattens it rather than trusting it.
      final record = line(selectedSize: 'JP\n 25', measurement: scannedFoot())!;

      expect(record, isNot(contains('\n')));
      expect(record, contains('raw="JP 25"'));
      expect(RegExp(r'\s\s').hasMatch(record), isFalse);
    });

    test('an identity-less row still produces a parseable line', () {
      final record = fitShadowLine(
        product: product(id: null),
        selectedSize: '42',
        measurement: scannedFoot(),
        probe: FitScanProbe.done,
      )!;

      expect(record, contains('product=?'));
      expect(record.split(' ').first, kFitShadowTag);
    });
  });
}
