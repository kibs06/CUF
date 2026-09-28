/// The 3D model request: its states, its four measurements, and the sentence
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
/// So there is a second door: the seller measures the pair with a ruler, the
/// team does the modelling, and this file is the language both sides speak.
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
/// rule, and the reason [ShoeModelRequestFormResult.messageFor] exists.
library;

import 'fit_engine.dart';
import 'glb_validator.dart';
import 'size_key.dart';

/// External width band. 40 mm is narrower than any wearable shoe and 200 mm is
/// wider than any shoe this shop makes, so a value outside it is a data-entry
/// error rather than a very wide sandal. Mirrors the column's CHECK.
const double kRequestExternalWidthMinMm = 40;
const double kRequestExternalWidthMaxMm = 200;

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

/// Which field an error belongs to, so the form can show it inline.
enum ShoeModelRequestField {
  externalLengthMm,
  externalWidthMm,
  heelHeightMm,
  measuredSizeEu,
}

/// The four numbers the team needs, in the seller's units.
class ShoeModelRequestMeasurements {
  /// Outside, heel to toe. **Required** — it is the figure the normaliser
  /// scales the mesh to, so a request without it cannot become a model.
  final double externalLengthMm;

  /// Outside, across the widest part. Optional and never used to scale
  /// anything: it is a sanity check a modeller can see at a glance, not an
  /// input to the render.
  final double? externalWidthMm;

  /// Stack height at the heel. Optional.
  final double? heelHeightMm;

  /// The EU size the pair measured was. Optional, and distinct from
  /// `authored_size_eu` on the model: that one says what the mesh was exported
  /// at, this one says what was on the bench.
  final double? measuredSizeEu;

  const ShoeModelRequestMeasurements({
    required this.externalLengthMm,
    this.externalWidthMm,
    this.heelHeightMm,
    this.measuredSizeEu,
  });
}

/// The outcome of reading the request form's four text fields, in one of three
/// states — the [FitSpecFormResult] shape, for the same reasons:
///
///  * [isEmpty] — every field blank, so there is nothing to send.
///  * [isError] — the seller has something to fix; [errorField] says where to
///    show the sentence, and [measurements] is null.
///  * otherwise — a complete, plausible set to send.
class ShoeModelRequestFormResult {
  /// The parsed measurements, or null when the fields are blank or invalid.
  final ShoeModelRequestMeasurements? measurements;

  /// The sentence to show the seller, or null when there is nothing to fix.
  final String? error;

  /// The field [error] belongs to; null when there is no error.
  final ShoeModelRequestField? errorField;

  const ShoeModelRequestFormResult._({
    this.measurements,
    this.error,
    this.errorField,
  });

  /// Every field blank.
  const ShoeModelRequestFormResult.empty()
      : measurements = null,
        error = null,
        errorField = null;

  /// Reads the four raw field values.
  factory ShoeModelRequestFormResult.fromFields({
    required String externalLengthMm,
    required String externalWidthMm,
    required String heelHeightMm,
    required String measuredSizeEu,
  }) {
    final lengthText = externalLengthMm.trim();
    final widthText = externalWidthMm.trim();
    final heelText = heelHeightMm.trim();
    final sizeText = measuredSizeEu.trim();

    if (lengthText.isEmpty &&
        widthText.isEmpty &&
        heelText.isEmpty &&
        sizeText.isEmpty) {
      return const ShoeModelRequestFormResult.empty();
    }

    // The length is required, and it is checked first so that a blank length
    // beside a filled width is reported as "the length is missing" rather than
    // as anything about the width.
    if (lengthText.isEmpty) {
      return const ShoeModelRequestFormResult._(
        error: 'Measure the pair and enter the length — the modeller scales '
            'everything from it, so a request without it cannot be started.',
        errorField: ShoeModelRequestField.externalLengthMm,
      );
    }

    final length = _parseMm(
      lengthText,
      what: 'the length',
      min: kPlausibleLengthMinMm,
      max: kPlausibleLengthMaxMm,
      centimetresHint: true,
    );
    if (length.error != null) {
      return ShoeModelRequestFormResult._(
        error: length.error,
        errorField: ShoeModelRequestField.externalLengthMm,
      );
    }

    final width = _parseMm(
      widthText,
      what: 'the width',
      min: kRequestExternalWidthMinMm,
      max: kRequestExternalWidthMaxMm,
      centimetresHint: true,
    );
    if (width.error != null) {
      return ShoeModelRequestFormResult._(
        error: width.error,
        errorField: ShoeModelRequestField.externalWidthMm,
      );
    }

    final heel = _parseMm(
      heelText,
      what: 'the heel height',
      min: kPlausibleHeelHeightMm,
      max: kPlausibleHeelHeightMaxMm,
      centimetresHint: false,
    );
    if (heel.error != null) {
      return ShoeModelRequestFormResult._(
        error: heel.error,
        errorField: ShoeModelRequestField.heelHeightMm,
      );
    }

    final size = _parseSize(sizeText);
    if (size.error != null) {
      return ShoeModelRequestFormResult._(
        error: size.error,
        errorField: ShoeModelRequestField.measuredSizeEu,
      );
    }

    return ShoeModelRequestFormResult._(
      measurements: ShoeModelRequestMeasurements(
        externalLengthMm: length.value!,
        externalWidthMm: width.value,
        heelHeightMm: heel.value,
        measuredSizeEu: size.value,
      ),
    );
  }

  /// Whether the fields are all blank — nothing to send, nothing to fix.
  bool get isEmpty => measurements == null && error == null;

  /// Whether the seller has something to fix.
  bool get isError => error != null;

  /// The sentence to show under [field], or null when that field is fine.
  String? messageFor(ShoeModelRequestField field) =>
      errorField == field ? error : null;
}

/// What the action sheet's row does when tapped.
enum ShoeModelRequestAction {
  /// Open the measurement form — the product has no request and no model.
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
      label: '3D model ready',
      subtitle: 'Customers can try this pair on',
      action: ShoeModelRequestAction.ready,
    );
  }

  switch (status) {
    case ShoeModelRequestStatus.requested:
    case ShoeModelRequestStatus.inProgress:
      return ShoeModelRequestRow(
        label: '3D model requested',
        subtitle: status!.sellerSentence,
        action: ShoeModelRequestAction.progress,
      );
    case ShoeModelRequestStatus.fulfilled:
      // A fulfilled request with no live model is a state the RPCs cannot
      // produce (`fulfil_shoe_model_request` refuses anything but an active
      // model), so this is what a *withdrawn* model leaves behind. Offering
      // the ask is the truthful answer: there is nothing on the product.
      return const ShoeModelRequestRow(
        label: 'Request a 3D model',
        subtitle: 'You had one made — it is no longer on this product',
        action: ShoeModelRequestAction.ask,
      );
    case ShoeModelRequestStatus.declined:
      return const ShoeModelRequestRow(
        label: '3D model request declined',
        subtitle: 'Tap to see why, or ask again',
        action: ShoeModelRequestAction.declined,
      );
    case ShoeModelRequestStatus.cancelled:
    case null:
      return const ShoeModelRequestRow(
        label: 'Request a 3D model',
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
        message: result['message']?.toString() ??
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

/// What to prefill the form with from a product's existing fit spec.
///
/// ⚠️ **The length is deliberately NOT prefilled, and that is the whole design
/// of this function.** `products.last_length_mm` is the INTERNAL last length —
/// 8–15 mm shorter than the outside of the same shoe on leather
/// (`SHOE_MODEL_AUTHORING_GUIDE.md` §5) — and the request needs the EXTERNAL
/// one. Offering the internal figure in the external field would put a
/// plausible wrong number in front of the seller, which is worse than an empty
/// box: they would confirm it, and every mesh from then on would be scaled
/// short by an amount nobody wrote down.
///
/// The heel height and the size ARE the same quantity measured the same way, so
/// prefilling those saves real work and cannot mislead. The length is measured
/// with a ruler and typed once, and the help text says where to put it.
({String externalLengthMm, String heelHeightMm, String measuredSizeEu})
    shoeModelRequestPrefill(Map<String, dynamic>? spec) {
  final heel = _number(spec?['heel_height_mm']?.toString());
  final size = _number(spec?['fit_ref_size_eu']?.toString());
  return (
    externalLengthMm: '',
    heelHeightMm: heel == null ? '' : formatSizeNumber(heel),
    measuredSizeEu: size == null ? '' : formatSizeNumber(size),
  );
}

// ── The team's side: modelling a pair somebody asked for (P2) ──────────────

/// What the admin's upload form starts with, taken from the seller's ask.
///
/// ⚠️ **The length IS prefilled here — the exact opposite of
/// [shoeModelRequestPrefill] — and the difference is the whole point.** There,
/// the only length on hand was `products.last_length_mm`, the *internal* last,
/// 8–15 mm shorter than the outside of the same shoe, so offering it would have
/// put a plausible wrong figure in front of a seller who would then confirm it.
/// Here the number on hand is the seller's own **external** measurement, taken
/// with a ruler across the outside of the pair and sent for exactly this
/// purpose: it is the figure the model is scaled to (§2.5.2), so it is the
/// right starting point and retyping it would only add a way to mistype it.
///
/// The size is the same quantity on both sides too — the EU size of the pair
/// that was measured — so it prefills as well. Nothing here invents a number:
/// a request always carries a length (the column is `NOT NULL`), and blank is
/// returned for the two optional figures when they were not sent.
({String externalLengthMm, String authoredSizeEu})
    shoeModelRequestModellingPrefill({
  required double? externalLengthMm,
  required double? measuredSizeEu,
}) =>
        (
          externalLengthMm: externalLengthMm == null
              ? ''
              : formatSizeNumber(externalLengthMm),
          authoredSizeEu:
              measuredSizeEu == null ? '' : formatSizeNumber(measuredSizeEu),
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
    message: 'The model is declared ${formatSizeNumber(declaredMm)} mm but the '
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
      message: 'The model did not go live, so the request is still waiting. '
          '$detail',
    );
  }

  if (!fulfilled) {
    return ShoeModelRequestModellingResult(
      ending: ShoeModelRequestModellingEnding.liveButOpen,
      modelId: modelId,
      message: 'The model is live on the product, but the request could not be '
          'closed — it still reads as waiting. Close it as done from the queue; '
          'the model is already there to pick.',
    );
  }

  return ShoeModelRequestModellingResult(
    ending: ShoeModelRequestModellingEnding.closed,
    modelId: modelId,
    message: 'Published and closed — the seller now sees "3D model ready".',
  );
}

// ── Internals ───────────────────────────────────────────────────────────────

/// The units message, in one place — the most valuable sentence this file
/// produces, and the one a seller is most likely to see.
const String _centimetresError =
    'Enter millimetres, not centimetres — write 270, not 27.';

/// One millimetre field: a bare number, an optional `mm` suffix, and a refusal
/// of centimetres whether or not the seller wrote the unit down.
({double? value, String? error}) _parseMm(
  String raw, {
  required String what,
  required double min,
  required double max,
  required bool centimetresHint,
}) {
  // Blank is "not measured", not a mistake — three of the four fields are
  // optional, and an empty optional field must never raise an error.
  if (raw.isEmpty) return (value: null, error: null);

  var text = raw.toLowerCase();
  if (text.endsWith('mm')) text = text.substring(0, text.length - 2).trim();
  if (text.endsWith('cm')) return (value: null, error: _centimetresError);

  final value = _number(text);
  if (value == null) {
    return (
      value: null,
      error: 'Enter $what as a number of millimetres, like 270.',
    );
  }

  // A figure that is right for centimetres and far too small for millimetres is
  // a units mistake, and saying so is the whole point: a bare `27` would
  // otherwise be told it is outside the band, which sends the seller hunting
  // for a different number instead of a different unit.
  if (centimetresHint && value < min / 2) {
    return (value: null, error: _centimetresError);
  }

  if (value < min || value > max) {
    return (
      value: null,
      error: 'That does not look right — $what should be between '
          '${formatSizeNumber(min)} and ${formatSizeNumber(max)} mm.',
    );
  }

  return (value: value, error: null);
}

({double? value, String? error}) _parseSize(String raw) {
  if (raw.isEmpty) return (value: null, error: null);

  var text = raw.toUpperCase();
  // Tolerate the ways a size gets written down: `EU 42`, `42`, `42.0`.
  for (final prefix in const ['EU', 'EUR']) {
    if (text.startsWith(prefix)) text = text.substring(prefix.length).trim();
  }

  final value = _number(text);
  if (value == null) {
    return (value: null, error: 'Enter the EU size as a number, like 42.');
  }
  if (value < 22 || value > 48) {
    return (
      value: null,
      error: 'EU sizes in this shop run from 22 to 48.',
    );
  }
  return (value: value, error: null);
}

double? _number(String? raw) {
  if (raw == null) return null;
  return double.tryParse(raw.trim());
}
