/// Floor stability for the foot scan (pure Dart, no Flutter).
///
/// A plane that is still settling moves under the measurement: heel, toe and
/// width points are raycast onto it, so a drifting floor height reads as a
/// different foot length. The area is only treated as locked once the floor
/// height has agreed across [kFloorStablePolls] consecutive polls.
library;

/// Largest allowed change of the floor height across the polls that must agree,
/// in metres. 2 cm: well above ARCore's per-poll jitter on a settled plane,
/// well below the height error a still-moving plane causes.
const double kFloorStableSpreadM = 0.02;

/// Consecutive polls that must agree before the floor counts as stable.
const int kFloorStablePolls = 2;

/// Probes that must hit the floor in one poll for that poll to count.
const int kMinFloorProbes = 3;

class FloorTracker {
  final List<double> _recentMedians = [];
  double? _floorY;

  /// The stable floor height in metres (world Y), or null while unstable.
  double? get floorY => _floorY;

  bool get isStable => _floorY != null;

  /// Feeds one poll's floor heights (metres, one per probe that hit a floor
  /// plane). Returns whether the floor is now stable.
  ///
  /// A poll with fewer than [kMinFloorProbes] hits breaks the streak: the
  /// floor cannot be vouched for, so it is not treated as stable.
  bool observe(List<double> heights) {
    if (heights.length < kMinFloorProbes) {
      reset();
      return false;
    }

    final sorted = [...heights]..sort();
    final median = sorted[sorted.length ~/ 2];

    _recentMedians.add(median);
    if (_recentMedians.length > kFloorStablePolls) {
      _recentMedians.removeAt(0);
    }
    if (_recentMedians.length < kFloorStablePolls) {
      _floorY = null;
      return false;
    }

    var lo = _recentMedians.first;
    var hi = _recentMedians.first;
    for (final m in _recentMedians) {
      if (m < lo) lo = m;
      if (m > hi) hi = m;
    }
    if (hi - lo <= kFloorStableSpreadM) {
      _floorY = median;
      return true;
    }
    _floorY = null;
    return false;
  }

  /// Forgets the streak. The next stable floor needs fresh agreeing polls.
  void reset() {
    _recentMedians.clear();
    _floorY = null;
  }
}
