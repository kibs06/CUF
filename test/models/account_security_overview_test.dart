import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/account_security_overview.dart';

/// The payload below mirrors what `public.admin_account_security_overview`
/// actually returns — it was captured from a real call against the local
/// stack, so these tests are parsing the real shape rather than an
/// invented one. The one thing they must NOT contain is a secret hash:
/// there is no such key in the contract, and `device_secrets` has no grants
/// at all, so the function can only report `has_secret` + a mint time.
Map<String, dynamic> payload({
  bool enforcementEnabled = true,
  bool emailConfirmed = true,
  bool hasProfile = true,
  List<Map<String, dynamic>>? devices,
  List<Map<String, dynamic>>? events,
  List<Map<String, dynamic>>? lockouts,
  List<String>? cannotAnswer,
}) {
  return {
    'account': {
      'user_id': 'a1000000-0000-0000-0000-00000000000b',
      'email': 'sec-customer@test.local',
      'has_profile': hasProfile,
      'full_name': hasProfile ? 'Sec Customer' : null,
      'role': 'customer',
      'seller_status': 'none',
      'email_confirmed': emailConfirmed,
      'email_confirmed_at': emailConfirmed ? '2026-08-01T09:00:00' : null,
      'confirmation_sent_at': null,
      'recovery_sent_at': '2026-09-15T10:50:00',
      'last_sign_in_at': '2026-09-15T10:00:00',
      'created_at': '2026-07-01T08:00:00',
    },
    'enforcement': {
      'enabled': enforcementEnabled,
      'updated_at': '2026-09-10T12:00:00',
      'updated_by': 'a1000000-0000-0000-0000-00000000000a',
    },
    'devices': devices ?? const [],
    'otp_challenges': events ?? const [],
    'lockouts': lockouts ?? const [],
    'cannot_answer': cannotAnswer ??
        const [
          'Failed OTP attempts are not recorded.',
          'Codes are known from the send request, not delivery.',
          'The device secret itself is never exposed.',
        ],
    'generated_at': '2026-09-15T11:00:00',
  };
}

Map<String, dynamic> device({
  required String id,
  required bool hasSecret,
  String? label,
  String lastSeen = '2026-09-15T09:00:00',
}) => {
  'device_id': id,
  'device_label': label,
  'first_seen_at': '2026-08-15T09:00:00',
  'last_seen_at': lastSeen,
  'trusted_at': '2026-08-15T09:00:00',
  'has_secret': hasSecret,
  'secret_minted_at': hasSecret ? '2026-08-15T09:00:00' : null,
};

Map<String, dynamic> event({
  required String kind,
  required String action,
  String at = '2026-09-15T10:50:00',
  String? ip,
}) => {
  'at': at,
  'action': action,
  'kind': kind,
  'ip_address': ip,
};

Map<String, dynamic> lockout({
  String status = 'locked',
  String lockedUntil = '2026-09-15T12:20:00',
  int attempts = 5,
}) => {
  'failed_at': '2026-09-15T11:50:00',
  'ip_address': '203.0.113.9',
  'user_agent': 'CUFMAI/1.0',
  'status': status,
  'attempt_count': attempts,
  'locked_until': lockedUntil,
};

final now = DateTime.parse('2026-09-15T12:00:00');

List<String> codesOf(AccountSecurityOverview o) =>
    o.findingsAt(now).map((f) => f.code).toList();

void main() {
  group('AccountSecurityOverview parsing', () {
    test('parses the account block', () {
      final overview = AccountSecurityOverview.fromJson(payload());

      expect(overview.account.email, 'sec-customer@test.local');
      expect(overview.account.role, 'customer');
      expect(overview.account.emailConfirmed, isTrue);
      expect(overview.account.hasProfile, isTrue);
      expect(overview.account.displayName, 'Sec Customer');
      expect(overview.account.lastSignInAt, DateTime.parse('2026-09-15T10:00:00'));
    });

    test('falls back to the email (then the id) when there is no profile name',
        () {
      final overview = AccountSecurityOverview.fromJson(
        payload(hasProfile: false),
      );
      expect(overview.account.fullName, isNull);
      expect(overview.account.displayName, 'sec-customer@test.local');
    });

    test('parses a device without a credential — null mint time, not a crash',
        () {
      final overview = AccountSecurityOverview.fromJson(
        payload(devices: [device(id: 'new-phone', hasSecret: false)]),
      );

      final d = overview.devices.single;
      expect(d.deviceId, 'new-phone');
      expect(d.hasSecret, isFalse);
      expect(d.secretMintedAt, isNull);
      expect(overview.devicesWithoutCredential, hasLength(1));
    });

    test('a device with no label falls back to its id for display', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(devices: [device(id: 'pixel-8', hasSecret: true)]),
      );
      expect(overview.devices.single.displayLabel, 'pixel-8');
    });

    test('maps GoTrue actions to readable timeline labels', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(
          events: [
            event(kind: 'otp_emailed', action: 'user_recovery_requested'),
            event(kind: 'account_created', action: 'user_signedup'),
          ],
        ),
      );

      expect(overview.events.first.label, 'Sign-in code emailed');
      expect(overview.events.last.label, 'Account created');
      expect(overview.codeEmails, hasLength(1));
    });

    test('an unpopulated ip_address is null, not an empty string', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(events: [event(kind: 'otp_emailed', action: 'x', ip: null)]),
      );
      expect(overview.events.single.ipAddress, isNull);
    });

    test('survives an empty or missing document without throwing', () {
      final overview = AccountSecurityOverview.fromJson(const {});

      expect(overview.devices, isEmpty);
      expect(overview.events, isEmpty);
      expect(overview.cannotAnswer, isEmpty);
      expect(overview.enforcement.enabled, isFalse);
      expect(overview.account.userId, '');
    });

    test('tolerates wrong types in the payload', () {
      final overview = AccountSecurityOverview.fromJson({
        'account': 'not-an-object',
        'devices': 'not-a-list',
        'lockouts': [42, 'nope'],
        'generated_at': 12345,
      });

      expect(overview.account.userId, '');
      expect(overview.devices, isEmpty);
      expect(overview.lockouts, isEmpty);
      expect(overview.generatedAt, isNull);
    });
  });

  group('the diagnosis (the support ticket)', () {
    test(
        'flags the locked-out new phone: a recorded device that holds no '
        'credential', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(
          devices: [
            device(id: 'new-phone-0002', hasSecret: false, label: 'Pixel 8'),
            device(id: 'old-phone-0001', hasSecret: true, label: 'Samsung A15'),
          ],
        ),
      );

      final finding = overview.headlineFindingAt(now)!;
      expect(finding.code, 'device_without_credential');
      expect(finding.severity, SecuritySeverity.warning);
      expect(finding.headline, 'A recorded device holds no credential');
      // The admin needs to know the gate is refusing it despite the app
      // listing it as trusted, and what to tell the customer.
      expect(finding.detail, contains('Pixel 8'));
      expect(finding.detail, isNot(contains('Samsung A15')));
      expect(finding.action, contains('emailed code'));
    });

    test('pluralises when more than one device lacks a credential', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(
          devices: [
            device(id: 'a-phone', hasSecret: false),
            device(id: 'b-phone', hasSecret: false),
          ],
        ),
      );
      expect(
        overview.headlineFindingAt(now)!.headline,
        '2 recorded devices hold no credential',
      );
    });

    test(
        'enforcement OFF suppresses the device findings — a credential-less '
        'device is not why the customer cannot get in', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(
          enforcementEnabled: false,
          devices: [device(id: 'new-phone-0002', hasSecret: false)],
        ),
      );

      final codes = codesOf(overview);
      expect(codes, contains('enforcement_off'));
      expect(codes, isNot(contains('device_without_credential')));
      expect(codes, isNot(contains('all_devices_credentialed')));
      expect(overview.headlineFindingAt(now)!.code, 'enforcement_off');
    });

    test('a live password lockout is reported as blocking', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(lockouts: [lockout()]),
      );

      final finding = overview.headlineFindingAt(now)!;
      expect(finding.code, 'password_lockout');
      expect(finding.severity, SecuritySeverity.blocking);
      expect(finding.detail, contains('5 failed attempts'));
    });

    test('an expired lockout is not reported at all', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(
          lockouts: [lockout(lockedUntil: '2026-09-15T11:00:00')],
        ),
      );

      expect(codesOf(overview), isNot(contains('password_lockout')));
      expect(overview.activeLockoutsAt(now), isEmpty);
    });

    test('an unconfirmed address is blocking (the step-up cannot complete)',
        () {
      final overview = AccountSecurityOverview.fromJson(
        payload(emailConfirmed: false, devices: [device(id: 'p', hasSecret: true)]),
      );

      final finding = overview.headlineFindingAt(now)!;
      expect(finding.code, 'email_unconfirmed');
      expect(finding.severity, SecuritySeverity.blocking);
    });

    test(
        'a lockout outranks an unconfirmed address — it blocks sign-in '
        'before either', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(emailConfirmed: false, lockouts: [lockout()]),
      );
      expect(overview.headlineFindingAt(now)!.code, 'password_lockout');
    });

    test(
        'an account with no devices says the step-up has never succeeded, and '
        'does NOT claim a phone was rejected', () {
      final overview = AccountSecurityOverview.fromJson(payload());

      final finding = overview.headlineFindingAt(now)!;
      expect(finding.code, 'no_trusted_devices');
      expect(finding.detail, contains('not that a phone was rejected'));
    });

    test(
        'when every device holds a credential it says the phone is simply not '
        'on record', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(devices: [device(id: 'p', hasSecret: true)]),
      );

      final finding = overview.headlineFindingAt(now)!;
      expect(finding.code, 'all_devices_credentialed');
      expect(finding.severity, SecuritySeverity.info);
      expect(finding.detail, contains('never'));
    });

    test('a missing profile row is flagged', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(hasProfile: false, devices: [device(id: 'p', hasSecret: true)]),
      );

      expect(codesOf(overview), contains('no_profile_row'));
    });

    test(
        'a healthy account has no PROBLEMS but still reports what it knows — '
        'the context finding must not read as a fault', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(devices: [device(id: 'p', hasSecret: true)]),
      );

      expect(overview.isHealthyAt(now), isTrue);
      expect(overview.problemsAt(now), isEmpty);
      // Still one observation — that every device is credentialed, which is
      // the answer to "is the phone in this ticket on record?".
      final context = overview.findingsAt(now).single;
      expect(context.code, 'all_devices_credentialed');
      expect(context.severity, SecuritySeverity.info);
    });

    test('an account with no devices at all is NOT healthy', () {
      final overview = AccountSecurityOverview.fromJson(payload());
      expect(overview.isHealthyAt(now), isFalse);
      expect(overview.problemsAt(now), hasLength(1));
    });

    test('never claims a device was refused — that is not recorded anywhere',
        () {
      final overview = AccountSecurityOverview.fromJson(
        payload(devices: [device(id: 'p', hasSecret: true)]),
      );

      for (final finding in overview.findingsAt(now)) {
        final text = '${finding.headline} ${finding.detail}';
        expect(text.toLowerCase(), isNot(contains('was rejected')));
        expect(text.toLowerCase(), isNot(contains('was denied')));
      }
    });

    test('findings are ordered by severity', () {
      final overview = AccountSecurityOverview.fromJson(
        payload(
          hasProfile: false,
          devices: [device(id: 'p', hasSecret: true)],
          lockouts: [lockout()],
        ),
      );

      final severities = overview
          .findingsAt(now)
          .map((f) => f.severity.index)
          .toList();
      final sorted = [...severities]..sort();
      expect(severities, sorted);
    });
  });
}
