import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/ar_try_on_channel.dart';
import '../services/shoe_preview_channel.dart';
import 'sole_ar_pill.dart';

/// The product page's **inline 3D box** — the customer turns the shoe with a
/// finger, and the "Try On in AR" button sits underneath it
/// ([ShoePreviewSection]).
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

  @override
  State<ShoePreview3D> createState() => _ShoePreview3DState();
}

class _ShoePreview3DState extends State<ShoePreview3D> {
  late final ShoePreviewChannel _channel =
      widget.channel ?? const ShoePreviewChannel();

  @override
  void initState() {
    super.initState();
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

/// **The section: the 3D box, and "Try On in AR" underneath it.**
///
/// One widget rather than two mounts on the page, because they are one decision:
/// a product with a live model gets both, a product without gets neither
/// (`resolveShoePreview`), and splitting them is how the button ends up on a
/// page whose box is missing.
///
/// ⚠️ **And it is the widget that can take itself off the page.** The native
/// renderer refuses to load an asset below `FEATURE_LEVEL_2`
/// (`kRendererUnsupportedReason`) rather than abort the process on it, and when
/// that report arrives this section removes **both** halves: on such a phone the
/// AR path cannot draw the shoe either, so offering a camera would be a promise
/// we cannot keep. See `kRendererUnsupportedReason` for the crash that made this
/// necessary.
class ShoePreviewSection extends StatefulWidget {
  const ShoePreviewSection({
    super.key,
    required this.model,
    required this.onTryOnInAr,
    this.channel,
    this.viewBuilder,
    this.height = 240,
    this.paused = false,
    this.events,
  });

  final TryOnModelSpec model;

  /// Pushes the AR screen. The page owns this because the AR screen needs the
  /// whole product row, which is the page's state rather than this section's.
  final VoidCallback onTryOnInAr;

  final ShoePreviewChannel? channel;
  final Widget Function()? viewBuilder;
  final double height;

  /// See [ShoePreview3D.paused]. The button keeps working while the box is
  /// paused — it is the thing being opened at that moment.
  final bool paused;

  /// Test seam: the preview's native event stream, instead of the channel's own.
  final Stream<Map<String, dynamic>>? events;

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

  @override
  void initState() {
    super.initState();
    _events = (widget.events ?? _channel.events).listen(_onEvent);
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['type']?.toString() != 'error') return;
    final data = event['data'];
    final reason = data is Map ? data['reason']?.toString() : null;
    if (reason != kRendererUnsupportedReason) return;
    if (!mounted) return;
    setState(() => _unsupported = true);
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The whole section, or nothing at all — and unmounting the box is what
    // disposes the native view and its engine.
    if (_unsupported) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShoePreview3D(
          model: widget.model,
          channel: widget.channel,
          viewBuilder: widget.viewBuilder,
          height: widget.height,
          paused: widget.paused,
        ),
        const SizedBox(height: 12),
        // The same pill the page used to pin above the buy bar, full width and
        // in the flow instead: it is the second thing this section offers, not
        // a floating shortcut past it.
        SizedBox(
          width: double.infinity,
          child: SoleARPill(onPressed: widget.onTryOnInAr),
        ),
      ],
    );
  }
}
