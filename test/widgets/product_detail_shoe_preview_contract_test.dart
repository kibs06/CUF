import 'dart:io';

import 'package:app/services/shoe_preview_channel.dart';
import 'package:app/utils/shoe_preview_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

/// The product page's **inline 3D box**, pinned at the call site.
///
/// The gate's *rule* is unit-tested in `test/utils/shoe_preview_visibility_test.dart`
/// and the box itself in `test/widgets/shoe_preview_3d_test.dart`. What neither
/// can assert is that the page is actually wired to them: the product screen
/// cannot be mounted here without a provider stack, a Supabase instance and a
/// live product row, so — the same tool `product_detail_try_on_gate_test.dart`
/// uses for the AR entry — these read the call site as source. A gate nobody
/// calls is the most common way a feature ends up "done" while the page still
/// shows the old thing.
void main() {
  final productScreen =
      File('lib/screens/customer/product_detail_screen.dart').readAsStringSync();
  final constants = File('lib/constants/app_constants.dart').readAsStringSync();
  final previewWidget = File('lib/widgets/shoe_preview_3d.dart').readAsStringSync();
  final previewChannel =
      File('lib/services/shoe_preview_channel.dart').readAsStringSync();

  /// Source with whole-line comments removed.
  ///
  /// The negative guards below are about *code* — "no route check here" — and
  /// this repo writes its reasons down, so the file goes out of its way to
  /// mention the very expression being forbidden. Asserting on the raw text would
  /// fail on the explanation rather than on the mistake.
  String codeOf(String source) => source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  /// The source between two anchors, so an assertion can be about *this* call
  /// site rather than about the file containing a string somewhere.
  String between(String source, String start, String end) {
    final from = source.indexOf(start);
    expect(from, isNonNegative, reason: '"$start" is gone — repoint this guard');
    final to = source.indexOf(end, from);
    expect(to, isNonNegative, reason: '"$end" is gone after "$start"');
    return source.substring(from, to);
  }

  group('the switch ships off and is the whole rollback', () {
    test('it is an environment switch with no default', () {
      expect(
        constants,
        contains("bool.fromEnvironment('SHOE_PREVIEW')"),
        reason: 'nobody has looked at a render on a device yet, so this must be '
            'opt-in until a device session says the framing is right',
      );
      expect(
        constants,
        isNot(contains("bool.fromEnvironment('SHOE_PREVIEW', defaultValue: true)")),
        reason: 'this one must not default on: the two-surface split and the '
            'preview camera are untested on hardware',
      );
    });

    test('off means the page keeps the entry it has always had', () {
      // With the switch off the box is not mounted and the pinned pill is — the
      // two are alternatives, not layers.
      expect(productScreen, contains('if (_shoePreview.hidden)'));
      expect(
        productScreen,
        contains('SoleARPill(onPressed: _openArTryOn)'),
        reason: 'the pinned pill is the switch-off path and must keep working',
      );
    });
  });

  group('the page is wired to the gate', () {
    test('it asks the rule, with every input the rule needs', () {
      final gate = between(productScreen, 'ShoePreviewDecision get _shoePreview', '}');

      expect(gate, contains('resolveShoePreview('));
      expect(gate, contains('enabled: AppConstants.shoePreviewEnabled'));
      expect(
        gate,
        contains('isAndroid: defaultTargetPlatform == TargetPlatform.android'),
        reason: 'iOS has no renderer at all, so the box must not be mounted there',
      );
      expect(gate, contains('hasModel: _tryOnPrefetchResult?.spec != null'));
      expect(
        gate,
        contains('hasLocalModel: _tryOnPrefetchResult?.path != null'),
        reason: '"the product has a row" is not the question — the native side is '
            'handed a local path and never does HTTP',
      );
    });

    test('the box is built from verified bytes, not from a row', () {
      final model = between(productScreen, 'TryOnModelSpec? get _shoePreviewModel', '}');

      expect(model, contains('if (spec == null || path == null) return null;'));
      expect(
        model,
        contains('TryOnModelSpec.fromModel(spec, path: path)'),
        reason: 'the payload must be the shared factory — the AR session sends '
            'the same shape to the same renderer',
      );
    });

    test('the section is mounted on the page, and renders nothing when the rule says so',
        () {
      expect(
        productScreen,
        contains('_shoePreviewSection(),'),
        reason: 'a gate nobody calls is a feature that is not built',
      );

      final helper = between(productScreen, 'Widget _shoePreviewSection()', '\n  /// Fetch inventory');
      expect(
        helper,
        contains('final decision = _shoePreview;'),
        reason: 'the condition is read once here, so the box cannot be gated by '
            'one answer and built from another',
      );
      expect(
        helper,
        contains('if (!decision.shown || model == null) {'),
        reason: 'a product with no model gets no box **and** no AR button, and '
            'no gap where they would have been',
      );
      expect(helper, contains('paused: _arTryOnOpen'));
      expect(
        helper,
        contains('_logPreviewReason(decision.reason)'),
        reason: 'the helper is the one place that knows the answer, so it is the '
            'only place that can report it',
      );
    });

    test('a failed prefetch is the one hidden state that gets words on the page', () {
      // ⚠️ Written after the first customer device report: a P30 Pro, GLES 3.2 —
      // well inside the renderer's floor — still showed pill-only. The gate's
      // hidden states were all silent, and a prefetch that failed on a phone
      // (mobile data, a cache miss, anything) was indistinguishable from a
      // product with no model. The page can show no logcat to anyone, so the
      // one recoverable hidden state says so, with a Retry.
      //
      // ⚠️ Tightened again after the SAME report came back on the hint build
      // itself: the v1.0.35 rule excluded reason `noModel` — but a prefetch that
      // fails during *resolution* computes exactly that reason, and a prefetch
      // that never completed left result null (`modelNotReady`, presumed
      // transient). Both hid a fault. The rule now keys on a measured catalogue
      // fact (`_productHasLiveModelRow`, asked from the table directly) rather
      // than on the prefetch's own outcome: with a live row, every hidden state
      // either has words or had a failure.
      final helper = between(productScreen, 'Widget _shoePreviewSection()', '\n  /// Fetch inventory');
      expect(helper, contains('TryOnPrefetchOutcome.failed'));
      expect(helper, contains('ShoePreviewHint('));
      expect(helper, contains("'Retry'"));
      expect(helper, contains('_retryShoePreview'));
      expect(
        helper,
        contains('_productHasLiveModelRow == true'),
        reason: 'the silence rule must key on the catalogue, not on prefetch luck — '
            'a resolve failure computes reason noModel and used to hide behind it',
      );
      expect(
        helper,
        contains('_previewWaitedTooLong'),
        reason: 'a prefetch that never completed (result still null) gets words too, '
            'after the grace period — modelNotReady was presumed transient and hid '
            'the never-ran case',
      );
    });

    test('the catalogue fact is asked, not inferred from the prefetch', () {
      // _productHasLiveModelRow reads the table directly (one indexed read), so
      // "this product has a model" cannot be corrupted by the very prefetch the
      // hint diagnoses. And a failed read leaves null — silence, never a wolf.
      final fact = between(productScreen, 'bool? _productHasLiveModelRow;', 'Future<void> _checkLiveModelRow');
      expect(fact, contains('bool? _productHasLiveModelRow;'));
      final check = between(productScreen, 'Future<void> _checkLiveModelRow()', '/// The prefetch, rebuilt');
      expect(check, contains(".eq('status', 'active')"));
      expect(check, contains('catch (_)'));
    });

    test('the grace-period timer exists, and is cancelled in dispose', () {
      expect(productScreen, contains('_previewWaitTimer = Timer(const Duration(seconds: 12)'));
      final dispose = between(productScreen, 'void dispose()', 'void _openFullScreenViewer');
      expect(dispose, contains('_previewWaitTimer?.cancel();'));
    });

    test('the prefetch survives a late inventory load', () {
      // The structural bug behind the same report: _prefetchTryOnModel returns
      // while no size is selected, and a payload without inventory only gets a
      // size after _fetchInventory — so the model was never fetched at all and
      // the box never appeared. The fetch must re-enter the prefetch.
      final fetch = between(productScreen, 'Future<void> _fetchInventory()', '\n  /// Fetch full variant rows');
      expect(
        fetch,
        contains('if (_selectedSize != null) _prefetchTryOnModel();'),
        reason: 'without the re-entry the prefetch is a silent no-op on any page '
            'whose sizes arrive over the network',
      );
    });

    test('and the page says which gate stopped it, in a release build too', () {
      // The box can only be *looked at* in a release build on a real phone
      // (`Filament` needs a device), and that is the one build with no debugger
      // attached. Four unrelated causes — the switch, the platform, the
      // catalogue, the prefetch — all present as an empty page, so the line is
      // the difference between a diagnosis and a guess.
      final log = between(productScreen, 'void _logPreviewReason(', '\n  }');
      expect(log, contains('debugPrint('));
      expect(
        log,
        contains("reason == ShoePreviewReason.none ? 'shown' : 'hidden'"),
        reason: 'the line must say which way it went, not merely that it ran',
      );
      expect(
        log,
        contains('reason.name'),
        reason: 'the reason *is* the message — a bare "hidden" says nothing',
      );
      expect(
        codeOf(log),
        isNot(contains('kDebugMode')),
        reason: 'guarding it with kDebugMode would print nothing in the only '
            'build where the box can be seen',
      );
    });
  });

  group('there is exactly one AR entry on the page', () {
    test('the button lives inside the section, under the box', () {
      // From the section's declaration to the end of the file: `ShoePreviewSection`
      // and the state that builds it are the last thing here, and both halves are
      // this section.
      final section = previewWidget.substring(
        previewWidget.indexOf('class ShoePreviewSection'),
      );
      expect(
        section,
        contains('SoleARPill(onPressed: widget.onTryOnInAr)'),
        reason: 'the button belongs to the section — including in the '
            'unsupported-renderer state, where it is the one entry that survives',
      );
      // The normal composition: the customer looks at the shoe first; the camera
      // is the escalation. (The unsupported fallback's pill sits earlier in the
      // source than the box — that is the branch where there IS no box — so the
      // order is pinned against the last occurrences, which are the normal path.)
      expect(
        section.lastIndexOf('ShoePreview3D('),
        lessThan(section.lastIndexOf('SoleARPill(')),
        reason: 'the customer looks at the shoe first; the camera is the escalation',
      );
      // And the unsupported state keeps the pill — the owner's decision after a
      // real phone showed the whole section (button included) vanishing on
      // return from AR, leaving no AR entry anywhere. The AR screen degrades to
      // its simulated mode on such a phone, so the entry stays honestly usable.
      final unsupported = between(section, 'if (_unsupported)', 'return Column');
      expect(
        unsupported,
        contains("'3D preview isn\\'t supported on this phone.'"),
      );
      expect(unsupported, contains('SoleARPill('));
    });

    test('and the page mounts it only when the box is not there', () {
      // Two live "Try On in AR" buttons on one screen is a bug rather than a
      // choice, so the pill is inside the complement of the box's condition.
      final pill = between(productScreen, 'if (_shoePreview.hidden)', 'SoleARPill(');
      expect(
        pill,
        isNot(contains('_shoePreviewSection')),
        reason: 'the pill must be gated on the box being absent, not on the flag',
      );

      expect(
        'SoleARPill('.allMatches(productScreen).length,
        1,
        reason: 'a second pill would be a second, ungated AR entry',
      );
    });
  });

  group('the box stops while the AR screen is on top', () {
    test('the page pauses it around the push, not from inside the widget', () {
      final open = between(productScreen, 'Future<void> _openArTryOn()', '\n  }');

      final paused = open.indexOf('_arTryOnOpen = true');
      final pushed = open.indexOf('Navigator.of(context).push');
      final resumed = open.indexOf('_arTryOnOpen = false');

      expect(paused, isNonNegative);
      expect(pushed, greaterThan(paused), reason: 'the engine must be gone before AR starts');
      expect(resumed, greaterThan(pushed), reason: 'and back when the screen pops');

      // ⚠️ Why the flag exists rather than a route check: a push does not rebuild
      // the route underneath it, so `ModalRoute.isCurrent` inside the widget would
      // silently never fire and the box would render under the whole AR session.
      expect(
        codeOf(previewWidget),
        isNot(contains('ModalRoute.of(context)')),
        reason: 'that check does not fire on a plain push — see the class header',
      );
    });
  });

  group('the channel is the one the native side registers', () {
    test('three names, and they match ArTryOnPlugin.kt', () {
      final plugin = File(
        'android/app/src/main/kotlin/com/solevision/app/tryon/ArTryOnPlugin.kt',
      ).readAsStringSync();

      // Quoted for each side: Dart writes `'…'`, Kotlin writes `"…"`, and a
      // drifted name produces the same symptom as a plugin that was never built.
      for (final name in <String>[
        'com.solevision/shoe_preview',
        'com.solevision/shoe_preview/events',
        'com.solevision/shoe_preview/view',
      ]) {
        expect(
          previewChannel,
          contains("'$name'"),
          reason: 'the Dart twin of $name is gone',
        );
        expect(
          plugin,
          contains('"$name"'),
          reason: '$name must be registered natively with this exact string',
        );
      }

      expect(plugin, contains('ArTryOnView.Mode.PREVIEW'));
      expect(
        plugin,
        contains('setPreviewModel'),
        reason: 'the handover method the Dart side calls',
      );
    });

    test('the reason a renderer cannot draw is spelled the same on both sides', () {
      // ⚠️ This one is a crash guard, not tidiness. The native side refuses to load
      // a glTF below FEATURE_LEVEL_2 because doing it aborted the process on the
      // emulator (SIGSEGV in libfilament-jni.so, 2026-09-29). If the Dart side did
      // not know the reason, the section would stay on screen and the next handover
      // would try again — which is the crash.
      final view = File(
        'android/app/src/main/kotlin/com/solevision/app/tryon/ArTryOnView.kt',
      ).readAsStringSync();

      expect(
        view,
        contains('REASON_RENDERER_UNSUPPORTED = "$kRendererUnsupportedReason"'),
        reason: 'the Dart reason and the native one must be the same string',
      );
      expect(
        codeOf(view),
        contains('if (!modelLoadingSupported)'),
        reason: 'without the refusal the loader is called on a renderer that aborts',
      );

      // The refusal has to come *before* the parse, not after it: `createAsset` is
      // what dies, so a guard that runs later guards nothing.
      final code = codeOf(view);
      expect(
        code.indexOf('if (!modelLoadingSupported)'),
        lessThan(code.indexOf('loader.createAsset(')),
        reason: 'the feature-level check must precede the asset load',
      );
      expect(
        code,
        contains('Engine.FeatureLevel.FEATURE_LEVEL_2'),
        reason: 'level 1 is the measured threshold, and the log must name it',
      );

      // And the section acts on it.
      expect(codeOf(previewWidget), contains('kRendererUnsupportedReason'));
    });

    test('the preview view is Android-only, and its failure is silent', () {
      expect(previewWidget, contains('kShoePreviewViewType'));
      expect(previewWidget, contains('TargetPlatform.android'));
      expect(
        previewChannel,
        contains('on MissingPluginException'),
        reason: 'a build with no plugin is the expected answer, not a page error',
      );
    });
  });

  group('the rule itself still matches what the page assumes', () {
    test('a product with no model shows neither half', () {
      final decision = resolveShoePreview(
        enabled: true,
        isAndroid: true,
        hasModel: false,
        hasLocalModel: false,
      );
      expect(decision.shown, isFalse);
      expect(decision.reason, ShoePreviewReason.noModel);
    });
  });
}
