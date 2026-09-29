import 'package:app/utils/shoe_preview_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

/// The inline 3D box's gate, as a table.
///
/// It is a pure rule for the reason `try_on_mode.dart` is: a page that shows a 3D
/// box for a product with nothing to render is a bug nobody can see from the code
/// that decides it, and this is the only place the decision is written down.
void main() {
  ShoePreviewDecision resolve({
    bool enabled = true,
    bool isAndroid = true,
    bool hasModel = true,
    bool hasLocalModel = true,
  }) =>
      resolveShoePreview(
        enabled: enabled,
        isAndroid: isAndroid,
        hasModel: hasModel,
        hasLocalModel: hasLocalModel,
      );

  group('the box is shown only for a model this device can actually draw', () {
    test('all four questions answered yes is the only way to a box', () {
      expect(resolve().shown, isTrue);
      expect(resolve().reason, ShoePreviewReason.none);
    });

    test('each question alone is enough to withhold it', () {
      expect(resolve(enabled: false).shown, isFalse);
      expect(resolve(isAndroid: false).shown, isFalse);
      expect(resolve(hasModel: false).shown, isFalse);
      expect(resolve(hasLocalModel: false).shown, isFalse);
    });
  });

  group('the reason reported is the first thing that stopped it', () {
    test('the build switch is asked first, because nothing else was read', () {
      // With the switch off no model is resolved, no channel call is made and the
      // page still renders the pinned pill — so "the device cannot show it" would
      // be a misleading sentence about a build that deliberately did nothing.
      final decision = resolve(
        enabled: false,
        isAndroid: false,
        hasModel: false,
        hasLocalModel: false,
      );
      expect(decision.reason, ShoePreviewReason.featureOff);
    });

    test('then the platform, before the catalogue', () {
      final decision = resolve(
        isAndroid: false,
        hasModel: false,
        hasLocalModel: false,
      );
      expect(decision.reason, ShoePreviewReason.notAndroid);
    });

    test('then the live model, before its bytes', () {
      // The two are different facts: most of the catalogue is `noModel` and that
      // is permanent until somebody models the shoe, while `modelNotReady` is a
      // download in flight. Reporting the wrong one sends the reader to the wrong
      // problem.
      final decision = resolve(hasModel: false, hasLocalModel: false);
      expect(decision.reason, ShoePreviewReason.noModel);

      expect(resolve(hasLocalModel: false).reason, ShoePreviewReason.modelNotReady);
    });
  });

  group('the decision is a value', () {
    test('two answers with the same shape are equal, and say what they are', () {
      expect(resolve(), ShoePreviewDecision.shownBox);
      expect(resolve(hasModel: false), resolve(hasModel: false));
      expect(resolve(hasModel: false), isNot(resolve(hasLocalModel: false)));
      expect(
        resolve(hasModel: false).toString(),
        'ShoePreviewDecision(false, noModel)',
      );
    });

    test('a hidden decision reports itself as hidden', () {
      expect(resolve(enabled: false).hidden, isTrue);
      expect(resolve().hidden, isFalse);
    });
  });
}
