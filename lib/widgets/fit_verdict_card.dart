import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../models/foot_measurement.dart';
import '../providers/auth_provider.dart';
import '../providers/foot_measurement_provider.dart';
import '../screens/customer/foot_instructions_screen.dart';
import '../services/fit_shadow_log.dart';
import '../utils/fit_engine.dart';
import '../utils/fit_shadow.dart';
import '../utils/fit_verdict_state.dart';
import '../utils/size_match.dart';

/// The V1 fit verdict on a product page: *this* shoe, in *this* size, on *this*
/// customer's foot — no 3D, no ARCore, no device.
///
/// Two widgets, deliberately split:
///
///  * **[FitVerdictPanel]** is the presentation and nothing else — it draws the
///    state it is handed. No providers, no flag, no network. This is what the
///    tests drive, and what a later surface (the cart) reuses.
///  * **`FitVerdictCard`** (this class) is the wiring: the kill switch, the
///    saved scan, and the one read it takes to have one.
///
/// **It fetches, and it has to.** `FootMeasurementProvider` holds a measurement
/// in memory only after a scan *in this session* — `loadLatest` is called
/// nowhere else in the app — so a customer who scanned last week arrives here
/// with nothing. Without the read, every returning customer would be invited to
/// scan feet they already scanned. The read is once per mount, only when the
/// answer can change ([_readSavedScan]), and the card renders a quiet
/// "checking" beat while it is in flight rather than the invitation, so a
/// scanned customer is never told to scan for a frame.
///
/// **Shadow mode (V1.7) rides on the same mount.** With
/// `AppConstants.virtualFitShadowEnabled` on, the card computes what it *would*
/// say and writes one line to the diag log instead of showing it — including
/// when the card itself is off, which is the whole point of the phase: collect
/// the sample the V1 accuracy bar is judged on before a customer reads a
/// verdict. The record is `fitShadowLine` (`lib/utils/fit_shadow.dart`), built
/// from the same inputs and the same decision, and written once per distinct
/// outcome per mount rather than once per rebuild.
///
/// The decision itself is not here: `fitVerdictCardStateFor` in
/// `lib/utils/fit_verdict_state.dart` owns every fallback rule, and
/// `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V1.5/V1.6 own the intent.
class FitVerdictCard extends StatefulWidget {
  /// The `products` row, for its last spec (`last_length_mm`,
  /// `last_width_mm`, `fit_ref_size_eu` — read through
  /// [FitSpecs.fromProduct], which validates them).
  final Map<String, dynamic> product;

  /// The size selected on the page, as the canonical database string. Null
  /// (sizes still loading, nothing in stock) hides the card: a verdict is
  /// about a size.
  final String? selectedSize;

  const FitVerdictCard({
    super.key,
    required this.product,
    this.selectedSize,
  });

  @override
  State<FitVerdictCard> createState() => _FitVerdictCardState();
}

class _FitVerdictCardState extends State<FitVerdictCard> {
  /// How far the card got in reading the customer's saved scan.
  ///
  /// Mutated in `build` (see [_readSavedScan]'s caller) on purpose: the value
  /// has to be `pending` before the frame that decides to fetch paints, or a
  /// scanned customer sees the "scan your feet" invitation for a frame, and a
  /// `setState` from inside `build` is not available. It is set at most once,
  /// and the post-frame read is what moves it on.
  FitScanProbe _probe = FitScanProbe.unnecessary;

  /// The last record handed to the log, so a rebuild cannot write the same
  /// line twice — the record is per page visit, not per frame.
  String? _lastShadowLine;

  @override
  Widget build(BuildContext context) {
    final shadow = AppConstants.virtualFitShadowEnabled;
    // The kill switch, first: off means nothing happens — no card, and no
    // query either, unless shadow mode is what is asking.
    if (!AppConstants.virtualFitEnabled && !shadow) {
      return const SizedBox.shrink();
    }

    // No usable last spec: answered from the row alone, before a provider is
    // looked up, a subscription registered or a scan read. This is also the
    // one outcome shadow mode does *not* record — how much of the catalog
    // carries a spec is a query (`products.last_length_mm IS NOT NULL`, the
    // coverage metric in the roadmap), not a page view.
    if (FitSpecs.fromProduct(widget.product) == null) {
      return const SizedBox.shrink();
    }

    final profile =
        context.select<AuthProvider, Map<String, dynamic>?>((p) => p.profile);
    final measurement = context
        .select<FootMeasurementProvider, FootMeasurement?>(
          (p) => p.latestMeasurement,
        );
    // Whether the customer claims a foot profile at all — the app's existing
    // marker, so "has a size on file" means one thing everywhere. A manual
    // picker entry writes it without ever producing millimetres; that customer
    // gets an empty measurement back and is invited to scan, which is true.
    final hasFootProfile = AppConstants.hasFootSize(profile);

    if (hasFootProfile && measurement == null) {
      if (_probe == FitScanProbe.unnecessary) {
        _probe = FitScanProbe.pending;
        WidgetsBinding.instance.addPostFrameCallback((_) => _readSavedScan());
      }
    }

    // With a measurement in hand the read's outcome no longer decides
    // anything — the verdict path never reads the probe.
    final probe = hasFootProfile && measurement == null
        ? _probe
        : FitScanProbe.unnecessary;

    if (shadow) _recordShadowLine(probe, measurement);

    return FitVerdictPanel(
      state: fitVerdictCardStateFor(
        // The switch's own rule, so a card that is off renders nothing even
        // while shadow mode is collecting beside it.
        enabled: AppConstants.virtualFitEnabled,
        product: widget.product,
        selectedSize: widget.selectedSize,
        measurement: measurement,
        probe: probe,
      ),
      onScanRequested: _openScan,
    );
  }

  /// Write the shadow record for this page, at most once per distinct line.
  ///
  /// Building the line here and writing it in a post-frame callback keeps the
  /// log write (synchronous, flushed per line) out of layout, and the dedupe
  /// keeps a page that rebuilds on every provider notification from filling the
  /// file with the same record.
  void _recordShadowLine(FitScanProbe probe, FootMeasurement? measurement) {
    final line = fitShadowLine(
      product: widget.product,
      selectedSize: widget.selectedSize,
      measurement: measurement,
      probe: probe,
    );
    if (line == null || line == _lastShadowLine) return;
    _lastShadowLine = line;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) logFitShadow(line);
    });
  }

  /// One read of the saved scan, once per mount. `loadLatest` never throws —
  /// it records `error` — so a failure is read off the provider, and a failed
  /// read suppresses the card entirely rather than inviting a scan we cannot
  /// prove is missing.
  Future<void> _readSavedScan() async {
    if (!mounted) return;
    final provider = context.read<FootMeasurementProvider>();
    final userId =
        context.read<AuthProvider>().currentUser?['id']?.toString();
    if (userId == null || userId.isEmpty) {
      if (mounted) setState(() => _probe = FitScanProbe.failed);
      return;
    }

    await provider.loadLatest(userId);
    if (!mounted) return;
    setState(
      () => _probe =
          provider.error != null ? FitScanProbe.failed : FitScanProbe.done,
    );
  }

  void _openScan() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FootInstructionsScreen()),
    );
  }
}

/// The card's look, drawn from a decided state — no providers, no flag, no
/// network. Renders nothing for every status that is not visible, so the mount
/// site needs no condition of its own.
class FitVerdictPanel extends StatelessWidget {
  final FitVerdictCardState state;

  /// What "Scan my feet" does. Null renders the invitation with a disabled
  /// button rather than a dead one.
  final VoidCallback? onScanRequested;

  const FitVerdictPanel({
    super.key,
    required this.state,
    this.onScanRequested,
  });

  @override
  Widget build(BuildContext context) {
    if (!state.isVisible) return const SizedBox.shrink();

    final verdict = state.verdict;
    final body = verdict != null
        ? _answer(verdict)
        : (state.status == FitVerdictCardStatus.needsScan
              ? _invite()
              : _checking());

    // Carries its own trailing gap (the `in_your_size_section` rule), so a
    // card that renders nothing leaves no space behind it — the mount site
    // needs no condition and no spacing of its own.
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: body);
  }

  /// The verdict itself: the phrase, the size it is about, the engine's
  /// reasons, and where the millimetres came from.
  Widget _answer(FitVerdict verdict) {
    final color = fitVerdictColor(verdict.kind);
    return Container(
      key: const ValueKey('fit-verdict-card'),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: fitVerdictIcon(verdict.kind), color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fitVerdictPhrase(verdict.kind),
                        style: AppConstants.bodyStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                    // The size the sentence is about, so a customer who
                    // switches size reads the change as the verdict's.
                    _SizeChip(sizeEu: state.sizeEu!, color: color),
                  ],
                ),
                const SizedBox(height: 3),
                // The engine's own sentences — the numbers behind the phrase,
                // including anything it could *not* compare.
                for (final reason in verdict.reasons)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      reason,
                      style: AppConstants.bodyStyle(
                        fontSize: 11.5,
                        color: AppConstants.secondary.withValues(alpha: 0.65),
                        height: 1.35,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Based on your saved foot measurements',
                  style: AppConstants.bodyStyle(
                    fontSize: 10.5,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// No scan, so no verdict — the one thing this card may say without one.
  ///
  /// The button sits **under** the copy rather than beside it, which the home
  /// screen's reminder banner can afford and this card cannot: a fixed-width
  /// label next to a flexible paragraph takes its width from the paragraph,
  /// and at 320 px with large text the sentence ends up in a column a couple
  /// of characters wide (an overflow, not a squeeze — the layout this was
  /// rebuilt for).
  Widget _invite() {
    return Container(
      key: const ValueKey('fit-scan-invite'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
      decoration: BoxDecoration(
        color: AppConstants.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppConstants.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IconTile(
                icon: Icons.straighten_outlined,
                color: AppConstants.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'See how this size fits you',
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scan your feet once — under a minute — and we can '
                      'compare them with this shoe.',
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        color: AppConstants.secondary.withValues(alpha: 0.65),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onScanRequested,
              style: TextButton.styleFrom(
                foregroundColor: AppConstants.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 40),
              ),
              child: Text(
                'Scan my feet',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A saved profile whose scan is being read. One quiet line, same box, so
  /// the verdict can replace it without the page jumping.
  Widget _checking() {
    return Container(
      key: const ValueKey('fit-checking'),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppConstants.secondary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.borderGray),
      ),
      child: Row(
        children: [
          _IconTile(
            icon: Icons.straighten_outlined,
            color: AppConstants.secondary.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Checking your saved measurements…',
              style: AppConstants.bodyStyle(
                fontSize: 11.5,
                color: AppConstants.secondary.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The verdict as words. Short on purpose: the caveats are the engine's
/// `reasons`, printed under it, so the phrase itself never hedges.
String fitVerdictPhrase(FitVerdictKind kind) => switch (kind) {
  FitVerdictKind.tooSmall => 'Too small',
  FitVerdictKind.snug => 'Snug',
  FitVerdictKind.trueToSize => 'True to size',
  FitVerdictKind.roomy => 'Roomy',
  FitVerdictKind.tooBig => 'Too big',
};

/// One colour per band: the two wrong directions read as errors, the two
/// off-target-but-wearable ones as caution, the target band as good.
Color fitVerdictColor(FitVerdictKind kind) => switch (kind) {
  FitVerdictKind.tooSmall || FitVerdictKind.tooBig => AppConstants.error,
  FitVerdictKind.snug || FitVerdictKind.roomy =>
    AppConstants.statusPendingColor,
  FitVerdictKind.trueToSize => AppConstants.success,
};

/// Never colour alone: the band carries an icon too (accessibility — a
/// red/green pair is exactly the pair a colour-blind customer cannot read).
IconData fitVerdictIcon(FitVerdictKind kind) => switch (kind) {
  FitVerdictKind.tooSmall => Icons.unfold_less,
  FitVerdictKind.snug => Icons.straighten,
  FitVerdictKind.trueToSize => Icons.check_circle_outline,
  FitVerdictKind.roomy => Icons.unfold_more,
  FitVerdictKind.tooBig => Icons.warning_amber_rounded,
};

class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconTile({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

/// The size the verdict is about, labelled through `euSizeLabel` so no surface
/// spells an `EU` literal of its own (the `size_key_test.dart` guard).
class _SizeChip extends StatelessWidget {
  final double sizeEu;
  final Color color;

  const _SizeChip({required this.sizeEu, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        euSizeLabel(sizeEu),
        style: AppConstants.bodyStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
