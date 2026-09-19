import '../services/diag_logger.dart' show kNavDiagEnabled, navDiag;

/// Wall-clock timing marks for the bottom-navigation performance work.
///
/// **Why the diag channel and not `debugPrint`.** USB / adb debugging is
/// unavailable on the test device used for this app, so `flutter run` console
/// output and DevTools timeline capture are not reachable. The numbers have to
/// be captured in-app and exported from the app, which is what
/// `DiagLogger` already does (it appends ms-stamped lines to `nav_diag.log` and
/// the foot-instructions screen exposes a share-sheet export). Routing through
/// [navDiag] means the timings land in the same exportable file as the rest of
/// the on-device evidence.
///
/// **Reading the log.** `+Nms` is milliseconds since process start, so the file
/// is a single timeline and a tab switch is the gap between its two lines:
///
/// ```
/// +1834ms  [PERF] tab:POS tapped
/// +2159ms  [PERF] tab:POS presented
/// ```
///
/// `tapped` is stamped from the nav bar's `onTap`; `presented` is stamped from
/// a post-frame callback on the destination, so the gap covers build + layout +
/// paint of the tab that was switched to. A small gap means the destination was
/// ready in memory; a large one means it had nothing to show and was building
/// or fetching.
///
/// For the fetches, pair the two marks emitted inside the query helpers:
/// `catalog:query` → `catalog:decoded` is HTTP + JSON decode (what you cannot
/// fix from Dart), and `catalog:decoded` → `catalog:mapped` is this app's own
/// model mapping (what you *can* move to `compute()` if it ever shows up).
///
/// This is instrumentation, not telemetry: everything here is a no-op unless
/// [kNavDiagEnabled] is on. Delete the call sites (and this file) once the
/// numbers are recorded.
class PerfTrace {
  PerfTrace._();

  /// Milliseconds since the first [PerfTrace] use, i.e. effectively since app
  /// start. Anchoring every label to one origin is what makes the exported log
  /// readable as a timeline instead of a pile of durations.
  static final Stopwatch _since = Stopwatch()..start();

  /// Logs `[PERF] +Nms  <label>`.
  static void mark(String label) {
    if (!kNavDiagEnabled) return;
    navDiag('[PERF] +${_since.elapsedMilliseconds}ms  $label');
  }

  /// Runs [body], logs how long it took, and returns (or rethrows) its result
  /// unchanged.
  ///
  /// Used around network calls so a slowdown is attributed to the call that
  /// actually caused it without altering any call's semantics or error type.
  static Future<T> span<T>(String label, Future<T> Function() body) async {
    if (!kNavDiagEnabled) return body();
    final stopwatch = Stopwatch()..start();
    try {
      final result = await body();
      navDiag('[PERF] ${stopwatch.elapsedMilliseconds}ms  $label');
      return result;
    } catch (_) {
      navDiag('[PERF] ${stopwatch.elapsedMilliseconds}ms  $label (failed)');
      rethrow;
    }
  }
}
