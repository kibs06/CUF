import 'dart:io';

import 'package:app/screens/customer/ar_fitting_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3.9's wiring, pinned.
///
/// The gate's *rule* is unit-tested in `test/providers/try_on_mode_test.dart`.
/// What cannot be asserted there is that the product page is actually plugged
/// into it — a gate nobody calls is the most common way a feature flag ends up
/// "done" while the surface still shows the old thing. Two of these tests read
/// the call site as source (the same tool this repo used for the fit card's
/// mount guard), because the product screen cannot be mounted here without a
/// provider stack, a Supabase instance and a live product row; the third is a
/// real widget assertion where one is possible.
void main() {
  final productScreen = File(
    'lib/screens/customer/product_detail_screen.dart',
  ).readAsStringSync();

  final constants = File('lib/constants/app_constants.dart').readAsStringSync();

  group('the V3 switch ships off', () {
    test('it is an environment switch with no default', () {
      expect(
        constants,
        contains("bool.fromEnvironment('TRY_ON_V3')"),
        reason: 'the renderer route and the device numbers are both unsettled, '
            'so this switch must be opt-in',
      );
      expect(
        constants,
        isNot(contains("bool.fromEnvironment('TRY_ON_V3', defaultValue: true)")),
        reason: 'V3 is the one switch in this file that must not default on — '
            'V0.7 has not chosen the renderer and there is no model to render',
      );
    });
  });

  group('the product page is wired to the gate', () {
    test('the availability half is the prefetch\'s verified local file', () {
      // V3.5 ORed the QA seam in front of the real check, so the assertion is
      // about the *shape* being preserved: the seam may only ever add
      // availability, and the answer a real build uses is still the prefetch's
      // verified local file.
      expect(
        productScreen,
        contains('AppConstants.tryOnPlaceholderModelEnabled ||'),
        reason: 'the bundled block-out is the only way the path is reachable '
            'while product_models has no rows',
      );
      expect(productScreen, contains('tryOnModelAvailable('));
      expect(productScreen, contains('enabled: AppConstants.tryOnV3Enabled'));
      expect(
        productScreen,
        contains('hasLocalModel: _tryOnPrefetchResult?.hasLocalModel ?? false'),
        reason: '"the product has a row" is not the question — the native side '
            'is handed a local path and never does HTTP',
      );
    });

    test('the prefetch result is kept, not discarded', () {
      expect(
        productScreen,
        contains('.then(_recordTryOnAvailability)'),
        reason: 'a fire-and-forget prefetch has nowhere to leave the answer '
            'the try-on entry needs',
      );
    });

    test('the try-on entry hands the answer to the screen', () {
      expect(productScreen, contains('modelAvailable: _tryOnModelAvailable'));
      expect(
        productScreen,
        isNot(contains('ARVirtualFitScreen(preselectedProduct: widget.product)')),
        reason: 'the single-line call site would drop the gate on the floor',
      );
    });
  });

  group('the screen carries the answer', () {
    test('it defaults to the simulated feed', () {
      // Every other entry point (home, store, collection) passes nothing, so the
      // default is what keeps them on today's placeholder — D8's fallback.
      const screen = ARVirtualFitScreen();

      expect(screen.modelAvailable, isFalse);
    });

    test('it carries what the gate decided', () {
      const screen = ARVirtualFitScreen(modelAvailable: true);

      expect(screen.modelAvailable, isTrue);
    });
  });
}
