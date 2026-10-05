/// The reference normalizer, exposed to JavaScript — the entry point behind the
/// admin portal's "Compress it" step on `/model-requests`.
///
/// **Why this file exists.** A seller files a model request, a partner sends
/// back a raw export, and it is 90 MB with 1.5 million triangles: too big for
/// the bucket, and refused by the authoring contract besides. The admin's only
/// route used to be a terminal, which is the exact gap
/// `docs/RoadMap/SHOE_MODEL_AUTHORING_GUIDE.md` §C9.1 opens with. This compiles
/// the *same* `normalizeShoeModel` the CLI runs (`tool/prepare_shoe_model.dart`)
/// into JavaScript, so the portal can do it in the page.
///
/// **It is the reference implementation, not a port.** That distinction is the
/// whole reason this approach was chosen over reimplementing the normalizer in
/// JavaScript: the eleven-check contract has two implementations on purpose
/// (the Dart reference and the TypeScript mirror in `validate-shoe-model`,
/// parity-checked over 22 fixtures), and the portal's own rule is that it adds
/// no third. Compiling the Dart is not a third copy — it is the first one,
/// running in a different runtime.
///
/// ```bash
/// node tool/build_shoe_model_normalizer_web.mjs      # writes the artifact
/// ```
///
/// The artifact is checked in so `npm install && npm run build` works in
/// `admin-portal/` with no Dart toolchain — the portal's CI job installs Node
/// and nothing else. `modelCompress.contract.test.js` fails if the Dart sources
/// change without a rebuild, so the two cannot drift.
///
/// **What is deliberately not exposed: the validator.** `validate_glb.dart`'s
/// eleven checks stay where they are. The portal compresses, then uploads, and
/// the server judges the stored bytes — a green run here is not acceptance and
/// nothing in the UI claims it is (guide §5.2's reviewer rows still apply).
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:app/utils/glb_normalizer.dart';

/// `globalThis.soleVisionNormalize`, for the worker to call.
@JS('soleVisionNormalize')
external set _exported(JSFunction value);

void main() {
  _exported = _normalize.toJS;
}

ToeEnd? _toeEnd(String? raw) => switch (raw) {
      '+x' => ToeEnd.plusX,
      '-x' => ToeEnd.minusX,
      '+z' => ToeEnd.plusZ,
      '-z' => ToeEnd.minusZ,
      _ => null,
    };

/// One normalization, with the options as a JSON string.
///
/// Returns `{ ok: true, bytes, changes, before, after }` or
/// `{ ok: false, error }` — never throws, because a thrown exception across the
/// JS boundary arrives as an unhelpful `DartError` and the message is the whole
/// value of the refusal (`GlbNormalizationException`'s text is written to be
/// forwarded to whoever sent the model).
///
/// `changes`, `before` and `after` travel as JSON strings for the same reason
/// the options arrive as one: the shapes are nested and the caller only ever
/// renders them. `bytes` is a real `Uint8Array` because it is transferred, not
/// read.
JSObject _normalize(JSAny input, JSAny optionsJson) {
  final out = JSObject();
  try {
    final bytes = (input as JSUint8Array).toDart;
    final options = jsonDecode((optionsJson as JSString).toDart) as Map<String, dynamic>;

    final renames = <String, String>{};
    final rawRenames = options['materialRenames'];
    if (rawRenames is Map) {
      rawRenames.forEach((key, value) => renames[key.toString()] = value.toString());
    }

    final result = normalizeShoeModel(
      Uint8List.fromList(bytes),
      options: GlbNormalizerOptions(
        externalLengthMm: (options['externalLengthMm'] as num?)?.toDouble(),
        toe: _toeEnd(options['toe'] as String?),
        authoredSizeEu: (options['authoredSizeEu'] as num?)?.toDouble(),
        maxTextureSize:
            (options['maxTextureSize'] as num?)?.toInt() ?? kNormalizerTextureSize,
        jpegQuality:
            (options['jpegQuality'] as num?)?.toInt() ?? kNormalizerJpegQuality,
        materialRenames: renames,
        soleBandMm: (options['soleBandMm'] as num?)?.toDouble(),
      ),
    );

    out.setProperty('ok'.toJS, true.toJS);
    out.setProperty('bytes'.toJS, result.bytes.toJS);
    out.setProperty('changes'.toJS, jsonEncode(result.changes).toJS);
    out.setProperty('before'.toJS, jsonEncode(result.before).toJS);
    out.setProperty('after'.toJS, jsonEncode(result.after).toJS);
  } on GlbNormalizationException catch (error) {
    out.setProperty('ok'.toJS, false.toJS);
    out.setProperty('error'.toJS, error.message.toJS);
  } catch (error) {
    // Anything else is a bug rather than a bad file, and the caller needs to be
    // able to tell the two apart in the report.
    out.setProperty('ok'.toJS, false.toJS);
    out.setProperty('error'.toJS, error.toString().toJS);
  }
  return out;
}
