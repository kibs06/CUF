import 'dart:io';

import 'package:app/constants/app_constants.dart';
import 'package:app/constants/app_palette.dart';
import 'package:app/services/shoe_preview_channel.dart';
import 'package:app/utils/shoe_preview_visibility.dart';
import 'package:flutter/material.dart';
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

  group('the stage is the page, and the model is not stretched', () {
    test('the viewer hands the box the full width and the words a gutter', () {
      // 2026-10-03, the owner's request: the box takes the page's full width (its
      // 20 px gutters came off) and the room that used to sit empty between it and
      // the pinned pill, so the shoe has more room to turn and zoom. None of that
      // touches the model — the renderer is handed the same asset and frames it
      // itself — so what is pinned here is the *window*: the box bleeds, and
      // everything that is text keeps the page's gutter.
      expect(previewScreen, contains('bleed: true,'));
      expect(
        previewScreen,
        contains('padding: const EdgeInsets.only(top: 8, bottom: 12)'),
        reason: 'a scroll view that still insets the section undoes the bleed',
      );
      // The header row is drawn inside the box widget, so it is the one thing
      // that has to inset itself — with the shared number, not a literal.
      expect(
        previewWidget,
        contains('horizontal: widget.bleed ? kShoePreviewGutter : 0'),
      );
      expect(
        previewWidget,
        contains('borderRadius: BorderRadius.circular(widget.bleed ? 0 : 16)'),
        reason: 'a stage that is the page surface has no corners to round; inset, '
            'it stays the card its other callers draw',
      );
      // And the section forwards the flag rather than re-deciding it, the way it
      // forwards the engine choice.
      final section = previewWidget.substring(
        previewWidget.indexOf('class ShoePreviewSection'),
      );
      expect(section, contains('bleed: widget.bleed,'));
    });

    test('and its height is the room the page has, not a fixed strip', () {
      // ⚠️ The reserve is the pill below and the header above, and it is a
      // constant on purpose: the header row is laid out a frame *after* the box
      // that has to be sized for it, and waiting for the measurement would cost a
      // frame of the one surface the viewer was opened for.
      final height = between(previewScreen, 'final boxHeight =', '.toDouble()');
      expect(height, contains('_notTheStage'));
      expect(height, contains('.clamp(240.0, _stageCeiling)'));
      expect(
        previewScreen,
        contains('static const double _notTheStage = 160;'),
        reason: 'the reserve is the pill (~80) plus the header and padding (~50), '
            'plus slack for a larger text scale',
      );
      expect(previewScreen, contains('static const double _stageCeiling = 900;'));
    });
  });

  group('there is exactly one AR entry on the page', () {
    test('the viewer draws it once, at the foot of the page', () {
      // ⚠️ The pill lived inside the section from 2026-10-01 to 2026-10-03, in
      // the flow directly under the box. The owner asked for it at the bottom of
      // the screen — with a box that fills most of the page, the button left a
      // dead half-page beneath it. What the move must not cost is the reason the
      // two used to be one widget (one entry, present exactly when the box is,
      // surviving a renderer that refuses), so each half of that is pinned here.
      expect(
        'SoleARPill('.allMatches(previewScreen).length,
        1,
        reason: 'one entry: a second pill is a second way into the same camera',
      );
      expect(previewScreen, contains('SoleARPill(onPressed: _openArTryOn)'));
      // Drawn after the scroll body — the bottom bar is the page's own slot, not
      // a child of the box — and only on the door that has someone to try the
      // pair on.
      expect(
        previewScreen.indexOf('SoleARPill('),
        greaterThan(previewScreen.indexOf('SingleChildScrollView(')),
        reason: 'a pill in the flow under the box is the layout this moved to fix',
      );
      expect(
        previewScreen,
        contains('if (widget.showTryOn)'),
        reason: "the seller's door must keep offering no camera at all",
      );
      // And the box widget draws none: no branch over there — the refusal
      // included — can take the entry off the page any more. That is the
      // structural half of the guarantee the owner asked for on 2026-09-30, after
      // a real phone showed the whole section (button included) vanishing on
      // return from AR.
      final section = previewWidget.substring(
        previewWidget.indexOf('class ShoePreviewSection'),
      );
      expect(section, isNot(contains('SoleARPill(')));
      expect(section, isNot(contains('onTryOnInAr')));
      // The refusal branch keeps its honest sentence — which is the whole of what
      // that branch is now.
      final unsupported = between(
        section,
        'if (_unsupported || _diagnosticDetail != null)',
        'return Column',
      );
      expect(
        unsupported,
        contains("'3D preview isn\\'t supported on this phone.'"),
      );
    });

    test('the product page itself mounts none of them — the icon is the only entry',
        () {
      // The pinned pill came off the page on 2026-10-01. AR is now one tap
      // deeper, inside the viewer, which is the escalation rather than a second,
      // competing button on the page.
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

  group('the WebView engine is additive, and cannot ship by accident', () {
    // ⚠️ The second engine exists because the native one *stops returning* from
    // two JNI calls into the P30 Pro's GL driver (`setTransform` on the load tail,
    // `destroyAsset` on a second teardown). A WebView moves that failure into
    // Chromium's process, where a stall blanks the box instead of killing the app.
    // The guards below are about it staying a *second* engine: additive, off by
    // default, and unable to smuggle the two QA locks in with it.
    final webView = File('lib/widgets/shoe_preview_webview.dart').readAsStringSync();

    test('it is an environment switch, and it now defaults to the engine with a device behind it', () {
      // ⚠️ **The default flipped on measurement, and the measurement is the reason.**
      // On a vivo V2022 the native engine killed the app on **2 of 3** attempts to open
      // the 3D box (`SIGSEGV` in `TransformManager_nSetTransform+64`), while the WebView
      // engine ran five opens in one process with zero crashes. This assertion pins the
      // decision so it cannot be reverted by accident — and pins that it is still an
      // environment switch, so `SHOE_PREVIEW_WEBVIEW=false` restores the native path
      // from a shipped build with no code change.
      expect(
        constants,
        contains(
            "bool.fromEnvironment('SHOE_PREVIEW_WEBVIEW', defaultValue: true)"),
        reason: 'the native engine is what crashes the app; the WebView engine is what '
            'was measured working',
      );
    });

    test('the QA workflow passes the define either way, so `false` really builds native', () {
      // ⚠️ **This is a direct consequence of the default flipping, and it would fail
      // silently without the assertion.** While the code default was `false`, the
      // workflow could pass the define only when it wanted the WebView engine. With
      // the default now `true`, omitting it for `webview_engine=false` builds a
      // WebView APK while the input, the artifact name and the report all say native
      // — a QA run measuring the wrong engine and filing the result as evidence.
      final workflow = File('.github/workflows/qa-apk.yml').readAsStringSync();
      expect(workflow, contains('--dart-define=SHOE_PREVIEW_WEBVIEW=true'));
      expect(
        workflow,
        contains('--dart-define=SHOE_PREVIEW_WEBVIEW=false'),
        reason: 'omitting the define now selects WebView by default, which is the '
            'opposite of what `webview_engine=false` promises',
      );
    });

    test('the native renderer is not deleted — both engines stay compiled in', () {
      // The whole point of a switch rather than a rewrite: the rollback from a
      // shipped build is one define, and the native path keeps its instrumentation
      // and its tests while the new engine is measured.
      expect(previewWidget, contains('kShoePreviewViewType'));
      expect(previewWidget, contains('AndroidView('));
      expect(previewWidget, contains('ShoePreviewWebView('));
    });

    test('the WebView engine never opens a second AR door', () {
      // `<model-viewer>` can hand a model to the Google app over an `intent://`
      // URL. The app has its own AR path with the fit logic behind it, and a
      // shopper must not be launched into another application from the box.
      expect(
        codeOf(webView),
        contains('ar: false'),
        reason: 'a true here launches Scene Viewer out of a product page',
      );
    });

    test('the model is loaded from disk, never from the network', () {
      // The same rule the native side is held to (§5: "the native side never
      // does HTTP"). The package serves the bytes over loopback from this file.
      expect(webView, contains("src: 'file://\${widget.model.path}'"));
      expect(
        codeOf(webView),
        isNot(contains('http://')),
        reason: 'a model URL in the widget would mean the box fetches from a host',
      );
    });

    test('the debug dump stays off', () {
      // ⚠️ `debugLogging` defaults to **true** in the package, and it prints the
      // whole generated HTML document on every build.
      expect(
        codeOf(webView),
        contains('debugLogging: false'),
        reason: 'the package default prints the entire HTML document per build',
      );
    });

    test('the box says why it is empty, because a colour cannot', () {
      // ⚠️ **A missing WebGL context and a `model-viewer` element with no box to
      // draw in are the same picture and raise the *same* `load` event**, so a
      // blank box cannot be diagnosed from Dart by looking at it. Both are probed
      // on the page and relayed as measurements instead of as states. Measured on
      // the vivo V2022 (2026-10-02) as `gl:webgl2` and `box=396x520`.
      expect(webView, contains("post('gl:"));
      expect(webView, contains('getContext'));
      expect(webView, contains('box='));
    });

    test('the element is given a root height rather than trusting the template', () {
      // ⚠️ The package's template sets `body, model-viewer { height: 100% }` and
      // never sets a height on `html`, so neither percentage resolves. This is a
      // **guard**, not the repair that made the shoe appear — the element measured
      // a correct `396x520` while blank — and it is asserted so a future template
      // or package bump cannot quietly remove the only height the canvas has.
      expect(webView, contains('relatedCss:'));
      expect(webView, contains('html { height: 100%; }'));
    });

    test('reporting a line never rebuilds the box, because rebuilding it reloads it', () {
      // ⚠️ **The measured cause of the first blank box, and the least obvious one.**
      // `ModelViewer` creates its loopback server and its `WebViewController` in
      // `initState`, so re-inflating the element discards the load in flight and
      // starts a second one. A build that drew its own QA line by switching its
      // root between `ModelViewer` and a `Stack` therefore reloaded the model every
      // time a status line appeared — logged on the vivo V2022 as
      // `error — :loadfailure` followed by a full re-fetch. The parent draws the
      // line; this widget must not rebuild itself to say anything.
      final reportStart = webView.indexOf('void _report(');
      expect(reportStart, greaterThan(-1));
      final reportBody =
          webView.substring(reportStart, webView.indexOf('\n  }', reportStart));
      expect(
        reportBody,
        isNot(contains('setState')),
        reason: 'a setState here re-inflates ModelViewer and restarts the load',
      );
    });

    test('a load that fails says so on the page rather than staying blank', () {
      // The native path reports through its channel; this engine has no native
      // side, so the page's own `load`/`error` events are the only witness. Without
      // them a WebView that never draws is indistinguishable from one still
      // loading — the "blank box with no explanation" this feature exists to avoid.
      expect(webView, contains("addEventListener('load'"));
      expect(webView, contains("addEventListener('error'"));
      expect(webView, contains('whenDefined'));
    });

    test('the cleartext exception is scoped to loopback, not the application', () {
      // ⚠️ The package bridges Dart and the WebView over a loopback HTTP server,
      // and Android 9+ blocks cleartext by default. The blanket
      // `android:usesCleartextTraffic="true"` would permit it to *every* host — a
      // real regression for an app carrying a Supabase client, payment redirects
      // and an OTA updater.
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final config = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync();

      expect(manifest, contains('android:networkSecurityConfig="@xml/network_security_config"'));
      expect(
        manifest,
        isNot(contains('usesCleartextTraffic="true"')),
        reason: 'the blanket flag would allow cleartext to every host',
      );
      expect(config, contains('cleartextTrafficPermitted="true"'));
      expect(config, contains('127.0.0.1'));
      expect(
        config,
        contains('<base-config cleartextTrafficPermitted="false" />'),
        reason: 'the default must stay exactly as Android 9 set it',
      );
    });
  });

  group('the stage behind the shoe follows the customer\'s appearance', () {
    // ⚠️ **The box was pinned dark in both brightnesses, and that was the one
    // surface in the app that could not follow the theme.** The renderer cleared
    // to `#0E0F12` (the tone the native view's `DEFAULT_CLEAR_COLOR` still holds),
    // `ShoePreviewIdle` and the WebView engine's page matched it, and a light-mode
    // customer looking at a white page got a black rectangle — the screenshot the
    // owner filed on 2026-10-03. The stage is now one brightness-aware token
    // (`AppConstants.stage`) and the guards below are about it staying one: every
    // face of the box reads it, neither engine pins a hex, and the tone reaches a
    // renderer that is *already running* when the customer flips the theme.
    final webView =
        File('lib/widgets/shoe_preview_webview.dart').readAsStringSync();
    final view = File(
      'android/app/src/main/kotlin/com/solevision/app/tryon/ArTryOnView.kt',
    ).readAsStringSync();
    final plugin = File(
      'android/app/src/main/kotlin/com/solevision/app/tryon/ArTryOnPlugin.kt',
    ).readAsStringSync();

    test('it is one token, and neither engine pins a tone of its own', () {
      // Light is a paper surface (the tone the app's recessed fills use) and dark
      // is *exactly* the value this feature has cleared to since V3.2 — the one
      // thing that must not move, because it is the tone the owner's device work
      // was all measured against.
      expect(AppPalette.light.stage.computeLuminance(), greaterThan(0.8),
          reason: 'a light-mode box has to be a light surface, not a black slab');
      expect(
        AppPalette.dark.stage,
        const Color(0xFF0E0F12),
        reason: 'dark mode keeps the renderer tone, so nothing about the shipped '
            'dark presentation moves',
      );
      expect(
        AppConstants.stage,
        AppPalette.light.stage,
        reason: 'and the getter resolves through the published brightness',
      );

      for (final source in <String>[previewWidget, webView]) {
        expect(
          codeOf(source),
          isNot(contains('0xFF0E0F12')),
          reason: 'a pinned tone in either Dart face is the black rectangle in '
              'light mode this change removed',
        );
      }
    });

    test('the WebView engine gets the token, and is re-keyed to repaint it', () {
      // ⚠️ The package bakes `backgroundColor` into the HTML it serves from its
      // loopback server and builds that document in `initState` — it has no
      // `didUpdateWidget`, so a changed colour on the same element keeps serving
      // the page it was built with. Re-keying is the only way a live box follows
      // the theme.
      expect(webView, contains('backgroundColor: AppConstants.stage'));
      expect(
        webView,
        contains('AppBrightness.current.name'),
        reason: 'the ModelViewer key has to carry the brightness, or a theme flip '
            'leaves the old page running',
      );
    });

    test('the native renderer is handed the token and restaged in place', () {
      // The wire: the preview's own channel, a method of its own (a theme flip has
      // no model to ride on), ARGB because that is what a Flutter `Color` is.
      expect(previewChannel, contains("'setPreviewBackground'"));
      expect(previewChannel, contains('color.toARGB32()'));
      expect(
        previewWidget,
        contains('_handOverStage();'),
        reason: 'the box has to send it — from `build`, because a brightness change '
            'repaints these elements without re-creating or updating them',
      );
      expect(previewWidget, contains('AppBrightness.current'));

      // Native: parked like the model (it arrives with the box, a frame before the
      // platform view), replayed on creation, and applied to a *live* renderer too.
      expect(plugin, contains('"setPreviewBackground" ->'));
      expect(plugin, contains('created::setBackground'));
      expect(plugin, contains('parkedPreviewBackground'));

      expect(view, contains('fun setBackground(argb: Int)'));
      expect(
        codeOf(view),
        contains('stageColor ?: DEFAULT_CLEAR_COLOR'),
        reason: 'a colour that has not arrived must leave the shipped tone in place',
      );
      expect(
        between(view, 'private fun applyClearColor(', '/**'),
        contains('setClearOptions'),
        reason: 'the only way a running renderer changes its stage',
      );
      expect(
        between(view, 'createLights(created)', 'Log.i('),
        contains('applyClearColor()'),
        reason: 'engine creation is where a colour that arrived first is applied',
      );
      expect(
        view,
        contains('val DEFAULT_CLEAR_COLOR = doubleArrayOf(0.055, 0.06, 0.07, 1.0)'),
        reason: 'the dark tone the feature shipped with, spelled once',
      );

      // ⚠️ **AR is not sent one, and must not be.** The AR screen is a camera feed:
      // it keeps its dark clear colour in both brightnesses, so the stage travels
      // on the preview channel rather than as a field of the shared model payload
      // (which the AR session sends too).
      expect(
        File('lib/services/ar_try_on_channel.dart').readAsStringSync(),
        isNot(contains('setBackground')),
        reason: 'a stage colour on the AR channel would turn a camera surface into '
            'a light-mode page',
      );
    });
  });

  group('the gesture tutorial is one overlay, and it cannot become a wall', () {
    // ⚠️ The owner's report on 2026-10-03: the box carried one line of instruction
    // ("Drag to rotate", in the section's header) over a shoe that *spins on its
    // own*, so a customer who read it as a picture tapped the AR pill and never
    // learned it turns. The tutorial answers that with a hand sweeping over the
    // pill and both gestures named, after ten seconds of stillness — and these are
    // the three properties that make it safe: it never competes for the gesture, it
    // is silent to a screen reader that cannot turn the model anyway, and it does
    // not leak a timer into every test or every visit.
    final webView =
        File('lib/widgets/shoe_preview_webview.dart').readAsStringSync();

    test('it observes the touch without competing for it', () {
      // Both engines hand the gesture arena to their platform view, so a
      // `GestureDetector` here could never win a drag — and would try, which is how
      // the shoe stops turning. A raw `Listener` is not a competitor.
      expect(previewWidget, contains('behavior: HitTestBehavior.translucent'));
      expect(previewWidget, contains('onPointerDown: _touchStarted'));
      expect(
        previewWidget,
        contains('if (_hintVisible && _engineDraws)'),
        reason: 'the pill is only ever drawn over a box that has something to draw',
      );

      // And the pill itself lets the finger through: a tutorial that eats the
      // gesture it teaches is worse than none.
      final hint = between(
        previewWidget,
        'class ShoePreviewGestureHint',
        'class _GestureLine',
      );
      expect(hint, contains('IgnorePointer'));
      expect(
        hint,
        contains('ExcludeSemantics'),
        reason: 'the header already carries the instruction as text, and the box '
            'under the pill is a platform view a screen reader cannot turn',
      );
    });

    test('the wait is named, and the timer cannot outlive the box', () {
      expect(previewWidget, contains('static const Duration hintAfterIdle'));
      expect(
        previewWidget,
        contains('Timer(ShoePreview3D.hintAfterIdle'),
        reason: 'a literal here would be a second number for the widget test to '
            'guess at',
      );
      expect(
        between(previewWidget, 'void dispose()', 'super.dispose();'),
        contains('_idleTimer?.cancel();'),
        reason: 'a pending timer fails every test that mounts the box (and would '
            'fire a hand over a box that is gone)',
      );
    });

    test('there is exactly one tutorial, because the package has one too', () {
      // ⚠️ `<model-viewer>` shows its own animated hand after 3 s idle, and it is
      // **on by default**. It stays off for a stronger reason than the one it was
      // turned off for (the header said the same thing): two prompts in one box, in
      // two visual languages — and the package's would cover the WebView engine
      // only, which is how the two engines start looking like two products.
      expect(codeOf(webView), contains('interactionPrompt: InteractionPrompt.none'));
      expect(previewWidget, contains('class ShoePreviewGestureHint'));
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
