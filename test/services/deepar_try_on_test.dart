import 'package:app/services/deepar_try_on.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deepArEffectForProduct', () {
    test('blank product id has no effect', () {
      expect(deepArEffectForProduct('  '), isNull);
    });

    test('returns Luna effect for known product', () {
      expect(
        deepArEffectForProduct(
          '0aebaa64-4d9e-44f8-8876-6b3ee9855fae',
        ),
        'assets/effects/luna_loafers.deepar',
      );
      expect(
        deepArEffectForProduct('luna-loafers'),
        'assets/effects/luna_loafers.deepar',
      );
    });

    test('Luxe resolves by row id, slug, and product name', () {
      expect(
        deepArEffectForProduct('77b8c0a3-0f09-41a6-aa70-fc1db04e4cc1'),
        'assets/effects/luxe_cross_strap_sandals.deepar',
      );
      expect(
        deepArEffectForProduct('luxe-cross-strap-sandals'),
        'assets/effects/luxe_cross_strap_sandals.deepar',
      );
      expect(
        deepArEffectForProduct(
          'some-uuid-nobody-recorded',
          productName: 'Luxe Cross-Strap Sandals',
        ),
        'assets/effects/luxe_cross_strap_sandals.deepar',
      );
    });

    test('JBC resolves by slug and product name', () {
      expect(
        deepArEffectForProduct('jbc-crown-leather-sandals'),
        'assets/effects/jbc_crown_leather_sandals.deepar',
      );
      expect(
        deepArEffectForProduct(
          'some-uuid-nobody-recorded',
          productName: 'JBC Crown Leather Sandals',
        ),
        'assets/effects/jbc_crown_leather_sandals.deepar',
      );
    });

    test('unknown product has no effect yet', () {
      expect(deepArEffectForProduct('abc123'), isNull);
    });

    test('respects published allow-list', () {
      const luna = '0aebaa64-4d9e-44f8-8876-6b3ee9855fae';
      expect(
        deepArEffectForProduct(luna, published: {luna}),
        isNotNull,
      );
      expect(
        deepArEffectForProduct(luna, published: {'other'}),
        isNull,
      );
    });
  });

  group('deepArUnavailableMessage', () {
    test('unconfigured build names setup', () {
      expect(
        deepArUnavailableMessage(configured: false),
        contains('not set up'),
      );
    });

    test('configured build without effect names product', () {
      expect(
        deepArUnavailableMessage(configured: true),
        contains('No DeepAR shoe effect'),
      );
    });
  });

  test('deepArConfigured is false without dart-defines', () {
    // No --dart-define passed under flutter test, so both keys are empty.
    expect(deepArConfigured, isFalse);
  });
}
