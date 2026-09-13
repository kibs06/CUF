import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Recent-search history for the customer home search bar.
///
/// Stored locally in SharedPreferences (keyed per user when signed in),
/// deduplicated (a repeat term moves to the front), capped at [maxEntries].
/// Purely on-device — nothing is sent to the server.
class SearchHistoryService {
  SearchHistoryService._();

  static final SearchHistoryService instance = SearchHistoryService._();

  static const int maxEntries = 8;
  static const String _keyPrefix = 'search_history_';

  List<String> _cache = const [];
  bool _loaded = false;

  String get _key {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return '$_keyPrefix${userId ?? 'anon'}';
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _cache = prefs.getStringList(_key) ?? const [];
    } catch (_) {
      _cache = const [];
    }
    _loaded = true;
  }

  /// Current history, newest first.
  Future<List<String>> history() async {
    await _ensureLoaded();
    return List.unmodifiable(_cache);
  }

  /// Record a completed search. Empty/duplicate handling: duplicates move
  /// to the front; the list is capped at [maxEntries].
  Future<void> record(String term) async {
    final t = term.trim();
    if (t.isEmpty || t.length < 2) return;
    await _ensureLoaded();

    _cache = [
      t,
      ..._cache.where((e) => e.toLowerCase() != t.toLowerCase()),
    ];
    if (_cache.length > maxEntries) {
      _cache = _cache.sublist(0, maxEntries);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, _cache);
    } catch (_) {
      // History is best-effort — failures never break search.
    }
  }

  /// Remove a single term (e.g. via an ✕ on its chip).
  Future<void> remove(String term) async {
    await _ensureLoaded();
    _cache = _cache.where((e) => e != term).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, _cache);
    } catch (_) {}
  }

  /// Clear all history for the current user.
  Future<void> clear() async {
    await _ensureLoaded();
    _cache = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
