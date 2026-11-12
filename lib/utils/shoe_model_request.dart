/// The 3D model request: its states, its measurements, and the sentence
/// each state says to the seller.
///
/// Pure Dart — no Flutter — so the rules are unit-testable (the
/// `fit_spec_form.dart` / `size_key.dart` precedent), and so the form, the
/// service and the database agree by construction: the plausibility bounds
/// below are the CHECK constraints on `public.shoe_model_requests` in
/// `supabase/migrations/20260928140000_add_shoe_model_requests.sql`.
///
/// WHY THIS EXISTS (roadmap V2.10):
///
/// The upload path next door (`shoe_model_upload.dart`) assumes a seller who
/// can hand over a contract-compliant `.glb`. That is not this market —
/// CUFMAI's sellers are local artisans, and V2.7's first real partner asset
/// came from a marketplace and still needed a normaliser run before it passed.
/// So there is a second door: the seller asks, the team does the modelling,
/// and this file is the language both sides speak.
///
/// Since 2026-11-12 the seller sends no measurements at all — the fitting
/// sizes itself to each customer's foot, so there is nothing a ruler could add
/// that the team cannot see on the product — and the ask is a bare request
/// plus an optional note. The measurement fields stay on the row for the asks
/// that already carry them, and the admin queue still shows those.
///
/// ⚠️ THE ONE NUMBER THAT IS EASY TO GET WRONG, AND EXPENSIVE:
///
/// The length asked for here is the **EXTERNAL** length — what the shoe
/// measures outside, which is what the renderer scales to. It is NOT
/// `products.last_length_mm`, the *internal* last length the fit verdict
/// compares. `SHOE_MODEL_AUTHORING_GUIDE.md` §5 puts the gap at 8–15 mm on
/// leather shoes and says plainly that confusing them "makes the shoe either
/// oversize or misleading". The field is named `external`, the help text says
/// "outside the shoe", and the labels never say "last".
///
/// The second most expensive mistake is a **units** one, and it is likelier
/// here than anywhere else in the app: someone measuring a shoe with a tape
/// writes `27`, not `270`. A centimetre figure is a *plausible* number to a
/// parser and nonsense to a shoemaker, so it earns a message about units
/// rather than "enter a number between 100 and 400" — the `fit_spec_form.dart`
/// rule.
library;

import 'glb_validator.dart';
import 'size_key.dart';

/// External width band. 40 mm is narrower than any wearable shoe and 200 mm is
/// wider than any shoe this shop makes, so a value outside it is a data-entry
/// error rather than a very wide sandal. Mirrors the column's CHECK.
const double kRequestExternalWidthMinMm = 40;
const double kRequestExternalWidthMaxMm = 200;

/// The band for the shoe's overall height — the sole to its highest point.
///
/// There is no existing constant to mirror: this is a new declaration, and the
/// band is chosen so the two ends of this shop's catalogue fit (a sandal's strap
/// is about 40 mm, a knee boot's collar about 400 mm) while two mistakes do not
/// — a figure typed in metres (`0.27`) and a centimetre figure (`27` for a
/// boot), both of which the hint catches below rather than the range.
const double kRequestUpperHeightMinMm = 10;
const double kRequestUpperHeightMaxMm = 400;

/// What the seller is told about the wait, in one place — the ask form and
/// the progress sheet say it in the same words, so the wait cannot be 7 days
/// on one surface and 9 on another.
///
/// 7 business days or more for the model, 9 for the fitting to go live: the
/// two numbers are the team's, and the sentence does not compress them into
/// one because a seller waiting on day 8 should know which half they are
/// waiting on.
const String kShoeModelRequestTimelineMessage =
    'No measuring needed — the CUFMAI team builds the 3D model from your '
    'product, and the fitting sizes itself to each customer\'s foot '
    'automatically. Please allow around 7 business days or more for the 3D '
    'model, and around 9 business days for the 3D fitting to be ready after '
    'you send this request.';

/// Where a request is in its life.
///
/// Two of these are "open" and three are "closed", and the difference is not
/// cosmetic: the partial unique index on the table allows exactly one open
/// request per product, so [isOpen] is what decides whether the seller sees
/// "ask" or "we are on it", and whether they may ask again.
enum ShoeModelRequestStatus {
  requested('requested', 'Waiting for the CUFMAI team'),
  inProgress('in_progress', 'The CUFMAI team is modelling it'),
  fulfilled('fulfilled', 'Ready — it is on your product now'),
  declined('declined', 'The team could not make one'),
  cancelled('cancelled', 'You withdrew this request');

  const ShoeModelRequestStatus(this.wire, this.sellerSentence);

  /// The value the database stores, so no caller invents its own spelling.
  final String wire;

  /// What this state means, in the seller's words rather than the table's.
  final String sellerSentence;

  /// Whether the request is still occupying the product's one open slot.
  bool get isOpen =>
      this == ShoeModelRequestStatus.requested ||
      this == ShoeModelRequestStatus.inProgress;

  /// Reads a status off a row, or null when the value is not one of the five.
  ///
  /// Null rather than a throw, deliberately: an unknown status is a row this
  /// build does not understand (a newer state shipped by a later version), and
  /// the honest answer for the sheet is to offer nothing rather than to claim
  /// the seller has no request.
  static ShoeModelRequestStatus? parse(Object? value) {
    final text = value?.toString();
    for (final status in ShoeModelRequestStatus.values) {
      if (status.wire == text) return status;
    }
    return null;
  }
}

/// The numbers the team needs, plus the size run — every one of them now
/// optional, because the seller sends none (2026-11-12).
class ShoeModelRequestMeasurements {
  /// Outside, heel to toe. The figure the normaliser scales the mesh to —
  /// null since the seller stopped measuring, which is the normal case rather
  /// than a gap: the team models from the product itself.
  final double? externalLengthMm;

  /// Outside, across the widest part. Optional and never used to scale
  /// anything: it is a sanity check a modeller can see at a glance, not an
  /// input to the render.
  final double? externalWidthMm;

  /// Stack height at the heel. Optional.
  final double? heelHeightMm;

  /// Sole to the highest point of the pair. Optional, and the one dimension of
  /// the silhouette the authoring contract does not already check — the
  /// validator reads the mesh's length and grounding, so a declared height is a
  /// second opinion rather than a duplicate of one.
  final double? upperHeightMm;

  /// The EU size the pair measured was. Optional, and distinct from
  /// `authored_size_eu` on the model: that one says what the mesh was exported
  /// at, this one says what was on the bench.
  final double? measuredSizeEu;

  /// **Every size this shoe is made in** — the seller's own run, not a size they
  /// happened to measure.
  ///
  /// It changes nothing the renderer does: one model serves every size, and the
  /// renderer grades the mesh per EU size from the fit spec (§2.5.2's 6.67 mm
  /// step). What the run is for is the **team**: when the model goes on the
  /// bench the modeller can check the sizes that are actually sold rather than
  /// the one pair that was measured, and a run that disagrees with the mesh is a
  /// question worth asking before publish instead of after.
  ///
  /// Empty means "not stated", which is a valid answer and not an error — the
  /// request is complete without it.
  final List<double> sizesEu;

  /// Whether the ask carries anything a ruler could have produced — what
  /// decides whether the progress sheet shows "what you sent" or the wait
  /// instead. A bare ask is not an empty one, so this is never an error.
  bool get hasMeasurements =>
      externalLengthMm != null ||
      externalWidthMm != null ||
      heelHeightMm != null ||
      upperHeightMm != null ||
      measuredSizeEu != null ||
      sizesEu.isNotEmpty;

  const ShoeModelRequestMeasurements({
    this.externalLengthMm,
    this.externalWidthMm,
    this.heelHeightMm,
    this.upperHeightMm,
    this.measuredSizeEu,
    this.sizesEu = const [],
  });

  /// The run as a sentence, for the sheets and the admin queue. A run with no
  /// gaps is written as a range, because `40–44` is what the seller would say.
  String get sizeRunSentence {
    if (sizesEu.isEmpty) return 'Not stated';
    final parts = <String>[];
    var start = sizesEu.first;
    var previous = sizesEu.first;
    for (final size in sizesEu.skip(1)) {
      // A gap of one whole step keeps the run going; two or more starts a new
      // part. The picker offers half sizes, so this is the smallest step that
      // cannot swallow a genuine gap (40 → 42 is not a run of 40–42).
      if (size - previous <= 1) {
        previous = size;
        continue;
      }
      parts.add(_run(start, previous));
      start = size;
      previous = size;
    }
    parts.add(_run(start, previous));
    return parts.join(', ');
  }

  String _run(double start, double end) => start == end
      ? formatSizeNumber(start)
      : '${formatSizeNumber(start)}–${formatSizeNumber(end)}';
}

/// What the action sheet's row does when tapped.
enum ShoeModelRequestAction {
  /// Open the ask form — the product has no request and no model.
  ask,

  /// Open the progress detail — somebody is on it.
  progress,

  /// Show the model that was delivered.
  ready,

  /// Show why it could not be made, and offer to ask again.
  declined,
}

/// One row of the product action sheet, derived from the request's state.
///
/// A record rather than a widget so the four states can be pinned by tests
/// without pumping a screen — and because the label is the thing a seller
/// reads, it is worth asserting word for word.
class ShoeModelRequestRow {
  final String label;
  final String? subtitle;
  final ShoeModelRequestAction action;

  const ShoeModelRequestRow({
    required this.label,
    required this.action,
    this.subtitle,
  });
}

/// The row for a product, given what the queue says about it.
///
/// [productHasModel] wins over everything: a product that already carries a
/// model has nothing to ask for, whatever any historical request says. That
/// ordering is the point — it is what stops a fulfilled request from offering
/// "ask again" on a product that is already done.
ShoeModelRequestRow shoeModelRequestRow({
  required ShoeModelRequestStatus? status,
  required bool productHasModel,
}) {
  if (productHasModel) {
    return const ShoeModelRequestRow(
      label: '3D fitting ready',
      subtitle: 'Customers can try this pair on',
      action: ShoeModelRequestAction.ready,
    );
  }

  switch (status) {
    case ShoeModelRequestStatus.requested:
    case ShoeModelRequestStatus.inProgress:
      return ShoeModelRequestRow(
        label: '3D fitting requested',
        subtitle: status!.sellerSentence,
        action: ShoeModelRequestAction.progress,
      );
    case ShoeModelRequestStatus.fulfilled:
      // A fulfilled request with no live model is a state the RPCs cannot
      // produce (`fulfil_shoe_model_request` refuses anything but an active
      // model), so this is what a *withdrawn* model leaves behind. Offering
      // the ask is the truthful answer: there is nothing on the product.
      return const ShoeModelRequestRow(
        label: 'Request a 3D fitting',
        subtitle: 'You had one made — it is no longer on this product',
        action: ShoeModelRequestAction.ask,
      );
    case ShoeModelRequestStatus.declined:
      return const ShoeModelRequestRow(
        label: '3D fitting request declined',
        subtitle: 'Tap to see why, or ask again',
        action: ShoeModelRequestAction.declined,
      );
    case ShoeModelRequestStatus.cancelled:
    case null:
      return const ShoeModelRequestRow(
        label: 'Request a 3D fitting',
        action: ShoeModelRequestAction.ask,
      );
  }
}

/// What an RPC answered, in a shape the UI can use.
///
/// The RPCs return `{success, message, request_id?}` rather than raising, for
/// everything except an authorisation failure — so "no" arrives as a sentence
/// the seller can read rather than as a PostgrestException nobody can.
class ShoeModelRequestOutcome {
  final bool success;
  final String message;
  final String? requestId;

  const ShoeModelRequestOutcome({
    required this.success,
    required this.message,
    this.requestId,
  });

  /// Reads the json the RPC returned, tolerating the shapes it can arrive in.
  ///
  /// A null body means the call reached the server and came back without a
  /// verdict — which is *not* success, and must never be read as one: the
  /// house rule is that an unknown answer degrades to "not done, and say so".
  factory ShoeModelRequestOutcome.fromRpc(Object? result) {
    if (result is Map) {
      final success = result['success'];
      return ShoeModelRequestOutcome(
        success: success == true,
        message:
            result['message']?.toString() ??
            (success == true
                ? 'Done.'
                : 'The request could not be sent. Please try again.'),
        requestId: result['request_id']?.toString(),
      );
    }
    return const ShoeModelRequestOutcome(
      success: false,
      message: 'The request could not be sent. Please try again.',
    );
  }
}

// ── The team's side: modelling a pair somebody asked for (P2) ──────────────

/// What the admin's upload form starts with, taken from the seller's ask.
///
/// Asks filed before 2026-11-12 carry the seller's own **external** length,
/// taken with a ruler across the outside of the pair: it is the figure the
/// model is scaled to (§2.5.2), so it prefills here and retyping it would
/// only add a way to mistype it. Newer asks carry no measurements at all —
/// the team models from the product itself — and prefill with blanks, which
/// is an empty starting point rather than a missing one. Nothing here invents
/// a number either way.
({String externalLengthMm, String authoredSizeEu})
shoeModelRequestModellingPrefill({
  required double? externalLengthMm,
  required double? measuredSizeEu,
}) => (
  externalLengthMm: externalLengthMm == null
      ? ''
      : formatSizeNumber(externalLengthMm),
  authoredSizeEu: measuredSizeEu == null
      ? ''
      : formatSizeNumber(measuredSizeEu),
);

/// Whether the length the admin declares on the model agrees with the length
/// the seller measured — and the sentence to show when it does not.
///
/// **Two numbers about one shoe, from two different acts.** The seller put a
/// ruler across the outside of the pair; the modeller declares what the mesh was
/// authored to. The contract's tolerance is ±[kLengthToleranceMm] mm (guide
/// §5), and inside it the two are simply two views of the same shoe. Outside it
/// one of them is wrong, and the consequence is asymmetric: the renderer scales
/// the mesh to the **declared** figure, so a mesh declared 20 mm long draws an
/// oversize shoe on every customer's foot — the specific failure the authoring
/// guide's §5 warns about, arriving through the one door this feature opened.
///
/// So it is a **note, not a gate**: the admin may know the seller measured the
/// wrong pair, and refusing to publish would be refusing a correct model. The
/// sentence says which number is bigger and what to check before publishing.
({bool disagrees, String? message}) shoeModelDeclaredLengthAgreement({
  required double? measuredMm,
  required double? declaredMm,
}) {
  if (measuredMm == null || declaredMm == null) {
    return (disagrees: false, message: null);
  }

  final delta = (declaredMm - measuredMm).abs();
  if (delta <= kLengthToleranceMm) {
    return (disagrees: false, message: null);
  }

  final direction = declaredMm > measuredMm ? 'longer' : 'shorter';
  return (
    disagrees: true,
    message:
        'The model is declared ${formatSizeNumber(declaredMm)} mm but the '
        'seller measured ${formatSizeNumber(measuredMm)} mm outside — '
        '${formatSizeNumber(delta)} mm $direction. The renderer scales every '
        'size to the declared figure, so one of the two is wrong: re-measure '
        'the pair, or re-export the mesh at its real size (guide §5).',
  );
}

/// How "model this pair from a link, then close the ask" ends.
///
/// Three endings, and the third is the one worth having a name for.
///
/// The publish and the close are two writes and they can disagree. Collapsing
/// them into "worked" / "failed" would misreport the state to the one person
/// who can fix it, so the partial case is its own ending with copy that states
/// both halves.
///
/// P2 = roadmap V2.10's second half: the seller asks, the team models.
enum ShoeModelRequestModellingEnding {
  /// The model is live **and** the ask is fulfilled — the only ending where the
  /// seller's row turns into "3D model ready".
  closed,

  /// Nothing went live (the server refused the file, or no verdict arrived), so
  /// the ask is untouched and still waiting. Customers see nothing.
  notLive,

  /// ⚠️ **The model went live but the ask could not be closed.** Not a failure —
  /// customers can now render the pair — and not a success either: the seller's
  /// row still says somebody is working on it, and a "done" that never reaches
  /// the seller is the one outcome this feature must not quietly produce.
  liveButOpen,
}

/// One upload-and-close attempt, in a shape the queue can report.
class ShoeModelRequestModellingResult {
  final ShoeModelRequestModellingEnding ending;

  /// What the admin reads. Always set: every ending has something to say.
  final String message;

  /// `product_models.id` this produced, when there is one.
  final int? modelId;

  const ShoeModelRequestModellingResult({
    required this.ending,
    required this.message,
    this.modelId,
  });

  /// True when the seller's ask is now answered.
  bool get closed => ending == ShoeModelRequestModellingEnding.closed;

  /// True when the ask still occupies the product's single open slot, so the
  /// queue must be read again rather than assumed changed.
  bool get requestStaysOpen => !closed;

  /// True when the bytes are live for customers, whatever the ask says. The
  /// distinction [liveButOpen] exists to keep.
  bool get modelIsLive => ending != ShoeModelRequestModellingEnding.notLive;
}

/// Classifies one attempt from the two answers that produced it. Pure, so the
/// three endings and the sentences an admin acts on are pinned by tests rather
/// than by the sheet that happens to call this.
///
/// [refusal] is the server's own sentence when the model did not go live
/// (`ShoeModelServerVerdict.sellerMessage`), because "refused: materials, scale"
/// is actionable and "it did not work" is not.
ShoeModelRequestModellingResult shoeModelRequestModellingResult({
  required bool modelIsLive,
  required bool fulfilled,
  int? modelId,
  String? refusal,
}) {
  if (!modelIsLive) {
    final detail = refusal == null || refusal.trim().isEmpty
        ? 'The server did not accept the file, so it stays hidden.'
        : refusal.trim();
    return ShoeModelRequestModellingResult(
      ending: ShoeModelRequestModellingEnding.notLive,
      modelId: modelId,
      message:
          'The model did not go live, so the request is still waiting. '
          '$detail',
    );
  }

  if (!fulfilled) {
    return ShoeModelRequestModellingResult(
      ending: ShoeModelRequestModellingEnding.liveButOpen,
      modelId: modelId,
      message:
          'The model is live on the product, but the request could not be '
          'closed — it still reads as waiting. Close it as done from the queue; '
          'the model is already there to pick.',
    );
  }

  return ShoeModelRequestModellingResult(
    ending: ShoeModelRequestModellingEnding.closed,
    modelId: modelId,
    message: 'Published and closed — the seller now sees "3D fitting ready".',
  );
}

// ── Internals ───────────────────────────────────────────────────────────────

/// The EU band the column's CHECK enforces, named here so the one guard that
/// still reads the run does not carry a bare `22` and `48` no one can trace
/// back to the schema.
const double kRequestEuSizeMin = 22;
const double kRequestEuSizeMax = 48;

/// Cleans a picked size run: in band, no duplicates, ascending.
///
/// The chips can only produce in-band values, so this is a guard rather than a
/// filter — but a run that reaches the database out of order or twice would make
/// the queue's sentence read as nonsense, and the sorting has to happen
/// somewhere. Silent by design: a size outside the shop's band is not an error
/// the seller can act on from a chip row that never offered it.
List<double> normaliseSizeRun(Iterable<double> sizes) {
  final cleaned =
      sizes
          .where(
            (size) => size >= kRequestEuSizeMin && size <= kRequestEuSizeMax,
          )
          .toSet()
          .toList()
        ..sort();
  return List<double>.unmodifiable(cleaned);
}
