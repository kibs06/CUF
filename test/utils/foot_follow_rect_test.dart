import 'package:app/utils/foot_follow_rect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the box is the foot extent padded on each side', () {
    final rect = footFollowRect(const [
      Offset(0.40, 0.45),
      Offset(0.60, 0.45),
      Offset(0.48, 0.35),
      Offset(0.54, 0.35),
    ]);

    // x: 0.40..0.60 + 0.08 each side = 0.32..0.68 (width 0.36, above the minimum).
    expect(rect.left, closeTo(0.32, 1e-9));
    expect(rect.right, closeTo(0.68, 1e-9));
    // y: 0.35..0.45 + 0.08 each side = 0.27..0.53 (height 0.26, above the minimum).
    expect(rect.top, closeTo(0.27, 1e-9));
    expect(rect.bottom, closeTo(0.53, 1e-9));
  });

  test('a small extent is widened to the minimum side, centred on the foot', () {
    final rect = footFollowRect(const [Offset(0.50, 0.50), Offset(0.51, 0.50)]);

    expect(rect.width, closeTo(kFollowMinSide, 1e-9));
    expect(rect.height, closeTo(kFollowMinSide, 1e-9));
    expect(rect.center.dx, closeTo(0.505, 1e-9));
    expect(rect.center.dy, closeTo(0.50, 1e-9));
  });

  test('the box is clamped inside the frame', () {
    final rect = footFollowRect(const [Offset(0.02, 0.98), Offset(0.10, 0.99)]);

    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(1));
    expect(rect.bottom, lessThanOrEqualTo(1));
  });
}
