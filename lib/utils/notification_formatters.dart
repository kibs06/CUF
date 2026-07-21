/// Shared notification formatting helpers.
///
/// Used by both customer and seller notification UIs so badge
/// rendering stays consistent and can't drift between screens.
library;

/// Format an unread count for badge display.
///
/// Returns the raw number up to 99, then "99+" for anything above.
/// This is a display-layer rule only — never truncate the underlying
/// stored/queried count.
String formatBadgeCount(int count) => count > 99 ? '99+' : '$count';
