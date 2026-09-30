import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/ar_try_on_channel.dart';
import '../../services/shoe_preview_channel.dart';
import '../../services/try_on_prefetch.dart';
import '../../widgets/shoe_preview_3d.dart';
import '../customer/ar_fitting_screen.dart';

/// **The full-screen 3D viewer** — the one surface that shows a product's model,
/// whoever is looking at it.
///
/// Two doors, and they differ only in what is already known when it opens:
///
///   * **[ShoePreviewScreen.new]** — the product page's 3D icon
///     (`Sole3DIconButton`). The page's own prefetch (V2.6) already resolved a
///     verified local model while the customer was reading, so it is handed over
///     directly and the box is up on the first frame.
///   * **[ShoePreviewScreen.forProduct]** — the seller's "3D fitting ready" row in
///     the product action sheet (`ShoeModelRequestTile`). Nobody has resolved
///     anything on a seller's device, so the screen does it: one read, a download
///     if the bytes are not cached yet, and an honest sentence if there turns out
///     to be nothing to draw. That last state is the point of the seller door —
///     "3D fitting ready" is a claim about a *row*, and the seller asking to see
///     it is exactly how a row with no usable model gets found.
///
/// **Why this lives in `screens/shared/`.** It was written for the product page
/// and moved here the day the seller's row needed the same surface: settings,
/// terms and the help screens already live in this folder for the same reason,
/// and the alternative — a seller screen importing a customer one — is a
/// boundary this codebase does not cross anywhere else.
///
/// **What it does not change.** It is still `ShoePreview3D` in the same
/// `Mode.PREVIEW`, drawing the same verified `.glb` through the same native
/// renderer the AR session uses, mounted through `ShoePreviewSection` — which is
/// the widget that knows what to draw when the renderer *refuses* (the refusal
/// sentence, the QA banner, the measured facts) and which carries the
/// "Try On in AR" escalation. This screen is framing, a title, the optional
/// resolve, and the AR push.
///
/// **The AR push and the pause, moved here with the button.** The box stops
/// rendering while the AR screen is on top — a flag this screen owns rather than
/// a `ModalRoute.isCurrent` check inside the widget, because a plain push does
/// not rebuild the route underneath it and the check would silently never fire.
/// `ShoePreviewSection.paused` carries it; the reasoning is written out on
/// [ShoePreview3D.paused] and on [_openArTryOn]. It is **off** for the seller
/// ([showTryOn]), who is looking at the pair rather than trying it on.
///
/// ⚠️ **It is a light screen on purpose.** The AR screen is dark because it is a
/// camera feed; this one is a page. `ShoePreviewSection` inks its own header and
/// its refusal sentence with [AppConstants.secondary], which resolves to
/// near-black on a light-mode device — drawn on the dark `surfaceDark` that the
/// AR screen uses, both lines would be invisible. The box itself is dark (the
/// renderer clears to `#0E0F12`), which is what frames the shoe, so nothing
/// about the renderer's presentation depends on this choice.
class ShoePreviewScreen extends StatefulWidget {
  /// The customer door: a model already resolved by the page that opened this.
  const ShoePreviewScreen({
    super.key,
    required TryOnModelSpec this.model,
    required this.product,
    this.modelAvailable = true,
    this.showTryOn = true,
    this.note,
    this.prefetch,
    this.channel,
    this.viewBuilder,
    this.events,
  }) : productId = null;

  /// The seller door: nothing is resolved yet, so this screen resolves it.
  ///
  /// The switch that gates the customer's prefetch is **not** consulted here, and
  /// that is deliberate: a seller who taps "3D fitting ready" is asking for the
  /// file by name, which is a different question from spending a shopper's data
  /// on a warm cache they never asked for.
  const ShoePreviewScreen.forProduct({
    super.key,
    required String this.productId,
    required this.product,
    this.showTryOn = false,
    this.note,
    this.prefetch,
    this.channel,
    this.viewBuilder,
    this.events,
  })  : model = null,
        modelAvailable = false;

  /// The verified local model, in the same payload the AR path hands over.
  /// Null on the seller door, where [productId] is given instead.
  final TryOnModelSpec? model;

  /// The product whose model this screen must resolve. Null on the customer
  /// door, where the model is handed over.
  final String? productId;

  /// The product the AR escalation hands to `ARVirtualFitScreen`. It is the
  /// page's whole row rather than an id because the AR screen reads the product
  /// (name, sizes, price) directly.
  final Map<String, dynamic> product;

  /// Passed straight through to `ARVirtualFitScreen` (V3.9's availability half).
  final bool modelAvailable;

  /// Whether to offer the AR escalation at all.
  ///
  /// True for a customer: the camera is the step after a look. **False for the
  /// seller**, who cannot try the pair on — the person trying it on is the
  /// customer, and an AR button here would launch a fitting flow on the wrong
  /// side of the shop.
  final bool showTryOn;

  /// One line under the box, for the caller that has something to say about the
  /// model itself. The seller's is "Change it any time from the product form."
  /// Null draws nothing.
  final String? note;

  /// Test seam: where the seller door's model comes from. See [productId].
  final TryOnPrefetch? prefetch;

  /// Test seam: a channel to record calls instead of a real one. See
  /// [ShoePreviewSection.channel].
  final ShoePreviewChannel? channel;

  /// Test seam: the widget that stands in for the platform view —
  /// `AndroidView` cannot be mounted under `flutter test`.
  final Widget Function()? viewBuilder;

  /// Test seam: the preview's native event stream, instead of the channel's own.
  final Stream<Map<String, dynamic>>? events;

  @override
  State<ShoePreviewScreen> createState() => _ShoePreviewScreenState();
}

class _ShoePreviewScreenState extends State<ShoePreviewScreen> {
  /// True while the AR screen is pushed on top of this one — see the class
  /// header. The box stops rendering while it is, because the AR session needs
  /// the GPU and two Filament engines for one customer is a frame-rate argument
  /// nobody wins.
  bool _arTryOnOpen = false;

  /// The model to draw: handed over on the customer door, resolved on the
  /// seller's.
  TryOnModelSpec? _model;

  /// True while the seller door's resolve is in flight.
  bool _resolving = false;

  /// What the resolve answered, kept so the screen can say *which* silence this
  /// is. Null while it is still running.
  TryOnPrefetchResult? _resolution;

  /// Enabled unconditionally: this prefetch only ever serves the seller door,
  /// which is a seller asking for the file by name rather than a shopper's page
  /// warming a cache they never asked for — the trade
  /// `AppConstants.tryOnPrefetchEnabled` exists to gate.
  late final TryOnPrefetch _prefetch =
      widget.prefetch ?? TryOnPrefetch(enabled: true);

  @override
  void initState() {
    super.initState();
    _model = widget.model;
    if (_model == null) _resolve();
  }

  /// One read, and a download if the bytes are not cached yet.
  ///
  /// It reuses the customer path's policy object rather than reaching for
  /// `ShoeModelService` directly: `prefetch` never throws, and every failure —
  /// no row, no table, no network, a hash mismatch, an unwritable cache —
  /// arrives as an outcome this screen turns into one sentence.
  Future<void> _resolve() async {
    final productId = widget.productId;
    if (productId == null) return;

    setState(() => _resolving = true);
    // ⚠️ `anyVariant`, and it is the difference between this screen working and
    // lying: the seller has no colour in hand and no customer to show the shoe
    // to, so "which shoe does this customer see?" would answer "no model" on a
    // product whose rows are all colour-scoped — a "3D fitting ready" row
    // contradicting itself in the seller's own hands.
    final result = await _prefetch.prefetch(
      productId: productId,
      anyVariant: true,
    );
    if (!mounted) return;

    final spec = result.spec;
    final path = result.path;
    setState(() {
      _resolving = false;
      _resolution = result;
      _model = (spec != null && path != null)
          ? TryOnModelSpec.fromModel(spec, path: path)
          : null;
    });
  }

  Future<void> _openArTryOn() async {
    setState(() => _arTryOnOpen = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ARVirtualFitScreen(
            preselectedProduct: widget.product,
            modelAvailable: widget.modelAvailable,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _arTryOnOpen = false);
    }
  }

  /// The sentence for a resolve that produced nothing to draw, or null while one
  /// is still running.
  ///
  /// The three failures are told apart because they need different actions from
  /// the seller: `noModel` means the row behind "3D fitting ready" is gone or was
  /// never usable and there is nothing to retry, while the rest are worth one
  /// more attempt. A screen that said "couldn't load" for both would send a
  /// seller round a retry loop that cannot succeed.
  String? get _failureSentence {
    if (_resolving || _model != null) return null;
    final outcome = _resolution?.outcome;
    if (outcome == TryOnPrefetchOutcome.noModel) {
      return 'No 3D model is on this product any more.';
    }
    return 'The 3D model could not be fetched just now.';
  }

  /// Whether the failure is worth offering a retry for — a missing model is not.
  bool get _canRetry => _failureSentence != null &&
      _resolution?.outcome != TryOnPrefetchOutcome.noModel;

  @override
  Widget build(BuildContext context) {
    final model = _model;
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceLight,
        foregroundColor: AppConstants.secondary,
        elevation: 0,
        // The title is the product, not "View in 3D": the section below says
        // what the surface is, and a customer who opened this from a photo they
        // were three pages deep in is owed the name of the thing they are
        // looking at.
        title: Text(
          widget.product['name']?.toString() ?? 'View in 3D',
          style: AppConstants.bodyStyle(fontSize: 16, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The box takes what the screen has left once the header, the AR
            // pill and the screen's own chrome are accounted for, clamped so a
            // short screen does not squeeze it into a strip and a tablet does
            // not stretch one shoe over the whole page.
            final boxHeight =
                (constraints.maxHeight - 240).clamp(240.0, 520.0).toDouble();
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (model != null)
                    ShoePreviewSection(
                      model: model,
                      onTryOnInAr: _openArTryOn,
                      paused: _arTryOnOpen,
                      height: boxHeight,
                      showTryOn: widget.showTryOn,
                      channel: widget.channel,
                      viewBuilder: widget.viewBuilder,
                      events: widget.events,
                    )
                  else
                    _resolving
                        ? const _ResolvingBox()
                        : ShoePreviewHint(
                            message: _failureSentence!,
                            actionLabel: _canRetry ? 'Retry' : null,
                            onAction: _canRetry ? _resolve : null,
                          ),
                  if (widget.note != null && model != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        widget.note!,
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color: AppConstants.secondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The shape of the wait, at the size of the surface that is coming.
///
/// A bare spinner in the middle of an empty page reads as a hang; the box's own
/// proportions — and its colour, the tone the renderer clears to — say that the
/// dark rectangle is on its way and is going to be this big. The download is a
/// few megabytes over a phone connection, which is long enough to need saying.
class _ResolvingBox extends StatelessWidget {
  const _ResolvingBox();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fetching the 3D model…',
          style: AppConstants.bodyStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: const SizedBox(
            width: double.infinity,
            // The box's own height, so nothing shifts when the model lands.
            height: 240,
            child: ShoePreviewIdle(),
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }
}
