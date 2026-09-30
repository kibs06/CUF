import 'package:app/providers/try_on/try_on_mode.dart';
import 'package:flutter_test/flutter_test.dart';

/// The capability gate decides what a customer sees when they tap "Try on".
/// Two inputs, four combinations, one rule — and one rule for every way ARCore
/// can refuse a session, including the codes a future native build may invent.
///
/// The property that matters most here is [TryOnMode.simulated] being a
/// *result*: every combination below either renders for real or falls back with
/// a stated reason, and none of them is an error (decision D8).
void main() {
  group('resolveTryOnDecision: the whole table', () {
    final cases = <({
      bool ar,
      bool model,
      TryOnMode mode,
      TryOnDegradeReason reason,
    })>[
      (
        ar: true,
        model: true,
        mode: TryOnMode.real,
        reason: TryOnDegradeReason.none,
      ),
      (
        ar: true,
        model: false,
        mode: TryOnMode.simulated,
        reason: TryOnDegradeReason.modelMissing,
      ),
      (
        ar: false,
        model: true,
        mode: TryOnMode.simulated,
        reason: TryOnDegradeReason.arFailed,
      ),
      (
        ar: false,
        model: false,
        mode: TryOnMode.simulated,
        reason: TryOnDegradeReason.modelMissing,
      ),
    ];

    for (final c in cases) {
      test('ar=${c.ar} model=${c.model} → ${c.mode.name}/${c.reason.name}', () {
        final decision =
            resolveTryOnDecision(arSupported: c.ar, modelAvailable: c.model);

        expect(decision.mode, c.mode);
        expect(decision.reason, c.reason);
        expect(decision.isReal, c.mode == TryOnMode.real);
        expect(decision.isSimulated, c.mode == TryOnMode.simulated);
      });
    }

    test('only one combination renders for real', () {
      final real = <String>[];
      for (final ar in [true, false]) {
        for (final model in [true, false]) {
          if (resolveTryOnDecision(arSupported: ar, modelAvailable: model)
              .isReal) {
            real.add('ar=$ar model=$model');
          }
        }
      }

      expect(real, ['ar=true model=true'],
          reason: 'a device that can render with nothing to render, or a model '
              'with a device that cannot render it, are both the placeholder');
    });

    test('a missing model is reported before an unsupported device', () {
      // Both inputs false: the reason is the one the catalogue can fix, because
      // "this pair has no 3D model yet" is a support answer and "your phone
      // cannot do AR" is not.
      expect(
        resolveTryOnDecision(arSupported: false, modelAvailable: false).reason,
        TryOnDegradeReason.modelMissing,
      );
    });
  });

  group('resolveTryOnMode is the same rule', () {
    test('the published signature agrees with the decision form', () {
      for (final ar in [true, false]) {
        for (final model in [true, false]) {
          expect(
            resolveTryOnMode(arSupported: ar, modelAvailable: model),
            resolveTryOnDecision(arSupported: ar, modelAvailable: model).mode,
            reason: 'ar=$ar model=$model',
          );
        }
      }
    });
  });

  group('tryOnModelAvailable: the availability half', () {
    test('the switch is ANDed with the cache, never ORed', () {
      expect(tryOnModelAvailable(enabled: true, hasLocalModel: true), isTrue);
      expect(tryOnModelAvailable(enabled: true, hasLocalModel: false), isFalse);
      expect(tryOnModelAvailable(enabled: false, hasLocalModel: true), isFalse);
      expect(tryOnModelAvailable(enabled: false, hasLocalModel: false), isFalse);
    });
  });

  group('tryOnDegradeReasonForArFailure', () {
    test('maps the vocabulary the shipped scan already uses', () {
      expect(tryOnDegradeReasonForArFailure('unsupported_device'),
          TryOnDegradeReason.arUnsupported);
      expect(tryOnDegradeReasonForArFailure('unsupported'),
          TryOnDegradeReason.arUnsupported);
      expect(tryOnDegradeReasonForArFailure('needs_install'),
          TryOnDegradeReason.arNeedsInstall);
      expect(tryOnDegradeReasonForArFailure('user_opted_out'),
          TryOnDegradeReason.arOptedOut);
      expect(tryOnDegradeReasonForArFailure('timeout'),
          TryOnDegradeReason.arFailed);
      expect(tryOnDegradeReasonForArFailure('error'),
          TryOnDegradeReason.arFailed);
    });

    test('the renderer refusal below FEATURE_LEVEL_2 gets its own reason', () {
      // Measured on a real P30 Pro, 2026-09-30: the phone is GLES 3.2 on paper,
      // yet Filament's context lands below the floor — and the sentence the
      // simulated screen needs for that is not "AR failed" but "this phone
      // cannot render the shoe at all". The literal is pinned to
      // `kRendererUnsupportedReason` by the shoe-preview contract test, which
      // reads both files.
      expect(tryOnDegradeReasonForArFailure('renderer_feature_level_unsupported'),
          TryOnDegradeReason.rendererUnsupported);
    });

    test('a code from a future native build is a fallback, not a crash', () {
      for (final Object? code in <Object?>[
        null,
        '',
        'something_new',
        'UNSUPPORTED_DEVICE',
      ]) {
        expect(
          tryOnDegradeReasonForArFailure(code as String?),
          TryOnDegradeReason.arFailed,
          reason: 'code: $code',
        );
      }
    });
  });

  group('TryOnDecision is a value', () {
    test('equal when both halves match', () {
      expect(
        resolveTryOnDecision(arSupported: true, modelAvailable: true),
        equals(resolveTryOnDecision(arSupported: true, modelAvailable: true)),
      );
      expect(
        resolveTryOnDecision(arSupported: true, modelAvailable: true),
        isNot(equals(
          resolveTryOnDecision(arSupported: true, modelAvailable: false),
        )),
      );
      expect(
        resolveTryOnDecision(arSupported: true, modelAvailable: true).hashCode,
        resolveTryOnDecision(arSupported: true, modelAvailable: true).hashCode,
      );
      expect(TryOnDecision.real.toString(), 'TryOnDecision(real, none)');
    });
  });
}
