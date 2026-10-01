import 'dart:io';

import 'package:app/services/shoe_preview_channel.dart';
import 'package:app/utils/shoe_preview_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

/// The product page's **3D entry**, pinned at the call site.
///
/// The gate's *rule* is unit-tested in `test/utils/shoe_preview_visibility_test.dart`
/// and the box itself in `test/widgets/shoe_preview_3d_test.dart`. What neither
/// can assert is that the page is actually wired to them: the product screen
/// cannot be mounted here without a provider stack, a Supabase instance and a
/// live product row, so — the same tool `product_detail_try_on_gate_test.dart`
/// uses for the AR entry — these read the call site as source. A gate nobody
/// calls is the most common way a feature ends up "done" while the page still
/// shows the old thing.
///
/// ⚠️ **Repointed on 2026-10-01, when the entry moved onto the photograph.** The
/// pinned "Try On in AR" pill came off the page and the inline box left the
/// scroll: the page's only 3D entry is now the icon in the hero's lower-right
/// corner (`Sole3DIconButton`), which opens the full-screen viewer
/// (`lib/screens/shared/shoe_preview_screen.dart`). The box, the refusal
/// handling and the AR escalation are all still `ShoePreviewSection` — which is
/// why the sections below that assert *its* internals are unchanged, while the
/// ones that assert where it is mounted moved to the viewer's file.
void main() {
  final productScreen =
      File('lib/screens/customer/product_detail_screen.dart').readAsStringSync();
  final constants = File('lib/constants/app_constants.dart').readAsStringSync();
  final previewWidget = File('lib/widgets/shoe_preview_3d.dart').readAsStringSync();
  final previewChannel =
      File('lib/services/shoe_preview_channel.dart').readAsStringSync();
  // The viewer lives in `screens/shared/` since 2026-10-01: the product photo's
  // icon opens it, and so does the seller's "3D fitting ready" row.
  final previewScreen =
      File('lib/screens/shared/shoe_preview_screen.dart').readAsStringSync();

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

    test('off means the page shows no 3D icon at all', () {
      // With the switch off the gate says hidden, so the icon on the photograph
      // is not built — and the page has no AR pill of its own any more (it came
      // off on 2026-10-01), so there is no second entry left to fall back on.
      expect(productScreen, contains('if (_showPreviewIcon)'));
      expect(
        productScreen,
        contains('Sole3DIconButton(onPressed: _openShoePreview)'),
        reason: 'the icon is the entry the switch gates; without it the page has '
            'no 3D surface at all, which is the honest answer for a build where '
            'nobody has seen a render on hardware',
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

    test('the icon is gated on the model as well as the rule', () {
      final icon = between(productScreen, 'bool get _showPreviewIcon', ';');

      expect(icon, contains('_shoePreview.shown'));
      expect(
        icon,
        contains('_shoePreviewModel != null'),
        reason: 'the rule answers the build switch, the platform and the '
            'catalogue — but the icon opens a viewer, and a viewer with no bytes '
            'on disk can only apologise',
      );
    });

    test('the icon opens the viewer, with the model and the page\'s own row', () {
      final open = between(productScreen, 'Future<void> _openShoePreview()', '\n  }');

      expect(open, contains('ShoePreviewScreen('));
      expect(open, contains('model: model'));
      expect(
        open,
        contains('product: widget.product'),
        reason: 'the AR escalation inside the viewer needs the whole row, the same '
            'way the page used to hand it over',
      );
      expect(open, contains('modelAvailable: _tryOnModelAvailable'));
      expect(
        open,
        contains('if (model == null) return;'),
        reason: 'the viewer cannot be opened without bytes to draw',
      );
    });

    test('the viewer is the thing that mounts the section', () {
      expect(
        productScreen,
        contains('_shoePreviewNotice(),'),
        reason: 'a gate nobody calls is a feature that is not built — the notice '
            'is what is left on the page',
      );
      expect(previewScreen, contains('ShoePreviewSection('));
      expect(previewScreen, contains('height: boxHeight'));
      // The customer door hands the resolved model over. The *other* door
      // (`forProduct`) is the seller's, and it is the one that resolves.
      expect(previewScreen, contains('ShoePreviewScreen.forProduct({'));
      expect(
        productScreen,
        isNot(contains('ShoePreviewScreen.forProduct(')),
        reason: 'the page always has the model in hand — its own prefetch ran '
            'while the customer was reading, and a viewer that re-resolved would '
            'be a second read for an answer already on screen',
      );
    });

    test('the notice renders nothing when the rule says so', () {
      final helper = between(productScreen, 'Widget _shoePreviewNotice()', '\n  /// Fetch inventory');
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
      expect(
        previewScreen,
        contains('paused: _arTryOnOpen'),
        reason: 'the box belongs to the viewer now, so the viewer is what stops '
            'it while AR is on top',
      );
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
      final helper = between(productScreen, 'Widget _shoePreviewNotice()', '\n  /// Fetch inventory');
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
      //
      // The branch grew a second condition on 2026-09-30 — it also answers the QA
      // build's non-refusal failure (`_diagnosticDetail`, behind
      // `SHOE_PREVIEW_DIAGNOSTICS`) — so this window is repointed to the whole
      // branch. Both states keep the pill; what a customer build sees is still the
      // one honest sentence, which the assertion below is about.
      final unsupported =
          between(section, 'if (_unsupported || _diagnosticDetail != null)', 'return Column');
      expect(
        unsupported,
        contains("'3D preview isn\\'t supported on this phone.'"),
      );
      expect(unsupported, contains('SoleARPill('));
    });

    test('the page itself mounts none of them — the icon is the only entry', () {
      // The pinned pill came off the page on 2026-10-01. AR is now one tap
      // deeper, inside the viewer, which is the escalation the section has
      // always carried rather than a second, competing button on the page.
      expect(
        productScreen,
        isNot(contains('SoleARPill(')),
        reason: 'the page is the 3D icon plus the recovery notice, nothing else',
      );
      expect(
        'Sole3DIconButton('.allMatches(productScreen).length,
        1,
        reason: 'two icon buttons would be two entries into the same viewer',
      );
      // And the viewer gets exactly one, from the section rather than of its own.
      expect(previewScreen, isNot(contains('SoleARPill(')));
      expect(previewScreen, contains('onTryOnInAr: _openArTryOn'));
    });
  });

  group('the box stops while the AR screen is on top', () {
    test('the viewer pauses it around the push, not from inside the widget', () {
      // The push moved from the page to the viewer with the button: the box is
      // mounted by the pushed route now, so the route that owns both the box and
      // the AR push is the viewer.
      final open = between(previewScreen, 'Future<void> _openArTryOn()', '\n  }');

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
      expect(
        plugin,
        contains('"setPreviewDiagnostics"'),
        reason: 'the QA readout seam the Dart side calls — SHOE_PREVIEW_DIAGNOSTICS '
            'is a Dart define, so the native side cannot read it and this call is '
            'the switch\'s other half',
      );
      expect(
        previewChannel,
        contains("'setPreviewDiagnostics'"),
        reason: 'the Dart half of the same call',
      );
    });

    test('the QA self-report reaches the page, not a log nobody can read', () {
      // ⚠️ Written on the day the first real-device render arrived (2026-10-01). That
      // phone has locked developer options, so `adb logcat` will never be read from
      // it — and the two faults the run produced (a box that stops presenting while
      // its frame loop keeps running, and a crash on the *second* open of the same
      // box) both destroy their own evidence. Hence four guards, each one a fact the
      // screenshot has to be able to carry: the heartbeat exists, Dart parses it, the
      // last line survives a crash, and a failing frame reports instead of killing
      // the process.
      final view = File(
        'android/app/src/main/kotlin/com/solevision/app/tryon/ArTryOnView.kt',
      ).readAsStringSync();

      expect(
        view,
        contains('listener.onEvent("status"'),
        reason: 'the heartbeat type, spelled natively the way Dart parses it',
      );
      expect(
        codeOf(previewWidget),
        contains("type == 'status'"),
        reason: 'and the Dart side has to actually handle it — an event nobody '
            'reads is the same silent log this seam exists to replace',
      );
      expect(
        view,
        contains('STATUS_FILE_NAME'),
        reason: 'the heartbeat goes to a file too, or it dies with the process it '
            'was describing and explains nothing',
      );
      expect(
        view,
        contains('preview_frame_failed'),
        reason: 'an exception in the frame callback is process death on Android: it '
            'has to be caught and reported',
      );
      expect(
        view,
        contains('pendingTeardown'),
        reason: 'the second-open crash is a teardown racing the next create, and the '
            'fix is the ordering this latch holds',
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

  group('the QA seams are opt-in, and the risky one is locked twice', () {
    // `SHOE_PREVIEW_DIAGNOSTICS` and `SHOE_PREVIEW_ALLOW_LEVEL1` exist for one
    // question: whether the renderer refusal can be avoided on a real phone. One
    // prints the measured facts on the page (the P30 Pro's developer options are
    // locked, so no logcat will ever be read from it); the other lets the load the
    // guard forbids actually happen — which is why it carries two locks.
    final view = File(
      'android/app/src/main/kotlin/com/solevision/app/tryon/ArTryOnView.kt',
    ).readAsStringSync();

    test('all three are environment switches, and none defaults on', () {
      for (final name in <String>[
        'SHOE_PREVIEW_DIAGNOSTICS',
        'SHOE_PREVIEW_ALLOW_LEVEL1',
        'SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1',
      ]) {
        expect(constants, contains("bool.fromEnvironment('$name')"));
        expect(
          constants,
          isNot(contains("bool.fromEnvironment('$name', defaultValue: true)")),
          reason: '$name must ship off: one is not customer copy, one is a load '
              'that can abort the process, and one lowers the renderer on purpose',
        );
      }
    });

    test('the definition file every release copies lists all three off', () {
      final defines = File('dart_defines.json.example').readAsStringSync();
      expect(defines, contains('"SHOE_PREVIEW_DIAGNOSTICS": false'));
      expect(defines, contains('"SHOE_PREVIEW_ALLOW_LEVEL1": false'));
      expect(defines, contains('"SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1": false'));
    });

    test('the override rides on the preview handover, and only there', () {
      final handover = between(
        previewChannel,
        'Future<void> setModel(TryOnModelSpec spec)',
        ';',
      );
      expect(handover, contains("'setPreviewModel'"));
      expect(
        handover,
        contains("'allowUnsupportedRenderer': AppConstants.shoePreviewAllowLevel1"),
        reason: 'the switch has to reach the native side on the handover, or the '
            'guard it relaxes never hears about it',
      );
      expect(
        handover,
        contains("'lowerEngineToLevel1': AppConstants.shoePreviewLowerEngineToLevel1"),
        reason: 'the engine-level switch travels on the same handover — the '
            'renderer has to be told before it is built, and the handover is the '
            'only thing that arrives before it',
      );
      expect(
        File('lib/services/ar_try_on_channel.dart').readAsStringSync(),
        isNot(contains('allowUnsupportedRenderer')),
        reason: 'the AR session sends the same payload shape and must not be able '
            'to ask a crashing load into existence',
      );
      expect(
        File('lib/services/ar_try_on_channel.dart').readAsStringSync(),
        isNot(contains('lowerEngineToLevel1')),
        reason: 'and it must not be able to ask for a permanently worse renderer '
            'either',
      );
      expect(
        previewWidget,
        contains('showDiagnostics = AppConstants.shoePreviewDiagnosticsEnabled'),
        reason: 'the readout is gated by the switch rather than by the mere fact '
            'that something failed',
      );
    });

    test('the native refusal keeps its guard, and the override is debuggable-only',
        () {
      // The guard *and* the override on one condition: the crash F22 measured is
      // skipped by asking, never by accident.
      // The first `if (!modelLoadingSupported)` in the file is the log-only block
      // in `createEngineIfNeeded`; the *guard* is the line that also consults the
      // override, so it is found by the override rather than by the guard.
      // Found by the *call site's* argument — `pendingModel`, because the guard runs
      // before the payload is parsed out of the park — rather than by the function
      // name, which the declaration line would match first.
      final guardLine = codeOf(view)
          .split('\n')
          .firstWhere((line) => line.contains('allowsUnsupportedRenderer(pendingModel)'));
      expect(guardLine, contains('if (!modelLoadingSupported &&'));

      // The window starts at the function, so the KDoc above it (which names these
      // very expressions) cannot satisfy the assertion.
      final override = between(
        codeOf(view),
        'private fun allowsUnsupportedRenderer(',
        '/**',
      );
      expect(override, contains('spec?.allowUnsupportedRenderer != true'));
      expect(
        override,
        contains('debuggableBuild()'),
        reason: 'lock 2: a published release APK is not debuggable, so a customer '
            'build ignores the request even if the define leaks into one. The '
            'check itself is spelled once and asserted in the engine-level test '
            'below, so the two switches cannot drift apart',
      );

      // And the refusal carries the numbers, which is the half the phone can show.
      final refusal = between(
        codeOf(view),
        'REASON_RENDERER_UNSUPPORTED',
        'return',
      );
      expect(
        refusal,
        contains('\$rendererDiagnostic'),
        reason: 'a refusal with no measured facts is a bug report the page cannot '
            'answer',
      );
      expect(codeOf(view), contains('describeRenderer(created)'));
    });

    test('the engine-level switch is locked twice, and it only ever lowers', () {
      // Lock 1 — the caller asks, and only the preview's handover can.
      final lock = between(
        codeOf(view),
        'private fun shouldLowerEngineToLevel1(',
        '/**',
      );
      expect(lock, contains('spec?.lowerEngineToLevel1 != true'));
      expect(
        lock,
        contains('debuggableBuild()'),
        reason: 'lock 2: the same check the load override uses — a lowered '
            'renderer on a shopper\'s phone is not a crash, it is a worse product',
      );

      // ...and the check itself is written once, so the two locks cannot drift
      // apart. (The override test above asserts its own lock 1; this asserts the
      // half both switches share.)
      final debuggable = between(codeOf(view), 'private fun debuggableBuild(', '/**');
      expect(debuggable, contains('ApplicationInfo.FLAG_DEBUGGABLE'));

      // Both application points, because the engine may or may not exist when the
      // handover arrives: the model usually precedes the surface, and so the
      // engine — but not always, and a switch that silently does nothing half the
      // time would read as a failed experiment rather than as a race.
      expect(
        codeOf(view),
        contains('engineBuilder.featureLevel(Engine.FeatureLevel.FEATURE_LEVEL_1)'),
        reason: 'the builder is the only route that exists before the first frame',
      );
      final runtime = between(
        codeOf(view),
        'private fun applyEngineLevelRequest(',
        '/**',
      );
      expect(
        runtime,
        contains('setActiveFeatureLevel(Engine.FeatureLevel.FEATURE_LEVEL_1)'),
      );
      expect(
        runtime,
        contains('rendererDiagnostic = describeRenderer(created)'),
        reason: 'a lowered engine that still reports the level it started at is a '
            'screenshot nobody can trust',
      );

      // Applied *before* the load the guard would refuse, or the run would measure
      // a level-2 engine and look like the experiment had failed.
      final handover = between(codeOf(view), 'fun setModel(spec: ModelSpec)', '}');
      expect(
        handover.indexOf('applyEngineLevelRequest(spec)'),
        lessThan(handover.indexOf('applyPendingModel()')),
      );

      // And the page says which build produced it: either switch draws the banner,
      // and the engine one names itself in the readout as well.
      final qaBuild = between(previewWidget, 'bool get _qaBuild', ';');
      expect(qaBuild, contains('AppConstants.shoePreviewAllowLevel1'));
      expect(qaBuild, contains('AppConstants.shoePreviewLowerEngineToLevel1'));
      expect(previewWidget, contains("'QA · engine pinned to level 1'"));
    });

    test('the engine asks for the level the material path needs', () {
      // ⚠️ Measured on hardware, 2026-10-01, and it is the reason this feature had
      // never rendered anywhere: Filament's `BuilderDetails::mFeatureLevel` defaults
      // to `FEATURE_LEVEL_1` (`filament/src/details/Engine.cpp`, v1.72.1) and
      // `FEngine::init` then takes `std::min(requested, driver)` — the level can be
      // clamped *down* and never raised. Nothing in this app ever asked for 2, so
      // the engine came up at level 1 on a GLES 3.2 phone whose driver reported 2
      // (`Feature level: 2` → `Backend feature level: 2` → `FEngine feature level:
      // 1`), and `canLoadModels` refused on every device ever tried. The sentence
      // the customer saw — "3D preview isn't supported on this phone." — was
      // therefore about our own request, not about their phone.
      final builder = between(
        codeOf(view),
        'val engineBuilder = Engine.Builder()',
        'val created = engineBuilder.build()',
      );
      expect(
        builder,
        contains(
          'engineBuilder.featureLevel(Engine.FeatureLevel.FEATURE_LEVEL_2)',
        ),
        reason: 'the builder default is level 1 on every device, so not asking '
            'is the same as refusing; a level-1 device is unaffected because the '
            'clamp is the driver\'s',
      );
      // The QA switch is the *other* branch, not a later override: a run that
      // lowered the engine after building it at 2 would measure the wrong thing.
      expect(
        builder.indexOf('shouldLowerEngineToLevel1(pendingModel)'),
        lessThan(builder.indexOf('FEATURE_LEVEL_2')),
        reason: 'the lowering branch must be the else of the level-2 request',
      );
    });

    test('the load stops at the first success, and nothing creates a second asset', () {
      // ⚠️ A crash guard, and it cost a real process abort: `repeat`'s lambda
      // return is a `continue`, so `if (loaded != null) return@repeat` kept
      // loading — up to LOAD_ATTEMPTS whole assets, each holding material
      // instances that nothing destroyed. Teardown's `destroyMaterials()` then
      // aborted in native code, uncatchably, on a phone whose render was fine:
      //
      //     utils::PreconditionPanic: reason: destroying material
      //     "base_lit_opaque" but 4 instances still alive.
      //
      // That is the crash on *leaving* the box — the one the owner's phone could
      // never report, because it has no logcat.
      final loader = between(
        codeOf(view),
        'for (attempt in 0 until LOAD_ATTEMPTS)',
        'val createdAsset = loaded',
      );
      expect(loader, contains('if (loaded != null) break'));
      expect(
        loader,
        isNot(contains('return@repeat')),
        reason: 'a lambda return continues the loop, and every extra createAsset '
            'is an asset nobody destroys',
      );

      // The staging loader is freed as well: `AssetLoader`'s own javadoc is
      // `loadResources` … `resourceLoader.destroy()`.
      expect(
        codeOf(view),
        contains('resources.destroy()'),
        reason: 'the resource loader holds native staging buffers per open',
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
