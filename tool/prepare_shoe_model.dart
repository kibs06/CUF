/// Offline GLB normaliser — the command that turns a partner's export into one
/// the authoring contract accepts (roadmap V2.7,
/// `docs/RoadMap/SHOE_MODEL_AUTHORING_GUIDE.md`).
///
/// ```bash
/// dart run tool/prepare_shoe_model.dart deliver/<file>.glb \
///     --external-length-mm 278 --authored-size-eu 42 --toe -x
/// dart run tool/validate_glb.dart deliver/<file>.contract.glb \
///     --external-length-mm 278 --authored-size-eu 42
/// ```
///
/// The rules live in `lib/utils/glb_normalizer.dart` (pure Dart, unit-tested);
/// this file is only the command line around them: it reads the file, applies
/// the options, writes `<name>.contract.glb` beside the input, prints what it
/// changed, and exits non-zero when it cannot.
///
/// Exit codes: `0` normalised · `1` the file cannot be normalised (the reason is
/// printed, and it is written to be forwarded to whoever sent the model) ·
/// `2` the command itself could not run (bad path, bad arguments).
library;

import 'dart:convert';
import 'dart:io';

import 'package:app/utils/glb_normalizer.dart';

const String _usage = '''
Usage: dart run tool/prepare_shoe_model.dart <file.glb> [options]

Re-axes, re-grounds, rescales, re-bakes and renames a partner's .glb so that
`validate_glb.dart` can pass it. Writes <name>.contract.glb beside the input.

Options:
  --external-length-mm <mm>   declared external heel-to-toe length; the mesh is
                              scaled to it (without it nothing is scaled and the
                              scale check will still fail)
  --authored-size-eu <n>      declared reference size, echoed into the report
  --toe +x|-x|+z|-z           which end of the long axis is the toe. Defaults to
                              the positive end, and says so in its output; the
                              validator cannot check this, a person can
  --material <from=to>        rename a part (repeatable), e.g. --material
                              "Material.001=upper"
  --sole-band-mm <mm>         for a single-material scan: put every triangle
                              entirely within this height above the ground in its
                              own "sole" primitive. An approximation, reported
                              as one
  --texture-size <n>          longest side after re-baking (default 1024)
  --png                       keep PNG instead of re-encoding to JPEG
  --out <path>                output path (default <name>.contract.glb)
  --json                      print the machine-readable result
  -h, --help                  this text

What this cannot decide: toe-versus-heel (above), the declared length (above),
whether the albedo was de-lit, whether it looks like the product, and what frame
rate it holds on device — those stay reviewer rows in the guide.
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

  final input = File(parsed.path!);
  if (!input.existsSync()) {
    stderr.writeln('error: no such file: ${parsed.path}');
    exit(2);
  }

  final GlbNormalizationResult result;
  try {
    result = normalizeShoeModel(
      input.readAsBytesSync(),
      options: GlbNormalizerOptions(
        externalLengthMm: parsed.externalLengthMm,
        toe: parsed.toe,
        authoredSizeEu: parsed.authoredSizeEu,
        maxTextureSize: parsed.textureSize,
        jpegQuality: parsed.png ? null : kNormalizerJpegQuality,
        materialRenames: parsed.renames,
        soleBandMm: parsed.soleBandMm,
      ),
    );
  } on GlbNormalizationException catch (error) {
    stderr.writeln('cannot normalise ${parsed.path}:');
    stderr.writeln('  $error');
    exit(1);
  }

  final outPath = parsed.out ?? _defaultOutput(parsed.path!);
  File(outPath).writeAsBytesSync(result.bytes);

  if (parsed.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'input': parsed.path,
      'output': outPath,
      'changes': result.changes,
      'before': result.before,
      'after': result.after,
    }));
    return;
  }

  stdout.writeln('Prepared ${parsed.path} → $outPath');
  stdout.writeln();
  _printMetrics('before', result.before);
  stdout.writeln();
  _printMetrics('after', result.after);
  stdout.writeln();
  stdout.writeln('Changes:');
  for (final change in result.changes) {
    stdout.writeln('  · $change');
  }
  stdout.writeln();
  stdout.writeln('Now check it: dart run tool/validate_glb.dart $outPath'
      ' --external-length-mm ${(result.after['lengthMm'] as double).toStringAsFixed(1)}'
      '${parsed.authoredSizeEu == null ? '' : ' --authored-size-eu ${parsed.authoredSizeEu!.toStringAsFixed(0)}'}');
  stdout.writeln('A green run is not acceptance: the reviewer still signs off '
      'toe-versus-heel, likeness, de-lit albedo and on-device frame rate.');
}

void _printMetrics(String label, Map<String, dynamic> metrics) {
  final bounds = metrics['boundsMm'] as List?;
  stdout.writeln(label);
  stdout.writeln('  size      ${_size(metrics['bytes'] as int)}');
  stdout.writeln('  triangles ${metrics['triangles']}');
  stdout.writeln('  vertices  ${metrics['vertices']}');
  stdout.writeln('  materials ${(metrics['materials'] as List).isEmpty ? '(none)' : (metrics['materials'] as List).join(', ')}');
  stdout.writeln('  L×W×H     ${_mm(metrics['lengthMm'] as double)} × '
      '${_mm(metrics['widthMm'] as double)} × ${_mm(metrics['heightMm'] as double)}');
  if (bounds != null && bounds.length == 6) {
    stdout.writeln('  bounds    x ${_mm(bounds[0] as double)}..${_mm(bounds[3] as double)}'
        '  y ${_mm(bounds[1] as double)}..${_mm(bounds[4] as double)}'
        '  z ${_mm(bounds[2] as double)}..${_mm(bounds[5] as double)}');
  }
}

String _mm(double value) => '${value.toStringAsFixed(1)} mm';

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
}

String _defaultOutput(String path) {
  final dot = path.lastIndexOf('.');
  return dot <= 0
      ? '$path.contract.glb'
      : '${path.substring(0, dot)}.contract.glb';
}

class _Args {
  final String? path;
  final String? out;
  final double? externalLengthMm;
  final double? authoredSizeEu;
  final ToeEnd? toe;
  final Map<String, String> renames;
  final double? soleBandMm;
  final int textureSize;
  final bool png;
  final bool json;
  final bool help;

  const _Args({
    this.path,
    this.out,
    this.externalLengthMm,
    this.authoredSizeEu,
    this.toe,
    this.renames = const {},
    this.soleBandMm,
    this.textureSize = kNormalizerTextureSize,
    this.png = false,
    this.json = false,
    this.help = false,
  });

  static _Args? parse(List<String> args) {
    String? path;
    String? out;
    double? externalLengthMm;
    double? authoredSizeEu;
    ToeEnd? toe;
    final renames = <String, String>{};
    double? soleBandMm;
    var textureSize = kNormalizerTextureSize;
    var png = false;
    var json = false;
    var help = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? next() => i + 1 < args.length ? args[++i] : null;
      switch (arg) {
        case '-h':
        case '--help':
          help = true;
        case '--json':
          json = true;
        case '--png':
          png = true;
        case '--external-length-mm':
          final value = next();
          if (value == null) return null;
          externalLengthMm = double.tryParse(value);
          if (externalLengthMm == null || externalLengthMm <= 0) return null;
        case '--authored-size-eu':
          final value = next();
          if (value == null) return null;
          authoredSizeEu = double.tryParse(value);
          if (authoredSizeEu == null) return null;
        case '--sole-band-mm':
          final value = next();
          if (value == null) return null;
          soleBandMm = double.tryParse(value);
          if (soleBandMm == null || soleBandMm <= 0) return null;
        case '--texture-size':
          final value = next();
          if (value == null) return null;
          textureSize = int.tryParse(value) ?? 0;
          if (textureSize < 16) return null;
        case '--toe':
          final value = next();
          if (value == null) return null;
          toe = switch (value.toLowerCase()) {
            '+x' => ToeEnd.plusX,
            '-x' => ToeEnd.minusX,
            '+z' => ToeEnd.plusZ,
            '-z' => ToeEnd.minusZ,
            _ => null,
          };
          if (toe == null) return null;
        case '--material':
          final value = next();
          if (value == null) return null;
          final split = value.indexOf('=');
          if (split <= 0) return null;
          renames[value.substring(0, split)] = value.substring(split + 1);
        case '--out':
          out = next();
          if (out == null) return null;
        default:
          if (arg.startsWith('-')) return null;
          if (path != null) return null; // exactly one model per run
          path = arg;
      }
    }
    if (!help && path == null) return null;
    return _Args(
      path: path,
      out: out,
      externalLengthMm: externalLengthMm,
      authoredSizeEu: authoredSizeEu,
      toe: toe,
      renames: renames,
      soleBandMm: soleBandMm,
      textureSize: textureSize,
      png: png,
      json: json,
      help: help,
    );
  }
}
