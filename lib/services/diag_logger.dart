// TEMPORARY Phase-1b diagnostics — REMOVE ENTIRE FILE after root cause is
// confirmed and the fix verified (see PHASE_1B_ONDEVICE_DIAGNOSTICS_PROMPT.md
// Step 5). Everything here is gated behind [kNavDiagEnabled]; flipping that
// single const to false disables all capture (and lets the compiler tree-shake
// it out of release builds).
//
// Why this exists: adb/USB debugging is unavailable on the test device, so the
// investigation of "scan completes → app closes instead of showing results"
// depends entirely on in-app capture. This logger:
//   * appends ms-timestamped lines to a FIXED file in the app documents dir
//     (`nav_diag.log`). Fixed name on purpose — the bug closes the process,
//     so the surviving file must be picked up by the NEXT launch's export.
//   * writes synchronously with a flush per line (RandomAccessFile
//     writeStringSync + flushSync) because the moment being captured IS the
//     process death — an async buffered sink would lose the tail.
//   * hands the same path to the native side via the existing
//     `com.solevision/ar_foot_sizing` MethodChannel (`setDiagLogFile`), where
//     DiagRelay.kt mirrors Kotlin events into the identical file. Both sides
//     stamp wall-clock time so lines are orderable across the boundary.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'ar_core_channel.dart' show invokeArFootMethod;

/// Master switch for ALL Phase-1b diagnostic capture. Set to false (or delete
/// this file and its call sites) once the fix is verified.
const bool kNavDiagEnabled = true;

/// Convenience top-level entry point used by the `[NAV-DEBUG]` call sites.
void navDiag(String message) => DiagLogger.instance.log(message);

class DiagLogger {
  DiagLogger._();

  static final DiagLogger instance = DiagLogger._();

  RandomAccessFile? _raf;
  String? _path;
  bool _initStarted = false;

  /// Lines logged before init finished (async dir lookup) — flushed to disk
  /// once the file is open.
  final List<String> _preInit = [];

  String? get logPath => _path;

  Future<void> init() async {
    if (!kNavDiagEnabled || _initStarted) return;
    _initStarted = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}${Platform.pathSeparator}nav_diag.log';
      final raf = await File(path).open(mode: FileMode.append);
      _path = path;
      _raf = raf;
      _writeDirect('=== diag session start (new process launch) ===');
      for (final line in _preInit) {
        _writeDirect(line);
      }
      _preInit.clear();
    } catch (e) {
      debugPrint('[NAV-DIAG] init failed: $e');
      return;
    }
    // Hand the path to Kotlin so native-side events land in the SAME file.
    try {
      await invokeArFootMethod('setDiagLogFile', {'path': _path});
    } catch (e) {
      debugPrint('[NAV-DIAG] native relay registration failed: $e');
    }
    // Capture Dart-visible app lifecycle: if the activity finishes, the
    // engine detaches and we see it here as inactive/detached/paused.
    WidgetsBinding.instance.addObserver(_LifecycleObserver());
    log('DiagLogger ready at $_path');
  }

  void log(String message) {
    if (!kNavDiagEnabled) return;
    debugPrint('[NAV-DIAG] $message');
    final stamped = '${_fmt(DateTime.now())} [DART] $message';
    final raf = _raf;
    if (raf == null) {
      _preInit.add(stamped);
      return;
    }
    try {
      raf.writeStringSync('$stamped\n');
      raf.flushSync();
    } catch (_) {/* never let diagnostics break the app */}
  }

  /// Share-sheet export of the current log file. No new permissions needed.
  Future<void> export() async {
    final path = _path;
    if (!kNavDiagEnabled || path == null) return;
    log('export requested');
    try {
      _raf?.flushSync();
    } catch (_) {}
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'text/plain')],
        subject: 'nav_diag.log',
      ),
    );
  }

  void _writeDirect(String line) {
    try {
      _raf?.writeStringSync('$line\n');
      _raf?.flushSync();
    } catch (_) {}
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    navDiag('AppLifecycleState → $state');
  }
}

/// Local-time timestamp with forced millisecond precision, e.g.
/// `2026-08-23T14:05:09.123`. Matches DiagRelay.kt's format so Dart/native
/// lines interleave in true wall-clock order.
String _fmt(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}T${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.'
    '${t.millisecond.toString().padLeft(3, '0')}';
