import 'package:app/services/email_otp_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// [EmailOtpPolicy] is pure, so every rule the OTP screen relies on is
/// asserted here rather than through the widget layer: code shape, the
/// resend cooldown, and the expiry countdown.
void main() {
  final sent = DateTime(2026, 9, 15, 12, 0, 0);

  group('EmailOtpPolicy.isCompleteCode', () {
    test('accepts exactly 6 digits', () {
      expect(EmailOtpPolicy.isCompleteCode('123456'), isTrue);
      expect(EmailOtpPolicy.isCompleteCode('000000'), isTrue);
      expect(EmailOtpPolicy.isCompleteCode(' 123456 '), isTrue);
    });

    test('rejects anything else', () {
      expect(EmailOtpPolicy.isCompleteCode('12345'), isFalse);
      expect(EmailOtpPolicy.isCompleteCode('1234567'), isFalse);
      expect(EmailOtpPolicy.isCompleteCode(''), isFalse);
      expect(EmailOtpPolicy.isCompleteCode('12345a'), isFalse);
      expect(EmailOtpPolicy.isCompleteCode('12 456'), isFalse);
      // Unicode digits are not code digits — the field is digitsOnly too.
      expect(EmailOtpPolicy.isCompleteCode('١٢٣٤٥٦'), isFalse);
    });
  });

  group('EmailOtpPolicy.resendWaitSeconds', () {
    test('counts down from the cooldown', () {
      expect(EmailOtpPolicy.resendWaitSeconds(sent, sent), 60);
      expect(
        EmailOtpPolicy.resendWaitSeconds(
          sent,
          sent.add(const Duration(seconds: 1)),
        ),
        59,
      );
      expect(
        EmailOtpPolicy.resendWaitSeconds(
          sent,
          sent.add(const Duration(seconds: 59)),
        ),
        1,
      );
    });

    test('is 0 once the cooldown has elapsed, and never negative', () {
      expect(
        EmailOtpPolicy.resendWaitSeconds(
          sent,
          sent.add(const Duration(seconds: 60)),
        ),
        0,
      );
      expect(
        EmailOtpPolicy.resendWaitSeconds(
          sent,
          sent.add(const Duration(hours: 5)),
        ),
        0,
      );
    });
  });

  group('EmailOtpPolicy.validitySeconds', () {
    test('matches the configured otp_expiry (3600s in config.toml)', () {
      expect(EmailOtpPolicy.expirySeconds, 3600);
      expect(EmailOtpPolicy.validitySeconds(sent, sent), 3600);
      expect(
        EmailOtpPolicy.validitySeconds(
          sent,
          sent.add(const Duration(minutes: 30)),
        ),
        1800,
      );
    });

    test('expires at the configured window and stays at 0 after', () {
      expect(
        EmailOtpPolicy.validitySeconds(
          sent,
          sent.add(const Duration(seconds: 3599)),
        ),
        1,
      );
      expect(
        EmailOtpPolicy.validitySeconds(
          sent,
          sent.add(const Duration(seconds: 3600)),
        ),
        0,
      );
      expect(
        EmailOtpPolicy.validitySeconds(sent, sent.add(const Duration(days: 1))),
        0,
      );
    });
  });

  group('EmailOtpPolicy.formatCountdown', () {
    test('renders mm:ss zero-padded', () {
      expect(EmailOtpPolicy.formatCountdown(3599), '59:59');
      expect(EmailOtpPolicy.formatCountdown(3600), '60:00');
      expect(EmailOtpPolicy.formatCountdown(723), '12:03');
      expect(EmailOtpPolicy.formatCountdown(0), '00:00');
    });

    test('never renders a negative countdown', () {
      expect(EmailOtpPolicy.formatCountdown(-5), '00:00');
    });
  });

  group('EmailOtpPolicy constants stay in step with config', () {
    test('code length matches config.toml otp_length = 6', () {
      expect(EmailOtpPolicy.codeLength, 6);
    });

    test('the resend cooldown is shorter than the validity window', () {
      // Otherwise a user could be told to wait longer than the code lives.
      expect(
        EmailOtpPolicy.resendCooldownSeconds,
        lessThan(EmailOtpPolicy.expirySeconds),
      );
    });
  });
}
