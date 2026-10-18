import 'package:app/utils/shoe_fit_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shoeFitViewFor', () {
    test('orients the shoe to the captured yaw and looks down its top', () {
      final fit = shoeFitViewFor(
        yawDeg: 30,
        lengthMm: 260,
        authoredLengthMm: 260,
      );

      expect(fit, isNotNull);
      expect(fit!.orientation, '0deg 0deg 30.000deg');
      // theta = yaw + 180, wrapped into [-180, 180): 210 becomes -150.
      expect(fit.cameraOrbit, '-150.000deg $kShoeFitTopOrbitPhi $kShoeFitOrbitRadius');
    });

    test('scales the shoe to the measured foot length', () {
      final fit = shoeFitViewFor(
        yawDeg: 0,
        lengthMm: 260,
        authoredLengthMm: 300,
      );

      expect(fit!.scale, '0.8667 0.8667 0.8667');
    });

    test('wraps a yaw past 180 degrees into the same direction', () {
      final fit = shoeFitViewFor(
        yawDeg: 200,
        lengthMm: 260,
        authoredLengthMm: 260,
      );

      expect(fit!.orientation, '0deg 0deg -160.000deg');
      // theta = 380 wraps to 20.
      expect(fit.cameraOrbit, startsWith('20.000deg '));
    });

    test('leaves the size unset when no authored length is known', () {
      final fit = shoeFitViewFor(
        yawDeg: -12,
        lengthMm: 260,
        authoredLengthMm: null,
      );

      expect(fit, isNotNull);
      expect(fit!.scale, isNull);
      expect(fit.orientation, '0deg 0deg -12.000deg');
    });

    test('refuses a pose it cannot use', () {
      expect(
        shoeFitViewFor(yawDeg: double.nan, lengthMm: 260, authoredLengthMm: 260),
        isNull,
      );
      expect(
        shoeFitViewFor(yawDeg: 0, lengthMm: 0, authoredLengthMm: 260),
        isNull,
      );
      expect(
        shoeFitViewFor(yawDeg: 0, lengthMm: -5, authoredLengthMm: 260),
        isNull,
      );
    });
  });
}
