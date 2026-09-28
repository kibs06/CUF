/// One line per product page: what the fit card **would** have said, printed
/// for nobody but the people deciding whether to turn it on.
///
/// This is the roadmap's V1.7 — *shadow mode*. The V1 exit criterion is that
/// the verdict matches an artisan's opinion on 10 real products, and that
/// sample has to exist **before** a customer reads a verdict, not after. So the
/// record is computed as if the card were on (`enabled: true`) regardless of
/// what `AppConstants.virtualFitEnabled` says, and it is written to a log
/// instead of a screen.
///
/// Pure Dart, following `fit_engine.dart`: the *formatting* is unit-testable,
/// and the one place the line is written lives in
/// `lib/services/fit_shadow_log.dart`.
///
/// **What the line is for.** Two readers: the artisan (or whoever runs the
/// V0.8 workshop) comparing our band with what they know about the shoe, and
/// the engineer asking why a page produced nothing. So it carries the identity
/// and the size, the band and the millimetres behind it, the confidence, the
/// customer's foot and the seller's last — enough to diagnose a disagreement
/// without a second look — and, when there is no verdict, *which* rule said so,
/// named exactly as `FitVerdictCardStatus` names it.
library;

import '../models/foot_measurement.dart';
import 'fit_engine.dart';
import 'fit_verdict_state.dart';
import 'size_match.dart';

/// The tag every record starts with — one grep for `[FIT]` in the exported log
/// collects the whole sample.
const String kFitShadowTag = '[FIT]';

/// The shadow record for one product page, or null when there is nothing worth
/// recording.
///
/// Null is one status only: [FitVerdictCardStatus.awaitingScan] is a loading
/// beat, not an outcome — the read that follows it (or the record for it) is
/// what belongs in the log. Every *other* outcome is recorded, including the
/// ones that render nothing, because "how often does this surface have nothing
/// to say" is part of judging whether the flip is worth making.
///
/// [FitVerdictCardStatus.noSpecs] never reaches this function: the card returns
/// before it reads a provider for a product it cannot grade, and how much of
/// the catalog carries a spec is a query (`products.last_length_mm IS NOT
/// NULL` — the coverage metric in the roadmap), not a page view.
///
/// The product row, the selected size and the scan are the raw inputs the card
/// uses, so the record is built by the same decision (`fitVerdictCardStateFor`)
/// that draws the card — with the switch forced on. Two calls of a pure
/// function per page, and no second implementation that could disagree with the
/// screen.
String? fitShadowLine({
  required Map<String, dynamic> product,
  required String? selectedSize,
  required FootMeasurement? measurement,
  required FitScanProbe probe,
  FitBands bands = const FitBands(),
}) {
  final state = fitVerdictCardStateFor(
    enabled: true,
    product: product,
    selectedSize: selectedSize,
    measurement: measurement,
    probe: probe,
    bands: bands,
  );
  if (state.status == FitVerdictCardStatus.awaitingScan) return null;

  final parts = <String>[
    kFitShadowTag,
    'product=${_id(product['id'])}',
  ];

  final verdict = state.verdict;
  if (verdict == null) {
    parts.add('would=${state.status.name}');
  } else {
    parts.add('size=${euSizeLabel(state.sizeEu!)}');
    parts.add('band=${verdict.kind.name}');
    parts.add('toe=${verdict.toeAllowanceMm.round()}');
    final width = verdict.widthAllowanceMm;
    // Omitted rather than zero when the width was never compared: a `width=0`
    // would read as "the same width as the foot", which is a different thing
    // from "we do not know".
    if (width != null) parts.add('width=${width.round()}');
    parts.add('conf=${verdict.confidence.toStringAsFixed(2)}');
  }

  // The raw page size when it did not resolve: `size=EU 42` above already
  // carries the resolved one, and a stored `'JP 25'` is exactly the kind of
  // thing the reviewer needs to see spelled out.
  if (state.verdict == null && selectedSize != null) {
    parts.add('raw=${_quoted(selectedSize)}');
  }

  final footLength = footFitInputFrom(measurement)?.lengthMm;
  if (footLength != null) parts.add('foot=${footLength.round()}');
  final lastLength = FitSpecs.fromProduct(product)?.lastLengthMm;
  if (lastLength != null) parts.add('last=${lastLength.round()}');

  if (verdict != null && verdict.reasons.isNotEmpty) {
    parts.add('why=${_quoted(verdict.reasons.join(' | '))}');
  }

  return parts.join(' ');
}

/// A product id as a bare token — `String`, `int`, or `?` when the row carries
/// none. Never empty and never containing a space, so the line stays parseable
/// by eye (or by `cut`).
String _id(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? '?' : text;
}

/// One field's value, quoted and flattened onto a single line.
///
/// The reasons are the engine's sentences and the sizes are database strings,
/// so neither should contain a newline — but the log is line-based and a stray
/// one would turn a record into two, so the flattening is not left to trust.
String _quoted(String value) {
  final flattened = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return '"${flattened.replaceAll('"', "'")}"';
}
