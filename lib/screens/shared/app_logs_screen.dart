import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../constants/app_constants.dart';
import '../../services/diag_logger.dart';

/// **The app's own log, readable and sendable from Settings.**
///
/// Why this exists at all: the phone this was written for — the owner's P30 Pro —
/// has developer options locked behind a password its previous owner set, so
/// `adb logcat` will never be read from it. Every fact about a fault on that phone
/// has to be written down by the app and carried out by hand
/// (`DiagLogger` + `DiagRelay`, the same `nav_diag.log`, one `fsync` per line, so
/// a process death leaves the lines that led to it).
///
/// What was missing was not capture but *reach*: the only way to the file was a
/// bug icon inside Foot Sizing, and the only way out of it was a share sheet. A
/// face-to-face debugging loop needs to *read* the tail and paste it, which is
/// what this screen adds — with the share sheet still there for the whole file.
///
/// **Dev-mode only, on purpose.** The row that opens this lives behind
/// `DevMode.instance.isEnabled` (Settings → Developer), so no customer build shows
/// it: a log screen is a diagnostic tool, not a support surface, and the strings
/// in the file are operational rather than customer-facing.
///
/// ⚠️ **Honest about what it is not.** This is the *app's* log, not Android's
/// `logcat` and not a tombstone. When a native abort kills the process — which is
/// the fault this was built for — there is no Java stack here, only the relay
/// lines that came before it. Those are usually enough to say *which step* died
/// (engine built? model loaded? surface detached?), which is the question a fix
/// starts from.
/// What the screen reads: the decoded text, and how many bytes it came from.
class LogContents {
  const LogContents({required this.text, required this.bytes});

  final String text;
  final int bytes;
}

/// How a log is read. `null` means there is no file at that path.
typedef LogTailReader = Future<LogContents?> Function(String path);

/// Decodes log bytes **permissively**, because the write a dying process
/// interrupted is exactly the write worth keeping: strict decoding would throw on
/// the last line of the crash this file exists to describe.
String decodeLogBytes(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true);

class AppLogsScreen extends StatefulWidget {
  const AppLogsScreen({super.key, this.pathOverride, this.reader});

  /// Test seam: read this file instead of the app's real log.
  final String? pathOverride;

  /// Test seam: how to read it. Production reads the bytes itself
  /// ([decodeLogBytes]); a widget test injects one because a `testWidgets` body
  /// runs in a fake-async zone where `dart:io` never completes.
  final LogTailReader? reader;

  @override
  State<AppLogsScreen> createState() => _AppLogsScreenState();
}

class _AppLogsScreenState extends State<AppLogsScreen> {
  /// How many trailing lines are shown. The *tail* is the part that matters
  /// (a crash is at the end), and a long-running app can write tens of thousands
  /// of lines; the whole file is still what the share button sends.
  static const int _maxShownLines = 2000;

  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  String? _path;
  String? _error;
  List<String> _lines = const <String>[];
  int _totalLines = 0;
  int _bytes = 0;
  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<String?> _resolvePath() async {
    if (widget.pathOverride != null) return widget.pathOverride;
    final opened = DiagLogger.instance.logPath;
    if (opened != null) return opened;
    // `init()` has not run (or capture is off): the file has a fixed name in the
    // documents directory precisely so it survives a process death, so the path is
    // derivable without the logger.
    try {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}${Platform.pathSeparator}nav_diag.log';
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final resolved = await _resolvePath();
    if (resolved == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _path = null;
        _lines = const <String>[];
        _totalLines = 0;
        _bytes = 0;
        _truncated = false;
      });
      return;
    }
    try {
      final contents = await _read(resolved);
      if (contents == null) {
        // No file yet — not a failure, just nothing recorded.
        if (!mounted) return;
        setState(() {
          _loading = false;
          _path = resolved;
          _lines = const <String>[];
          _totalLines = 0;
          _bytes = 0;
          _truncated = false;
        });
        return;
      }
      final all = const LineSplitter().convert(contents.text);
      final shown = all.length > _maxShownLines
          ? all.sublist(all.length - _maxShownLines)
          : all;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _path = resolved;
        _bytes = contents.bytes;
        _totalLines = all.length;
        _lines = shown;
        _truncated = shown.length != all.length;
      });
      _jumpToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _path = resolved;
        _error = '$e';
        _lines = const <String>[];
      });
    }
  }

  /// Reads the log, or returns `null` when there is no file at [path].
  Future<LogContents?> _read(String path) async {
    final reader = widget.reader;
    if (reader != null) return reader(path);
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return LogContents(text: decodeLogBytes(bytes), bytes: bytes.length);
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _copyAll() async {
    final path = _path;
    if (path == null) return;
    String payload;
    try {
      payload = (await _read(path))?.text ?? _lines.join('\n');
    } catch (_) {
      payload = _lines.join('\n');
    }
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied $_totalLines lines — paste them into the report.',
          style: AppConstants.bodyStyle(fontSize: 13),
        ),
      ),
    );
  }

  Future<void> _shareFile() async {
    // The whole file, not the shown tail: the share sheet is the only route out
    // of a phone with no cable.
    await DiagLogger.instance.export();
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'App logs',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy every line',
            icon: const Icon(Icons.copy_all_outlined, size: 20),
            onPressed: _lines.isEmpty ? null : _copyAll,
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _lines.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton.icon(
                  onPressed: _shareFile,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: Text(
                    'Send the whole file',
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.secondary,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _message(
        icon: Icons.error_outline,
        title: 'Could not read the log',
        body: _error!,
      );
    }
    if (_lines.isEmpty) {
      return _message(
        icon: Icons.receipt_long_outlined,
        title: 'Nothing recorded yet',
        body: kNavDiagEnabled
            ? 'The app writes here as it runs. Open a product\'s 3D preview — or '
                'reproduce the fault — then tap reload above, and the lines will be '
                'here.'
            : 'Capture is switched off in this build (kNavDiagEnabled is false), '
                'so the app is not writing a log.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                _path ?? '',
                style: AppConstants.bodyStyle(fontSize: 11)
                    .copyWith(color: AppConstants.secondary.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 4),
              Text(
                '${_fmtBytes(_bytes)} · $_totalLines lines'
                '${_truncated ? ' · showing the last ${_lines.length}' : ''}',
                style: AppConstants.bodyStyle(fontSize: 12),
              ),
              if (_truncated)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Send the whole file to get the rest.',
                    style: AppConstants.bodyStyle(fontSize: 12)
                        .copyWith(color: AppConstants.secondary.withValues(alpha: 0.6)),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              itemCount: _lines.length,
              itemBuilder: (context, index) => SelectableText(
                _lines[index],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppConstants.secondary.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
