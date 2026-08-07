import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for the sale-reveal state — which products the current user
/// has already revealed, for **two independent interactions**:
///
///   * the **hanging sale tag** ("how much is the discount?") and
///   * the **peel-away price tape** ("what is the actual sale price?").
///
/// The two are deliberately separate (confirmed design decision — Option B):
/// tapping the tag only reveals the tag, tapping the tape only peels the
/// tape. Each has its OWN key and its own stored set, so revealing one never
/// affects the other. A user may reveal neither, either, or both.
///
/// Storage is **local-only** (SharedPreferences), keyed per signed-in user
/// (`sale_tag_reveals_<userId>` / `sale_price_reveals_<userId>` → JSON arrays
/// of product ids). This is a deliberate simplification over a Supabase
/// table:
///
///   * ✅ No migration, works offline, zero latency.
///   * ⚠️ Known limitation: reveals do NOT sync across devices. If the user
///     logs in on another device, tags/tape there start unrevealed again.
///
/// Revealed ids are keyed by `userId` so a different user on the same device
/// sees every tag and tape unrevealed (each account has its own keys).
class SaleTagService {
  SaleTagService._();

  static final SaleTagService instance = SaleTagService._();

  static String _tagKey(String userId) => 'sale_tag_reveals_$userId';
  static String _tapeKey(String userId) => 'sale_price_reveals_$userId';

  static Set<String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Load the set of product ids whose HANGING TAG the user has revealed.
  /// Best-effort: any corrupt/unparseable payload falls back to an empty set.
  Future<Set<String>> loadRevealedIds(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decode(prefs.getString(_tagKey(userId)));
    } catch (_) {
      return <String>{};
    }
  }

  /// Persist a TAG reveal (idempotent — re-saving an already-revealed product
  /// is a no-op that leaves the stored list unchanged).
  Future<void> saveRevealed(String userId, String productId) async {
    try {
      final ids = await loadRevealedIds(userId);
      if (ids.contains(productId)) return;
      ids.add(productId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tagKey(userId), jsonEncode(ids.toList()));
    } catch (_) {
      // Best-effort: a failed persist must never block the UI flip.
    }
  }

  /// Load the set of product ids whose PRICE TAPE the user has peeled away.
  /// Completely independent of the tag set — a product can be in one, both,
  /// or neither.
  Future<Set<String>> loadTapeRevealedIds(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decode(prefs.getString(_tapeKey(userId)));
    } catch (_) {
      return <String>{};
    }
  }

  /// Persist a TAPE reveal (idempotent).
  Future<void> saveTapeRevealed(String userId, String productId) async {
    try {
      final ids = await loadTapeRevealedIds(userId);
      if (ids.contains(productId)) return;
      ids.add(productId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tapeKey(userId), jsonEncode(ids.toList()));
    } catch (_) {
      // Best-effort: a failed persist must never block the UI flip.
    }
  }
}
