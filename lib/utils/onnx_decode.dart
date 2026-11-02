/// Pure Dart port of the portal's YOLO11n-pose ONNX decode
/// (`customer-portal/src/lib/footDetectorOnnx.js` + the `[1,11,N]` unpack in
/// `footTracker.worker.js`).
///
/// The single source of truth for the proposal contract: one row per proposal
///   `[cx, cy, w, h, hx, hy, hc, tx, ty, tc, boxConf]`
/// where the box is in letterbox-normalized space and the keypoints are
/// already mapped back to source-frame UV (the worker's `toUV` inversion).
/// Rows with low box confidence, missing heel AND toe, or non-finite boxes
/// are dropped; a tiny NMS (IoU 0.45) keeps at most 2; side is always
/// `left` — the single-class schema has no left/right.
///
/// The Android native plugin (`OnnxFootDetectorPlugin.kt`) implements this
/// same logic in Kotlin; these Dart functions pin the thresholds so the two
/// can never drift (see `test/utils/onnx_decode_test.dart`).
library;

/// Model input edge (portal `ONNX_SIZE`).
const int kOnnxInputSize = 640;

/// Minimum box confidence to keep a proposal (portal `ONNX_BOX_CONF`).
const double kOnnxBoxConf = 0.35;

/// Minimum keypoint confidence to keep a heel/toe point (portal `ONNX_KPT_CONF`).
const double kOnnxKptConf = 0.3;

/// IoU threshold for the tiny NMS pass (portal `ONNX_NMS_IOU`).
const double kOnnxNmsIou = 0.45;

/// A decoded foot in source-frame UV (same shape the portal tracker emits).
class OnnxDecodedFoot {
  final String side;
  final double heelX;
  final double heelY;
  final double heelScore;
  final double toeX;
  final double toeY;
  final double toeScore;
  final double score;

  const OnnxDecodedFoot({
    required this.side,
    required this.heelX,
    required this.heelY,
    required this.heelScore,
    required this.toeX,
    required this.toeY,
    required this.toeScore,
    required this.score,
  });
}

double _boxIou(
  double ax, double ay, double aw, double ah,
  double bx, double by, double bw, double bh,
) {
  final x1 = (ax - aw / 2) > (bx - bw / 2) ? (ax - aw / 2) : (bx - bw / 2);
  final y1 = (ay - ah / 2) > (by - bh / 2) ? (ay - ah / 2) : (by - bh / 2);
  final x2 = (ax + aw / 2) < (bx + bw / 2) ? (ax + aw / 2) : (bx + bw / 2);
  final y2 = (ay + ah / 2) < (by + bh / 2) ? (ay + ah / 2) : (by + bh / 2);
  final interW = x2 - x1;
  final interH = y2 - y1;
  final inter = (interW > 0 && interH > 0) ? interW * interH : 0.0;
  final union = aw * ah + bw * bh - inter;
  if (!(union > 0)) return 0.0;
  return inter / union;
}

/// Decode raw proposal rows into portal feet (highest confidence first).
List<OnnxDecodedFoot> decodeOnnxProposals(List<List<double>> rows) {
  final kept = <_Kept>[];
  for (final r in rows) {
    if (r.length < 11) continue;
    final cx = r[0];
    final cy = r[1];
    final w = r[2];
    final h = r[3];
    final hx = r[4];
    final hy = r[5];
    final hc = r[6];
    final tx = r[7];
    final ty = r[8];
    final tc = r[9];
    final conf = r[10];
    if (!(conf >= kOnnxBoxConf)) continue;
    if (!(cx.isFinite && cy.isFinite && w.isFinite && h.isFinite)) continue;
    final heelOk =
        hx.isFinite && hy.isFinite && hc >= kOnnxKptConf;
    final toeOk =
        tx.isFinite && ty.isFinite && tc >= kOnnxKptConf;
    if (!heelOk || !toeOk) continue;
    kept.add(_Kept(cx, cy, w, h, hx, hy, hc, tx, ty, tc, conf));
  }
  kept.sort((a, b) => b.conf.compareTo(a.conf));
  final picked = <_Kept>[];
  for (final c in kept) {
    var overlaps = false;
    for (final o in picked) {
      if (_boxIou(o.cx, o.cy, o.w, o.h, c.cx, c.cy, c.w, c.h) >
          kOnnxNmsIou) {
        overlaps = true;
        break;
      }
    }
    if (overlaps) continue;
    picked.add(c);
    if (picked.length >= 2) break;
  }
  return [
    for (final c in picked)
      OnnxDecodedFoot(
        side: 'left',
        heelX: c.hx,
        heelY: c.hy,
        heelScore: c.hc,
        toeX: c.tx,
        toeY: c.ty,
        toeScore: c.tc,
        score: c.conf,
      ),
  ];
}

class _Kept {
  final double cx;
  final double cy;
  final double w;
  final double h;
  final double hx;
  final double hy;
  final double hc;
  final double tx;
  final double ty;
  final double tc;
  final double conf;

  _Kept(this.cx, this.cy, this.w, this.h, this.hx, this.hy, this.hc, this.tx,
      this.ty, this.tc, this.conf);
}
