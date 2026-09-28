/// Offline GLB validator — the command a partner runs on an exported shoe
/// model (roadmap V2.7, `docs/RoadMap/SHOE_MODEL_AUTHORING_GUIDE.md` §C9).
///
/// ```bash
/// dart run tool/validate_glb.dart deliver/<partner>_<product>_<colour>_v1.glb
/// ```
///
/// The checks themselves live in `lib/utils/glb_validator.dart` (pure Dart,
/// unit-tested); this file is only the command line around them: it reads the
/// file, finds the declared external length (a `--flag` first, then the
/// `declaration.txt` beside the model, per guide §5.1), prints a pass/fail
/// table, and exits non-zero on any failure so a pipeline can gate on it.
///
/// Exit codes: `0` all checks pass · `1` at least one check failed ·
/// `2` the command itself could not run (bad path, bad arguments).
library;

import 'dart:convert';
import 'dart:io';

import 'package:app/utils/glb_validator.dart';

final String _usage = '''
Usage: dart run tool/validate_glb.dart <file.glb> [options]

The file must be the exported .glb. The declared external length comes from
--external-length-mm when given, otherwise from declaration.txt beside the
model (guide §5.1). Without either, the ±5 mm scale check fails on purpose —
that number is the handover's job.

Options:
  --external-length-mm <mm>   declared external heel-to-toe length (wins over declaration.txt)
  --declaration <path>        declaration file to read (default: <model dir>/declaration.txt)
  --authored-size-eu <n>      reference size, echoed in the report
  --side left|right           declared side, echoed in the report
  --json                      print the machine-readable report instead of the table
  -h, --help                  this text

Checks: GLB structure and single-file embedding · file size (5 MiB budget,
8 MiB bucket cap) · triangles (60,000 cap) · material part names
(${kApprovedPartNames.join(', ')}) · texture dimensions (1024² max) ·
compression gate (Draco / meshopt / KTX2 rejected until V0.7) · units
(metres) · up-axis (the long axis must be +Z) · origin and grounding
(±${kOriginToleranceMm.toInt()} mm) · external length vs declared (±${kLengthToleranceMm.toInt()} mm).

Not checkable from the file — those stay reviewer rows in the guide:
toe-vs-heel direction (a bbox is symmetric), albedo de-lighting, likeness,
on-device frame rate.
''';

Future<void> main(List<String> args) async {
  final parsed = _Args.parse(args);
  if (parsed == null) {
    stdout.writeln(_usage);
    exit(2);
  }
  if (parsed.help) {
    stdout.writeln(_usage);
    return;
  }
  final path = parsed.path!;

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('error: no such file: $path');
    exit(2);
  }

  final declaration = _loadDeclaration(path, parsed.declarationPath);
  final declaredLength = parsed.externalLengthMm ??
      declarationNumber(declaration.values['external_length_mm']);
  final authoredSizeEu =
      parsed.authoredSizeEu ?? declarationNumber(declaration.values['authored_size_eu']);
  final side = parsed.side ?? _nonEmpty(declaration.values['shoe_side']);

  final report = validateGlb(
    file.readAsBytesSync(),
    options: GlbValidationOptions(
      label: path,
      externalLengthMm: declaredLength,
      authoredSizeEu: authoredSizeEu,
      shoeSide: side,
    ),
  );

  if (parsed.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } else {
    _printTable(report, declarationPath: declaration.path);
  }

  exit(report.passed ? 0 : 1);
}

// ─── Output ────────────────────────────────────────────────────────────────

void _printTable(GlbValidationReport report, {String? declarationPath}) {
  final width = report.checks
      .map((c) => c.name.length)
      .fold<int>(0, (a, b) => a > b ? a : b);

  stdout.writeln('GLB validator — ${report.options.label}');
  stdout.writeln();
  for (final check in report.checks) {
    stdout.writeln(
        '  ${_tag(check.status)}  ${check.name.padRight(width)}  ${check.detail}');
  }
  stdout.writeln();

  stdout.writeln('  declared external length: '
      '${report.options.externalLengthMm == null ? 'MISSING' : '${report.options.externalLengthMm!.toStringAsFixed(1)} mm'}'
      '${declarationPath == null ? '' : ' (from $declarationPath)'}');
  if (report.options.authoredSizeEu != null) {
    stdout.writeln(
        '  authored reference size:  EU ${report.options.authoredSizeEu!.toStringAsFixed(0)}');
  }
  if (report.options.shoeSide != null) {
    stdout.writeln('  declared side:            ${report.options.shoeSide}');
  }

  for (final note in report.notes) {
    stdout.writeln('  note: $note');
  }
  stdout.writeln();

  if (report.passed) {
    stdout.writeln(
        'RESULT: PASS — ${report.checks.length} checks'
        '${report.warningCount == 0 ? '' : ', ${report.warningCount} warning(s)'}');
  } else {
    stdout.writeln(
        'RESULT: FAIL — ${report.failCount} of ${report.checks.length} checks failed');
  }
  stdout.writeln(
      'Attach this output to the handover (guide §5.1). A green run is not '
      'acceptance: orientation (toe vs heel), de-lit albedo, likeness and '
      'on-device fps stay with the reviewer (checklist 2, 6, 7, 9).');
}

String _tag(GlbCheckStatus status) => switch (status) {
      GlbCheckStatus.pass => 'PASS',
      GlbCheckStatus.fail => 'FAIL',
      GlbCheckStatus.warning => 'WARN',
    };

// ─── Input ─────────────────────────────────────────────────────────────────

/// Reads `declaration.txt` — explicit path first, else the model's own
/// directory. Returns an empty map (and no path) when there is none.
///
/// The parsing itself lives in `lib/utils/glb_validator.dart`
/// ([parseGlbDeclaration]); this is only the file lookup.
({Map<String, String> values, String? path}) _loadDeclaration(
    String modelPath, String? explicitPath) {
  String? path = explicitPath;
  if (path == null) {
    final separator = Platform.pathSeparator;
    final directory = File(modelPath).parent.path;
    final candidate = '$directory${separator}declaration.txt';
    if (!File(candidate).existsSync()) return (values: const {}, path: null);
    path = candidate;
  }
  final file = File(path);
  if (!file.existsSync()) return (values: const {}, path: null);
  return (values: parseGlbDeclaration(file.readAsStringSync()), path: path);
}

String? _nonEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim().toLowerCase();
  return trimmed.isEmpty ? null : trimmed;
}

// ─── Arguments ─────────────────────────────────────────────────────────────

class _Args {
  final String? path;
  final String? declarationPath;
  final double? externalLengthMm;
  final double? authoredSizeEu;
  final String? side;
  final bool json;
  final bool help;

  const _Args({
    this.path,
    this.declarationPath,
    this.externalLengthMm,
    this.authoredSizeEu,
    this.side,
    this.json = false,
    this.help = false,
  });

  /// Returns null on a malformed command line (the caller prints usage).
  static _Args? parse(List<String> args) {
    String? path;
    String? declarationPath;
    double? externalLengthMm;
    double? authoredSizeEu;
    String? side;
    var json = false;
    var help = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '-h':
        case '--help':
          help = true;
        case '--json':
          json = true;
        case '--external-length-mm':
          final value = _next(args, ++i);
          if (value == null) return null;
          externalLengthMm = double.tryParse(value);
          if (externalLengthMm == null) return null;
        case '--declaration':
          declarationPath = _next(args, ++i);
          if (declarationPath == null) return null;
        case '--authored-size-eu':
          final value = _next(args, ++i);
          if (value == null) return null;
          authoredSizeEu = double.tryParse(value);
          if (authoredSizeEu == null) return null;
        case '--side':
          final value = _next(args, ++i);
          if (value == null) return null;
          final normalised = value.toLowerCase();
          if (normalised != 'left' && normalised != 'right') return null;
          side = normalised;
        default:
          if (arg.startsWith('-')) return null;
          if (path != null) return null; // exactly one model per run
          path = arg;
      }
    }

    if (!help && path == null) return null;
    return _Args(
      path: path,
      declarationPath: declarationPath,
      externalLengthMm: externalLengthMm,
      authoredSizeEu: authoredSizeEu,
      side: side,
      json: json,
      help: help,
    );
  }

  static String? _next(List<String> args, int index) =>
      index < args.length ? args[index] : null;
}
