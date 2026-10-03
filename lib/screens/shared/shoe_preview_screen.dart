import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/ar_try_on_channel.dart';
import '../../services/shoe_preview_channel.dart';
import '../../services/try_on_prefetch.dart';
import '../../widgets/shoe_preview_3d.dart';
import '../../widgets/sole_ar_pill.dart';
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
/// **The stage is the page, edge to edge** (2026-10-03, the owner's request):
/// the box no longer takes the page's 20 px gutter, and it takes back the room
/// that used to sit empty between it and the pinned pill. The promise that makes
/// that safe is that **the model does not stretch with the box**: what widens is
/// the window, and the renderer frames the same asset itself — a turning shoe in
/// a bigger stage, not a widening shoe. Everything that is *text* (the section's
/// header, its sentences, the note) keeps the gutter by its own inset — see
/// [kShoePreviewGutter], which exists so those numbers cannot drift apart.
///
/// **What it does not change.** It is still `ShoePreview3D` in the same
/// `Mode.PREVIEW`, drawing the same verified `.glb` through the same native
/// renderer the AR session uses, mounted through `ShoePreviewSection` — the
/// widget that knows what to draw when the renderer *refuses* (the refusal
/// sentence, the QA banner, the measured facts). This screen is framing, a title,
/// the optional resolve, the AR push — and, since 2026-10-03, the pill that makes
/// that push.
///
/// **The escalation is the page's, and it lives at the foot of the page.** The
/// pill used to be `ShoePreviewSection`'s own last child, in the flow directly
/// under the box; under a box that now fills most of the screen it left a dead
/// half-page beneath the button, and the owner asked for it at the bottom
/// instead. It is pinned there — full width, above the system bar, outside the
/// scroll area — which is the treatment this pill had on the product page before
/// the viewer existed (a floating CTA above the buy bar). Two properties fall out
/// of the move, and both are why it is safe:
///
///   * **The box and the entry are still one decision.** This screen mounts the
///     box *and* draws the pill, so a product that resolves no model gets
///     neither, and there is exactly one way into AR.
///   * **A refusal cannot take the entry with it.** The renderer's refusal swaps
///     the box for its honest sentence *inside* the section; the pill is outside
///     it now, so the state that once had to remember to keep the button — the
///     owner's decision of 2026-09-30, after a real phone lost it mid-visit —
///     has no branch left that can drop it.
///
/// **The AR push and the pause.** The box stops
/// rendering while the AR screen is on top — a flag this screen owns rather than
/// a `ModalRoute.isCurrent` check inside the widget, because a plain push does
/// not rebuild the route underneath it and the check would silently never fire.
/// `ShoePreviewSection.paused` carries it; the reasoning is written out on
/// [ShoePreview3D.paused] and on [_openArTryOn]. It is **off** for the seller
/// ([showTryOn]), who is looking at the pair rather than trying it on.
///
/// ⚠️ **It is a page, not a camera.** The AR screen is dark because it is a
/// camera feed; this one follows the customer's brightness at every level.
/// `ShoePreviewSection` inks its own header and its refusal sentence with
/// [AppConstants.secondary], which resolves to near-black on a light-mode device
/// — drawn on the dark `surfaceDark` that the AR screen uses, both lines would be
/// invisible. And the box itself clears to [AppConstants.stage] — a light neutral
/// on light, the renderer's `#0E0F12` on dark — handed to whichever engine is
/// running (`ShoePreviewChannel.setBackground`), so the frame around the shoe is
/// the customer's own surface rather than a fixed black rectangle.
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
  /// side of the shop. Where it is true, the pill is drawn at the foot of the
  /// page rather than under the box; see the class header.
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
  /// **What this page spends on anything that is not the stage**, in logical
  /// pixels: the AR pill pinned below when this door has one (~80 with its 8/20
  /// padding), the section's header row and the 8 px gap under it (~30), and the
  /// scroll view's own breathing room. The stage takes the rest.
  ///
  /// A constant rather than a measurement, because the row being measured — the
  /// header inside `ShoePreview3D` — is laid out *after* the box it would have
  /// to size; a wrong reserve costs a few pixels of stage, while waiting for the
  /// measurement would cost a frame of the surface the viewer was opened for.
  static const double _notTheStage = 160;

  /// The seller's one line under the box. Only that door has one.
  static const double _noteRoom = 60;

  /// The tallest the stage may get. No phone reaches it — it is here so a tablet
  /// or a desktop window offers the shoe a generous window rather than a
  /// thousand-pixel field with one shoe in the middle of it.
  static const double _stageCeiling = 900;

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
            // The stage takes everything the page has once the pill, the header
            // and the page's own breathing room are off the top — see
            // [_notTheStage]. Clamped so a short screen still gets a usable
            // window, and so a tablet does not get a whole screen of empty stage.
            final boxHeight = (constraints.maxHeight -
                    _notTheStage -
                    (widget.note == null ? 0 : _noteRoom))
                .clamp(240.0, _stageCeiling)
                .toDouble();
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    // ⚠️ No horizontal padding: the box is the page's width now.
                    // The text that used to ride on the page's gutter — the
                    // section's header, its sentences, the note below — carries
                    // [kShoePreviewGutter] itself.
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (model != null)
                          ShoePreviewSection(
                            model: model,
                            paused: _arTryOnOpen,
                            height: boxHeight,
                            // The page's width, and only the box's: see
                            // [ShoePreview3D.bleed] for what that moves and what
                            // it leaves alone.
                            bleed: true,
                            channel: widget.channel,
                            viewBuilder: widget.viewBuilder,
                            events: widget.events,
                          )
                        else if (_resolving)
                          _ResolvingBox(height: boxHeight)
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: kShoePreviewGutter,
                            ),
                            child: ShoePreviewHint(
                              message: _failureSentence!,
                              actionLabel: _canRetry ? 'Retry' : null,
                              onAction: _canRetry ? _resolve : null,
                            ),
                          ),
                        if (widget.note != null && model != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              kShoePreviewGutter,
                              16,
                              kShoePreviewGutter,
                              0,
                            ),
                            child: Text(
                              widget.note!,
                              style: AppConstants.bodyStyle(
                                fontSize: 13,
                                color:
                                    AppConstants.secondary.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // The escalation, pinned to the bottom edge rather than left in
                // the flow under the box: full width, above the system bar, and
                // outside the scroll area so a longer screen never moves it.
                //
                // ⚠️ **It is outside `ShoePreviewSection` on purpose.** The
                // renderer's refusal swaps the box for a sentence inside that
                // section; a pill drawn here cannot be taken off the page by a
                // branch over there — which is exactly the fault that put the
                // button inside the section in the first place.
                if (widget.showTryOn)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: SoleARPill(onPressed: _openArTryOn),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The shape of the wait, at the size of the surface that is coming.
///
/// A bare spinner in the middle of an empty page reads as a hang; the stage's own
/// area — and its colour, the tone the renderer clears to — say that the surface
/// is on its way and is going to be this big. The download is a few megabytes over
/// a phone connection, which is long enough to need saying.
class _ResolvingBox extends StatelessWidget {
  const _ResolvingBox({required this.height});

  /// The stage's own height — see `_notTheStage` for how it is arrived at — so
  /// the block that stands in for the box is the block the model lands in, and
  /// nothing shifts when the download finishes.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kShoePreviewGutter),
          child: Text(
            'Fetching the 3D model…',
            style:
                AppConstants.bodyStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: height,
          child: const ShoePreviewIdle(),
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
