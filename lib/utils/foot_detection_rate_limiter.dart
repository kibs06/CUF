/// Pure rate limiter for the V4 foot-tracking detection loop (MISSION v2 Phase 1.1).
///
/// The controller's 100 ms `Timer.periodic` already drops a tick when the
/// previous tick is still running (`_footTickInProgress`). This class makes
/// that rule explicit and testable, plus enforces a minimum interval between
/// detection *starts* so a slow detector degrades to its sustainable rate
/// instead of queueing stale poses.
///
/// Pure Dart on purpose: no timers, no channels, exact under `fakeAsync`.
library;

/// Decides whether a detection tick may start now.
///
/// - [minInterval] is the cadence (e.g. 100 ms = 10 Hz).
/// - [inProgress] mirrors the controller's overlap guard: a tick already
///   running means this one drops, never queues.
/// - [lastStart] is the last tick's start time (null = never ran).
///
/// Returns true when the tick may start. Call [markStarted] when it does.
class FootDetectionRateLimiter {
  FootDetectionRateLimiter({required this.minInterval});

  final Duration minInterval;
  DateTime? _lastStart;

  DateTime? get lastStart => _lastStart;

  bool shouldRun({required DateTime now, required bool inProgress}) {
    if (inProgress) return false;
    final last = _lastStart;
    if (last == null) return true;
    return now.difference(last) >= minInterval;
  }

  void markStarted(DateTime now) {
    _lastStart = now;
  }

  void reset() {
    _lastStart = null;
  }
}
