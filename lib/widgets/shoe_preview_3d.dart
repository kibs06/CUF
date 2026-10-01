import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/ar_try_on_channel.dart';
import '../services/shoe_preview_channel.dart';
import 'sole_ar_pill.dart';

/// The **3D box** — the customer turns the shoe with a finger, and the
/// "Try On in AR" button sits underneath it ([ShoePreviewSection]).
///
/// ⚠️ **Where it is mounted changed on 2026-10-01, and the widget did not.** It
/// used to be a row on the product page, 240 px tall, under the size grid. It is
/// now the body of the full-screen viewer the product photo's 3D icon opens
/// (`ShoePreviewScreen`, `Sole3DIconButton`) — same renderer, same payload, same
/// section, at the size of a screen instead of the size of a paragraph. The page
/// keeps only the recovery notice (`_shoePreviewNotice`) and the pinned
/// "Try On in AR" pill is gone from it, so the AR escalation this section carries
/// is now the only way into AR from a product.
///
/// **Why a box before a button.** "Try On in AR" was the only entry on the page
/// and it asked for three things before it showed anything: an ARCore-capable
/// phone, an app with the AR build flag on, and a customer willing to point a
/// camera at their feet — in public, at a shoe they are still deciding about.
/// The 3D box asks for none of them. It renders the **same verified `.glb`**
/// through the same native renderer (`ArTryOnView` in `Mode.PREVIEW`), so what
/// the customer turns is the mesh that would be tracked onto their foot, and a
/// tap on the button below is the escalation rather than the entry fee.
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
    this.height = 240,
    this.paused = false,
    this.diagnostics = AppConstants.shoePreviewDiagnosticsEnabled,
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
  final Widget Function()? viewBuilder;

  /// The box's height. 240 px shows a whole shoe at a three-quarter view without
  /// taking the size grid off the first screen.
  final double height;

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

  @override
  State<ShoePreview3D> createState() => _ShoePreview3DState();
}

class _ShoePreview3DState extends State<ShoePreview3D> {
  late final ShoePreviewChannel _channel =
      widget.channel ?? const ShoePreviewChannel();

  @override
  void initState() {
    super.initState();
    // Before the handover, and before the view exists (the plugin parks it): the readout has to be
    // on for a view whose model never arrives, which is the state a failed load leaves behind.
    if (widget.diagnostics) {
      unawaited(_channel.setDiagnostics(true));
    }
    _handOver();
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
  }

  void _handOver() {
    // `setModel` swallows `MissingPluginException` and platform errors by
    // design, so there is nothing to await and nothing to report here.
    unawaited(_channel.setModel(widget.model));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: double.infinity,
            height: widget.height,
            child: widget.paused ? const ShoePreviewIdle() : _view(),
          ),
        ),
      ],
    );
  }

  Widget _view() {
    final injected = widget.viewBuilder;
    if (injected != null) return injected();

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

/// The box's face while no native view is mounted: the same height, and the same
/// colour the renderer clears to.
///
/// ⚠️ The colour is not decorative. `ArTryOnView.createEngineIfNeeded` sets
/// `ClearOptions.clearColor` to `(0.055, 0.06, 0.07)`; matching it here means the
/// box does not flash from one dark tone to another as the engine starts, and it
/// keeps the layout honest — a preview that never loads looks exactly like a
/// preview that has not loaded *yet*, which is the truth for both.
class ShoePreviewIdle extends StatelessWidget {
  const ShoePreviewIdle({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF0E0F12));
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

/// **The section: the 3D box, and "Try On in AR" underneath it.**
///
/// One widget rather than two mounts on the page, because they are one decision:
/// a product with a live model gets both, a product without gets neither
/// (`resolveShoePreview`), and splitting them is how the button ends up on a
/// page whose box is missing.
///
/// ⚠️ **And it is the widget that can lose its box and keep its button.** The
/// native renderer refuses to load an asset below `FEATURE_LEVEL_2`
/// (`kRendererUnsupportedReason`) rather than abort the process on it, and when
/// that report arrives this section swaps the box for the not-supported line
/// while **keeping the AR pill**: the AR screen degrades to its simulated mode
/// on such a phone, so the entry stays honestly usable. (Originally the whole
/// section removed itself — until a real phone showed the customer the pill
/// vanishing mid-visit.) See `kRendererUnsupportedReason` for the crash that
/// made the refusal necessary.
///
/// **The escalation is the customer's, and only the customer's**
/// ([showTryOn]). The seller's door to this section (`ShoePreviewScreen
/// .forProduct`) is a seller checking what the shop is selling; the person who
/// tries the pair on is the customer, and a camera button on the seller's screen
/// launches a fitting flow on the wrong side of the shop.
class ShoePreviewSection extends StatefulWidget {
  const ShoePreviewSection({
    super.key,
    required this.model,
    required this.onTryOnInAr,
    this.showTryOn = true,
    this.channel,
    this.viewBuilder,
    this.height = 240,
    this.paused = false,
    this.events,
    this.showDiagnostics = AppConstants.shoePreviewDiagnosticsEnabled,
  });

  final TryOnModelSpec model;

  /// Pushes the AR screen. The page owns this because the AR screen needs the
  /// whole product row, which is the page's state rather than this section's.
  final VoidCallback onTryOnInAr;

  /// Whether the "Try On in AR" pill is drawn at all. True everywhere a customer
  /// is looking at the shoe; false on the seller's viewer, which has nobody to
  /// try the pair on. See the class header.
  final bool showTryOn;

  final ShoePreviewChannel? channel;
  final Widget Function()? viewBuilder;
  final double height;

  /// See [ShoePreview3D.paused]. The button keeps working while the box is
  /// paused — it is the thing being opened at that moment.
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

  @override
  void initState() {
    super.initState();
    _events = (widget.events ?? _channel.events).listen(_onEvent);
  }

  void _onEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString();
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
  /// this phone turned out to have. `SHOE_PREVIEW_ALLOW_LEVEL1` also announces
  /// itself here, so a screenshot from a QA run says which build produced it —
  /// and `SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1` announces itself separately,
  /// because "level-1 override on" and "the engine *is* level 1" are different
  /// claims about the same run and the `supported=` half of the line is the only
  /// thing that can tell a lowered engine from a capped one.
  String? get _diagnosticDetail {
    if (!widget.showDiagnostics || _errorReason == null) return null;
    return <String>[
      if (AppConstants.shoePreviewAllowLevel1) 'QA · level-1 override on',
      if (AppConstants.shoePreviewLowerEngineToLevel1) 'QA · engine pinned to level 1',
      _errorReason!,
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
    super.dispose();
  }

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
    if (_unsupported || _diagnosticDetail != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
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
              message: _unsupported
                  ? '3D preview isn\'t supported on this phone.'
                  : '3D preview failed on this build.',
              detail: _diagnosticDetail,
            ),
            if (widget.showTryOn) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SoleARPill(onPressed: widget.onTryOnInAr),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_qaBuild) ...<Widget>[
          const ShoePreviewQaBanner(),
          const SizedBox(height: 8),
        ],
        ShoePreview3D(
          model: widget.model,
          channel: widget.channel,
          viewBuilder: widget.viewBuilder,
          height: widget.height,
          paused: widget.paused,
          // The section's own QA flag is the only one: one switch, not two that can disagree.
          diagnostics: widget.showDiagnostics,
        ),
        if (widget.showDiagnostics && _statusLine != null) ...<Widget>[
          const SizedBox(height: 6),
          _QaStatusLine(text: _statusLine!),
        ],
        if (widget.showTryOn) ...<Widget>[
          const SizedBox(height: 12),
          // The same pill the page used to pin above the buy bar, full width and
          // in the flow instead: it is the second thing this section offers, not
          // a floating shortcut past it.
          SizedBox(
            width: double.infinity,
            child: SoleARPill(onPressed: widget.onTryOnInAr),
          ),
        ],
      ],
    );
  }
}
