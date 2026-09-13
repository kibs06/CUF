/// Compact number formatting for social-proof counters (sold counts,
/// review counts, …).
///
/// Rules:
///   < 1000          → as-is          (42, 999)
///   1000 ..< 1e6    → k with ≤1 decimal  (1k, 1.2k, 999k)
///   ≥ 1e6           → m with ≤1 decimal  (1m, 2.5m)
///
/// Trailing ".0" is stripped (1.0k → 1k).
String compactNumber(int n) {
  if (n < 1000) return n.toString();

  String format(double value, String suffix) {
    // One decimal only when it's meaningful; strip trailing ".0".
    final s = value.toStringAsFixed(1);
    final trimmed = s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    return '$trimmed$suffix';
  }

  if (n < 1000000) return format(n / 1000, 'k');
  return format(n / 1000000, 'm');
}
