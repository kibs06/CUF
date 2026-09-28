/// The fit verdict: two sets of millimetres in, one honest answer out.
///
/// Pure Dart — no Flutter — so the band rules are unit-testable without a
/// widget harness, following `size_key.dart` and `size_match.dart`.
///
/// This is the V1 fit engine of `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md`: no
/// 3D, no ARCore, no device. It is the piece a customer feels even when
/// rendering is off, because it answers the question a size label cannot —
/// *this* shoe, in *this* size, on *this* foot.
///
/// **The two halves never mix.** The foot side is compensated millimetres from a
/// scan (`ScanResultsPayloadV2` already carries the sock allowance in, so this
/// engine adds none — architecture §2.6). The shoe side is the **internal last**
/// length and width at a reference size (`products.last_length_mm`,
/// `last_width_mm`, `fit_ref_size_eu`), never the mesh's external heel-to-toe
/// length, which is a rendering number (architecture §2.5.1 vs §2.7.3). Mixing
/// them would hand every customer a verdict one size too generous.
///
/// **No specs, no verdict.** A product without last dimensions returns null
/// rather than a guess, and every uncertain input lowers
/// [FitVerdict.confidence] and is named in [FitVerdict.reasons] instead. The
/// same rule the rest of the size-aware work follows
/// (`docs/AI/SIZE_AWARE_SHOPPING_PLAN.md` §8 R1): never wrong, never confident
/// about it.
///
/// **Every number here is a workshop default.** The bands in [FitBands], the
/// 2 mm width grade and the confidence weights are starting points to be tuned
/// with artisan partners (roadmap V0.8, architecture §2.6) — collected in one
/// place so tuning is a one-file change, and unit tests pin the shipped
/// defaults so a change is deliberate rather than incidental.
library;

import '../models/foot_measurement.dart';
import 'size_match.dart';

/// The EU length grade: one EU size step is 6.67 mm of last length.
///
/// The same number the **rendering** path grades with (architecture §2.5.2),
/// applied here to the internal last instead of the external mesh. They are one
/// constant so the shoe on screen and the shoe in the verdict can never drift
/// apart.
const double kEuLengthStepMm = 6.67;

/// Width gained per EU size step, for lasts that grade linearly.
///
/// Adult lasts widen roughly 1.5–2.5 mm per size; 2.0 mm is the midpoint until
/// partners measure their own grading. Only used to move a measured last width
/// from [FitSpecs.refSizeEu] to the size being judged.
const double kDefaultWidthGradeMm = 2.0;

/// Foot lengths outside this band are a broken measurement, not a small foot.
///
/// The app accepts EU 22 (a child's ~135 mm last) through EU 48; the bounds are
/// deliberately wider than that. A 40 mm "foot" reaching the engine means
/// something upstream failed, and the correct answer is no verdict.
const double kPlausibleFootLengthMm = 110;
const double kPlausibleFootLengthMaxMm = 360;

/// Same idea for width — a scan that reports a 10 mm wide foot has failed.
const double kPlausibleFootWidthMm = 55;
const double kPlausibleFootWidthMaxMm = 160;

/// Last lengths outside this band are a data-entry error, not a small shoe.
/// Mirrors the CHECK constraints on `products.last_length_mm`.
const double kPlausibleLastLengthMm = 120;
const double kPlausibleLastLengthMaxMm = 360;

/// Last widths outside this band are treated as absent rather than fatal: the
/// length comparison is still worth making, so the verdict degrades to a
/// length-only one and says so. Mirrors the CHECK on `products.last_width_mm`.
const double kPlausibleLastWidthMm = 40;
const double kPlausibleLastWidthMaxMm = 140;

/// Heel/stack height band. No band reads heel height yet, so this exists so the
/// seller form (`fit_spec_form.dart`) and the column's CHECK constraint
/// (`products.heel_height_mm`) validate against the same numbers instead of
/// each owning half a rule.
const double kPlausibleHeelHeightMm = 0;
const double kPlausibleHeelHeightMaxMm = 80;

/// The size the linear grade is trusted to reach without losing much accuracy.
/// Within ±2 steps the verdict is not discounted at all.
const int kFreeExtrapolationSteps = 2;

/// Beyond [kFreeExtrapolationSteps] each extra step costs 5 % of confidence,
/// down to this floor; past [kMaxExtrapolationSteps] no verdict is produced at
/// all, because a 6.67 mm/step straight line says nothing about a last ten
/// sizes away from the sample that was measured.
const double kMinExtrapolationFactor = 0.7;
const int kMaxExtrapolationSteps = 8;

/// Scan confidence assumed when a measurement carries none — older scans, and
/// paper/manual entries that never captured quality signals. Not 1.0: an
/// unmeasured confidence is not a good one.
const double kUnknownScanConfidence = 0.75;

/// Below this the verdict is still worth showing as a hint, but no surface
/// should present it as an answer (`FitVerdict.isConfident`).
const double kMinVerdictConfidence = 0.45;

/// What the engine thinks of one size.
///
/// Names map to architecture §2.6 one-for-one; `true` is a reserved word in
/// Dart, hence [trueToSize].
enum FitVerdictKind {
  /// No toe room left, or the last is narrower than the foot.
  tooSmall,

  /// 3–8 mm of toe room: close, usually wearable, worth saying out loud.
  snug,

  /// The target band — 8–14 mm of toe room with the width inside −1…6 mm.
  trueToSize,

  /// More room than the band wants: >14 mm of toe room or a last >6 mm wider.
  roomy,

  /// >22 mm of toe room: the shoe is a whole size out, not a preference.
  tooBig,
}

/// The band thresholds, in millimetres — the one place they are written down.
///
/// Width bands are signed allowances (`last − foot`): −1 mm means the last is
/// 1 mm narrower than the foot. Pass a tuned instance to
/// [fitVerdictAt]/[recommendFit] after the V0.8 workshop rather than editing
/// the defaults in place, so old and new verdicts stay comparable.
class FitBands {
  final double tooSmallToeMm;
  final double snugToeMm;
  final double trueToeMaxMm;
  final double tooBigToeMm;
  final double narrowWidthMm;
  final double wideWidthMm;

  const FitBands({
    this.tooSmallToeMm = 3,
    this.snugToeMm = 8,
    this.trueToeMaxMm = 14,
    this.tooBigToeMm = 22,
    this.narrowWidthMm = -1,
    this.wideWidthMm = 6,
  });
}

/// The foot side of a verdict: compensated millimetres, already sock-adjusted.
class FootFitInput {
  /// Compensated length of the sizing foot, in mm.
  final double lengthMm;

  /// Compensated width of the same foot, in mm — null when unknown. The verdict
  /// then compares length only and says so.
  ///
  /// A width outside [kPlausibleFootWidthMm]…[kPlausibleFootWidthMaxMm] is
  /// treated the same way: the length is the primary signal and is still worth
  /// judging, so one broken number does not cost the customer the verdict.
  final double? widthMm;

  /// 0–1 quality of the scan this came from, or null when the measurement never
  /// carried one. Multiplied into [FitVerdict.confidence].
  final double? scanConfidence;

  const FootFitInput({
    required this.lengthMm,
    this.widthMm,
    this.scanConfidence,
  });
}

/// The shoe side of a verdict: the **internal last** at a reference size.
class FitSpecs {
  /// Internal last length in mm at [refSizeEu].
  final double lastLengthMm;

  /// Internal last width in mm at [refSizeEu]; null when the seller has not
  /// measured it. Width grading from [refSizeEu] uses [widthGradeMm].
  final double? lastWidthMm;

  /// Carried for later silhouette nuance; the current bands do not read it.
  final double? heelHeightMm;

  /// The EU size [lastLengthMm] and [lastWidthMm] were measured at. Required:
  /// every other size is graded from this one, and guessing it would grade the
  /// whole range from a number nobody measured.
  final double refSizeEu;

  /// Length added per EU size step. Overridable for a last that grades
  /// unusually, though the contract expects the standard 6.67 mm.
  final double sizeStepMm;

  /// Width added per EU size step.
  final double widthGradeMm;

  const FitSpecs({
    required this.lastLengthMm,
    required this.refSizeEu,
    this.lastWidthMm,
    this.heelHeightMm,
    this.sizeStepMm = kEuLengthStepMm,
    this.widthGradeMm = kDefaultWidthGradeMm,
  });

  /// Read the fit spec off a `products` row, or null when the row cannot carry
  /// a verdict.
  ///
  /// Null covers three cases the caller must not try to tell apart — it hides
  /// the card either way: the columns are unset (no spec yet), the length and
  /// reference size disagree with each other (half-filled), or a value is
  /// outside the plausible band (a typo). The engine re-checks the numbers, so
  /// a bad row can never reach a verdict through a different door.
  static FitSpecs? fromProduct(Map<String, dynamic> product) {
    final length = _number(product['last_length_mm']);
    final refSize = _number(product['fit_ref_size_eu']);
    if (length == null || refSize == null) return null;
    if (length < kPlausibleLastLengthMm ||
        length > kPlausibleLastLengthMaxMm) {
      return null;
    }
    if (refSize < kPlausibleEuMin || refSize > kPlausibleEuMax) return null;

    final width = _number(product['last_width_mm']);
    return FitSpecs(
      lastLengthMm: length,
      refSizeEu: refSize,
      // An implausible width is dropped, not fatal: a length-only verdict is
      // still worth having, and the reasons will say the width went unchecked.
      lastWidthMm: width != null &&
              width >= kPlausibleLastWidthMm &&
              width <= kPlausibleLastWidthMaxMm
          ? width
          : null,
      heelHeightMm: _number(product['heel_height_mm']),
    );
  }
}

/// What the engine concluded, and how much of it to believe.
class FitVerdict {
  /// The EU size this verdict is about.
  final double sizeEu;

  final FitVerdictKind kind;

  /// Last length at [sizeEu] minus foot length, in mm. Negative means the shoe
  /// is shorter than the foot.
  final double toeAllowanceMm;

  /// Last width minus foot width, in mm; null when either side is unknown, so
  /// no surface should imply the width was checked.
  final double? widthAllowanceMm;

  /// 0–1. Scan quality × spec completeness × distance from the measured sample.
  final double confidence;

  /// Short human-readable sentences — the "why" a card can print under the
  /// verdict. The numbers above stay the source of truth; these explain them.
  final List<String> reasons;

  const FitVerdict({
    required this.sizeEu,
    required this.kind,
    required this.toeAllowanceMm,
    required this.widthAllowanceMm,
    required this.confidence,
    required this.reasons,
  });

  /// Whether the width was actually compared (both sides known).
  bool get widthCompared => widthAllowanceMm != null;

  /// Whether this is worth showing as an answer rather than a hint.
  bool get isConfident => confidence >= kMinVerdictConfidence;

  FitVerdict withReason(String reason) => FitVerdict(
        sizeEu: sizeEu,
        kind: kind,
        toeAllowanceMm: toeAllowanceMm,
        widthAllowanceMm: widthAllowanceMm,
        confidence: confidence,
        reasons: [...reasons, reason],
      );
}

/// The last's internal length at [sizeEu], graded from the measured sample.
double lastLengthAt(FitSpecs shoe, double sizeEu) =>
    shoe.lastLengthMm + (sizeEu - shoe.refSizeEu) * shoe.sizeStepMm;

/// The last's internal width at [sizeEu], or null when it was never measured.
double? lastWidthAt(FitSpecs shoe, double sizeEu) {
  final measured = shoe.lastWidthMm;
  if (measured == null) return null;
  return measured + (sizeEu - shoe.refSizeEu) * shoe.widthGradeMm;
}

/// The verdict for one size, or null when there is nothing honest to say.
///
/// Null means: no usable foot length, no usable last spec, an implausible
/// number on either side, or a size so far from the measured sample that the
/// linear grade is meaningless ([kMaxExtrapolationSteps]). Every one of those
/// is a "render nothing" for the caller — never a default verdict.
FitVerdict? fitVerdictAt({
  required FootFitInput foot,
  required FitSpecs shoe,
  required double sizeEu,
  FitBands bands = const FitBands(),
}) {
  if (!_plausibleFoot(foot)) return null;
  if (!_plausibleShoe(shoe)) return null;
  if (sizeEu.isNaN || sizeEu.isInfinite) return null;
  if ((sizeEu - shoe.refSizeEu).abs() > kMaxExtrapolationSteps) return null;

  final toeAllowance = lastLengthAt(shoe, sizeEu) - foot.lengthMm;
  final widthAllowance = _widthAllowance(foot, shoe, sizeEu);
  final kind = _classify(toeAllowance, widthAllowance, bands);
  final steps = (sizeEu - shoe.refSizeEu).abs();
  final scan = _scanConfidence(foot);
  final confidence = _confidence(
    scan: scan,
    widthCompared: widthAllowance != null,
    steps: steps,
  );

  return FitVerdict(
    sizeEu: sizeEu,
    kind: kind,
    toeAllowanceMm: toeAllowance,
    widthAllowanceMm: widthAllowance,
    confidence: confidence,
    reasons: _reasons(
      shoe: shoe,
      foot: foot,
      sizeEu: sizeEu,
      kind: kind,
      toeAllowanceMm: toeAllowance,
      widthAllowanceMm: widthAllowance,
      bands: bands,
      steps: steps,
      scan: scan,
      confidence: confidence,
    ),
  );
}

/// The size to buy out of [sizesEu], or null when no candidate can be judged.
///
/// "The tightest size that still fits": the healthy band is a *range* of toe
/// room, so among sizes that reach it the smallest is the right buy — the shoe
/// that reaches the band first is the one that will not stretch into a
/// different shape. When nothing reaches the band the answer is the candidate
/// closest to it, which is what the caller's "closest fit" wording reports.
///
/// Because last length grows monotonically with size, the candidates form one
/// contiguous block per band; the ranking below is therefore a preference
/// order, not a vote ([_rank]).
FitVerdict? recommendFit({
  required FootFitInput foot,
  required FitSpecs shoe,
  required Iterable<double> sizesEu,
  FitBands bands = const FitBands(),
}) {
  final verdicts = <FitVerdict>[];
  for (final size in sizesEu.toSet()) {
    final verdict = fitVerdictAt(
      foot: foot,
      shoe: shoe,
      sizeEu: size,
      bands: bands,
    );
    if (verdict != null) verdicts.add(verdict);
  }
  if (verdicts.isEmpty) return null;

  verdicts.sort((a, b) => _compare(a, b, bands));
  final best = verdicts.first;
  return best.kind == FitVerdictKind.trueToSize
      ? best
      : best.withReason(
          'closest fit among the sizes available — not the target fit itself',
        );
}

// ── Internals ───────────────────────────────────────────────────────────────

/// Length only. The width is handled by [_usableFootWidth] — a bad width costs
/// the width comparison, not the verdict.
bool _plausibleFoot(FootFitInput foot) {
  if (foot.lengthMm.isNaN || foot.lengthMm.isInfinite) return false;
  if (foot.lengthMm < kPlausibleFootLengthMm) return false;
  return foot.lengthMm <= kPlausibleFootLengthMaxMm;
}

/// A width the engine is willing to compare, or null when there is none to
/// trust — absent, NaN/infinite, or outside the plausible band. Mirrors how an
/// implausible product width is dropped in [FitSpecs.fromProduct].
///
/// [_badFootWidth] keeps the *reason* apart from a plain absence: "no width in
/// your scan" and "the width in your scan is not usable" are different things
/// to tell a customer, and the second one is a bug report.
double? _usableFootWidth(FootFitInput foot) {
  final width = foot.widthMm;
  if (width == null || width.isNaN || width.isInfinite) return null;
  if (width < kPlausibleFootWidthMm || width > kPlausibleFootWidthMaxMm) {
    return null;
  }
  return width;
}

/// The unusable width itself, or null when the width was simply absent.
///
/// Never returns NaN/infinite: a reason has to be printable, and
/// `double.nan.round()` throws.
double? _badFootWidth(FootFitInput foot) {
  final width = foot.widthMm;
  if (width == null || width.isNaN || width.isInfinite) return null;
  return _usableFootWidth(foot) == null ? width : null;
}

bool _plausibleShoe(FitSpecs shoe) {
  if (shoe.lastLengthMm.isNaN || shoe.lastLengthMm.isInfinite) return false;
  if (shoe.lastLengthMm < kPlausibleLastLengthMm) return false;
  if (shoe.lastLengthMm > kPlausibleLastLengthMaxMm) return false;
  if (shoe.refSizeEu.isNaN || shoe.refSizeEu.isInfinite) return false;
  if (shoe.refSizeEu < kPlausibleEuMin || shoe.refSizeEu > kPlausibleEuMax) {
    return false;
  }
  return shoe.sizeStepMm > 0;
}

double? _widthAllowance(FootFitInput foot, FitSpecs shoe, double sizeEu) {
  final footWidth = _usableFootWidth(foot);
  final lastWidth = lastWidthAt(shoe, sizeEu);
  if (footWidth == null || lastWidth == null) return null;
  return lastWidth - footWidth;
}

/// Width can veto length, and only in the directions architecture §2.6 gives
/// it. Bands are checked in the order that table lists them, first match wins:
///
///  * a last 1 mm narrower than the foot is [FitVerdictKind.tooSmall] however
///    much toe room there is — a foot that cannot enter the shoe is not a fit
///    question;
///  * a last 6 mm wider is [FitVerdictKind.roomy] even when the length is snug,
///    because the size that would fix the length makes the width worse. The
///    reasons name that conflict rather than hiding it behind one word.
FitVerdictKind _classify(
  double toeAllowance,
  double? widthAllowance,
  FitBands bands,
) {
  if (toeAllowance < bands.tooSmallToeMm ||
      (widthAllowance != null && widthAllowance < bands.narrowWidthMm)) {
    return FitVerdictKind.tooSmall;
  }
  if (toeAllowance > bands.tooBigToeMm) return FitVerdictKind.tooBig;
  if (toeAllowance > bands.trueToeMaxMm ||
      (widthAllowance != null && widthAllowance > bands.wideWidthMm)) {
    return FitVerdictKind.roomy;
  }
  // A known width that is outside the band was already claimed above, so only
  // the length is left to check here.
  if (toeAllowance >= bands.snugToeMm) return FitVerdictKind.trueToSize;
  return FitVerdictKind.snug;
}

double _scanConfidence(FootFitInput foot) {
  final raw = foot.scanConfidence;
  if (raw == null || raw.isNaN) return kUnknownScanConfidence;
  return raw.clamp(0.0, 1.0);
}

/// Scan quality × completeness × how far the size is from the measured sample.
///
/// Deliberately multiplicative: a low-quality scan cannot be rescued by a
/// complete spec, and a spec measured at EU 42 says little about EU 32 no
/// matter how good the scan was. The floor keeps the result usable — a hint —
/// and [kMaxExtrapolationSteps] is where the engine stops answering at all.
double _confidence({
  required double scan,
  required bool widthCompared,
  required double steps,
}) {
  final completeness = widthCompared ? 0.85 : 0.60;
  final extrapolation = steps <= kFreeExtrapolationSteps
      ? 1.0
      : (1.0 - (steps - kFreeExtrapolationSteps) * 0.05)
          .clamp(kMinExtrapolationFactor, 1.0);
  return (scan * completeness * extrapolation).clamp(0.0, 1.0);
}

List<String> _reasons({
  required FitSpecs shoe,
  required FootFitInput foot,
  required double sizeEu,
  required FitVerdictKind kind,
  required double toeAllowanceMm,
  required double? widthAllowanceMm,
  required FitBands bands,
  required double steps,
  required double scan,
  required double confidence,
}) {
  final reasons = <String>[_toeSentence(kind, toeAllowanceMm, bands)];

  if (widthAllowanceMm != null) {
    reasons.add(_widthSentence(widthAllowanceMm, bands));
    // "Snug in length" has to mean it: below the minimum the advice is simply
    // wrong — a different *size* is exactly what would fix a shoe that is too
    // short — so the line only appears while the length sits inside the snug
    // band. When the length is out of band, the two sentences above already
    // say both things without offering a conclusion that does not follow.
    if (widthAllowanceMm > bands.wideWidthMm &&
        toeAllowanceMm >= bands.tooSmallToeMm &&
        toeAllowanceMm < bands.snugToeMm) {
      reasons.add(
        'snug in length but loose in width — a different last shape is likely '
        'to fit you better than a different size',
      );
    }
  } else {
    if (shoe.lastWidthMm == null) {
      reasons.add('width not compared — this product has no last width recorded');
    }
    final badWidth = _badFootWidth(foot);
    if (badWidth != null) {
      reasons.add(
        'width not compared — your scan reported ${badWidth.round()} mm, '
        'which is out of range',
      );
    } else if (foot.widthMm == null) {
      reasons.add('width not compared — no width in your scan');
    } else if (foot.widthMm!.isNaN || foot.widthMm!.isInfinite) {
      reasons.add('width not compared — your scan\'s width is not a number');
    }
  }

  if (steps > kFreeExtrapolationSteps) {
    // `euSizeLabel` (size_match.dart) rather than a hand-built label: one place
    // spells a size for every surface, and `size_key_test.dart`'s guard keeps it
    // that way.
    reasons.add(
      'spec measured at ${euSizeLabel(shoe.refSizeEu)}; '
      '${euSizeLabel(sizeEu)} is ${steps.round()} sizes away',
    );
  }
  if (scan < 0.6) {
    reasons.add(
      'scan confidence ${scan.toStringAsFixed(2)} — the measurement is the '
      'weakest link here',
    );
  }
  if (confidence < kMinVerdictConfidence) {
    reasons.add(
      'overall confidence ${confidence.toStringAsFixed(2)}, under the '
      '${kMinVerdictConfidence.toStringAsFixed(2)} floor — treat as a hint, '
      'not an answer',
    );
  }
  return reasons;
}

String _toeSentence(
  FitVerdictKind kind,
  double toeAllowanceMm,
  FitBands bands,
) {
  final toe = toeAllowanceMm.round();
  final target = '${bands.snugToeMm.round()}–${bands.trueToeMaxMm.round()} mm';
  if (toeAllowanceMm < 0) {
    return 'the last is ${-toe} mm shorter than your foot';
  }
  // The "under the minimum" clause belongs to a *length* veto. When the width
  // is what made the verdict `tooSmall` — a last narrower than the foot,
  // whatever the toe room — the toe is inside the band and the width sentence
  // printed under this one does the explaining. Claiming the minimum was
  // broken there would contradict the reason right below it.
  if (kind == FitVerdictKind.tooSmall && toeAllowanceMm < bands.tooSmallToeMm) {
    return 'only $toe mm of toe room — under the '
        '${bands.tooSmallToeMm.round()} mm minimum';
  }
  return switch (kind) {
    FitVerdictKind.snug => '$toe mm of toe room — snug '
        '(target $target)',
    FitVerdictKind.trueToSize => '$toe mm of toe room — true to size',
    FitVerdictKind.roomy => '$toe mm of toe room — roomier than the '
        '$target target',
    FitVerdictKind.tooBig => '$toe mm of toe room — a whole size too much',
    FitVerdictKind.tooSmall => 'only $toe mm of toe room',
  };
}

String _widthSentence(double widthAllowanceMm, FitBands bands) {
  final width = widthAllowanceMm.round();
  if (width > 0) return 'the last is $width mm wider than your foot';
  if (width < 0) return 'the last is ${-width} mm narrower than your foot';
  return 'the last is the same width as your foot';
}

/// Preference order across bands. A contiguous run of sizes produces at most
/// one band block each, so this decides *between* blocks: a true fit always
/// wins, and when there is none, snug (slightly close) beats roomy (slightly
/// loose) beats a shoe that is outright wrong in either direction.
int _rank(FitVerdictKind kind) => switch (kind) {
      FitVerdictKind.trueToSize => 0,
      FitVerdictKind.snug => 1,
      FitVerdictKind.roomy => 2,
      FitVerdictKind.tooSmall => 3,
      FitVerdictKind.tooBig => 4,
    };

/// How far outside the healthy band a verdict sits, in mm. 0 inside it; used to
/// break ties within one band, so the snug candidate closest to 8 mm wins and
/// the roomy one closest to 14 mm wins. Ties fall to the smaller size, so the
/// engine never advertises a bigger shoe than it has to.
int _compare(FitVerdict a, FitVerdict b, FitBands bands) {
  final byRank = _rank(a.kind).compareTo(_rank(b.kind));
  if (byRank != 0) return byRank;
  final byMiss = _miss(a, bands).compareTo(_miss(b, bands));
  if (byMiss != 0) return byMiss;
  return a.sizeEu.compareTo(b.sizeEu);
}

double _miss(FitVerdict verdict, FitBands bands) =>
    _toeMiss(verdict.toeAllowanceMm, bands) +
    _widthMiss(verdict.widthAllowanceMm, bands);

double _toeMiss(double toeAllowance, FitBands bands) {
  if (toeAllowance < bands.snugToeMm) return bands.snugToeMm - toeAllowance;
  if (toeAllowance > bands.trueToeMaxMm) {
    return toeAllowance - bands.trueToeMaxMm;
  }
  return 0;
}

double _widthMiss(double? widthAllowance, FitBands bands) {
  if (widthAllowance == null) return 0;
  if (widthAllowance < bands.narrowWidthMm) {
    return bands.narrowWidthMm - widthAllowance;
  }
  if (widthAllowance > bands.wideWidthMm) {
    return widthAllowance - bands.wideWidthMm;
  }
  return 0;
}

/// The foot side of a verdict from a stored scan.
///
/// Uses the *compensated* millimetres on the sizing foot — the same numbers the
/// recommended size was derived from (the v2 E8 rule: every mm the customer
/// sees comes from one conversion path). Returns null when the scan has no
/// length at all: a saved width alone cannot answer a sizing question.
FootFitInput? footFitInputFrom(FootMeasurement? measurement) {
  final length = measurement?.maxFootLength;
  if (measurement == null || length == null) return null;
  return FootFitInput(
    lengthMm: length,
    widthMm: measurement.sizingFootWidth,
    scanConfidence: _scanConfidenceFrom(measurement),
  );
}

double? _scanConfidenceFrom(FootMeasurement measurement) {
  final score = measurement.overallConfidenceScore;
  if (score != null && !score.isNaN) return score.clamp(0.0, 1.0);
  return switch (measurement.confidenceLevel) {
    'high' => 0.9,
    'medium' => 0.7,
    'low' => 0.5,
    // No score and no level: leave it to the engine's documented default rather
    // than inventing one here.
    _ => null,
  };
}

/// A JSON value that may arrive as a number or as a numeric string.
double? _number(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}
