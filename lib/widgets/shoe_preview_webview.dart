import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../constants/app_brightness.dart';
import '../constants/app_constants.dart';
import '../services/ar_try_on_channel.dart';
import '../services/diag_logger.dart';

/// **The 3D box drawn by a WebView instead of the native Filament view** — the
/// alternative engine behind `AppConstants.shoePreviewWebViewEnabled`.
///
/// It renders the **same verified `.glb` on disk** that the native renderer
/// draws, through Google's `<model-viewer>` web component, inside the system
/// WebView. `ShoePreview3D` picks between the two engines and everything else
/// about the feature — the gate, the prefetch, the AR pill, the honest failure
/// line — is unchanged.
///
/// ⚠️ **Why this exists, in one paragraph, because it is a measurement and not a
/// preference.** The native renderer draws the shoe correctly on the P30 Pro at
/// `FEATURE_LEVEL_2` and ~57 fps, and then dies in ways that take the whole
/// process with it: a `SIGSEGV` inside
/// `Java_com_google_android_filament_TransformManager_nSetTransform`, and a
/// `SIGABRT` (`destroying material "base_lit_opaque" but 2 instances still
/// alive`) inside teardown's `destroyMaterials()` — both measured on a vivo
/// V2022 on 2026-10-02. Neither is catchable. A WebView moves the render into
/// Chromium's own process: if it stalls or dies, **this app is still standing**
/// and the box is merely blank — a state the feature already handles honestly.
/// The trade is a second rendering surface and a loopback HTTP bridge, against
/// the removal of an entire class of app-killing failure.
///
/// ✅ **Measured on that device, where the native engine crashed four times in its
/// first thirty seconds.** Five open/close cycles of the same model, in **one
/// process**: five loads, five `gl:webgl2` probes, zero errors, zero tombstones,
/// `box=396x520` identical every time, and a drag that turns the shoe. Both of the
/// native engine's death sites — `setTransform` on the load tail and
/// `destroyAsset` on a second teardown — have no counterpart here, because this
/// path makes no native call of ours at all.
///
/// **What the package does with the model, since it is the part worth knowing.**
/// `model_viewer_plus` binds an `HttpServer` to `InternetAddress.loopbackIPv4` on
/// an ephemeral port and serves the page plus the model over it, so the WebView
/// loads from `http://127.0.0.1:<port>/`. The bytes are read from the local file
/// this widget is handed and **never leave the device**; the server is closed
/// with `force: true` in the widget's `dispose`. It does require cleartext to
/// `127.0.0.1`, which is why
/// `android/app/src/main/res/xml/network_security_config.xml` exists and is
/// scoped to the loopback address alone.
///
/// ⚠️ **`ar` is false and that is deliberate.** `<model-viewer>` can hand a model
/// to the Google app / Scene Viewer over an `intent://` URL, which would launch a
/// *different application* from a shopper's product page. The app already has its
/// own AR path (`Mode.AR`, the "Try On in AR" pill under this box) and it is the
/// one that carries the fit logic.
///
/// ⚠️ **Nothing here may call `setState` (or notify the parent) before the first
/// frame.** That is not style advice — it is a bug this widget shipped with for
/// one build, and the Flutter error names it exactly:
///
///     setState() or markNeedsBuild() called during build.
///       the widget marked:  ShoePreviewSection
///       the widget being built: ShoePreview3D
///
/// A widget may only be marked dirty during the build phase when it is the widget
/// being built **or a descendant of it**. `ShoePreviewSection` is an *ancestor*
/// of `ShoePreview3D`, so notifying it from `initState` throws — and because the
/// throw happens inside `initState`, `build()` never runs, `dispose()` never
/// runs, and the box is a permanently blank rectangle with a single mount line as
/// its only evidence. Hence [_logOnly] (safe anywhere, no `setState`) versus
/// [_report] (only ever called from the page's async event bridge).
class ShoePreviewWebView extends StatefulWidget {
  const ShoePreviewWebView({
    super.key,
    required this.model,
    this.onStatus,
    this.diagnostics = AppConstants.shoePreviewDiagnosticsEnabled,
  });

  /// The verified local model — the same payload the native engine is handed.
  final TryOnModelSpec model;

  /// Reports the engine's own state as one short line, for the QA readout.
  ///
  /// ⚠️ **A callback rather than a channel event**, because this engine has no
  /// native side to raise one: `ShoePreviewSection`'s `status` events come from
  /// Kotlin, and nothing Kotlin runs on this path. The same line also goes to
  /// `nav_diag.log` through [navDiag] — the route that actually reaches the phone
  /// this was written for, since it has no readable logcat.
  ///
  /// ⚠️ **Ancestor, so it may not be called before the first frame** — see the
  /// class header.
  final ValueChanged<String>? onStatus;

  /// Whether the engine narrates itself at all. Off in every customer build, the
  /// same rule the native engine's heartbeat follows.
  final bool diagnostics;

  @override
  State<ShoePreviewWebView> createState() => _ShoePreviewWebViewState();
}

class _ShoePreviewWebViewState extends State<ShoePreviewWebView> {
  /// One-shot guards, so neither trace can become a per-frame relay call (the
  /// relay `fsync`s every line).
  bool _traced = false;
  bool _tracedMissing = false;

  @override
  void initState() {
    super.initState();
    // Log only. See the class header for what notifying the parent here costs.
    _logOnly('mounted (model ${widget.model.modelId})');
  }

  @override
  void dispose() {
    // ⚠️ A disposal trace, because "built and then removed" is a real state on
    // this feature: `ShoePreviewSection` unmounts the box the moment the renderer
    // reports it cannot draw, so a box whose only evidence is its mount line looks
    // identical to one that is on screen and blank. Two lines tell them apart —
    // and their *absence* is how the `initState` throw above was found.
    _logOnly('disposed (model ${widget.model.modelId})');
    super.dispose();
  }

  /// Writes a line and nothing else — **safe from `initState` and `build`.**
  void _logOnly(String line) {
    if (!widget.diagnostics) return;
    navDiag('[preview-web] $line');
  }

  /// Writes a line and tells the parent, which owns the readout.
  ///
  /// ⚠️ **`ShoePreviewSection` draws the only QA line, not this widget.** The
  /// parent already renders its `_statusLine` under the box for the native
  /// engine, and it renders this one through the same field — so drawing a second
  /// overlay here would show every line twice, once per engine's idea of where the
  /// box ends. One surface, one source, whichever engine is running.
  ///
  /// ⚠️ **It must not rebuild this widget, and that is a measured requirement
  /// rather than a style rule.** `ModelViewer` builds its loopback server and its
  /// `WebViewController` in `initState`, so re-inflating the element discards the
  /// load in flight and starts a second one. An earlier build drew its own QA line
  /// by switching its root between `ModelViewer` and a `Stack`, and on a vivo
  /// V2022 (2026-10-02) that produced `error — :loadfailure`, a full re-fetch and
  /// a blank box — from nothing worse than a status line appearing under the box.
  /// So the parent draws the line, and this widget never rebuilds itself to say
  /// anything.
  ///
  /// ⚠️ **Only for the page's event bridge**, which fires long after the first
  /// frame. Calling this from `initState` is the bug documented on the class.
  void _report(String line) {
    _logOnly(line);
    if (!mounted) return;
    widget.onStatus?.call(line);
  }

  /// The page-side listeners, injected by the package after the `<model-viewer>`
  /// element it builds.
  ///
  /// ⚠️ **Two ordering traps, both closed here.**
  ///
  /// 1. The package writes its `script type="module" src="model-viewer.min.js"
  ///    defer` into the document's `head`, and a deferred module script runs
  ///    *after* this inline one. So the `model-viewer` element is not upgraded
  ///    yet when this executes, and `whenDefined` is what guarantees it is before
  ///    a listener is attached.
  /// 2. The model is served over loopback and can finish loading before any of
  ///    this runs. A listener attached after the fact would wait forever for an
  ///    event that already fired, and the box would report "loading" over a
  ///    picture the customer can already see — hence the `mv.loaded` read.
  ///
  /// ⚠️ **It also reports two measurements, and they are the reason a blank box
  /// can be diagnosed at all.** A WebGL context that cannot be created and a
  /// `model-viewer` element that laid out to zero height both look identical from
  /// Dart — no picture — and produce *the same* `load` event, so a colour alone
  /// cannot tell them apart. `gl:` is asked once per page, and `box=` rides along
  /// with every event because the element's size is the thing that can be wrong.
  static const String _listeners = r'''
const post = (m) => { try { ShoePreviewEngine.postMessage(m); } catch (e) {} };
const probe = () => {
  try {
    const c = document.createElement('canvas');
    if (c.getContext('webgl2')) return 'webgl2';
    if (c.getContext('webgl') || c.getContext('experimental-webgl')) return 'webgl1';
    return 'none';
  } catch (e) { return 'none'; }
};
post('gl:' + probe());
customElements.whenDefined('model-viewer').then(() => {
  const mv = document.querySelector('model-viewer');
  if (!mv) { post('error:no-element'); return; }
  const box = () => mv.clientWidth + 'x' + mv.clientHeight +
    ' body=' + document.body.clientHeight + ' win=' + window.innerHeight;
  mv.addEventListener('load', () => post('loaded box=' + box()));
  mv.addEventListener('error', (e) => {
    const t = (e && e.detail && e.detail.type) ? e.detail.type : 'unknown';
    post('error:' + t);
  });
  mv.addEventListener('progress', (e) => {
    const p = (e && e.detail && typeof e.detail.totalProgress === 'number')
      ? e.detail.totalProgress : 0;
    post('progress:' + Math.round(p * 100) + ' box=' + box());
  });
  if (mv.loaded) post('loaded box=' + box());
});
''';

  /// The bridge from the page's own events back into Dart.
  ///
  /// ⚠️ **This is the part that keeps the feature honest on the new engine.** The
  /// native path reports a load through its channel; without this, a WebView that
  /// never draws would be indistinguishable from one still loading — the "blank
  /// box with no explanation" this feature exists to avoid.
  Set<JavascriptChannel> get _channels => <JavascriptChannel>{
        JavascriptChannel(
          'ShoePreviewEngine',
          onMessageReceived: (message) {
            final text = message.message;
            if (text.startsWith('loaded')) {
              _report('loaded ${text.substring(6)}'.trim());
            } else if (text.startsWith('error')) {
              _report('error — ${text.substring(5)}');
            } else if (text.startsWith('progress:')) {
              // Kept because a load that stalls at 40% is a different fault from
              // one that never starts, and the phone this is read from has no
              // other way to tell them apart.
              _report('progress ${text.substring(9)}');
            } else {
              // `gl:<kind>` — a measurement, not a state. It never changes the
              // box; it only ever explains one.
              _logOnly(text);
            }
          },
        ),
      };

  @override
  Widget build(BuildContext context) {
    // ⚠️ **Read here rather than cached in `initState`.** The check is one
    // `existsSync` on a path that does not change for the life of the widget, and
    // computing it during build is what makes this branch reachable at all: a
    // stored flag would have to be written from `initState`, which is the throw
    // this file exists to not repeat.
    final missing = !shoePreviewModelOnDisk(widget.model);

    if (!_traced) {
      _traced = true;
      _logOnly('branch=${missing ? 'missing' : 'engine'} · '
          'platform=$defaultTargetPlatform · file=${!missing}');
    }

    if (missing) {
      if (!_tracedMissing) {
        _tracedMissing = true;
        _logOnly('model missing on disk: ${widget.model.path}');
      }
      return const _BoxFace(
        message: 'The 3D model is not on this device.',
      );
    }

    // iOS has no entry here — the gate refuses non-Android before this is built —
    // and a WebView elsewhere would throw rather than degrade. Same second line of
    // defence `ShoePreview3D._view` keeps for the native view.
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const _BoxFace();
    }

    final engine = ModelViewer(
      // ⚠️ **Keyed by path — and by brightness.** `ModelViewer` is a StatefulWidget
      // that builds its loopback server, its WebView controller and the whole HTML
      // document in `initState` (it has no `didUpdateWidget`), so a changed `src`
      // *or* a changed `backgroundColor` on the same element keeps serving the page
      // it was built with. The key is what makes a colour variant swap the asset,
      // and it is what makes a theme flip repaint the stage: re-inflating costs one
      // reload from the local file, and the alternative is a live box clearing to
      // #0E0F12 inside a light-mode viewer.
      key: ValueKey<String>(
        '${widget.model.path}#${AppBrightness.current.name}',
      ),
      // The package turns this into the loopback URL `/model` and reads the file
      // itself; `file://` is the documented way to hand it a path on disk.
      src: 'file://${widget.model.path}',
      // ⚠️ Not negotiable — see the class header. `false` here is what keeps a tap
      // inside the box from launching another application.
      ar: false,
      // The customer turns the shoe with a finger; this is the whole interaction.
      cameraControls: true,
      // Matches the native preview's opening pose so the two engines are the same
      // product: `INITIAL_YAW_DEG = 60`, and `INITIAL_PITCH_DEG = 18` from the
      // horizontal is model-viewer's phi of 90 − 18 = 72.
      cameraOrbit: '60deg 72deg 105%',
      // The same idle spin the native preview runs (2.5 s, 20°/s), so a customer
      // who does not touch the box still sees that it is a 3D object.
      autoRotate: true,
      autoRotateDelay: 2500,
      rotationPerSecond: '20deg',
      // The page header already says "Drag to rotate"; model-viewer's animated
      // hand would be a second, competing affordance for the same instruction.
      interactionPrompt: InteractionPrompt.none,
      // The stage the shoe stands on — the same brightness-aware token the native
      // renderer is handed (`ShoePreviewChannel.setBackground`) and the same one
      // `ShoePreviewIdle` paints, so the box does not flash from one tone to
      // another as the engine starts and all three faces are one rectangle.
      backgroundColor: AppConstants.stage,
      alt: 'A 3D model of this shoe. Drag to rotate.',
      // ⚠️ **Off, and it defaults to ON.** The package prints the entire generated
      // HTML document to the console on every build when this is true.
      debugLogging: false,
      // ⚠️ **A guard, not the fix.** The package's template sets
      // `body, model-viewer { height: 100% }` and gives `html` no height, so
      // neither percentage has a definite containing block to resolve against and
      // both compute to `auto` — the canvas is laid out only because something
      // else happens to give it a box. `box=396x520` was measured on a vivo V2022
      // (2026-10-02) *with* this line present, so this is defence against a
      // collapse that did not occur, not the repair that made the shoe appear.
      // `relatedCss` substitutes into the template's `/* other-css */`, which is
      // the only hook the package leaves for it.
      relatedCss: 'html { height: 100%; }',
      relatedJs: _listeners,
      javascriptChannels: _channels,
    );

    return engine;
  }
}

/// **Whether the bytes this box was handed are actually on disk.**
///
/// One implementation for two readers, so they can never disagree about which
/// state the box is in: the WebView engine's own face (a model that vanished
/// between the page's prefetch and this mount says so rather than drawing a blank
/// box), and `ShoePreview3D`'s gesture tutorial, which must not appear over that
/// sentence — see `_engineDraws`. A `stat` per build is what both can afford; the
/// reasoning for reading it during `build` rather than storing it is on
/// `ShoePreviewWebView.build`.
bool shoePreviewModelOnDisk(TryOnModelSpec model) =>
    model.path.isNotEmpty && File(model.path).existsSync();

/// The box's face when it has nothing to draw, with an optional sentence on it.
///
/// The same tone the renderer clears to ([AppConstants.stage]) rather than the
/// page behind it, so a box that cannot draw still reads as *the box* rather than
/// as a gap in the layout — and it matches `ShoePreviewIdle` and the WebView
/// engine's own background, so all three states are the same rectangle to a
/// customer, in either brightness.
class _BoxFace extends StatelessWidget {
  const _BoxFace({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return ColoredBox(
      color: AppConstants.stage,
      child: text == null
          ? const SizedBox.expand()
          : Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
    );
  }
}
