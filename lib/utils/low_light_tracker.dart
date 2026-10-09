/// Low-light state for the foot scan (pure Dart, no Flutter).
///
/// ARCore builds a floor plane from visual feature points. In a dim room the
/// sensor is noisy and the feature points thin out, so the plane never forms
/// and the customer is left on "Looking for the floor…". This tracker turns the
/// mean brightness of the camera's Y (luma) plane into a "too dark" flag so the
/// coach can say why, and offer the torch.
///
/// Two thresholds give hysteresis: the view counts as dark once the mean drops
/// below [kDarkEnterLuma], and only recovers above [kDarkExitLuma]. Without the
/// gap, a room hovering at the edge would flip the coach text on every poll.
library;

/// Mean luma (0–255) below which the view counts as too dark.
///
/// Not calibrated on a device: chosen as a conservative "clearly dim" line. Tune
/// it from the luma values the native side reports on a dark-room test.
const double kDarkEnterLuma = 45;

/// Mean luma above which the view stops counting as too dark.
const double kDarkExitLuma = 65;

class LowLightTracker {
  bool _dark = false;

  /// Whether the view is currently too dark to find the floor.
  bool get isDark => _dark;

  /// Feeds one mean-luma reading (0–255). A null reading (no frame yet) keeps
  /// the current state: absence of data is not evidence of light or dark.
  /// Returns [isDark] after the reading.
  bool observe(double? meanLuma) {
    if (meanLuma == null) return _dark;
    if (_dark) {
      if (meanLuma > kDarkExitLuma) _dark = false;
    } else {
      if (meanLuma < kDarkEnterLuma) _dark = true;
    }
    return _dark;
  }

  /// Forgets the state, e.g. when a new scan session starts.
  void reset() {
    _dark = false;
  }
}
