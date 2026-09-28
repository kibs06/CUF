import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/fit_spec_form.dart';
import 'package:app/utils/size_match.dart';

/// The seller form's fit fields: the one place in the product form where a
/// *plausible-looking* typo is worse than a missing value.
///
/// These tests are mostly about refusals, because that is the job: `27.5` is a
/// parser-valid last length and a nonsense one, a US size is a perfectly good
/// size and the wrong answer to "which EU size did you measure at", and a width
/// with no length saves fine and then never produces a verdict. Each of those
/// is pinned here with the sentence the seller is shown.

FitSpecFormResult parse({
  String lastLengthMm = '',
  String lastWidthMm = '',
  String heelHeightMm = '',
  String refSizeEu = '',
}) =>
    FitSpecFormResult.fromFields(
      lastLengthMm: lastLengthMm,
      lastWidthMm: lastWidthMm,
      heelHeightMm: heelHeightMm,
      refSizeEu: refSizeEu,
    );

void main() {
  group('a complete spec', () {
    test('reads the four fields', () {
      final result = parse(
        lastLengthMm: '275',
        lastWidthMm: '98',
        heelHeightMm: '25',
        refSizeEu: '42',
      );

      expect(result.isError, isFalse);
      expect(result.isEmpty, isFalse);
      expect(result.specs!.lastLengthMm, 275);
      expect(result.specs!.lastWidthMm, 98);
      expect(result.specs!.heelHeightMm, 25);
      expect(result.specs!.refSizeEu, 42);
    });

    test('a length and its size are enough — both extras stay null', () {
      final result = parse(lastLengthMm: '275', refSizeEu: '42');

      expect(result.isError, isFalse);
      expect(result.specs!.lastLengthMm, 275);
      expect(result.specs!.lastWidthMm, isNull);
      expect(result.specs!.heelHeightMm, isNull);
    });

    test('tolerates the units a seller types after the number', () {
      expect(parse(lastLengthMm: '275 mm', refSizeEu: '42').specs!.lastLengthMm,
          275);
      expect(parse(lastLengthMm: '275mm', refSizeEu: '42').specs!.lastLengthMm,
          275);
      expect(parse(lastLengthMm: '275,5', refSizeEu: '42mm').specs!.refSizeEu,
          42);
    });

    test('accepts a size written with its system', () {
      expect(parse(lastLengthMm: '275', refSizeEu: 'EU 42').specs!.refSizeEu, 42);
    });

    test('accepts a half size', () {
      expect(parse(lastLengthMm: '275', refSizeEu: '42.5').specs!.refSizeEu, 42.5);
    });

    test('trims whitespace a paste brings with it', () {
      final result = parse(
        lastLengthMm: ' 275 ',
        lastWidthMm: ' 98 ',
        refSizeEu: ' 42 ',
      );

      expect(result.isError, isFalse);
      expect(result.specs!.lastLengthMm, 275);
      expect(result.specs!.lastWidthMm, 98);
    });
  });

  group('blank fields', () {
    test('all four blank is "not measured", not an error', () {
      final result = parse();

      expect(result.isEmpty, isTrue);
      expect(result.isError, isFalse);
      expect(result.specs, isNull);
    });

    test('an empty optional field never raises an error', () {
      // The regression this pins: an empty width passed through the mm parser
      // used to come back as "enter the last width as a number of millimetres".
      final result = parse(lastLengthMm: '275', refSizeEu: '42');

      expect(result.isError, isFalse);
      expect(result.messageFor(FitSpecField.lastWidthMm), isNull);
      expect(result.messageFor(FitSpecField.heelHeightMm), isNull);
    });
  });

  group('the centimetre guard', () {
    test('names the unit mistake instead of quoting a band', () {
      final result = parse(lastLengthMm: '27.5', refSizeEu: '42');

      expect(result.errorField, FitSpecField.lastLengthMm);
      expect(result.error, contains('centimetres'));
      expect(result.error, contains('275'));
      expect(result.error, isNot(contains('between')));
    });

    test('the value alone is enough — no unit has to be typed', () {
      // 27.5 cm is a real last; 27.5 mm is not a shoe. The band decides which
      // reading the seller meant.
      expect(parse(lastLengthMm: '27.5', refSizeEu: '42').error,
          contains('centimetres'));
      expect(
        parse(lastLengthMm: '275', lastWidthMm: '9.8', refSizeEu: '42')
            .errorField,
        FitSpecField.lastWidthMm,
      );
      expect(
        parse(lastLengthMm: '275', lastWidthMm: '9.8', refSizeEu: '42').error,
        contains('centimetres'),
      );
      // Typed, or implied by the value: same sentence.
      expect(
        parse(lastLengthMm: '275', lastWidthMm: '98mm', refSizeEu: '42')
            .isError,
        isFalse,
      );
    });

    test('a centimetre figure that is plausible at both readings is accepted',
        () {
      // 2.5 is a 2.5 mm sole and a 25 mm heel. Nothing in the number says which,
      // so the parser cannot honestly refuse it.
      final result = parse(
        lastLengthMm: '275',
        heelHeightMm: '2.5',
        refSizeEu: '42',
      );

      expect(result.isError, isFalse);
      expect(result.specs!.heelHeightMm, 2.5);
    });

    test('an explicit cm suffix is refused even when the value is plausible',
        () {
      final result = parse(
        lastLengthMm: '275',
        heelHeightMm: '2.5cm',
        refSizeEu: '42',
      );

      expect(result.errorField, FitSpecField.heelHeightMm);
      expect(result.error, contains('centimetres'));
    });
  });

  group('plausibility', () {
    test('refuses a number outside what a shoe can be, on the right field', () {
      final result = parse(lastLengthMm: '4200', refSizeEu: '42');

      expect(result.errorField, FitSpecField.lastLengthMm);
      expect(result.error, contains('between 120 and 360'));
    });

    test('the bands match the engine and the database columns', () {
      // Length bounds.
      expect(parse(lastLengthMm: '120', refSizeEu: '42').isError, isFalse);
      expect(parse(lastLengthMm: '360', refSizeEu: '42').isError, isFalse);
      expect(parse(lastLengthMm: '119', refSizeEu: '42').isError, isTrue);
      expect(parse(lastLengthMm: '361', refSizeEu: '42').isError, isTrue);
      // Width bounds.
      expect(
        parse(lastLengthMm: '275', lastWidthMm: '40', refSizeEu: '42').isError,
        isFalse,
      );
      expect(
        parse(lastLengthMm: '275', lastWidthMm: '39', refSizeEu: '42').isError,
        isTrue,
      );
      // Heel bounds.
      expect(
        parse(lastLengthMm: '275', heelHeightMm: '80', refSizeEu: '42').isError,
        isFalse,
      );
      expect(
        parse(lastLengthMm: '275', heelHeightMm: '81', refSizeEu: '42').isError,
        isTrue,
      );
      // Reference size bounds — the same band the catalog treats as EU.
      expect(parse(lastLengthMm: '275', refSizeEu: '22').isError, isFalse);
      expect(parse(lastLengthMm: '275', refSizeEu: '48').isError, isFalse);
      expect(parse(lastLengthMm: '275', refSizeEu: '21').isError, isTrue);
      expect(parse(lastLengthMm: '275', refSizeEu: '49').isError, isTrue);
      expect(kPlausibleEuMin, 22);
      expect(kPlausibleEuMax, 48);
    });

    test('a word where a number belongs is refused', () {
      expect(parse(lastLengthMm: 'about 275', refSizeEu: '42').error,
          contains('number of millimetres'));
    });
  });

  group('a US/UK size is refused by name', () {
    for (final entry in const [
      ('US 9', 'US size'),
      ('UK 6', 'UK size'),
    ]) {
      test('${entry.$1} comes back asking for EU', () {
        final result = parse(lastLengthMm: '275', refSizeEu: entry.$1);

        expect(result.errorField, FitSpecField.refSizeEu);
        expect(result.error, contains(entry.$2));
        expect(result.error, contains('EU'));
      });
    }

    test('an unparseable size asks for the EU size', () {
      expect(parse(lastLengthMm: '275', refSizeEu: 'large').error,
          contains('Enter the EU size'));
    });
  });

  group('half-filled shapes', () {
    test('a size with no length names the missing length', () {
      final result = parse(refSizeEu: '42');

      expect(result.errorField, FitSpecField.lastLengthMm);
      expect(result.error, contains('Add the last length'));
    });

    test('a width with no length names the missing length', () {
      final result = parse(lastWidthMm: '98', refSizeEu: '42');

      expect(result.errorField, FitSpecField.lastLengthMm);
      expect(result.error, contains('decided by length'));
    });

    test('a heel height with no length is refused too', () {
      final result = parse(heelHeightMm: '25');

      expect(result.errorField, FitSpecField.lastLengthMm);
      expect(result.error, contains('Add the last length'));
    });

    test('a length with no reference size cannot be graded', () {
      final result = parse(lastLengthMm: '275');

      expect(result.errorField, FitSpecField.refSizeEu);
      expect(result.error, contains('grades from it'));
    });
  });

  group('messageFor', () {
    test('only the field the error belongs to sees the sentence', () {
      final result = parse(lastLengthMm: '27.5', refSizeEu: '42');

      expect(result.messageFor(FitSpecField.lastLengthMm), isNotNull);
      expect(result.messageFor(FitSpecField.lastWidthMm), isNull);
      expect(result.messageFor(FitSpecField.heelHeightMm), isNull);
      expect(result.messageFor(FitSpecField.refSizeEu), isNull);
    });

    test('a valid spec has no message for any field', () {
      final result = parse(lastLengthMm: '275', refSizeEu: '42');

      for (final field in FitSpecField.values) {
        expect(result.messageFor(field), isNull, reason: '$field');
      }
    });
  });

  group('prefill from a stored product', () {
    Map<String, dynamic> product(Map<String, dynamic> fit) => {
          'id': 'p1',
          'name': 'Penny Loafer',
          ...fit,
        };

    test('shows the stored numbers, whole ones without a decimal point', () {
      final texts = fitSpecFieldTexts(product(const {
        'last_length_mm': 275,
        'last_width_mm': '98.5',
        'heel_height_mm': 25,
        'fit_ref_size_eu': '42',
      }));

      expect(texts.lastLengthMm, '275');
      expect(texts.lastWidthMm, '98.5');
      expect(texts.heelHeightMm, '25');
      expect(texts.refSizeEu, '42');
    });

    test('a product with no spec prefills blank', () {
      final texts = fitSpecFieldTexts(product(const {}));

      expect(texts.lastLengthMm, '');
      expect(texts.lastWidthMm, '');
      expect(texts.heelHeightMm, '');
      expect(texts.refSizeEu, '');
    });

    test('a spec the engine would refuse prefills blank, not as-is', () {
      // A length with no reference size cannot be graded: showing the seller a
      // number the app is ignoring invites them to save it again.
      final texts = fitSpecFieldTexts(product(const {'last_length_mm': 275}));

      expect(texts.lastLengthMm, '');
      expect(texts.refSizeEu, '');
    });

    test('an implausible width drops only the width', () {
      final texts = fitSpecFieldTexts(product(const {
        'last_length_mm': 275,
        'last_width_mm': 5,
        'fit_ref_size_eu': 42,
      }));

      expect(texts.lastLengthMm, '275');
      expect(texts.refSizeEu, '42');
      expect(texts.lastWidthMm, '');
    });

    test('a null product prefills blank', () {
      expect(fitSpecFieldTexts(null).lastLengthMm, '');
    });

    test('a prefilled product round-trips through the parser', () {
      final texts = fitSpecFieldTexts(product(const {
        'last_length_mm': 275,
        'last_width_mm': 98,
        'heel_height_mm': 25,
        'fit_ref_size_eu': 42,
      }));
      final result = FitSpecFormResult.fromFields(
        lastLengthMm: texts.lastLengthMm,
        lastWidthMm: texts.lastWidthMm,
        heelHeightMm: texts.heelHeightMm,
        refSizeEu: texts.refSizeEu,
      );

      expect(result.isError, isFalse);
      expect(result.specs!.lastLengthMm, 275);
      expect(result.specs!.refSizeEu, 42);
      expect(result.specs!.lastWidthMm, 98);
    });
  });
}
