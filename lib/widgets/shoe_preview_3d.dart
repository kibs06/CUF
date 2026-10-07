import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../constants/app_brightness.dart';
import '../constants/app_constants.dart';
import '../services/ar_try_on_channel.dart';
import '../services/diag_logger.dart';
import '../services/shoe_preview_channel.dart';
import '../services/shoe_preview_fallback_guard.dart';
import 'shoe_preview_webview.dart';

/// **The viewer page's horizontal gutter** — the 20 px the page insets its own
/// text with.
///
/// It is one number in one place because the stage stopped taking it on
/// 2026-10-03: the owner asked for more room to turn and zoom the shoe, so the
/// box is the page's full width now, and the 20 px has to be carried by the
/// things that *are* text — the header row drawn inside [ShoePreview3D] (via
/// [ShoePreview3D.bleed]), the section's banner, its refusal sentence and its QA
/// readout, and the viewer's own note and failure hint ([ShoePreviewScreen]
/// insets those). Two numbers that disagreed would show up as a header that does
/// not line up with the sentence beneath it.
const double kShoePreviewGutter = 20;

/// **The one sentence a phone that cannot draw 3D is owed**, spelled once because
/// two states now say it.
///
/// The renderer's own refusal (`kRendererUnsupportedReason`, an engine below
/// glTF's `FEATURE_LEVEL_2`) is the state it was written for. Since 2026-10-07 the
/// engine ladder adds a second: a phone whose WebView engine cannot draw **and**
/// whose native fallback is latched off, because the last attempt to use it killed
/// the app inside the load (`ShoePreviewFallbackGuard`). Two call sites, one
/// sentence — a phone told "not supported" twice in slightly different words would
/// read as two different faults, and this app's whole diagnostic history says the
/// words are how a fault is found.
const String kShoePreviewUnsupportedMessage =
    '3D preview isn\'t supported on this phone.';

/// The **3D box** — the customer turns the shoe with a finger.
///
/// ⚠️ **Where it is mounted changed on 2026-10-01, and the widget did not.** It
/// used to be a row on the product page, 240 px tall, under the size grid. It is
/// now the body of the full-screen viewer the product photo's 3D icon opens
/// (`ShoePreviewScreen`, `Sole3DIconButton`) — same renderer, same payload, same
/// section, at the size of a screen instead of the size of a paragraph. The page
/// keeps only the recovery notice (`_shoePreviewNotice`) and the pinned
/// "Try On in AR" pill is gone from it — the viewer draws its own, at the foot of
/// the page (`ShoePreviewScreen`), and that is the only way into AR from a
/// product.
///
/// **Why a box before a button.** "Try On in AR" was the only entry on the page
/// and it asked for three things before it showed anything: an ARCore-capable
/// phone, an app with the AR build flag on, and a customer willing to point a
/// camera at their feet — in public, at a shoe they are still deciding about.
/// The 3D box asks for none of them. It renders the **same verified `.glb`**
/// through the same native renderer (`ArTryOnView` in `Mode.PREVIEW`), so what
/// the customer turns is the mesh that would be tracked onto their foot, and a
/// tap on the pill at the foot of the page is the escalation rather than the
/// entry fee.
///
/// **It is gated before it is built, not inside.** Whether this widget exists at
/// all is `resolveShoePreview` in `lib/utils/shoe_preview_visibility.dart` — a
/// pure rule the page consults, so a product with no live model shows no box and
/// no button rather than an empty frame.
///
/// ⚠️ **Two things this widget does that look like details and are not:**
///
///   * **It stops rendering when it is covered** — [paused], which the page sets
///     while the AR screen is on top. Unmounting the native view disposes the
///     platform view and, with it, an entire Filament engine: two live engines
///     (one underneath the AR session, one in it) is a frame-rate argument nobody
///     wins, and the box is worth nothing while the customer is in AR anyway. The
///     idle face keeps the same height, so coming back does not jump the page.
///
///     ⚠️ **It is a flag rather than a route check, and that is a finding
///     rather than a preference.** The obvious version — read
///     `ModalRoute.of(context)?.isCurrent` in `build` — does **not** work here: a
///     plain `Navigator.push` does not rebuild the route underneath it, so the
///     box would keep its engine for the whole AR session, which is exactly the
///     case this exists to prevent. (A `RouteObserver` would, at the cost of
///     registering an observer in the app's `MaterialApp` for one widget's
///     benefit.) The page pushes the AR screen, so the page is the thing that
///     knows — see `_openArTryOn`.
///   * **The handover is fire-and-forget.** `setPreviewModel` is sent the moment
///     this state is created, before the platform view exists, because waiting
///     for a view is a race on a cold page — the native side parks the payload
///     and replays it on creation (finding F18, the same contract the AR path
///     uses). A preview that fails to load draws nothing and says so nowhere:
///     the page is a shop, not a diagnostics panel.
class ShoePreview3D extends StatefulWidget {
  const ShoePreview3D({
    super.key,
    required this.model,
    this.channel,
    this.viewBuilder,
    this.webViewBuilder,
    this.pixelProbeOverride,
    this.pixelCaptureSeesPlatformView =
        !AppConstants.shoePreviewHybridComposition,
    this.height = 240,
    this.bleed = false,
    this.paused = false,
    this.diagnostics = AppConstants.shoePreviewDiagnosticsEnabled,
    this.useWebViewEngine = AppConstants.shoePreviewWebViewEnabled,
    this.onEngineStatus,
  });

  /// The verified local model, in the same payload the AR path hands over.
  final TryOnModelSpec model;

  /// Test seam: a channel to record calls instead of a real one.
  final ShoePreviewChannel? channel;

  /// Test seam: the widget that stands in for the platform view.
  ///
  /// `AndroidView` cannot be mounted under `flutter test` — there is no
  /// platform-view registry — so the view is reached through a seam rather than
  /// built inline, the same boundary `ARVirtualFitScreen.tryOnViewBuilder`
  /// documents.
  ///
  /// ⚠️ **It stands in for whichever engine is selected**, and that is what keeps
  /// this widget's tests engine-agnostic: a test that injects a view asserts the
  /// handover and the layout, and never needs to know whether a platform view or
  /// a WebView would have been built.
  final Widget Function()? viewBuilder;

  /// **Test seam: the WebView engine, handed the page's line channel.**
  ///
  /// It stands where [viewBuilder] cannot, and the split is deliberate rather than
  /// tidy. [viewBuilder] is returned *before* the engine is chosen, so a test that
  /// injects one can never exercise the WebView branch — and the ladder this box
  /// now belongs to (`ShoePreviewSection`) is built entirely out of the lines that
  /// branch produces (`gl:webgl2`, `loaded`, `error`). Those lines come from a page
  /// that only exists inside a real WebView, which `flutter test` cannot mount.
  ///
  /// So a ladder test injects this instead: a stand-in that keeps the callback and
  /// hands it back to the test, letting the test report exactly what a phone's page
  /// reported and assert what the box did about it. The `onStatus` it is given is
  /// the real channel, not a copy — the same one the section's readout and the
  /// ladder listen on — which is why a stand-in engine's line still travels the
  /// production path all the way to the decision.
  final Widget Function(ValueChanged<String> onStatus)? webViewBuilder;

  /// **Test seam: the box's own pixels, in place of the raster capture.**
  ///
  /// The real capture (`RenderRepaintBoundary.toImage`) needs a *real* event loop —
  /// a fake clock does not advance the raster thread, which is why golden tests wrap
  /// theirs in `runAsync` — and crossing into the real loop in this suite also lets
  /// the harness's unrelated traffic run (a preview EventChannel with no plugin host,
  /// `google_fonts` reaching for a font over the network), so a test taking the real
  /// picture would fail on the harness rather than on the box. Those are artifacts of
  /// the test, not of the code.
  ///
  /// So the seam is the **bytes**, not the capture: everything this feature decides
  /// ([measureBoxPixels], [blankBoxColourFloor], the `blank:` line, the ladder's move)
  /// is then exercised exactly, and the capture itself is verified where it matters —
  /// on a phone, where it caught this fault in the first place.
  final Uint8List Function()? pixelProbeOverride;

  /// **Whether a capture of this box can contain the engine's pixels at all** —
  /// and therefore whether [ShoePreview3D.pixelProbeOverride]'s reading is a
  /// verdict or only news.
  ///
  /// ⚠️ **In hybrid composition it cannot, and this is measured rather than
  /// assumed.** On the owner's P30 Pro on 2026-10-07, the moment the page reported
  /// `loaded` the *screen* measured **77.6% exactly `#F5F5F5`** (137,200 of 176,904
  /// sampled pixels of the box's band — the stage the page paints inline on its
  /// element) with **696 distinct colours** and 14.5% dark ink: the shoe, drawn on
  /// the glass by the WebView. A `RepaintBoundary` capture of that same box, that
  /// same second, read `distinct=1 dark=100%` — because a hybrid-composited
  /// platform view is presented *over* the Flutter scene
  /// (`initExpensiveAndroidView`'s `FlutterImageView`) rather than inside the layer
  /// tree `toImage` rasterises. The instrument is blind to the thing it was built
  /// to measure, and a blind instrument that reports "empty" would move a working
  /// box onto the frozen native renderer on **every** phone.
  ///
  /// So the reading is kept and the *verdict* is dropped when the capture cannot
  /// see the view: the line still lands in the log (it is the control that proves
  /// the capture works at all in the other mode), and
  /// [kShoePreviewBlankBoxLine] is never sent. The other three verdicts — `gl:`, an
  /// element `error`, and eight seconds of silence — are page-side and unaffected,
  /// so a WebView that genuinely cannot draw is still handed to the native engine.
  ///
  /// It is a `final` on the widget rather than a bare constant so both directions
  /// are testable; its default follows the same switch that chooses the composition
  /// mode ([AppConstants.shoePreviewHybridComposition]), which is what keeps the two
  /// from drifting apart.
  final bool pixelCaptureSeesPlatformView;

  /// The box's height. 240 px shows a whole shoe at a three-quarter view without
  /// taking the size grid off the first screen.
  final double height;

  /// **Whether the page has handed this box its full width** — see
  /// [ShoePreviewScreen], which stopped insetting the box on 2026-10-03 so the
  /// model has more room to turn and zoom in.
  ///
  /// When true the box spans the page edge to edge — square corners included,
  /// because a rounded card hanging off both screen edges is neither a card nor
  /// the page — and the **header row insets itself** by [kShoePreviewGutter]:
  /// that row is drawn by this widget, and once the page's gutter is gone there
  /// is nowhere else for it to come from.
  ///
  /// ⚠️ **What does not change is the model.** Only the window around it does:
  /// the renderer gets the same asset, the same camera and the same stage tone,
  /// and it frames the shoe by itself. A wider or taller box is more room to
  /// turn and zoom in — never a stretched shoe.
  final bool bleed;

  /// True while something is covering this box — in practice, the AR screen it
  /// just pushed. Mounts [ShoePreviewIdle] instead of the native view, which is
  /// what stops a second Filament engine from rendering under an AR session.
  final bool paused;

  /// Whether this build asked the renderer to describe itself (`status` events).
  ///
  /// A parameter as well as the switch it defaults to, the same shape
  /// [ShoePreviewSection.showDiagnostics] uses and for the same reason: the
  /// readout is the evidence a device screenshot carries, so a test has to be able
  /// to turn it on without a `--dart-define` on the test run.
  final bool diagnostics;

  /// **Which engine draws the box.** Defaults to
  /// [AppConstants.shoePreviewWebViewEnabled].
  ///
  /// A parameter as well as the switch it defaults to, the same shape
  /// [diagnostics] and [ShoePreviewSection.showDiagnostics] use and for the same
  /// reason: the choice is compile-time in a shipped build, so without this a test
  /// could never assert the path it is *not* built with. Both engines stay
  /// reachable in every build; only the default differs.
  final bool useWebViewEngine;

  /// **The WebView engine's heartbeat, for the same readout the native one
  /// feeds.**
  ///
  /// It exists because the two engines report their state through completely
  /// different machinery — the native one raises `status` events over an
  /// `EventChannel` from Kotlin, while the WebView one is a Dart widget with no
  /// native side to raise anything — and a QA screenshot has to look the same
  /// whichever engine produced it. The section owns the readout, so the section
  /// owns the callback; see [ShoePreviewWebView.onStatus].
  final ValueChanged<String>? onEngineStatus;

  /// **How long the box may sit untouched before it demonstrates the gesture**
  /// ([ShoePreviewGestureHint]).
  ///
  /// Ten seconds is the owner's number, and it is deliberately longer than
  /// `<model-viewer>`'s own prompt (3 s, which stays off here — see
  /// `ShoePreviewWebView`'s `interactionPrompt`): the customer who opens this from
  /// a photograph is *reading* a page, and a hand waving over the shoe after three
  /// seconds is an interruption rather than a rescue. Ten is past the point where a
  /// still shoe has been mistaken for a picture, which is the fault this answers.
  ///
  /// A parameter-of-the-build rather than a hidden literal for the same reason the
  /// rest of this file's numbers are: the widget test waits it out with
  /// `tester.pump(ShoePreview3D.hintAfterIdle)`, so the wait can be asserted without
  /// a stopwatch.
  static const Duration hintAfterIdle = Duration(seconds: 10);

  /// **How long after the engine reports a draw the box waits before it reads its
  /// own pixels.**
  ///
  /// Enough for a compositor to have presented a frame and for `loaded` to mean a
  /// picture rather than a scene — and short enough that the cartoon hand of
  /// [ShoePreviewGestureHint] (which appears after [hintAfterIdle] of stillness)
  /// cannot be in the picture, because a hint is not a shoe.
  static const Duration paintCheckDelay = Duration(milliseconds: 1500);

  /// **The floor below which a captured box counts as empty.**
  ///
  /// Pinned as a name because it is a decision, not a magic number: the failure it
  /// exists for leaves the box *one* colour (the Flutter page behind a platform
  /// view that rendered into nothing — measured on the owner's P30 Pro), while any
  /// drawing of a shoe — even a white shoe on a white stage — carries shading, a
  /// shadow and an edge, which is dozens to hundreds of distinct colours in the
  /// same region (the native renderer on that phone measures 459 on the glass).
  /// Twelve is far from both.
  static const int blankBoxColourFloor = 12;

  @override
  State<ShoePreview3D> createState() => _ShoePreview3DState();
}

class _ShoePreview3DState extends State<ShoePreview3D> {
  late final ShoePreviewChannel _channel =
      widget.channel ?? const ShoePreviewChannel();

  /// **The box's own pixels.** The only witness in this app that can see a platform
  /// view which rendered and never arrived — see [kWebViewBlankBoxReason] for the
  /// phone that produced that verdict, and [_checkPaint] for what is measured.
  final GlobalKey _boxKey = GlobalKey();

  /// Reads the box's picture as raw RGBA, or null when there is nothing to read.
  ///
  /// Split out from [_checkPaint] so the *decision* can be exercised without a
  /// raster thread — see [ShoePreview3D.pixelProbeOverride].
  Future<Uint8List?> _captureBoxPixels() async {
    final boundary = _boxKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    try {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      // A capture that fails says nothing about the phone, and must never become a
      // verdict — a frame that has not painted yet, a boundary whose layer is not on
      // screen (the box is paused, or gone).
      return null;
    }
  }

  /// One shot per engine mount, so a rebuild cannot turn one picture into a loop.
  bool _paintChecked = false;

  /// The one pending picture, held so [dispose] can cancel it — a timer that outlives
  /// its box is a leak, and a test suite is the first place that shows.
  Timer? _paintTimer;

  /// Passes an engine line up, and starts the pixel check the moment the page says
  /// it drew.
  void _onEngineLine(String line) {
    widget.onEngineStatus?.call(line);
    if (shoePreviewWebViewLoaded(line)) _schedulePaintCheck();
  }

  @override
  void initState() {
    super.initState();
    // Before the handover, and before the view exists (the plugin parks it): the readout has to be
    // on for a view whose model never arrives, which is the state a failed load leaves behind.
    if (widget.diagnostics) {
      unawaited(_channel.setDiagnostics(true));
    }
    _handOver();
    // The countdown to the gesture tutorial starts with the box rather than with
    // the model: the shoe is on screen within a frame, and a wait that began when
    // the bytes arrived would be a different number on every connection.
    _restartIdleHint();
    if (!widget.useWebViewEngine) _scheduleNativePaintCheck();
  }

  @override
  void didUpdateWidget(covariant ShoePreview3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different model (a colour variant swapping the asset, a republished
    // version) means different bytes: hand the new one over. Same bytes, no call.
    if (oldWidget.model.modelId != widget.model.modelId ||
        oldWidget.model.path != widget.model.path) {
      _handOver();
    }
    // ⚠️ The ladder moved this box onto the other engine, and it must be measured
    // too: the native renderer's own reading is what proves the instrument can see
    // a *working* platform view, without which "the capture is empty" would be a
    // claim about the instrument rather than about the phone.
    if (oldWidget.useWebViewEngine != widget.useWebViewEngine) {
      _paintChecked = false;
      if (!widget.useWebViewEngine) _scheduleNativePaintCheck();
    }
    if (widget.paused != oldWidget.paused) {
      // AR is on top (or has just come back). The tutorial is not shown to a
      // customer looking at a camera, and coming back starts a fresh wait rather
      // than showing a hand the instant the box reappears.
      if (widget.paused) {
        _idleTimer?.cancel();
        _idleTimer = null;
        if (_hintVisible) setState(() => _hintVisible = false);
      } else {
        _restartIdleHint();
      }
    }
  }

  /// The brightness the stage was last handed over for, so a rebuild that did not
  /// change it re-sends nothing.
  Brightness? _stageSent;

  /// The countdown to [ShoePreviewGestureHint], or null while none is running.
  ///
  /// It is restarted — not resumed — by every touch that ends, so the wait is
  /// always a full [hintAfterIdle] of stillness.
  Timer? _idleTimer;

  /// True while the gesture tutorial is up. Owned here rather than inside the
  /// hint so the same `Listener` that dismisses it can also be the thing that
  /// sees the touch at all.
  bool _hintVisible = false;

  /// **Whether the box has something to draw**, i.e. whether a gesture tutorial
  /// over it would be teaching anything.
  ///
  /// ⚠️ Only the WebView engine can be in the other state, and it says so in words
  /// (`'The 3D model is not on this device.'`): the bytes can be evicted between the
  /// page's prefetch and this mount. The check is that engine's own
  /// ([shoePreviewModelOnDisk], shared rather than re-spelled), and it is skipped
  /// when a `viewBuilder` stands in for the engine — a test seam is not a file, and
  /// asserting one would make every test mount a fixture on disk.
  ///
  /// The native engine has no equivalent state to ask about: a renderer that cannot
  /// draw takes the whole section off the page before this widget is built
  /// ([ShoePreviewSection]), and a load that fails on a renderer that *can* draw
  /// leaves an empty stage that nothing reports — see [ShoePreviewHint].
  bool get _engineDraws {
    if (widget.paused) return false;
    if (widget.viewBuilder != null) return true;
    if (!widget.useWebViewEngine) return true;
    return shoePreviewModelOnDisk(widget.model);
  }

  /// Schedules the box's one picture of itself, [#paintCheckDelay] after the page
  /// says it drew.
  void _schedulePaintCheck() {
    if (_paintChecked) return;
    _paintChecked = true;
    _paintTimer = Timer(ShoePreview3D.paintCheckDelay, () => unawaited(_checkPaint()));
  }

  /// Schedules the same picture on the native engine, which reports its state only
  /// in a QA build — so the box cannot wait to be told and waits a fixed beat
  /// instead. It is the control for the WebView verdict, logged and never acted on:
  /// the native renderer is the last rung, so there is nothing below it to hand the
  /// box to.
  void _scheduleNativePaintCheck() {
    if (_paintChecked) return;
    _paintChecked = true;
    _paintTimer = Timer(
      ShoePreview3D.paintCheckDelay + const Duration(seconds: 3),
      () => unawaited(_checkPaint()),
    );
  }

  /// **Reads the box's own pixels, because nothing else in the app can see the
  /// fault this was written for.**
  ///
  /// `loaded` means the model is in `<model-viewer>`'s scene; it does **not** mean a
  /// pixel reached the glass, and on the owner's P30 Pro (2026-10-07) it did not: the
  /// page reported `gl:webgl2` and `loaded box=424x672` while the screen measured
  /// pure `#FFFFFF` in the box — the Flutter page behind a platform view whose
  /// surface never arrived. The page cannot detect that. A capture of the box can,
  /// and the question it answers is the cheap one: *does this region contain more
  /// than a handful of colours?*
  ///
  /// ⚠️ **Only the WebView engine's answer is a verdict**, and only when the picture
  /// is flat ([ShoePreview3D.blankBoxColourFloor]): the line goes up the same channel
  /// the page's lines use (see [kShoePreviewBlankBoxLine]) and the section's ladder
  /// does the rest. The native engine's reading is a log line, because there is no
  /// engine below it to fall back to.
  Future<void> _checkPaint() async {
    final override = widget.pixelProbeOverride;
    final bytes = override != null ? override() : await _captureBoxPixels();
    if (bytes == null) return;
    final pixels = measureBoxPixels(bytes);
    if (pixels.sampled == 0) return;
    final flat = pixels.colours < ShoePreview3D.blankBoxColourFloor;
    final engine = widget.useWebViewEngine ? 'webview' : 'native';
    final verdictIsPossible = widget.pixelCaptureSeesPlatformView;
    final line = '${kShoePreviewBlankBoxLine}distinct=${pixels.colours} '
        'dark=${pixels.darkPercent}%';
    navDiag(
      '[preview] box pixels: $line flat=$flat ($engine'
      '${verdictIsPossible ? '' : ' · a hybrid-composited view is not in this capture'})',
    );
    // See [ShoePreview3D.pixelCaptureSeesPlatformView]: where the capture cannot
    // contain the platform view, a flat reading says nothing about the phone and
    // must not move the ladder.
    if (flat && widget.useWebViewEngine && mounted && verdictIsPossible) {
      widget.onEngineStatus?.call(line);
    }
  }

  /// Starts the countdown to the gesture tutorial.
  ///
  /// Never while paused: the box is not on screen then (the AR screen is), and the
  /// idle face must not come back with a hand waving over it.
  void _restartIdleHint() {
    _idleTimer?.cancel();
    if (widget.paused) return;
    _idleTimer = Timer(ShoePreview3D.hintAfterIdle, () {
      if (!mounted || widget.paused || !_engineDraws) return;
      setState(() => _hintVisible = true);
    });
  }

  /// A finger has gone down on the box: whatever the customer is doing, they have
  /// found the interaction, so the tutorial has done its job.
  void _touchStarted(PointerDownEvent event) {
    _idleTimer?.cancel();
    if (_hintVisible) setState(() => _hintVisible = false);
  }

  /// The finger is gone (or the gesture was cancelled): the box is idle again, so
  /// the countdown restarts from full — see [hintAfterIdle].
  void _touchEnded(PointerEvent event) => _restartIdleHint();

  /// **Tells the renderer which stage to clear to** — the same tone this widget
  /// paints when no engine is mounted ([ShoePreviewIdle]).
  ///
  /// ⚠️ **It is called from `build`, and that is a finding rather than a
  /// preference.** A brightness change repaints the tree element by element
  /// (`AppThemeRefresh.rebuildAll` marks each element dirty), so it neither
  /// re-creates this state (`initState`) nor updates this widget
  /// (`didUpdateWidget`) — a customer who flips the theme with the viewer open
  /// would leave the native renderer clearing to the old colour, which is exactly
  /// the mismatch this exists to prevent. The guard keeps it to one call per
  /// change, and the call is best-effort like every other one on this channel.
  void _handOverStage() {
    final brightness = AppBrightness.current;
    if (_stageSent == brightness) return;
    _stageSent = brightness;
    unawaited(_channel.setBackground(AppConstants.stage));
  }

  void _handOver() {
    // `setModel` swallows `MissingPluginException` and platform errors by
    // design, so there is nothing to await and nothing to report here.
    unawaited(_channel.setModel(widget.model));
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _paintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The stage colour follows the customer's appearance, and a theme flip has to
    // reach a renderer that already exists: see [_handOverStage] for why this is
    // not done in `initState`.
    _handOverStage();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The header keeps the page's gutter even when the box does not — it is
        // text, and text at 0 px from a screen edge is a different widget's
        // problem. See [bleed].
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.bleed ? kShoePreviewGutter : 0,
          ),
          child: Row(
            children: [
              Icon(
                Icons.threed_rotation,
                size: 18,
                color: AppConstants.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'View in 3D',
                style: AppConstants.bodyStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                'Drag to rotate',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          // A stage that is the page's own surface, edge to edge, is square:
          // rounding it would only show the page's colour in the corners it
          // does not cover. Inset, it stays the card it has always been.
          borderRadius: BorderRadius.circular(widget.bleed ? 0 : 16),
          child: SizedBox(
            width: double.infinity,
            height: widget.height,
            child: Listener(
              // ⚠️ **Raw pointer events rather than a gesture.** Both engines hand
              // the gesture arena to their platform view (`EagerGestureRecognizer`
              // on `AndroidView`, and the WebView widget's own), so a
              // `GestureDetector` here would never win a drag — and, worse, would
              // try: it would claim the arena on the tap and the shoe would stop
              // turning. A `Listener` is not a competitor; it observes the pointer
              // without asking for it, and `translucent` keeps the platform view in
              // the hit test underneath (a `deferToChild` Listener would miss every
              // event on a frame where the view has nothing to hit).
              behavior: HitTestBehavior.translucent,
              onPointerDown: _touchStarted,
              onPointerUp: _touchEnded,
              onPointerCancel: _touchEnded,
              // ⚠️ The boundary that makes the fault this feature cannot otherwise
              // see *visible*: see [_checkPaint] and [kWebViewBlankBoxReason].
              child: RepaintBoundary(
                key: _boxKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.paused ? const ShoePreviewIdle() : _view(),
                    // Only ever painted over a box that can draw and is on screen —
                    // see [_engineDraws]; the pill itself is `IgnorePointer`, so the
                    // drag it is teaching still reaches the renderer.
                    if (_hintVisible && _engineDraws)
                      const ShoePreviewGestureHint(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _view() {
    final injected = widget.viewBuilder;
    if (injected != null) return injected();

    // ⚠️ **Which engine draws is a compile-time decision**
    // (`AppConstants.shoePreviewWebViewEnabled`) and it is asked *before* the
    // platform check below, because the two engines refuse different platforms:
    // the native view has no iOS implementation at all, while the WebView engine
    // is Android-only here only because the gate is (`resolveShoePreview`).
    //
    // ⚠️ The flag is handed down rather than read here, because the *section* owns
    // the ladder: a WebView engine that reports it cannot draw flips this to
    // `false` and rebuilds the box around the native renderer — see
    // `ShoePreviewSection`.
    if (widget.useWebViewEngine) {
      final standIn = widget.webViewBuilder;
      if (standIn != null) return standIn(_onEngineLine);
      return ShoePreviewWebView(
        model: widget.model,
        diagnostics: widget.diagnostics,
        // The QA line goes to the section's readout, which is where the native
        // engine's `status` events land too — one surface, two engines. ⚠️ It goes
        // through [_onEngineLine] rather than straight up, because the box has to
        // see the page's `loaded` itself: that line is what starts the one pixel
        // check this engine needs ([_checkPaint]).
        onStatus: _onEngineLine,
      );
    }

    // iOS has no renderer at all, and an `AndroidView` elsewhere throws instead
    // of degrading. The gate already refuses non-Android platforms; this is the
    // second line of the same guard.
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const ShoePreviewIdle();
    }

    return AndroidView(
      viewType: kShoePreviewViewType,
      // The box is dragged and pinched, so the gesture arena has to be handed
      // over — a preview that cannot be turned is a picture.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }
}

/// **The gesture tutorial** — what the box shows a customer who has not touched
/// it for `ShoePreview3D.hintAfterIdle`.
///
/// ⚠️ **Why it exists, stated as the fault it answers.** The box shipped with one
/// line of instruction, in the section's header, above the frame: "Drag to rotate".
/// That line is at the *edge* of a 240–520 px surface whose whole content is a shoe
/// that already spins on its own (the engines' idle rotation), so a customer who
/// reads it as a picture — a picture being the thing every other product surface on
/// this page is — taps the AR pill and never learns the shoe turns. The hint is the
/// same instruction moved to where the eyes are, and given the gesture rather than
/// the words: a hand sweeps across the pill, over the shoe, exactly the way the
/// renderer expects to be dragged.
///
/// **It is one widget for both engines, and that is a finding rather than tidiness.**
/// `AndroidView` and `webview_flutter_android` both compose through **Texture Layer
/// Hybrid Composition** (`displayWithHybridComposition` defaults to `false` in the
/// package; the Flutter `AndroidView` widget defaults to the texture path), which is
/// the mode that lets Flutter paint *over* a platform view. So the tutorial is Dart,
/// in a `Stack` above whichever engine is running — no native overlay in Kotlin, no
/// CSS/JS injection into the `<model-viewer>` page, and therefore no second visual
/// language to keep in step with this one.
///
/// **What it deliberately does not do.**
///
///   * **It never eats the gesture it teaches** (`IgnorePointer`). There is no
///     "Got it" button either: the way to dismiss it is to do the thing, and the box's
///     own `Listener` hides it on the first touch — including the touch that starts a
///     drag, which therefore still turns the shoe on the same finger down.
///   * **It is silent to a screen reader** (`ExcludeSemantics`). The header already
///     carries "Drag to rotate" as text, and the surface under this pill is a platform
///     view a screen reader cannot turn at all — announcing a gesture with no
///     accessible equivalent would be a promise this feature cannot keep. The AR pill
///     below the box is the accessible route to the same shoe.
///   * **It honours reduced motion by holding still, not by disappearing.**
///     `MediaQuery.disableAnimations` stops the sweep (and parks the hand mid-travel)
///     while the words and the glyph stay: the tutorial is the only thing on this
///     screen that says a finger does anything, so a customer who asked for less
///     motion is not the one to hide it from.
class ShoePreviewGestureHint extends StatefulWidget {
  const ShoePreviewGestureHint({super.key});

  /// The line's label — spelled once, asserted in the widget test, and the same
  /// words the section's header uses for the gesture it advertises.
  static const String dragLabel = 'Drag to rotate';

  /// The second gesture, and the one nothing else on the surface mentions: both
  /// engines answer a pinch (`ScaleGestureDetector` on the native side,
  /// `cameraControls` in `<model-viewer>`), and a customer who never pinches never
  /// learns the shoe can be brought closer.
  static const String pinchLabel = 'Pinch to zoom';

  @override
  State<ShoePreviewGestureHint> createState() => _ShoePreviewGestureHintState();
}

class _ShoePreviewGestureHintState extends State<ShoePreviewGestureHint>
    with SingleTickerProviderStateMixin {
  /// One sweep of the hand. `repeat(reverse: true)` — right, back, again — for as
  /// long as the pill is up, which is until the customer touches the box.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in `initState`: `MediaQuery` is an inherited widget, and
    // this is the callback that may consult one.
    if (MediaQuery.disableAnimationsOf(context)) {
      // Parked mid-travel, so the glyph reads as *in motion* in a screenshot and in
      // a still frame, without anything moving.
      _sweep.stop();
      _sweep.value = 0.5;
    } else if (!_sweep.isAnimating) {
      _sweep.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              // The dark-glass control the 3D icon on the product photo already
              // wears (`Sole3DIconButton`): the pill sits on an unknown stage — a
              // light neutral in light mode, near-black in dark — and pinned black
              // glass with pinned white ink is legible on both, which no token can
              // be.
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GestureLine(
                  label: ShoePreviewGestureHint.dragLabel,
                  // The hand travels, the words do not: the gesture is the part a
                  // customer cannot guess from a still shoe.
                  icon: AnimatedBuilder(
                    animation: _sweep,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(
                        -_hintSweepPx +
                            2 * _hintSweepPx * Curves.easeInOut.transform(_sweep.value),
                        0,
                      ),
                      child: child,
                    ),
                    child: const Icon(Icons.swipe, size: 18, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                const _GestureLine(
                  label: ShoePreviewGestureHint.pinchLabel,
                  // Held still above the second line rather than animated: one
                  // moving thing in a pill this small is a lesson, two is a
                  // distraction.
                  icon: Icon(Icons.pinch, size: 18, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// **What a captured box contains, in the two numbers that can tell a shoe from
/// nothing**: how many distinct colours it holds (5 bits per channel) and what
/// share of it is dark ink.
///
/// A named record rather than a bare pair, and a pure function rather than a body
/// inside the capture, because it is the *decision* that has to be testable — a
/// raster thread is not something a widget test can always give it
/// (`RenderRepaintBoundary.toImage` needs the real event loop).
class ShoePreviewBoxPixels {
  const ShoePreviewBoxPixels({
    required this.colours,
    required this.darkPercent,
    required this.sampled,
  });

  /// Distinct colours, quantised to 5 bits per channel — the same quantisation the
  /// device measurements in this file's history used, so a log line and a phone
  /// screenshot can be compared without converting anything.
  final int colours;

  /// Share of sampled pixels below half luminance, rounded to a percent.
  final int darkPercent;

  /// How many pixels were read, so a caller can refuse to judge an empty image.
  final int sampled;
}

/// Measures raw RGBA bytes — see [ShoePreviewBoxPixels].
///
/// ⚠️ **Every fourth pixel** (`stride` in bytes, four bytes per pixel): a 424x672
/// box holds 285,000 of them, the answer cannot change between neighbours, and the
/// readback is a GPU stall worth bounding.
ShoePreviewBoxPixels measureBoxPixels(Uint8List rgba, {int stride = 16}) {
  final seen = <int>{};
  var dark = 0;
  var sampled = 0;
  for (var i = 0; i + 3 < rgba.length; i += stride) {
    final r = rgba[i];
    final g = rgba[i + 1];
    final b = rgba[i + 2];
    seen.add((r >> 3) << 10 | (g >> 3) << 5 | (b >> 3));
    if ((r * 299 + g * 587 + b * 114) ~/ 1000 < 128) dark++;
    sampled++;
  }
  return ShoePreviewBoxPixels(
    colours: seen.length,
    darkPercent: sampled == 0 ? 0 : (100 * dark / sampled).round(),
    sampled: sampled,
  );
}

/// How far the sweeping hand travels each way, in logical pixels.
///
/// Deliberately small: the pill is roughly 150 px wide and the hand is 18 px, so
/// ±8 px is a movement a customer reads as "back and forth" rather than as the
/// glyph drifting out of its own line.
const double _hintSweepPx = 8;

/// One gesture in [ShoePreviewGestureHint]: a glyph, a gap, its words.
class _GestureLine extends StatelessWidget {
  const _GestureLine({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fixed width so the words of the two lines start at the same x — the
        // animated hand must not shift the text it sits beside.
        SizedBox(width: 26, child: Center(child: icon)),
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// The box's face while no native view is mounted: the same height, and the same
/// colour the renderer clears to.
///
/// ⚠️ The colour is not decorative, and it is no longer fixed. `ShoePreviewIdle`
/// paints [AppConstants.stage] — the brightness-aware token the WebView engine's
/// page and the native renderer's `Renderer.ClearOptions.clearColor` are both set
/// from (`ArTryOnView.setBackground`) — so the box does not flash from one tone to
/// another as the engine starts, and it keeps the layout honest: a preview that
/// never loads looks exactly like a preview that has not loaded *yet*, which is
/// the truth for both. Before this it was pinned to the renderer's `#0E0F12`
/// in both modes, which framed the shoe on a white page as a black rectangle.
class ShoePreviewIdle extends StatelessWidget {
  const ShoePreviewIdle({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: AppConstants.stage);
  }
}

/// **The 3D icon sitting in the product photo's lower-right corner** — the
/// product page's whole 3D entry point (`ShoePreviewScreen`).
///
/// It replaced the pinned "Try On in AR" pill on 2026-10-01: the pill was a
/// full-width bar that took the bottom of every product page and asked for a
/// decision before it offered a look, while a shoe is a thing a shopper wants to
/// *turn*. The icon rides on the photograph the customer is already looking at,
/// only on a product whose model is verified on disk, and the camera behind it
/// stays one tap deeper (inside the viewer).
///
/// The chip is dark glass rather than an accent fill for one reason: it sits on
/// an unknown photograph, and the hero's own back/share buttons are already
/// black-at-30% circles — a third control on the same photo should read as a
/// sibling of those rather than as a new colour. Pinned light ink, pinned black
/// fill, so it is legible on a white studio shot and on a dark one.
class Sole3DIconButton extends StatelessWidget {
  const Sole3DIconButton({
    super.key,
    required this.onPressed,
    this.icon = Icons.threed_rotation,
    this.tooltip = 'View in 3D',
  });

  final VoidCallback onPressed;

  /// The glyph. `threed_rotation` is the same one the box's own header uses, so
  /// the icon the customer taps and the surface it opens share a symbol.
  final IconData icon;

  /// For the long-press tooltip and the accessibility label — an icon with no
  /// words is invisible to a screen reader, and this is the only way into the
  /// 3D viewer.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      // The long-press aid is for a sighted thumb; the accessible name comes from
      // the explicit `Semantics` below, and letting the tooltip add its own would
      // have a screen reader say "View in 3D" twice.
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one visible word for the states that would otherwise be silence: a
/// prefetch that failed and can be retried, a renderer that cannot draw.
///
/// It is deliberately a line of text, not a card or an error dialog — the page
/// is a shop, and most products have no model at all and *no* hint. This exists
/// only where the page could have shown a box and provably cannot: a customer
/// staring at pill-only with no way to know why is a bug report we cannot
/// answer (there is no logcat on the phones this market holds).
class ShoePreviewHint extends StatelessWidget {
  const ShoePreviewHint({
    super.key,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final String message;

  /// A second, dimmer line under [message] — **the measured renderer facts, and
  /// it has exactly one intended reader: a QA build on the owner's phone.**
  ///
  /// It is a separate field rather than a longer [message] on purpose: the
  /// honest sentence is a fact the customer is owed and the numbers are a
  /// diagnosis, and keeping them apart is what lets one be shown without the
  /// other (`ShoePreviewSection.showDiagnostics`).
  final String? detail;

  /// The one action the state allows — `Retry` after a failed prefetch. Absent
  /// where there is genuinely nothing to do (an unsupported renderer).
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppConstants.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.8),
                  ),
                ),
                if (detail != null && detail!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      detail!,
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        color: AppConstants.secondary.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// **The renderer's own heartbeat, as one dim line under the box.**
///
/// It is the QA half of a fault that could not be diagnosed any other way. The
/// phone it was written for has locked developer options, so there is no logcat;
/// and the two symptoms being chased — a box that stops presenting while its loop
/// keeps running, and an app that dies on the *second* open of the same box —
/// destroy their own evidence as they happen. So the renderer prints the facts a
/// screenshot can carry (loop, presents per second, swap chain and how often it
/// was rebuilt, surfaces, engine count, touches received), and its very first line
/// after a crash is the previous process's last words.
///
/// Never customer copy: it exists only when [ShoePreview3D.diagnostics] does, and
/// the native side is never even asked for it in a build that does not turn it on.
class _QaStatusLine extends StatelessWidget {
  const _QaStatusLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppConstants.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppConstants.bodyStyle(
          fontSize: 10,
          color: AppConstants.secondary.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// **A QA build says so, on the page — and says which switches are on.**
///
/// It exists because of the one screenshot that matters in this investigation:
/// `SHOE_PREVIEW_ALLOW_LEVEL1` lets the renderer attempt a load that may abort
/// the process (F22), and `SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1` asks the renderer
/// itself to come up at `FEATURE_LEVEL_1`, so it must never be possible to
/// confuse a build that has either with a customer's. A line above the box is
/// unmistakable in a photo, where a log line is not — and this phone has no
/// logcat at all.
///
/// ⚠️ **The text is composed rather than fixed, because the two switches mean
/// different things** and a photo has to say which one produced it: a *lowered*
/// engine that then loaded a shoe is the experiment succeeding, while the load
/// override alone on a modern phone measures nothing at all.
class ShoePreviewQaBanner extends StatelessWidget {
  const ShoePreviewQaBanner({
    super.key,
    this.loadOverride = AppConstants.shoePreviewAllowLevel1,
    this.engineLowered = AppConstants.shoePreviewLowerEngineToLevel1,
  });

  /// Whether the load the guard forbids is permitted on this build.
  final bool loadOverride;

  /// Whether this build asked the renderer itself to come up at level 1.
  final bool engineLowered;

  /// The sentence, from whichever switches are on.
  ///
  /// A constructor parameter as well as a switch, the same shape
  /// `ShoePreviewSection.showDiagnostics` uses and for the same reason: the
  /// wording is the evidence a screenshot carries, so it is asserted rather than
  /// eyeballed.
  static String textFor({
    required bool loadOverride,
    required bool engineLowered,
  }) =>
      <String>[
        'QA build',
        if (engineLowered) 'engine pinned to level 1',
        if (loadOverride) 'level-1 load override on — may abort the process',
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppConstants.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        textFor(loadOverride: loadOverride, engineLowered: engineLowered),
        style: AppConstants.bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppConstants.secondary.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

/// **The section: the 3D box, and what to say when the renderer refuses it.**
///
/// The box, its honest silences (the refusal sentence, the QA banner, the
/// measured facts behind [showDiagnostics]) — and nothing to tap.
///
/// ⚠️ **The AR escalation used to be this widget's own last child, and moved to
/// the viewer's bottom edge on 2026-10-03.** Under a box that now fills most of
/// the screen, a pill in the flow left a dead half-page beneath it; the owner
/// asked for the pill at the bottom of the page instead, so `ShoePreviewScreen`
/// draws it. The pairing the old arrangement existed to protect still holds, and
/// holds structurally rather than by convention: the *viewer* mounts the box and
/// draws the pill in the same build, so a product that resolves no model gets
/// neither (`resolveShoePreview`).
///
/// ⚠️ **A refusal is this widget's whole second half.** The native renderer
/// refuses to load an asset below `FEATURE_LEVEL_2` (`kRendererUnsupportedReason`)
/// rather than abort the process on it, and when that report arrives the box is
/// swapped for the not-supported line: the section stays mounted, saying why. The
/// AR entry that used to have to survive this — the owner's decision of
/// 2026-09-30, after a real phone showed the customer the whole section
/// vanishing — is now outside this widget entirely, which is the stronger form of
/// the same guarantee: there is no branch here that can drop it. See
/// `kRendererUnsupportedReason` for the crash that made the refusal necessary.
///
/// ⚠️ **And since 2026-10-07 the section owns the engine ladder, because a
/// refusal is no longer the only way a box ends up with nothing.** The shipped
/// engine is the WebView one, and a WebView cannot draw where its phone gives it
/// no WebGL2 context — the owner's P30 Pro is exactly that phone (a blank stage,
/// with every other phone showing the shoe). So the section watches the engine it
/// mounted: the page's `gl:` probe, the element's `error`, or
/// [kShoePreviewWebViewLoadDeadline] passing with no line at all each mean the same
/// thing — this phone's WebView cannot draw — and the box is rebuilt around the
/// **native** renderer, the one measured to draw this very shoe on that very
/// phone. The ladder moves one way and only on evidence, and when even that phone's
/// native renderer is off the table (`ShoePreviewFallbackGuard`, because it has
/// already killed this app once inside the load) the honest sentence above is what
/// is left — which is why both states say it in the same words.
class ShoePreviewSection extends StatefulWidget {
  const ShoePreviewSection({
    super.key,
    required this.model,
    this.channel,
    this.viewBuilder,
    this.height = 240,
    this.bleed = false,
    this.paused = false,
    this.events,
    this.webViewBuilder,
    this.showDiagnostics = AppConstants.shoePreviewDiagnosticsEnabled,
    this.useWebViewEngine = AppConstants.shoePreviewWebViewEnabled,
  });

  final TryOnModelSpec model;

  final ShoePreviewChannel? channel;
  final Widget Function()? viewBuilder;

  /// See [ShoePreview3D.webViewBuilder] — forwarded rather than re-spelled, so
  /// the box a test drives and the box this section mounts are the same box.
  final Widget Function(ValueChanged<String> onStatus)? webViewBuilder;

  final double height;

  /// **Whether the page has handed this section its full width, so that only the
  /// box takes it** — see [ShoePreview3D.bleed].
  ///
  /// The box spans the page edge to edge; everything else this section draws —
  /// the QA banner, the refusal sentence, the QA readout — keeps the page's
  /// gutter ([kShoePreviewGutter]) by insetting itself. A section that bled its
  /// *text* too would put a sentence against the screen edge every time the
  /// renderer refused.
  final bool bleed;

  /// See [ShoePreview3D.paused]. The box is the only thing this flag reaches;
  /// the AR entry is the viewer's, and it keeps working while the box is paused
  /// — it is the thing being opened at that moment.
  final bool paused;

  /// Test seam: the preview's native event stream, instead of the channel's own.
  final Stream<Map<String, dynamic>>? events;

  /// Whether a failure's **measured facts** are shown under the honest sentence.
  ///
  /// Defaults to `AppConstants.shoePreviewDiagnosticsEnabled` — off for every
  /// customer build, and a constructor parameter as well as a switch so the two
  /// behaviours can both be asserted without a rebuild. See
  /// `_diagnosticDetail` for what the line carries and why it exists.
  final bool showDiagnostics;

  /// **Which engine the box is *started* with.** See
  /// [ShoePreview3D.useWebViewEngine] — forwarded rather than re-decided, so the
  /// section and the box can never disagree about which engine is running.
  ///
  /// ⚠️ **It is the ladder's first rung, not its verdict.** The section hands the
  /// box this value and then watches the engine it produces: a WebView that cannot
  /// draw here moves the box to the native renderer without the caller's
  /// involvement (see `_failOver`), so the engine a running box is using is not
  /// always the one this flag asked for.
  final bool useWebViewEngine;

  @override
  State<ShoePreviewSection> createState() => _ShoePreviewSectionState();
}

class _ShoePreviewSectionState extends State<ShoePreviewSection> {
  late final ShoePreviewChannel _channel =
      widget.channel ?? const ShoePreviewChannel();

  StreamSubscription<Map<String, dynamic>>? _events;

  /// True once the renderer has said it cannot draw. Nothing un-hides it: the
  /// feature level of a running device does not change.
  bool _unsupported = false;

  /// The native `reason` and `message` of the last failure, kept **only** for the
  /// QA readout ([ShoePreviewSection.showDiagnostics]). A customer build acts on
  /// the one reason that takes the box off the page and forgets the rest; a QA
  /// build has to carry the numbers on screen, because the phone this was written
  /// for (a P30 Pro with locked developer options) has no reachable logcat.
  String? _errorReason;
  String? _errorMessage;

  /// **The ladder: which engine the box is drawn with right now.**
  ///
  /// It starts at [ShoePreviewSection.useWebViewEngine] and moves **one way** — to
  /// the native renderer — when the WebView engine reports that it cannot draw this
  /// model on this phone ([shoePreviewWebViewCannotDrawReason], or
  /// [kShoePreviewWebViewLoadDeadline] passing with nothing said). It never moves
  /// back: a phone's WebView does not learn to hand out a WebGL2 context, and
  /// re-trying would put a blank box in front of a customer on every product.
  late bool _webViewEngine = widget.useWebViewEngine;

  /// True once the WebView engine has proved it cannot draw on this phone.
  bool _webViewCannotDraw = false;

  /// Why, in the ladder's own vocabulary — the label half of the verdict.
  String? _webViewReason;

  /// The page line the verdict was read from, so a QA screenshot carries the
  /// evidence (`gl:webgl1`, `error — loadfailure`) rather than only the label.
  String? _webViewLine;

  /// True while the fallback decision is in flight, so a page that repeats its
  /// verdict cannot start two of them.
  bool _failingOver = false;

  /// **True when the native fallback is latched off on this phone** — the last
  /// attempt to use it ended in a process death inside the load, so this phone does
  /// not get a second one ([ShoePreviewFallbackGuard]). Only meaningful together
  /// with [_webViewCannotDraw]: with the WebView still drawing, the latch is never
  /// consulted.
  bool _fallbackBlocked = false;

  /// True once the page has said the model loaded — the one line that keeps the
  /// deadline from ever being armed again for this box.
  bool _webViewDrew = false;

  /// The clock that turns "the page never spoke" into a verdict — armed when this
  /// section hands the box the WebView engine, disarmed by the page's own `loaded`
  /// line.
  Timer? _webViewDeadline;

  @override
  void initState() {
    super.initState();
    _events = (widget.events ?? _channel.events).listen(_onEvent);
    _armWebViewDeadline();
  }

  @override
  void didUpdateWidget(covariant ShoePreviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A caller that changes the engine asks for a fresh ladder, not for the
    // verdict taken about the engine it replaced. Nothing in the app flips this at
    // runtime (it is a compile-time switch); the parameter exists so tests can
    // reach both branches, and this is what keeps a reused `State` honest.
    if (oldWidget.useWebViewEngine != widget.useWebViewEngine) {
      _webViewEngine = widget.useWebViewEngine;
      _webViewCannotDraw = false;
      _failingOver = false;
      _fallbackBlocked = false;
      _webViewReason = null;
      _webViewLine = null;
      _webViewDrew = false;
      _armWebViewDeadline();
    }
    // ⚠️ **A hidden box is not a slow one.** `paused` is set while the AR screen is
    // on top, and the box is unmounted then — so a clock left running would time out
    // a page that was never asked to draw and move the ladder on a verdict about
    // nothing. It stops while the box is hidden and starts fresh when it comes
    // back, which is also the honest reading of "how long has this page been
    // failing?": from the moment it was on screen.
    if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        _webViewDeadline?.cancel();
        _webViewDeadline = null;
      } else {
        _armWebViewDeadline();
      }
    }
  }

  /// [kShoePreviewWebViewLoadDeadline] against a page that has not said `loaded`.
  ///
  /// ⚠️ **Armed once per engine mount, not from `build`.** A rebuild — a theme
  /// flip, the gesture tutorial appearing, a QA line landing — must not restart
  /// the clock, or a page that never speaks would reset its own deadline every
  /// time it produced any news at all.
  ///
  /// ⚠️ **And never against a box that has nothing to draw.** The bytes can be
  /// evicted between the page's prefetch and this mount, and the WebView engine is
  /// the only face that says so in words ("The 3D model is not on this device.").
  /// A clock running there would time that sentence out and hand the box to a
  /// renderer with no file to open — trading the one honest state this feature has
  /// for a blank stage.
  void _armWebViewDeadline() {
    _webViewDeadline?.cancel();
    _webViewDeadline = null;
    if (!_webViewEngine ||
        _webViewDrew ||
        widget.paused ||
        !shoePreviewModelOnDisk(widget.model)) {
      return;
    }
    _webViewDeadline = Timer(kShoePreviewWebViewLoadDeadline, () {
      unawaited(_failOver(
        kWebViewLoadTimeoutReason,
        'no load in ${kShoePreviewWebViewLoadDeadline.inSeconds}s',
      ));
    });
  }

  void _onEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString();
    if (type == 'modelLoaded') {
      // ⚠️ **The native renderer got past the load, and that is the whole latch.**
      // Every measured death on this feature sits *before* this event — the P30 Pro
      // and the vivo V2022 both stop at `load: entities added — applying the
      // transform` and the process goes with them — so an engine that reaches it is
      // one this phone survived, and the next launch may try the native fallback
      // again. It is read here, in every build, because the native side raises this
      // event unconditionally; the `status` heartbeat beside it is diagnostics-only,
      // and hanging the latch on that would leave every customer's phone latched
      // forever after one unlucky start.
      ShoePreviewFallbackGuard.clearAttempt();
      return;
    }
    if (type == 'status') {
      _recordStatus(event['data']);
      return;
    }
    if (type != 'error') return;
    final data = event['data'];
    final reason = data is Map ? data['reason']?.toString() : null;
    if (reason == null) return;
    // ⚠️ A non-refusal error is *silence* in a customer build: a preview that
    // failed to load a model it could have drawn is not a reason to take a working
    // surface off a product page. In a QA build it is the measurement — the
    // level-1 override's whole question is what happens after the refusal stops
    // refusing — so there it becomes a line of text like everything else.
    if (reason != kRendererUnsupportedReason && !widget.showDiagnostics) return;
    if (!mounted) return;
    setState(() {
      _unsupported = reason == kRendererUnsupportedReason;
      _errorReason = reason;
      _errorMessage = data is Map ? data['message']?.toString() : null;
    });
  }

  /// The renderer's own heartbeat (`status`), kept only when this build asked for
  /// it.
  ///
  /// It exists because two real-device faults are invisible to Dart: a box that
  /// **stops presenting while its loop keeps running** (the customer sees a still
  /// picture that no finger can move, and the *only* thing that distinguishes that
  /// from "touch never arrived" is a counter), and a crash on the *second* open
  /// of the same box, which takes the readout that would explain it down with the
  /// process — hence the `prev:` line, the last heartbeat of the previous run.
  /// Nothing is *driven* by it: it is a line of text in a QA build and never
  /// exists in a customer one (the native side is never asked).
  String? _statusLine;

  /// The WebView engine's own heartbeat, arriving as a callback instead of an
  /// event.
  ///
  /// Kept separate from [_recordStatus] because the payloads are different kinds
  /// of thing: a native `status` event carries structured counters
  /// (`loop=`, `present=`, `beginFail=`), while this is already a finished line.
  /// Folding them would mean inventing a fake `data` map for one of them.
  void _recordEngineLine(String line) {
    if (line.isEmpty) return;
    // ⚠️ **Classified before the readout's gate, and the ordering is the fix
    // rather than a detail.** `showDiagnostics` is off in every customer build, and
    // it used to be the first statement in this method — so the QA switch, not the
    // phone, would have decided whether a box falls back to the engine that can
    // draw. The builds it would have decided against are the only builds most
    // customers ever run.
    final reason = shoePreviewWebViewCannotDrawReason(line);
    if (reason != null) {
      unawaited(_failOver(reason, line));
    } else if (shoePreviewWebViewLoaded(line)) {
      // The model is on screen: the page has kept the one promise the deadline was
      // waiting for, and it is never asked again for this box (a theme flip does not
      // make a page that drew stop having drawn).
      _webViewDrew = true;
      _webViewDeadline?.cancel();
      _webViewDeadline = null;
    }
    if (!widget.showDiagnostics || !mounted || line == _statusLine) return;
    setState(() => _statusLine = line);
  }

  /// **The verdict arrives: the WebView engine cannot draw this model on this
  /// phone, so the box is handed to the native renderer** — unless this phone has
  /// already proved that the native renderer kills it, in which case the box says
  /// so instead of dying again.
  ///
  /// ⚠️ **Why a ladder at all, in one sentence:** each engine is blind where the
  /// other sees. The native renderer is the one measured to draw this shoe on the
  /// owner's P30 Pro (~57 fps) and the one measured to abort the process on a vivo
  /// V2022; `<model-viewer>` is the reverse — five clean opens on the vivo, and a
  /// blank box on any phone whose WebView cannot hand it a WebGL2 context. A box
  /// that only ever tries one of them cannot show a shoe on every phone, and the
  /// requirement is every phone.
  ///
  /// ⚠️ **The latch is read here, not in `build`** — it is a disk read, and the one
  /// place it can be awaited is the moment a verdict arrives, which is long after
  /// the first frame and never inside a build.
  Future<void> _failOver(String reason, String line) async {
    if (_failingOver || _webViewCannotDraw) return;
    _failingOver = true;
    _webViewDeadline?.cancel();
    _webViewDeadline = null;

    final blocked = await ShoePreviewFallbackGuard.blockedOrLoad();
    if (!mounted) return;

    if (blocked) {
      navDiag('[preview] webview cannot draw ($reason · $line) and the native '
          'fallback is latched off on this phone — saying so instead');
      setState(() {
        _webViewCannotDraw = true;
        _fallbackBlocked = true;
        _webViewReason = reason;
        _webViewLine = line;
        // The readout is the only witness on a phone with no logcat, and the
        // ladder's own move has to be on it: without this line a screenshot of a
        // refused box says "not supported" and nothing about why.
        if (widget.showDiagnostics) {
          _statusLine = 'ladder: webview → blocked · $reason · $line';
        }
      });
      return;
    }

    // ⚠️ **Written before the native view is mounted, and synchronously.** The
    // death this records happens inside the load — about a second from here on the
    // phones it was measured on — and it takes the process with it, so an async
    // write queued behind a platform channel would not be on disk when the evidence
    // was needed. See `ShoePreviewFallbackGuard`.
    ShoePreviewFallbackGuard.markAttempt();
    navDiag('[preview] webview cannot draw ($reason · $line) — falling back to '
        'the native renderer');
    setState(() {
      _webViewCannotDraw = true;
      _webViewReason = reason;
      _webViewLine = line;
      _webViewEngine = false;
      if (widget.showDiagnostics) {
        _statusLine = 'ladder: webview → native · $reason · $line';
      }
    });
  }

  void _recordStatus(Object? data) {
    if (!widget.showDiagnostics || data is! Map) return;
    final line = data['line']?.toString();
    if (line == null || line.isEmpty) return;
    final previous = data['fromLastRun']?.toString();
    final frameError = data['lastFrameError']?.toString();
    final chainError = data['lastSwapChainError']?.toString();
    final composed = <String>[
      line,
      if (previous != null && previous.isNotEmpty) 'prev: $previous',
      if (frameError != null && frameError.isNotEmpty) 'frame: $frameError',
      if (chainError != null && chainError.isNotEmpty) 'chain: $chainError',
    ].join('\n');
    if (!mounted || composed == _statusLine) return;
    setState(() => _statusLine = composed);
  }

  /// The measured facts to print under a failure, or null when there is nothing
  /// to print — a customer build, or no failure yet.
  ///
  /// One string rather than three widgets because it is one idea: which renderer
  /// this phone turned out to have. Since the ladder exists it also carries the
  /// engine's own verdict (`engine=webview → native` and the page line that
  /// produced it), because "the box said not supported" and "the box said not
  /// supported after the WebView refused and the native renderer was latched off"
  /// are different facts about the same screenshot. `SHOE_PREVIEW_ALLOW_LEVEL1`
  /// also announces itself here, so a screenshot from a QA run says which build
  /// produced it —
  /// and `SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1` announces itself separately,
  /// because "level-1 override on" and "the engine *is* level 1" are different
  /// claims about the same run and the `supported=` half of the line is the only
  /// thing that can tell a lowered engine from a capped one.
  String? get _diagnosticDetail {
    if (!widget.showDiagnostics) return null;
    // ⚠️ **Non-null only where there is a failure to explain, and the ladder's own
    // verdict is not one.** A WebView that cannot draw has *moved the box to the
    // other engine*: that state has a shoe in it, so it must not be what puts this
    // section in its failure branch — which is exactly what a first cut of this did
    // in a QA build, taking the native box off the page the moment the fallback had
    // succeeded. The ladder's facts still ride in the detail line once a failure
    // exists (a latched-off fallback, or the native renderer's own refusal), and a
    // successful fallback is narrated by the status line under the box instead.
    if (_errorReason == null && !_fallbackBlocked) return null;
    return <String>[
      if (AppConstants.shoePreviewAllowLevel1) 'QA · level-1 override on',
      if (AppConstants.shoePreviewLowerEngineToLevel1) 'QA · engine pinned to level 1',
      if (_webViewCannotDraw)
        'engine=webview → '
            '${_fallbackBlocked ? 'no native fallback (latched off)' : 'native'}',
      ?_webViewReason,
      ?_webViewLine,
      ?_errorReason,
      if (_errorMessage != null && _errorMessage!.isNotEmpty) _errorMessage!,
      // The heartbeat goes here rather than becoming its own widget on this path:
      // the box is gone, so the native view is gone, and the last line it sent is
      // the most recent fact this screen has about the renderer.
      ?_statusLine,
    ].join(' · ');
  }

  /// Whether this build is a QA build: on when **either** QA switch is.
  ///
  /// A getter rather than the constant repeated at each call site, because the
  /// banner has to appear for both switches while the *sentence* above the box
  /// still depends on the refusal alone.
  bool get _qaBuild =>
      AppConstants.shoePreviewAllowLevel1 ||
      AppConstants.shoePreviewLowerEngineToLevel1;

  @override
  void dispose() {
    _events?.cancel();
    _webViewDeadline?.cancel();
    super.dispose();
  }

  /// The page's gutter, applied to everything this section draws except the box
  /// when the page has handed it the full width ([ShoePreviewSection.bleed]).
  EdgeInsets get _gutter => widget.bleed
      ? const EdgeInsets.symmetric(horizontal: kShoePreviewGutter)
      : EdgeInsets.zero;

  /// One-shot record of which branch this section rendered.
  ///
  /// ⚠️ It is a measurement, not decoration: the failure branch and the success
  /// branch differ by whether the box exists at all, and a customer sees both as
  /// "the 3D thing is missing". This is the line that says which one ran.
  bool _tracedBranch = false;

  @override
  Widget build(BuildContext context) {
    // The whole section, or nothing at all — and unmounting the box is what
    // disposes the native view and its engine. What stays is one line of text
    // plus the AR pill: on a phone the renderer cannot draw on, the 3D box is
    // dead, but the AR entry is *not* — the AR screen degrades to its simulated
    // mode with its own notice (the owner's decision, 2026-09-30, after the
    // first device report showed the original all-or-nothing rule eating the
    // pill mid-visit: the customer opens AR, comes back, and both entries are
    // gone because the gate now says "shown" while the section says "gone").
    if (widget.showDiagnostics && !_tracedBranch) {
      _tracedBranch = true;
      // Spelled into a local rather than nested inside the interpolation: two
      // ternaries deep, the lexer reads the inner quotes as the end of the
      // template. One line, one label.
      final ladder = !_webViewCannotDraw
          ? 'untouched'
          : (_fallbackBlocked ? 'blocked' : 'fell back');
      navDiag('[preview] section branch='
          '${_unsupported || _fallbackBlocked || _diagnosticDetail != null ? 'failure' : 'box'} · '
          'unsupported=$_unsupported · reason=$_errorReason · '
          'engine=${_webViewEngine ? 'webview' : 'native'} · '
          'ladder=$ladder · '
          'asked=${widget.useWebViewEngine ? 'webview' : 'native'}');
    }
    if (_unsupported || _fallbackBlocked || _diagnosticDetail != null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(_gutter.left, 0, _gutter.right, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_qaBuild) ...<Widget>[
              const ShoePreviewQaBanner(),
              const SizedBox(height: 8),
            ],
            // The refusal keeps the honest sentence it has always shown, with the
            // QA readout (if any) underneath it rather than folded into it: the
            // sentence is what a customer is owed, the numbers are a diagnosis.
            ShoePreviewHint(
              message: _unsupported || _fallbackBlocked
                  ? kShoePreviewUnsupportedMessage
                  : '3D preview failed on this build.',
              detail: _diagnosticDetail,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_qaBuild) ...<Widget>[
          Padding(padding: _gutter, child: const ShoePreviewQaBanner()),
          const SizedBox(height: 8),
        ],
        ShoePreview3D(
          model: widget.model,
          channel: widget.channel,
          viewBuilder: widget.viewBuilder,
          webViewBuilder: widget.webViewBuilder,
          height: widget.height,
          bleed: widget.bleed,
          paused: widget.paused,
          // The section's own QA flag is the only one: one switch, not two that can disagree.
          diagnostics: widget.showDiagnostics,
          // ⚠️ The ladder's current rung, not the caller's request. A WebView that
          // reported it cannot draw has already flipped this, which is what makes
          // the fallback a single `setState` rather than a second widget tree.
          useWebViewEngine: _webViewEngine,
          // ⚠️ **The WebView engine's line arrives here rather than through
          // `_onEvent`**, which only ever carries what the *native* side sends. A
          // build running the WebView engine has no native renderer at all, so a
          // readout fed only by `status` events would sit empty on exactly the
          // engine that is being measured. Same surface, same gate, one extra
          // source.
          onEngineStatus: _recordEngineLine,
        ),
        if (widget.showDiagnostics && _statusLine != null) ...<Widget>[
          const SizedBox(height: 6),
          Padding(padding: _gutter, child: _QaStatusLine(text: _statusLine!)),
        ],
      ],
    );
  }
}
