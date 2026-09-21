import 'package:shared_preferences/shared_preferences.dart';

/// Remembers that the customer has already turned "The Workshop Collection"
/// poster over — the one-time cue that teaches the card's sort list
/// (`lib/widgets/workshop_collection_card.dart`).
///
/// **It is a device flag, not a per-user one.** A [SaleTagService] reveal is
/// per-user because it is the customer's own data; this is not data at all — it
/// is *how the card works*, and the card behaves identically for every account
/// on the phone. Keying it per user would only mean a second person on the same
/// device meets a hint about a card they have been watching the whole time.
///
/// Both calls are **best-effort**, the same contract as [SaleTagService]: an
/// unavailable or unreadable store never throws into a build, and it reads as
/// "already seen". A store that cannot remember that the hint was spent must not
/// be the reason the hint shouts on every mount.
class WorkshopSortHintService {
  WorkshopSortHintService._();
  static final WorkshopSortHintService instance = WorkshopSortHintService._();

  /// The stored flag: `true` once the card has been used (or the hint has had
  /// its turn on screen).
  static const String key = 'workshop_sort_hint_seen';

  /// Whether the hint is spent. Unreadable store → `true` (stay quiet).
  Future<bool> hasBeenSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return true;
    }
  }

  /// Spend the hint for good. Best-effort: a failed write must never block the
  /// flip the customer just made.
  Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, true);
    } catch (_) {
      // Best-effort — see the class doc.
    }
  }
}
