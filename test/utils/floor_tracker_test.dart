import 'package:app/utils/floor_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a floor is stable only after kFloorStablePolls agreeing polls', () {
    final tracker = FloorTracker();
    expect(tracker.observe([0.0, 0.0, 0.0, 0.0]), isFalse);
    expect(tracker.isStable, isFalse);

    expect(tracker.observe([0.0, 0.0, 0.0, 0.0]), isTrue);
    expect(tracker.floorY, 0.0);
  });

  test('a floor still moving more than the spread never stabilises', () {
    final tracker = FloorTracker();
    // Each poll drifts further than kFloorStableSpreadM from the last.
    expect(tracker.observe([0.00, 0.00, 0.00]), isFalse);
    expect(tracker.observe([0.05, 0.05, 0.05]), isFalse);
    expect(tracker.observe([0.10, 0.10, 0.10]), isFalse);
    expect(tracker.isStable, isFalse);
  });

  test('small ARCore jitter within the spread still stabilises', () {
    final tracker = FloorTracker();
    tracker.observe([0.000, 0.001, 0.000]);
    expect(
      tracker.observe([0.005, 0.004, 0.006]),
      isTrue,
      reason: 'a few mm of jitter on a settled plane is not drift',
    );
  });

  test('the floor height is the median of the probes, not the mean', () {
    final tracker = FloorTracker();
    tracker.observe([0.00, 0.00, 0.00, 0.50]); // one outlier hit
    tracker.observe([0.00, 0.00, 0.00, 0.50]);
    expect(tracker.floorY, 0.00);
  });

  test('too few floor hits in a poll breaks the streak', () {
    final tracker = FloorTracker();
    tracker.observe([0.0, 0.0, 0.0]);
    expect(tracker.observe([0.0, 0.0]), isFalse,
        reason: 'two hits cannot vouch for the floor');
    expect(tracker.isStable, isFalse);
    // The streak restarted, so one more agreeing poll is not enough.
    expect(tracker.observe([0.0, 0.0, 0.0]), isFalse);
    expect(tracker.observe([0.0, 0.0, 0.0]), isTrue);
  });

  test('reset clears a stable floor', () {
    final tracker = FloorTracker();
    tracker.observe([0.0, 0.0, 0.0]);
    tracker.observe([0.0, 0.0, 0.0]);
    tracker.reset();
    expect(tracker.isStable, isFalse);
    expect(tracker.floorY, isNull);
  });
}
