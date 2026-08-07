import 'package:flutter/foundation.dart';

import '../services/sale_tag_service.dart';
import '../services/supabase_service.dart';

/// Owns the "has this user already revealed this product's sale tag?" state.
///
/// - Loads the revealed-id set **once per signed-in user** (lazily, on first
///   tag render) — never a request per card per render.
/// - `reveal()` flips the UI **optimistically** (notify first, persist in the
///   background) so the tag animates immediately without waiting on disk.
/// - Guests / signed-out browsing get in-memory flips only (`reveal()` skips
///   persistence when there is no user) — documented, sane fallback.
///
/// Persistence is local SharedPreferences via [SaleTagService] — see that
/// file for the known cross-device limitation.
class SaleTagProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService.instance;
  final SaleTagService _service = SaleTagService.instance;

  Set<String> _revealedProductIds = <String>{};
  String? _loadedForUserId;
  bool _loading = false;

  /// True while the per-user revealed set is being fetched from storage.
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

  /// True when this product's tag has already been revealed for the current
  /// user (per-user + per-product — the same everywhere it is shown).
  bool isRevealed(String productId) => _revealedProductIds.contains(productId);

  /// Load the current user's revealed set. Idempotent per user: a second call
  /// for the same user while already loaded (or in flight) does nothing.
  /// Called lazily by the hanging tag on first render; fire-and-forget.
  Future<void> ensureLoaded() async {
    final userId = _currentUserId();
    if (_loading || _loadedForUserId == userId) return;

    _loading = true;
    _loadedForUserId = userId;
    try {
      if (userId == null) {
        // Signed out — clear any previous user's reveals so a fresh login
        // never shows another account's tags.
        _revealedProductIds = <String>{};
        notifyListeners();
      } else {
        _revealedProductIds = await _service.loadRevealedIds(userId);
        notifyListeners();
      }
    } catch (_) {
      // Best-effort: keep whatever we had; tags just render unrevealed.
    } finally {
      _loading = false;
    }
  }

  /// Optimistically reveal a product's tag and persist in the background.
  void reveal(String productId) {
    if (_revealedProductIds.contains(productId)) return; // idempotent

    _revealedProductIds.add(productId);
    notifyListeners();

    final userId = _currentUserId();
    if (userId == null) return; // guest — session-only flip
    _service.saveRevealed(userId, productId); // intentionally not awaited
  }
}
