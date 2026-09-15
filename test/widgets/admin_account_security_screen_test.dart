import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:app/models/account_security_overview.dart';
import 'package:app/screens/admin/admin_account_security_screen.dart';
import 'package:app/screens/admin/admin_helpers.dart';
import 'package:app/services/account_security_service.dart';

class MockAccountSecurityService extends Mock
    implements AccountSecurityService {}

/// A payload shaped like the real RPC response, reused across the cases.
Map<String, dynamic> payload({
  bool enforcementEnabled = true,
  bool emailConfirmed = true,
  bool hasProfile = true,
  required List<Map<String, dynamic>> devices,
  List<Map<String, dynamic>>? events,
  List<Map<String, dynamic>>? lockouts,
}) => {
  'account': {
    'user_id': 'u-1',
    'email': 'sec-customer@test.local',
    'has_profile': hasProfile,
    'full_name': 'Sec Customer',
    'role': 'customer',
    'seller_status': 'none',
    'email_confirmed': emailConfirmed,
    'email_confirmed_at': emailConfirmed ? '2026-08-01T09:00:00' : null,
    'confirmation_sent_at': null,
    'recovery_sent_at': '2026-09-15T10:50:00',
    'last_sign_in_at': '2026-09-15T10:00:00',
    'created_at': '2026-07-01T08:00:00',
  },
  'enforcement': {'enabled': enforcementEnabled, 'updated_at': null, 'updated_by': null},
  'devices': devices,
  'otp_challenges': events ?? const [],
  'lockouts': lockouts ?? const [],
  'cannot_answer': const [
    'Failed OTP attempts are not recorded: an empty timeline is NOT evidence '
        'that nobody tried.',
  ],
  'generated_at': '2026-09-15T11:00:00',
};

Map<String, dynamic> device({
  required String id,
  required bool hasSecret,
  String? label,
}) => {
  'device_id': id,
  'device_label': label,
  'first_seen_at': '2026-08-15T09:00:00',
  'last_seen_at': '2026-09-15T09:00:00',
  'trusted_at': '2026-08-15T09:00:00',
  'has_secret': hasSecret,
  'secret_minted_at': hasSecret ? '2026-08-15T09:00:00' : null,
};

void main() {
  late MockAccountSecurityService mockService;

  setUp(() {
    mockService = MockAccountSecurityService();
  });

  Future<void> pump(
    WidgetTester tester,
    Map<String, dynamic> body, {
    String name = 'Sec Customer',
  }) async {
    when(() => mockService.fetchOverview(any())).thenAnswer(
      (_) async => AccountSecurityOverview.fromJson(body),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccountSecurityScreen(
          userId: 'u-1',
          userName: name,
          service: mockService,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('asks the service for the account it was opened with', (
    tester,
  ) async {
    await pump(tester, payload(devices: [device(id: 'p', hasSecret: true)]));

    verify(() => mockService.fetchOverview('u-1')).called(1);
    expect(find.textContaining('Account Security: Sec Customer'), findsOneWidget);
  });

  testWidgets('leads with the diagnosis for the locked-out new phone', (
    tester,
  ) async {
    await pump(
      tester,
      payload(
        devices: [
          device(id: 'new-phone-0002', hasSecret: false, label: 'Pixel 8'),
          device(id: 'old-phone-0001', hasSecret: true, label: 'Samsung A15'),
        ],
      ),
    );

    expect(find.text('A recorded device holds no credential'), findsOneWidget);
    // The device the gate will refuse, and its chip.
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('NO CREDENTIAL'), findsOneWidget);
    expect(find.text('CREDENTIAL OK'), findsOneWidget);
    // The reasoning and the fix.
    expect(find.textContaining('Pixel 8'), findsWidgets);
    expect(find.textContaining('emailed code'), findsWidgets);
  });

  testWidgets(
      'with enforcement OFF it does NOT blame the credential-less device — '
      'that is the wrong path for support', (tester) async {
    await pump(
      tester,
      payload(
        enforcementEnabled: false,
        devices: [device(id: 'new-phone-0002', hasSecret: false)],
      ),
    );

    expect(find.text('The device gate is switched off'), findsOneWidget);
    expect(find.text('Enforcement OFF'), findsOneWidget);
    expect(find.text('A recorded device holds no credential'), findsNothing);
  });

  testWidgets('a healthy account shows the all-clear plus its context', (
    tester,
  ) async {
    await pump(tester, payload(devices: [device(id: 'p', hasSecret: true)]));

    expect(
      find.text('Nothing on record would block this account'),
      findsOneWidget,
    );
    expect(
      find.text('Every recorded device holds a working credential'),
      findsOneWidget,
    );
  });

  testWidgets('a live lockout is shown as blocking a sign-in', (tester) async {
    await pump(
      tester,
      payload(
        devices: [device(id: 'p', hasSecret: true)],
        lockouts: [
          {
            'failed_at': '2026-09-15T11:50:00',
            // Far future, so the fixture cannot expire and flake.
            'locked_until': '2099-01-01T00:00:00',
            'ip_address': '203.0.113.9',
            'user_agent': 'CUFMAI/1.0',
            'status': 'locked',
            'attempt_count': 5,
          },
        ],
      ),
    );

    expect(find.text('Locked out after failed password attempts'), findsOneWidget);
    expect(find.text('BLOCKS SIGN-IN'), findsOneWidget);
    expect(find.text('5 attempts'), findsOneWidget);
  });

  testWidgets('an unconfirmed address is flagged', (tester) async {
    await pump(
      tester,
      payload(
        emailConfirmed: false,
        devices: [device(id: 'p', hasSecret: true)],
      ),
    );

    expect(find.text('Email address was never confirmed'), findsOneWidget);
    expect(find.text('NOT CONFIRMED'), findsOneWidget);
  });

  testWidgets('shows the server\'s own caveats, so the timeline is not '
      'over-read', (tester) async {
    await pump(tester, payload(devices: [device(id: 'p', hasSecret: true)]));

    expect(find.text('What this report cannot tell you'), findsOneWidget);
    expect(find.textContaining('NOT evidence'), findsOneWidget);
  });

  testWidgets('renders the code timeline', (tester) async {
    await pump(
      tester,
      payload(
        devices: [device(id: 'p', hasSecret: true)],
        events: [
          {
            'at': '2026-09-15T10:50:00',
            'action': 'user_recovery_requested',
            'kind': 'otp_emailed',
            'ip_address': null,
          },
          {
            'at': '2026-07-01T08:00:00',
            'action': 'user_signedup',
            'kind': 'account_created',
            'ip_address': null,
          },
        ],
      ),
    );

    // Scoped to the timeline card: the Account card also has a row labelled
    // "Account created", so an unscoped finder would match both.
    final timeline = find.ancestor(
      of: find.text('Sign-in & code timeline'),
      matching: find.byType(AdminCard),
    );
    expect(
      find.descendant(of: timeline, matching: find.text('Sign-in code emailed')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: timeline, matching: find.text('Account created')),
      findsOneWidget,
    );
    expect(find.textContaining('1 code(s) emailed'), findsOneWidget);
  });

  testWidgets('an empty device list explains that nothing is on record', (
    tester,
  ) async {
    await pump(tester, payload(devices: const []));

    expect(find.text('No device has cleared the step-up for this account'),
        findsOneWidget);
    expect(
      find.textContaining('never finished the emailed-code challenge'),
      findsOneWidget,
    );
  });

  testWidgets('a refused read shows the reason and retries on demand', (
    tester,
  ) async {
    when(() => mockService.fetchOverview(any())).thenThrow(
      const AccountSecurityException(
        'Only an admin account can read security diagnostics.',
        code: '42501',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccountSecurityScreen(
          userId: 'u-1',
          userName: 'Sec Customer',
          service: mockService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Only an admin account can read security diagnostics.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    verify(() => mockService.fetchOverview('u-1')).called(2);
  });

  testWidgets('an unexpected failure does not leak a raw error to the admin', (
    tester,
  ) async {
    when(() => mockService.fetchOverview(any()))
        .thenThrow(Exception('socket exploded'));

    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccountSecurityScreen(
          userId: 'u-1',
          userName: 'Sec Customer',
          service: mockService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Could not load the security report. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('socket exploded'), findsNothing);
  });
}
