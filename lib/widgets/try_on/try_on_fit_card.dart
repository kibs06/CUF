import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../utils/fit_engine.dart';
import '../../utils/size_match.dart';
import '../../utils/try_on_fit.dart';
import '../fit_verdict_card.dart' show fitVerdictColor, fitVerdictIcon, fitVerdictPhrase;
import '../foot_size_v2/glass_card.dart';

/// **V4.6's live fit verdict** — the sentence beside the shoe, graded from the
/// foot the camera can actually see.
///
/// A pure function of its inputs, the same split V4.5's coach card uses: the
/// controller owns the reading (`TryOnSessionController.liveFoot`), the rules
/// own the decision (`lib/utils/try_on_fit.dart`), and this widget owns only
/// the English and the glass. It renders **nothing** for every hidden state —
/// no spec, no gradeable size, no lock, no measurement yet — so the column it
/// sits in needs no condition of its own beyond the session gates.
///
/// **It says "live" and it means it.** The product page's card grades the
/// customer's saved scan; this one grades the tracker's own eased heel→toe
/// length, the same number V4.3 sizes the drawn shoe with. When the reading is
/// real but not confident enough to answer with, the card says so and asks for
/// a better one — the roadmap's "scan a bit closer for a better verdict" —
/// instead of printing a hint as a verdict.
///
/// The phrase, icon and colour tables are the V1 card's own functions, reused
/// rather than copied so the two surfaces can never phrase one band two ways.
class TryOnFitCard extends StatelessWidget {
  /// The `products` row, read through [FitSpecs.fromProduct] — the same last
  /// spec every other verdict surface uses.
  final Map<String, dynamic> product;

  /// The size currently selected on the try-on screen; a verdict is about it.
  final String? selectedSize;

  /// The tracker's latest reading, from `liveFoot`.
  final TryOnLiveFoot live;

  const TryOnFitCard({
    super.key,
    required this.product,
    required this.selectedSize,
    required this.live,
  });

  @override
  Widget build(BuildContext context) {
    final state = tryOnFitCardStateFor(
      product: product,
      selectedSize: selectedSize,
      live: live,
    );
    if (!state.isVisible) return const SizedBox.shrink();

    // The trailing gap belongs to the card that may not draw (the scan UI's
    // `in_your_size_section` rule): when the verdict is hidden the coach card
    // below it moves up instead of leaving a 10 px hole.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: state.status == TryOnFitCardStatus.verdict
          ? _VerdictBody(verdict: state.verdict!, sizeEu: state.sizeEu!)
          : const _NudgeBody(),
    );
  }
}

/// The verdict: the phrase, the size it is about, and the engine's own reasons —
/// the same three things the product-page card prints, on glass instead of a
/// light page.
class _VerdictBody extends StatelessWidget {
  final FitVerdict verdict;
  final double sizeEu;

  const _VerdictBody({required this.verdict, required this.sizeEu});

  @override
  Widget build(BuildContext context) {
    final color = fitVerdictColor(verdict.kind);
    return GlassCard(
      key: const ValueKey('try-on-fit-verdict'),
      tone: _toneFor(verdict.kind),
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(fitVerdictIcon(verdict.kind), size: 22, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        fitVerdictPhrase(verdict.kind),
                        style: AppConstants.bodyStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _SizeChip(sizeEu: sizeEu),
                  ],
                ),
                for (final reason in verdict.reasons)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      reason,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Live fit — measured from your foot in view',
                  style: AppConstants.bodyStyle(
                    fontSize: 10.5,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The measurement is real but the engine is not confident: say what to do,
/// not what the answer might be. The sentence is the roadmap's own (V4.6).
class _NudgeBody extends StatelessWidget {
  const _NudgeBody();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: const ValueKey('try-on-fit-nudge'),
      tone: GlassTone.active,
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.zoom_in, size: 22, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Scan a bit closer for a better verdict',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Move the phone a little closer and hold still — the live '
                  'reading is not steady enough to grade this size yet.',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The two wrong directions read as errors, the two off-target-but-wearable
/// ones as caution, the target band as good — the same mapping as the V1 card's
/// colours, expressed in the glass tone added for this surface.
GlassTone _toneFor(FitVerdictKind kind) => switch (kind) {
  FitVerdictKind.tooSmall || FitVerdictKind.tooBig => GlassTone.error,
  FitVerdictKind.snug || FitVerdictKind.roomy => GlassTone.warning,
  FitVerdictKind.trueToSize => GlassTone.success,
};

/// The size the verdict is about, labelled through `euSizeLabel` so no surface
/// spells an `EU` literal of its own (the `size_key_test.dart` guard).
class _SizeChip extends StatelessWidget {
  final double sizeEu;

  const _SizeChip({required this.sizeEu});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        euSizeLabel(sizeEu),
        style: AppConstants.bodyStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
