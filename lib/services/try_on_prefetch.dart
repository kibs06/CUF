/// Warm the model cache while the customer is still reading the product page
/// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V2.6).
///
/// **Why this file exists rather than a call to `ShoeModelService`.** The read
/// service is deliberately strict: [ShoeModelService.ensureLocal] *throws* when
/// bytes do not hash to their row, because serving an unverified model would be
/// worse than serving none. That is the right contract for the renderer, which
/// has a screen to fall back to. It is the wrong contract for a prefetch, which
/// runs while the customer is doing something else entirely: a download that
/// fails here must be *invisible*. This class is the policy that turns every one
/// of those failures — no row, no table, no network, wrong hash, unwritable
/// cache — into a returned outcome, so a warm cache can never cost the page it
/// was trying to help.
///
/// The four answers, and what each one costs:
///
///   * [TryOnPrefetchOutcome.disabled] — the switch is off. No network, no read,
///     nothing. The shipped default.
///   * [TryOnPrefetchOutcome.noModel] — the product has no usable model. The
///     common case today (nothing has been uploaded yet), and the one that
///     answers the roadmap's coverage metric.
///   * [TryOnPrefetchOutcome.alreadyCached] / [downloaded] — a verified local
///     file is ready. The download is the whole point of the phase; the cache
///     hit is the proof it only happens once per asset.
///   * [TryOnPrefetchOutcome.failed] — anything else, with [result.cause] kept
///     for a log. The page is untouched.
///
/// **Metered connections are not considered yet, and that is now an OPEN gap
/// rather than a covered one.** A prefetch spends the customer's data on a
/// feature whose renderer (V3) does not exist. It shipped behind
/// `AppConstants.tryOnPrefetchEnabled` (**off**) for exactly that reason, and
/// that switch was flipped **on** on 2026-09-28, once the table it reads was
/// verified applied — so the `connectivity_plus` check that keeps a 5 MB model
/// off a cellular link is the next hardening step instead of a precondition.
/// The pressure is not immediate: `product_models` is empty, so the only traffic
/// today is one read per product page view that returns nothing. It becomes real
/// the day a seller publishes a model.
library;

import '../utils/shoe_model_resolver.dart';
import 'shoe_model_service.dart';

/// What one prefetch attempt did.
enum TryOnPrefetchOutcome {
  /// The switch is off — nothing was read and nothing was fetched.
  disabled,

  /// The product has no usable model (no rows, or rows the resolver dropped).
  noModel,

  /// A verified local file was already in the cache; no download happened.
  alreadyCached,

  /// A model was downloaded, verified and cached.
  downloaded,

  /// Something went wrong. Kept for the log; the caller does nothing.
  failed,
}

/// The outcome plus what a log or a test wants to know about it.
class TryOnPrefetchResult {
  final TryOnPrefetchOutcome outcome;

  /// Local path of the verified `.glb`, when one exists after this call.
  final String? path;

  /// The model that was warmed, when one was resolved.
  final ShoeModelSpec? spec;

  /// The error, kept rather than swallowed: silent failure is the *behaviour*
  /// this class promises, not a reason to lose the reason it failed.
  final Object? cause;

  const TryOnPrefetchResult({
    required this.outcome,
    this.path,
    this.spec,
    this.cause,
  });

  /// True when the customer could tap "try on" and get a model with no
  /// download — the only success this phase is measuring.
  bool get hasLocalModel => path != null;

  /// A log-safe line. Never shown to a customer.
  String get summary => switch (outcome) {
        TryOnPrefetchOutcome.disabled => 'prefetch off',
        TryOnPrefetchOutcome.noModel => 'no model for this product',
        TryOnPrefetchOutcome.alreadyCached => 'model already cached',
        TryOnPrefetchOutcome.downloaded =>
          'model cached (${spec == null ? '?' : 'v${spec!.version}'})',
        TryOnPrefetchOutcome.failed => 'prefetch failed: $cause',
      };
}

/// Resolve → ensure local, with every failure turned into a result.
class TryOnPrefetch {
  /// The read service; injectable so tests drive the prefetch against fake
  /// rows and a temp cache without a socket or a server.
  final ShoeModelService models;

  /// Whether the feature is on. Defaults to the app switch, and is injectable
  /// so a test can exercise both configurations in one run.
  final bool enabled;

  /// De-dupes concurrent prefetches for one selection.
  ///
  /// A product page rebuild — a size tap, a colour tap, a provider notification
  /// — calls this again. `ensureLocal` already de-dupes the *download* by cache
  /// filename, but resolution costs a table read, and a storm of identical reads
  /// for one page view is waste the cache cannot prevent. Same
  /// same-future-only cleanup rule as `ShoeModelService._inFlight`.
  final Map<String, Future<TryOnPrefetchResult>> _inFlight = {};

  TryOnPrefetch({
    ShoeModelService? models,
    required this.enabled,
  }) : models = models ?? ShoeModelService();

  /// Warms the cache for [productId] as it will be rendered for [variantId].
  ///
  /// **Never throws** — that is the contract this class exists for, and it is
  /// tested for every failure mode it can be given. The returned future
  /// completes normally in all cases.
  ///
  /// [anyVariant] asks a different question of the same rows: "does this product
  /// have a model at all?" rather than "which shoe does this customer see?". The
  /// seller's 3D viewer is that caller — a product whose models are all
  /// colour-scoped answers "no model" to the second question and must not to the
  /// first. See `ShoeModelService.resolveForProduct`.
  Future<TryOnPrefetchResult> prefetch({
    required String productId,
    String? variantId,
    bool anyVariant = false,
  }) {
    if (!enabled) {
      return Future.value(
        const TryOnPrefetchResult(outcome: TryOnPrefetchOutcome.disabled),
      );
    }

    // `anyVariant` is part of the key: the two questions have different answers
    // for a product whose only rows are colour-scoped, so one must never be
    // served the other's future.
    final key = '$productId::${variantId ?? ''}::${anyVariant ? 'any' : 'scoped'}';
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _prefetch(
      productId: productId,
      variantId: variantId,
      anyVariant: anyVariant,
    );
    _inFlight[key] = future;
    future
        .whenComplete(() {
          if (identical(_inFlight[key], future)) _inFlight.remove(key);
        })
        .ignore();
    return future;
  }

  Future<TryOnPrefetchResult> _prefetch({
    required String productId,
    String? variantId,
    bool anyVariant = false,
  }) async {
    ShoeModelSpec? spec;
    try {
      spec = await models.resolveForProduct(
        productId,
        variantId: variantId,
        anyVariant: anyVariant,
      );
    } catch (e) {
      // A missing table (the migration is not applied), a dropped connection,
      // an RLS refusal — all the same to the page: no model, no problem.
      return TryOnPrefetchResult(
        outcome: TryOnPrefetchOutcome.failed,
        cause: e,
      );
    }

    if (spec == null) {
      return const TryOnPrefetchResult(outcome: TryOnPrefetchOutcome.noModel);
    }

    try {
      final file = await models.ensureLocal(spec);
      return TryOnPrefetchResult(
        outcome: file.fromCache
            ? TryOnPrefetchOutcome.alreadyCached
            : TryOnPrefetchOutcome.downloaded,
        path: file.path,
        spec: spec,
      );
    } catch (e) {
      // Integrity mismatch, storage 404, an unwritable cache directory — the
      // customer sees nothing, which is the entire promise of this class.
      return TryOnPrefetchResult(
        outcome: TryOnPrefetchOutcome.failed,
        spec: spec,
        cause: e,
      );
    }
  }
}
