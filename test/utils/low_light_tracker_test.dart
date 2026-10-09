import 'package:app/utils/low_light_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a bright view is not too dark', () {
    final t = LowLightTracker();
    expect(t.observe(120), isFalse);
    expect(t.isDark, isFalse);
  });

  test('a view below the enter line is too dark', () {
    final t = LowLightTracker();
    expect(t.observe(kDarkEnterLuma - 1), isTrue);
    expect(t.isDark, isTrue);
  });

  test('a view inside the gap keeps its previous state, so the coach does not flicker', () {
    final t = LowLightTracker();
    const mid = (kDarkEnterLuma + kDarkExitLuma) / 2;

    // Starting bright, a mid reading stays bright.
    expect(t.observe(mid), isFalse);

    // Once dark, the same mid reading stays dark.
    t.observe(kDarkEnterLuma - 1);
    expect(t.observe(mid), isTrue);
  });

  test('recovers only once the view is above the exit line', () {
    final t = LowLightTracker()..observe(0);
    expect(t.observe(kDarkExitLuma), isTrue,
        reason: 'exactly the exit line does not yet count as light');
    expect(t.observe(kDarkExitLuma + 1), isFalse);
  });

  test('a null reading keeps the current state', () {
    final t = LowLightTracker()..observe(0);
    expect(t.observe(null), isTrue);

    final bright = LowLightTracker()..observe(200);
    expect(bright.observe(null), isFalse);
  });

  test('reset forgets a dark reading', () {
    final t = LowLightTracker()..observe(0);
    t.reset();
    expect(t.isDark, isFalse);
  });
}
