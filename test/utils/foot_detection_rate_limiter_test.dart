import 'package:app/utils/foot_detection_rate_limiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FootDetectionRateLimiter', () {
    test('first tick runs, immediate second tick drops', () {
      final limiter = FootDetectionRateLimiter(
        minInterval: const Duration(milliseconds: 100),
      );
      final t0 = DateTime(2026, 10, 30, 12, 0, 0);
      expect(limiter.shouldRun(now: t0, inProgress: false), isTrue);
      limiter.markStarted(t0);
      expect(
        limiter.shouldRun(
          now: t0.add(const Duration(milliseconds: 10)),
          inProgress: false,
        ),
        isFalse,
      );
    });

    test('tick after interval runs', () {
      final limiter = FootDetectionRateLimiter(
        minInterval: const Duration(milliseconds: 100),
      );
      final t0 = DateTime(2026, 10, 30, 12, 0, 0);
      limiter.markStarted(t0);
      expect(
        limiter.shouldRun(
          now: t0.add(const Duration(milliseconds: 100)),
          inProgress: false,
        ),
        isTrue,
      );
    });

    test('in-progress tick always drops', () {
      final limiter = FootDetectionRateLimiter(
        minInterval: const Duration(milliseconds: 100),
      );
      final t0 = DateTime(2026, 10, 30, 12, 0, 0);
      expect(limiter.shouldRun(now: t0, inProgress: true), isFalse);
      limiter.markStarted(t0.subtract(const Duration(seconds: 10)));
      expect(
        limiter.shouldRun(now: t0, inProgress: true),
        isFalse,
        reason: 'overlap guard wins even when interval elapsed',
      );
    });

    test('reset allows immediate run', () {
      final limiter = FootDetectionRateLimiter(
        minInterval: const Duration(milliseconds: 100),
      );
      final t0 = DateTime(2026, 10, 30, 12, 0, 0);
      limiter.markStarted(t0);
      limiter.reset();
      expect(
        limiter.shouldRun(
          now: t0.add(const Duration(milliseconds: 1)),
          inProgress: false,
        ),
        isTrue,
      );
    });
  });
}
