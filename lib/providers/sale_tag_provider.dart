import 'package:flutter/foundation.dart';

import '../services/sale_tag_service.dart';
import '../services/supabase_service.dart';

/// Owns the per-user + per-product "has this user already revealed this?"
/// state for the two sale interactions — the **hanging sale tag** and the
/// **peel-away price tape**.
///
/// These are **independent by design** (confirmed decision — Option B):
/// revealing the tag has zero effect on the tape and vice versa, so the
/// provider keeps two separate sets and two separate lookups. A product can
/// be tag-revealed, tape-revealed, both, or neither — all four render
/// correctly.
///
/// - Loads both revealed-id sets **once per signed-in user** (lazily, on
///   first render) — never a request per card per render.
/// - `revealTag` / `revealTape` flip the UI **optimistically** (notify
///   first, persist in the background) so the flip/peel animates immediately
///   without waiting on disk.
/// - Guests / signed-out browsing get in-memory flips only (persistence is
///   skipped when there is no user) — documented, sane fallback.
///
/// Persistence is local SharedPreferences via [SaleTagService] — see that
/// file for the known cross-device limitation and the two separate keys.
///
/// Known edge (tiny window, pre-existing): a user tap made *while*
/// [ensureLoaded] is still awaiting is treated as an async-load reveal
/// (`isLoading` is still true) — it jumps instead of animating, and the
/// finished load overwrites that optimistic reveal. Local prefs load in
/// milliseconds, so this is practically unreachable.
class SaleTagProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService.instance;
  final SaleTagService _service = SaleTagService.instance;

  Set<String> _tagRevealedProductIds = <String>{};
  Set<String> _tapeRevealedProductIds = <String>{};
  String? _loadedForUserId;
  bool _loading = false;

  /// True while the per-user reveal sets are being fetched from storage.
  /// Widgets use this to distinguish a *user-triggered* reveal (animate the
  /// flip/peel) from an *async load* finishing (jump straight to revealed —
  /// never replay a wall of reveal animations on catalog load).
  bool get isLoading => _loading;

  /// Best-effort current-user lookup. Supabase may be uninitialized in tests
  /// or briefly unavailable at runtime — treat that as "signed out" rather
  /// than letting a reveal/load crash.
  String? _currentUserId() {
    try {
      return _db.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// True when this product's HANGING TAG has been revealed for the current
  /// user (per-user + per-product — the same everywhere it is shown).
  bool isTagRevealed(String productId) =>
      _tagRevealedProductIds.contains(productId);

  /// True when this product's PRICE TAPE has been peeled for the current
  /// user. Fully independent of [isTagRevealed].
  bool isTapeRevealed(String productId) =>
      _tapeRevealedProductIds.contains(productId);

  /// Load the current user's reveal sets (tag + tape, separately). Idempotent
  /// per user: a second call for the same user while already loaded (or in
  /// flight) does nothing. Called lazily by the widgets on first render;
  /// fire-and-forget.
  Future<void> ensureLoaded() async {
    final userId = _currentUserId();
    if (_loading || _loadedForUserId == userId) return;

    _loading = true;
    _loadedForUserId = userId;
    try {
      if (userId == null) {
        // Signed out — clear any previous user's reveals so a fresh login
        // never shows another account's tags or peeled tape.
        _tagRevealedProductIds = <String>{};
        _tapeRevealedProductIds = <String>{};
        notifyListeners();
      } else {
        // Two independent lookups — never merge the sets.
        final results = await Future.wait([
          _service.loadRevealedIds(userId),
          _service.loadTapeRevealedIds(userId),
        ]);
        _tagRevealedProductIds = results[0];
        _tapeRevealedProductIds = results[1];
        notifyListeners();
      }
    } catch (_) {
      // Best-effort: keep whatever we had; tags/tape just render unrevealed.
    } finally {
      _loading = false;
    }
  }

  /// Optimistically reveal a product's HANGING TAG and persist in the
  /// background. Never touches the tape's state.
  void revealTag(String productId) {
    if (_tagRevealedProductIds.contains(productId)) return; // idempotent

    _tagRevealedProductIds.add(productId);
    notifyListeners();

    final userId = _currentUserId();
    if (userId == null) return; // guest — session-only flip
    _service.saveRevealed(userId, productId); // intentionally not awaited
  }

  /// Optimistically peel a product's PRICE TAPE and persist in the
  /// background. Never touches the tag's state.
  void revealTape(String productId) {
    if (_tapeRevealedProductIds.contains(productId)) return; // idempotent

    _tapeRevealedProductIds.add(productId);
    notifyListeners();

    final userId = _currentUserId();
    if (userId == null) return; // guest — session-only peel
    _service.saveTapeRevealed(userId, productId); // intentionally not awaited
  }
}
