import 'package:app/services/device_trust_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceTrustPolicy.requiresEmailOtpChallenge', () {
    test('a known device never challenges', () {
      expect(
        DeviceTrustPolicy.requiresEmailOtpChallenge(
          deviceKnown: true,
          mfaEnabled: false,
        ),
        isFalse,
      );
      expect(
        DeviceTrustPolicy.requiresEmailOtpChallenge(
          deviceKnown: true,
          mfaEnabled: true,
        ),
        isFalse,
      );
    });

    test('an unknown device without MFA challenges', () {
      expect(
        DeviceTrustPolicy.requiresEmailOtpChallenge(
          deviceKnown: false,
          mfaEnabled: false,
        ),
        isTrue,
      );
    });

    test('TOTP MFA satisfies the step-up, so no email code is sent', () {
      // The documented step-6 decision: an authenticator app is a stronger
      // possession factor than an emailed code, so stacking both is pure
      // friction. This test is the contract for that choice.
      expect(
        DeviceTrustPolicy.requiresEmailOtpChallenge(
          deviceKnown: false,
          mfaEnabled: true,
        ),
        isFalse,
      );
    });
  });

  group('TrustedDevice.fromRow', () {
    test('parses ids, labels and timestamps', () {
      final device = TrustedDevice.fromRow({
        'device_id': 'abc-123-456',
        'device_label': 'samsung SM-A155F · Android 14',
        'first_seen_at': '2026-09-01T02:00:00.000Z',
        'last_seen_at': '2026-09-15T02:30:00.000Z',
        'trusted_at': '2026-09-01T02:00:00.000Z',
      });

      expect(device.deviceId, 'abc-123-456');
      expect(device.deviceLabel, 'samsung SM-A155F · Android 14');
      expect(device.displayLabel, 'samsung SM-A155F · Android 14');
      expect(device.firstSeenAt, isNotNull);
      expect(device.lastSeenAt, isNotNull);
      expect(device.trustedAt, isNotNull);
      // Parsed as UTC then converted for display.
      expect(device.lastSeenAt!.isUtc, isFalse);
    });

    test('tolerates a missing label and dates', () {
      final device = TrustedDevice.fromRow({'device_id': 'abcdef123456'});
      expect(device.deviceLabel, isNull);
      expect(device.lastSeenAt, isNull);
      // Falls back to a recognisable short id rather than an empty row.
      expect(device.displayLabel, 'Device abcdef12');
    });

    test('falls back to the raw id when it is too short to abbreviate', () {
      final device = TrustedDevice.fromRow({
        'device_id': 'short',
        'device_label': '   ',
      });
      expect(device.displayLabel, 'short');
    });
  });
}
