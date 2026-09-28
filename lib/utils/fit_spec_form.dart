/// The seller form's four "3D & fit" fields, turned into the numbers they save.
///
/// Pure Dart — no Flutter — so the rules are unit-testable (the `size_key.dart`
/// precedent), and so the form, the service and the database agree by
/// construction: the plausibility bounds below are `fit_engine.dart`'s, which
/// are the CHECK constraints on `products` in
/// `supabase/migrations/20260927120000_add_product_fit_specs.sql`.
///
/// This file exists because a fit spec is the one place in the product form
/// where a *plausible-looking* typo is worse than a missing value. `27.5` for a
/// last length, a US size where an EU one was asked for, a width with no length
/// — each saves happily, and each then either tells a customer nothing or tells
/// them something wrong. So the rules are strict, the messages say what to do
/// next, and the half-filled shapes are refused here rather than by a 400 from
/// the database.
///
/// One rule set, two callers: [FitSpecFormResult.fromFields] backs both the
/// inline field validators ([FitSpecFormResult.messageFor] says which field a
/// sentence belongs to) and the save path, so the two cannot disagree about
/// what is valid.
library;

import 'fit_engine.dart';
import 'size_key.dart';
import 'size_match.dart';

/// Which field an error belongs to, so the form can show it inline.
enum FitSpecField { lastLengthMm, lastWidthMm, heelHeightMm, refSizeEu }

/// The outcome of reading the four text fields, in one of three states:
///
///  * [isEmpty] — all four blank. The product carries no fit spec, and saving
///    clears the columns.
///  * [isError] — the seller has something to fix; [errorField] says where to
///    show the sentence. [specs] is null.
///  * otherwise — a complete, plausible [specs] to save.
class FitSpecFormResult {
  /// The parsed spec, or null when the fields are blank or invalid.
  final FitSpecs? specs;

  /// The sentence to show the seller, or null when there is nothing to fix.
  final String? error;

  /// The field [error] belongs to; null when there is no error.
  final FitSpecField? errorField;

  const FitSpecFormResult._({this.specs, this.error, this.errorField});

  /// All four fields blank — a delivered product whose last was never measured.
  const FitSpecFormResult.empty()
      : specs = null,
        error = null,
        errorField = null;

  /// Reads the four raw field values.
  factory FitSpecFormResult.fromFields({
    required String lastLengthMm,
    required String lastWidthMm,
    required String heelHeightMm,
    required String refSizeEu,
  }) {
    final lengthText = lastLengthMm.trim();
    final widthText = lastWidthMm.trim();
    final heelText = heelHeightMm.trim();
    final refText = refSizeEu.trim();

    if (lengthText.isEmpty &&
        widthText.isEmpty &&
        heelText.isEmpty &&
        refText.isEmpty) {
      return const FitSpecFormResult.empty();
    }

    // Every field is parsed for its *own* problems before any cross-field rule
    // runs, so a misspelled width is never reported as "add the last length".
    final ref = _parseRefSize(refText);
    if (ref.error != null) {
      return FitSpecFormResult._(
        error: ref.error,
        errorField: FitSpecField.refSizeEu,
      );
    }
    final refEu = ref.value;

    final length = _parseMm(
      lengthText,
      what: 'the last length',
      min: kPlausibleLastLengthMm,
      max: kPlausibleLastLengthMaxMm,
    );
    if (length.error != null) {
      return FitSpecFormResult._(
        error: length.error,
        errorField: FitSpecField.lastLengthMm,
      );
    }
    final lengthMm = length.value;

    final width = _parseMm(
      widthText,
      what: 'the last width',
      min: kPlausibleLastWidthMm,
      max: kPlausibleLastWidthMaxMm,
    );
    if (width.error != null) {
      return FitSpecFormResult._(
        error: width.error,
        errorField: FitSpecField.lastWidthMm,
      );
    }
    final widthMm = width.value;

    final heel = _parseMm(
      heelText,
      what: 'the heel height',
      min: kPlausibleHeelHeightMm,
      max: kPlausibleHeelHeightMaxMm,
    );
    if (heel.error != null) {
      return FitSpecFormResult._(
        error: heel.error,
        errorField: FitSpecField.heelHeightMm,
      );
    }
    final heelMm = heel.value;

    // The last length is the number everything else hangs off: it is what the
    // verdict compares, and it is the only one that can be graded across sizes.
    // A width, a heel height or a reference size without it is a measurement
    // that can never be used, so the message names the one missing thing.
    if (lengthMm == null) {
      if (widthMm != null || heelMm != null || refEu != null) {
        return const FitSpecFormResult._(
          error: 'Add the last length you measured — the fit verdict is decided '
              'by length, and a width or a size on its own cannot size '
              'anything.',
          errorField: FitSpecField.lastLengthMm,
        );
      }
      return const FitSpecFormResult.empty();
    }

    if (refEu == null) {
      return const FitSpecFormResult._(
        error: 'Say which EU size you measured — every other size grades from '
            'it.',
        errorField: FitSpecField.refSizeEu,
      );
    }

    return FitSpecFormResult._(
      specs: FitSpecs(
        lastLengthMm: lengthMm,
        lastWidthMm: widthMm,
        heelHeightMm: heelMm,
        refSizeEu: refEu,
      ),
    );
  }

  /// Whether the fields are all blank — nothing to save, nothing to fix.
  bool get isEmpty => specs == null && error == null;

  /// Whether the seller has something to fix.
  bool get isError => error != null;

  /// The sentence to show under [field], or null when that field is fine.
  ///
  /// The form's per-field validators call this, so an inline error and the
  /// save-time check are the same sentence from the same rule.
  String? messageFor(FitSpecField field) =>
      errorField == field ? error : null;
}

/// What to prefill the four fields with when editing an existing product, in
/// field order.
///
/// Reads through [FitSpecs.fromProduct], so a row the engine would refuse (a
/// half-filled or implausible spec) prefills as blank rather than showing the
/// seller numbers the app is ignoring.
({String lastLengthMm, String lastWidthMm, String heelHeightMm, String refSizeEu})
    fitSpecFieldTexts(Map<String, dynamic>? product) {
  final specs = product == null ? null : FitSpecs.fromProduct(product);
  return (
    lastLengthMm: _text(specs?.lastLengthMm),
    lastWidthMm: _text(specs?.lastWidthMm),
    heelHeightMm: _text(specs?.heelHeightMm),
    refSizeEu: _text(specs?.refSizeEu),
  );
}

/// One number as field text: `275.0` → `'275'`, `42.5` → `'42.5'`, null → `''`.
String _text(double? value) => value == null ? '' : formatSizeNumber(value);

// ── Internals ───────────────────────────────────────────────────────────────

/// The message a units mistake earns, in one place: it is the most valuable
/// sentence this file produces, and the only one a seller is likely to see
/// twice.
const String _centimetresError =
    'Enter millimetres, not centimetres — write 275, not 27.5.';

/// One millimetre field: a bare number, an optional `mm` suffix, and a refusal
/// of centimetres whether or not the seller wrote the unit down.
///
/// The `cm` guard is the important one. `26.5` is a *plausible* last length to
/// a parser and nonsense to a shoemaker — it is a centimetre figure, and it
/// would size every customer several sizes too small. A units mistake deserves
/// a message about units, not "enter a number between 120 and 360".
({double? value, String? error}) _parseMm(
  String raw, {
  required String what,
  required double min,
  required double max,
}) {
  // Blank is "not measured", not a mistake: three of the four fields are
  // optional, and an empty optional field must never raise an error. The rules
  // that make a *missing* value wrong are the cross-field ones below.
  if (raw.isEmpty) return (value: null, error: null);

  var text = raw.toLowerCase();
  if (text.endsWith('mm')) text = text.substring(0, text.length - 2).trim();
  if (text.endsWith('cm')) return (value: null, error: _centimetresError);

  final value = _number(text);
  if (value == null) {
    return (
      value: null,
      error: 'Enter $what as a number of millimetres, like 275.'
    );
  }
  if (value < min || value > max) {
    // A number that would fit the band *ten times larger* is far more likely to
    // be centimetres than to be a shoe nobody has ever made — `27.5` and `9.8`
    // are exactly what a tape measure reads, and sending them back with "must
    // be between 120 and 360 mm" teaches the seller nothing. Outside both
    // readings, the band message is the honest one.
    final asCentimetres = value * 10;
    if (asCentimetres >= min && asCentimetres <= max) {
      return (value: null, error: _centimetresError);
    }
    return (
      value: null,
      error: '$what must be between ${min.round()} and ${max.round()} mm — '
          '${formatSizeNumber(value)} mm is outside what a shoe can be.',
    );
  }
  return (value: value, error: null);
}

/// The EU size the seller measured at. Accepts `42`, `42.5`, `EU 42`.
///
/// A `US 9` / `UK 6` is refused by name rather than converted: the field asks
/// which size *they* measured, and picking a chart for them is a guess — which
/// is also why the answer comes back at #2 in the message.
({double? value, String? error}) _parseRefSize(String raw) {
  if (raw.isEmpty) return (value: null, error: null);

  final value = sizeNumber(raw);
  if (value == null) {
    return (
      value: null,
      error: 'Enter the EU size you measured at, like 42.',
    );
  }
  final system = sizeSystem(raw);
  if (system != kDefaultSizeSystem) {
    return (
      value: null,
      error: 'That looks like a $system size. Enter the EU size you measured '
          'at — the catalog and the fit verdict both speak EU.',
    );
  }
  if (value < kPlausibleEuMin || value > kPlausibleEuMax) {
    return (
      value: null,
      error: 'Reference size must be between EU '
          '${formatSizeNumber(kPlausibleEuMin)} and EU '
          '${formatSizeNumber(kPlausibleEuMax)}.',
    );
  }
  return (value: value, error: null);
}

/// A typed number, tolerating a decimal comma (`275,5`) and stray spaces.
double? _number(String raw) {
  final cleaned = raw.replaceAll(',', '.').trim();
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}
