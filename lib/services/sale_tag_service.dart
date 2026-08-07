import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for the "sale tag reveal" state — which products the current
/// user has already tapped open on a hanging sale tag.
///
/// Storage is **local-only** (SharedPreferences), keyed per signed-in user
/// (`sale_tag_reveals_<userId>` → JSON array of product ids). This is a
/// deliberate simplification over a Supabase table:
///
///   * ✅ No migration, works offline, zero latency.
///   * ⚠️ Known limitation: reveals do NOT sync across devices. If the user
///     logs in on another device, tags there start unrevealed again.
///
/// Revealed ids are keyed by `userId` so a different user on the same device
/// sees every tag unrevealed (each account has its own key).
class SaleTagService {
  SaleTagService._();

  static final SaleTagService instance = SaleTagService._();

  static String _key(String userId) => 'sale_tag_reveals_$userId';

  /// Load the set of product ids the user has revealed. Best-effort: any
  /// corrupt/unparseable payload falls back to an empty set.
  Future<Set<String>> loadRevealedIds(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null || raw.isEmpty) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Persist a reveal (idempotent — re-saving an already-revealed product is
  /// a no-op that leaves the stored list unchanged).
  Future<void> saveRevealed(String userId, String productId) async {
    try {
      final ids = await loadRevealedIds(userId);
      if (ids.contains(productId)) return;
      ids.add(productId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(userId), jsonEncode(ids.toList()));
    } catch (_) {
      // Best-effort: a failed persist must never block the UI flip.
    }
  }
}
