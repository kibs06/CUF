import 'package:app/models/card_fit_result.dart';
import 'package:app/utils/card_measurement_pipeline.dart';
import 'package:app/utils/foot_measurement_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Capture-to-Fit handoff: a pipeline success becomes the result the AR
/// screen applies, and the recommended EU size becomes an in-stock pick or
/// an honest null — never a silent substitution.
void main() {
  CardMeasurementSuccess successWith({
    double compensatedLengthMm = 268.0,
    String confidence = 'high',
  }) =>
      CardMeasurementSuccess(
        lengthMm: 266.0,
        widthMm: 102.0,
        compensatedLengthMm: compensatedLengthMm,
        compensatedWidthMm: 103.0,
        recommendation: recommendCardSizes(
          compensatedLengthMm: compensatedLengthMm,
          measurementSource: 'paper',
          confidenceLevel: confidence,
          shoeCategory: 'men',
        )!,
        scaleMedian: 0.42,
        scaleIqrMmPerPx: 0.001,
        burstFrames: 6,
      );

  CardFitResult resultWith({
    double compensatedLengthMm = 268.0,
    String confidence = 'high',
    String footSide = 'left',
  }) =>
      CardFitResult.fromSuccess(
        successWith(
          compensatedLengthMm: compensatedLengthMm,
          confidence: confidence,
        ),
        footSide: footSide,
        burstConfidenceLevel: confidence,
      );

  group('CardFitResult.fromSuccess', () {
    test('carries the pipeline numbers and the pass side', () {
      final result = resultWith(
        compensatedLengthMm: 268.0,
        footSide: 'right',
      );

      expect(result.compensatedLengthMm, 268.0);
      expect(result.widthMm, 102.0);
      expect(result.sizeEu, footLengthMmToEuSize(268.0));
      expect(result.footSide, 'right');
      expect(result.burstFrames, 6);
      expect(result.confidenceLevel, 'high');
    });

    test('live quality follows the burst confidence label', () {
      expect(resultWith(confidence: 'high').liveQuality, 0.9);
      expect(resultWith(confidence: 'medium').liveQuality, 0.7);
      expect(resultWith(confidence: 'low').liveQuality, 0.4);
    });
  });

  group('pickStockSizeForFit', () {
    test('exact in-stock match wins', () {
      expect(
        pickStockSizeForFit(
          sizes: {'41': 3, '42': 5, '43': 0},
          recommendedEu: '42',
        ),
        '42',
      );
    });

    test('nearest in-stock size within half a size wins', () {
      expect(
        pickStockSizeForFit(
          sizes: {'41': 0, '42.5': 4},
          recommendedEu: '42',
        ),
        '42.5',
      );
    });

    test('nothing close in stock is null — the selection stays', () {
      expect(
        pickStockSizeForFit(
          sizes: {'38': 4, '47': 2},
          recommendedEu: '42',
        ),
        isNull,
      );
    });

    test('out-of-stock sizes are skipped even when exact', () {
      expect(
        pickStockSizeForFit(
          sizes: {'42': 0, '43': 1},
          recommendedEu: '42',
        ),
        isNull,
        reason: '43 is a full size away, outside the half-size tolerance',
      );
    });

    test('unparseable recommendation or empty stock is null', () {
      expect(
        pickStockSizeForFit(sizes: {'42': 1}, recommendedEu: 'Other'),
        isNull,
      );
      expect(pickStockSizeForFit(sizes: {}, recommendedEu: '42'), isNull);
    });
  });
}
