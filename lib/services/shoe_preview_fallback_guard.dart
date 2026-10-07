import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// **The one fact a phone has to remember across a process death: the native
/// renderer killed it.**
///
/// **Why this exists, stated as the loop it breaks.** The 3D box has two engines
/// and a ladder between them (`ShoePreviewSection`): the WebView engine is tried
/// first, and a WebView that cannot hand out a WebGL2 context — or cannot run
/// `<model-viewer>` at all — can never draw, so the box falls back to the native
/// Filament renderer. On the phones this ladder is for, the native renderer
/// *does* draw the shoe (the owner's P30 Pro measured ~57 fps), and on some of
/// them it also **dies inside the load**, which takes the process with it: a
/// `SIGSEGV` in `TransformManager_nSetTransform` on the load tail, measured on
/// both a vivo V2022 (2 of 3 opens) and the P30 Pro. A death inside the load is
/// not catchable from Dart, so without this file the customer's experience is a
/// loop: open the 3D viewer → the app dies → reopen → the WebView cannot draw →
/// fall back → the app dies again. Forever.
///
/// **So the attempt is announced before it is made, and the announcement is the
/// evidence.** [markAttempt] writes a marker *synchronously* immediately before the
/// native view is mounted; [clearAttempt] deletes it the moment the native engine
/// reports `modelLoaded` — the event it raises after the asset is parsed, entities
/// are added and the transform is written
/// (`android/app/src/main/kotlin/com/solevision/app/tryon/ArTryOnView.kt`),
/// which is precisely the window every measured death on this feature sits in.
/// A launch that finds the marker still there is therefore a launch standing on
/// evidence: the previous process began a native attempt and never got past the
/// load. That phone is [blocked], the ladder stops at the WebView engine, and the
/// box says *"3D preview isn't supported on this phone."* instead of killing the
/// app again.
///
/// ⚠️ **The trade, stated plainly, because it is a real cost.** The latch is
/// **sticky and never expires** — nothing in the app clears it, and that is
/// deliberate: a phone that has killed this app once inside the load is not a
/// phone to gamble a customer's session on twice. The price is that a *clean*
/// process death inside that window — an OOM kill, the customer force-stopping
/// the app, an unrelated crash while the box was loading — is indistinguishable
/// from the renderer's own fault, and a phone in that position keeps the honest
/// sentence instead of the shoe. That error is the safe direction: the customer
/// loses a picture they were not seeing anyway (the WebView had already refused
/// to draw), rather than losing the whole session.
///
/// ⚠️ **What it does not cover.** A death *after* the load — the second-teardown
/// fault, the frozen-frame burst — has already cleared the latch, so the next
/// open tries the native engine again and may die on *leaving* the box. The
/// customer sees the shoe first, which is not the loop this file exists to stop,
/// and closing that hole needs a native-side signal this app does not have in a
/// customer build (the heartbeat is diagnostics-only). Written down so nobody
/// reads this latch as a stronger promise than it makes.
///
/// **Where it lives, and why not `SharedPreferences`.** The file is
/// `native_attempt` inside the `shoe_preview` folder of the app support directory
/// — the same internal, un-backup-able directory the verified `.glb` cache uses (`ShoeModelService`, which documents the choice:
/// this is internal state, not a user document, so `getApplicationDocumentsDirectory`
/// would be wrong). A file rather than preferences because the write has to be
/// *synchronous*: it lands immediately before a native frame that can kill the
/// process, and an async write queued behind a platform channel would not be on
/// disk when the death it is recording arrives. `navDiag` writes its lines this
/// way for the same reason.
///
/// ⚠️ **Nothing here may break the box.** Every file operation is wrapped, and a
/// support directory that cannot be read or written leaves [blocked] `false`,
/// which is exactly the behaviour the box had before this latch existed.
abstract final class ShoePreviewFallbackGuard {
  /// The folder inside the app support directory, beside `shoe_models`.
  static const String folderName = 'shoe_preview';

  /// The marker itself: its **existence** is the fact, its contents are for a
  /// human who goes looking.
  static const String markerName = 'native_attempt';

  static String? _dirPath;

  /// Resolved once per process — see [blockedOrLoad]. Kept as a `Future` rather
  /// than a bool so concurrent callers await the *same* read instead of racing
  /// one that has not finished.
  static Future<void>? _loading;

  static bool _blocked = false;

  /// Test-only directory, so a test can drive the real file write/delete without
  /// `path_provider`'s platform channel.
  @visibleForTesting
  static String? dirOverrideForTest;

  /// How many times the marker was written, counted **whether or not a file could
  /// be written** — a test asserting that the ladder announced the attempt before
  /// mounting the native view is asserting this counter's timing, and on a build
  /// with no writable directory (the unit-test binary) the timing is the only
  /// thing that can be observed.
  @visibleForTesting
  static int attemptMarks = 0;

  /// How many times the marker was cleared, on the same terms as [attemptMarks].
  @visibleForTesting
  static int clears = 0;

  /// Whether the native fallback is off **for good** on this phone.
  ///
  /// False until [blockedOrLoad] has read the disk, which is why the ladder calls
  /// that and never reads this getter directly: "not known yet" must not read as
  /// "safe to try".
  static bool get blocked => _blocked;

  /// Reads the marker (once per process) and answers whether the native fallback
  /// is off.
  ///
  /// Awaited by the ladder at the moment the WebView engine reports it cannot
  /// draw — never during `build`, so nothing is blocked on a disk read that has
  /// not happened yet.
  static Future<bool> blockedOrLoad() async {
    await (_loading ??= _load());
    return _blocked;
  }

  static Future<void> _load() async {
    try {
      final dir = await _directory();
      if (dir == null) return;
      _dirPath = dir.path;
      _blocked = _markerFile()?.existsSync() ?? false;
    } catch (_) {
      // A phone whose support directory cannot be read behaves exactly as it did
      // before this latch existed: the ladder is free to try the native engine.
      _blocked = false;
    }
  }

  /// **Announces a native attempt, and it must happen before the view is
  /// mounted.** Synchronous by design — see the class header.
  static void markAttempt() {
    attemptMarks++;
    final file = _markerFile();
    if (file == null) return;
    try {
      final dir = Directory(_dirPath!);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      file.writeAsStringSync(
        'native fallback attempt began ${DateTime.now().toIso8601String()} — '
        'this line is deleted once the engine reports the model loaded\n',
      );
    } catch (_) {/* never let the guard break the box */}
  }

  /// **The phone survived the load with the native engine** — the marker's whole
  /// reason to exist is over, and the next launch may try again.
  ///
  /// Called on the native engine's own `modelLoaded` event, which arrives in
  /// every build (it is not diagnostics-gated), which is why it is the signal the
  /// latch hangs on.
  static void clearAttempt() {
    clears++;
    final file = _markerFile();
    if (file == null) return;
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {/* the marker survives; the next launch simply stays latched */}
  }

  static File? _markerFile() {
    final path = _dirPath;
    if (path == null) return null;
    return File('$path${Platform.pathSeparator}$markerName');
  }

  static Future<Directory?> _directory() async {
    final override = dirOverrideForTest;
    if (override != null) return Directory(override);
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}$folderName');
  }

  /// Test-only: forget everything the process learned, including any resolved
  /// directory, so one test's latch cannot reach another's.
  @visibleForTesting
  static void resetForTest() {
    _dirPath = null;
    _loading = null;
    _blocked = false;
    dirOverrideForTest = null;
    attemptMarks = 0;
    clears = 0;
  }
}
