/// Whether the product page shows the **3D icon on the product photograph** —
/// and with it the viewer behind it, whose own section carries the
/// "Try On in AR" button.
///
/// A pure file with no Flutter and no Supabase import, the same shape as
/// `try_on_mode.dart` and `fit_verdict_state.dart`, for the same reason: the
/// answer is a table, and a page that shows a 3D box for a product with nothing
/// to render is a bug nobody can see from the code that decides it.
///
/// **The rule is deliberately all-or-nothing.** The icon and the AR button come
/// and go together, because the button is *part of* the section the icon opens
/// rather than a separate entry: a product with no model shows neither. That is a
/// product decision with a cost — the AR entry point used to be on every product
/// page, and until 2026-10-01 it was a pinned pill that showed on every product
/// regardless — and it is the reason `AppConstants.shoePreviewEnabled` exists as
/// a switch rather than as a rewrite: with it off, the page has no 3D entry at
/// all.
///
/// **The four questions, in the order they are asked.** Each one is a different
/// kind of fact, and the first that fails is the honest reason to report:
///
///   1. `enabled` — the build switch. Nothing is read, and the page shows no 3D
///      icon at all, when it is off.
///   2. `isAndroid` — there is no iOS renderer at all (`ios/` carries no
///      ARCore/try-on code), so on iOS the section must not exist rather than
///      exist and stay blank.
///   3. `hasModel` — the product has a **live** (`active`) model row. A draft
///      that failed the authoring contract is not a model anyone may render.
///      (The page adds one more fact of its own before it draws the icon: those
///      bytes verified on disk — `_showPreviewIcon`.)
///   4. `hasLocalModel` — those bytes are verified and on disk. The native side
///      is handed a local path and never does HTTP (§2.8), so "there is a row"
///      and "there is something to draw" are different questions, and only the
///      second one can put a box on the page. Until the prefetch finishes, the
///      honest answer is to show nothing — a spinner over a 3D box the customer
///      can already see is a worse lie than a beat of no box at all.
library;

/// Why the section is or is not on the page. Carried as a value so a test can
/// assert the *reason* instead of re-deriving it from one boolean, and so the
/// page can log the first thing that stopped it rather than a bare `false`.
enum ShoePreviewReason {
  /// Nothing stopped it: the box is shown.
  none,

  /// `SHOE_PREVIEW` is off for this build — the page has no 3D icon.
  featureOff,

  /// iOS (or desktop): there is no renderer to mount.
  notAndroid,

  /// The product has no live model — and most of the catalogue is here.
  noModel,

  /// A live model exists but is not verified on disk yet (the prefetch is
  /// still running, or it failed).
  modelNotReady,
}

/// The gate's answer: whether to show, and why not when not.
class ShoePreviewDecision {
  final bool shown;
  final ShoePreviewReason reason;

  const ShoePreviewDecision({required this.shown, required this.reason});

  /// The one answer that needs no explanation.
  static const ShoePreviewDecision shownBox =
      ShoePreviewDecision(shown: true, reason: ShoePreviewReason.none);

  bool get hidden => !shown;

  @override
  bool operator ==(Object other) =>
      other is ShoePreviewDecision &&
      other.shown == shown &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(shown, reason);

  @override
  String toString() => 'ShoePreviewDecision($shown, ${reason.name})';
}

/// The gate. See the file header for what each input means and why the order
/// matters.
ShoePreviewDecision resolveShoePreview({
  required bool enabled,
  required bool isAndroid,
  required bool hasModel,
  required bool hasLocalModel,
}) {
  if (!enabled) {
    return const ShoePreviewDecision(
      shown: false,
      reason: ShoePreviewReason.featureOff,
    );
  }
  if (!isAndroid) {
    return const ShoePreviewDecision(
      shown: false,
      reason: ShoePreviewReason.notAndroid,
    );
  }
  if (!hasModel) {
    return const ShoePreviewDecision(
      shown: false,
      reason: ShoePreviewReason.noModel,
    );
  }
  if (!hasLocalModel) {
    return const ShoePreviewDecision(
      shown: false,
      reason: ShoePreviewReason.modelNotReady,
    );
  }
  return ShoePreviewDecision.shownBox;
}
