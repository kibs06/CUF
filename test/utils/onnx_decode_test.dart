import 'package:app/utils/onnx_decode.dart';
import 'package:flutter_test/flutter_test.dart';

List<double> row({
  double cx = 0.5,
  double cy = 0.5,
  double w = 0.2,
  double h = 0.3,
  double hx = 0.45,
  double hy = 0.6,
  double hc = 0.9,
  double tx = 0.55,
  double ty = 0.4,
  double tc = 0.9,
  double conf = 0.9,
}) =>
    [cx, cy, w, h, hx, hy, hc, tx, ty, tc, conf];

void main() {
  test('keeps a confident heel+toe proposal as left', () {
    final feet = decodeOnnxProposals([row()]);
    expect(feet, hasLength(1));
    expect(feet.single.side, 'left');
    expect(feet.single.heelX, 0.45);
    expect(feet.single.score, 0.9);
  });

  test('drops low box confidence', () {
    expect(decodeOnnxProposals([row(conf: 0.2)]), isEmpty);
  });

  test('drops missing heel or toe', () {
    expect(decodeOnnxProposals([row(hc: 0.1)]), isEmpty);
    expect(decodeOnnxProposals([row(tc: 0.1)]), isEmpty);
  });

  test('drops short rows and non-finite boxes', () {
    expect(decodeOnnxProposals([[0.5, 0.5]]), isEmpty);
    expect(
        decodeOnnxProposals([row(cx: double.nan)]), isEmpty);
  });

  test('NMS keeps highest confidence overlapping box, max 2', () {
    final a = row(conf: 0.9);
    final b = row(conf: 0.8); // same box → suppressed
    final c = row(cx: 0.1, cy: 0.1, conf: 0.7); // far → kept
    final d = row(cx: 0.9, cy: 0.9, conf: 0.6); // far but over max-2 → dropped
    final feet = decodeOnnxProposals([b, a, c, d]);
    expect(feet.map((f) => f.score), [0.9, 0.7]);
  });
}
