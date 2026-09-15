// ════════════════════════════════════════════════════════════════════
// Admin account-security diagnostics — the CLIENT half of
// public.admin_account_security_overview (migration 20260915160000).
//
// This model exists to answer one support ticket: "I got a new phone and
// I can't get in." Everything the database can say about that is parsed
// here, and the part that actually answers it is [findings] — a PURE
// derivation from the payload, deliberately not in the widget, so the
// reasoning is testable without a Supabase connection.
//
// Two honesty rules are baked into the text below, both measured against
// a real GoTrue rather than assumed:
//
//   1. A WRONG CODE LEAVES NO TRACE server-side, so an empty timeline is
//      not evidence that nobody tried. Nothing here may imply that it is.
//   2. A device that has NEVER completed the step-up is not recorded at
//      all (the `trusted_devices` row and its credential are written in
//      the same call), so "no such device in the list" cannot be shown
//      as "that phone was rejected".
// ════════════════════════════════════════════════════════════════════

/// How loudly a [SecurityFinding] should be shown.
enum SecuritySeverity { blocking, warning, info }

/// One derived conclusion about an account, with what the admin can do.
class SecurityFinding {
  /// Stable id (also used by the tests to assert which rule fired).
  final String code;

  final SecuritySeverity severity;

  /// One line, shown as the headline.
  final String headline;

  /// The reasoning, in the admin's language.
  final String detail;

  /// What to tell the customer / do next. Null when nothing is actionable.
  final String? action;

  const SecurityFinding({
    required this.code,
    required this.severity,
    required this.headline,
    required this.detail,
    this.action,
  });
}

/// One device that has cleared the step-up for this account.
class TrustedDevice {
  final String deviceId;
  final String? deviceLabel;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;
  final DateTime? trustedAt;

  /// Whether a credential (the secret that satisfies the device gate)
  /// exists for this device server-side.
  ///
  /// `false` is the state a support ticket is usually about: the device is
  /// listed — so the app shows it as trusted — but the gate will refuse its
  /// requests. It can only be produced by a client that predates the
  /// credential (row written before migration 20260915150000), because the
  /// current `trust_device()` writes the row and the secret together. It is
  /// NOT what a phone that never finished a challenge looks like — that
  /// phone has no row at all.
  final bool hasSecret;

  /// When the credential was minted. Null when there is none.
  final DateTime? secretMintedAt;

  const TrustedDevice({
    required this.deviceId,
    required this.deviceLabel,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.trustedAt,
    required this.hasSecret,
    required this.secretMintedAt,
  });

  factory TrustedDevice.fromJson(Map<String, dynamic> json) => TrustedDevice(
    deviceId: json['device_id']?.toString() ?? '',
    deviceLabel: _nullableString(json['device_label']),
    firstSeenAt: _parseTime(json['first_seen_at']),
    lastSeenAt: _parseTime(json['last_seen_at']),
    trustedAt: _parseTime(json['trusted_at']),
    hasSecret: json['has_secret'] == true,
    secretMintedAt: _parseTime(json['secret_minted_at']),
  );

  /// The label the admin actually recognises, falling back to the raw id.
  String get displayLabel {
    final label = deviceLabel;
    if (label == null || label.isEmpty) return deviceId;
    return label;
  }
}

/// One row of GoTrue's own event stream for the account.
class SecurityEvent {
  final DateTime? at;

  /// GoTrue's raw action name, e.g. `user_recovery_requested`.
  final String action;

  /// The mapped kind: `otp_emailed`, `account_created`, `signed_in`, …
  final String kind;

  final String? ipAddress;

  const SecurityEvent({
    required this.at,
    required this.action,
    required this.kind,
    this.ipAddress,
  });

  factory SecurityEvent.fromJson(Map<String, dynamic> json) => SecurityEvent(
    at: _parseTime(json['at']),
    action: json['action']?.toString() ?? 'unknown',
    kind: json['kind']?.toString() ?? 'other',
    ipAddress: _nullableString(json['ip_address']),
  );

  /// Short human label for the timeline.
  String get label {
    switch (kind) {
      case 'otp_emailed':
        return 'Sign-in code emailed';
      case 'confirmation_emailed':
        return 'Confirmation code emailed';
      case 'account_created':
        return 'Account created';
      case 'signed_in':
        return 'Signed in';
      case 'session_refreshed':
        return 'Session refreshed';
      case 'account_updated':
        return 'Account updated';
      default:
        return action;
    }
  }

  /// True for the events that represent an emailed code — the ones that
  /// mean "the account was challenged", as far as the server knows.
  bool get isCodeSent => kind == 'otp_emailed' || kind == 'confirmation_emailed';
}

/// A password lockout row from `public.failed_logins`.
class LoginLockout {
  final DateTime? failedAt;
  final String? ipAddress;
  final String? userAgent;
  final String? status;
  final int? attemptCount;
  final DateTime? lockedUntil;

  const LoginLockout({
    required this.failedAt,
    required this.ipAddress,
    required this.userAgent,
    required this.status,
    required this.attemptCount,
    required this.lockedUntil,
  });

  factory LoginLockout.fromJson(Map<String, dynamic> json) => LoginLockout(
    failedAt: _parseTime(json['failed_at']),
    ipAddress: _nullableString(json['ip_address']),
    userAgent: _nullableString(json['user_agent']),
    status: _nullableString(json['status']),
    attemptCount: _parseInt(json['attempt_count']),
    lockedUntil: _parseTime(json['locked_until']),
  );

  /// Whether the lockout is still in force at [now].
  ///
  /// Takes `now` rather than reading the clock so the diagnosis below is
  /// deterministic in tests.
  bool isActiveAt(DateTime now) {
    final until = lockedUntil;
    if (until == null) return false;
    return until.isAfter(now);
  }

  bool get isLocked => status == 'locked' || status == 'suspended';
}

/// The account the admin is looking at.
class SecurityAccount {
  final String userId;
  final String? email;
  final bool hasProfile;
  final String? fullName;
  final String role;
  final String? sellerStatus;
  final bool emailConfirmed;
  final DateTime? emailConfirmedAt;
  final DateTime? recoverySentAt;
  final DateTime? lastSignInAt;
  final DateTime? createdAt;

  const SecurityAccount({
    required this.userId,
    required this.email,
    required this.hasProfile,
    required this.fullName,
    required this.role,
    required this.sellerStatus,
    required this.emailConfirmed,
    required this.emailConfirmedAt,
    required this.recoverySentAt,
    required this.lastSignInAt,
    required this.createdAt,
  });

  factory SecurityAccount.fromJson(Map<String, dynamic> json) => SecurityAccount(
    userId: json['user_id']?.toString() ?? '',
    email: _nullableString(json['email']),
    hasProfile: json['has_profile'] == true,
    fullName: _nullableString(json['full_name']),
    role: json['role']?.toString() ?? 'none',
    sellerStatus: _nullableString(json['seller_status']),
    emailConfirmed: json['email_confirmed'] == true,
    emailConfirmedAt: _parseTime(json['email_confirmed_at']),
    recoverySentAt: _parseTime(json['recovery_sent_at']),
    lastSignInAt: _parseTime(json['last_sign_in_at']),
    createdAt: _parseTime(json['created_at']),
  );

  /// What to show as the account's name.
  String get displayName {
    final name = fullName;
    if (name != null && name.isNotEmpty) return name;
    final mail = email;
    if (mail != null && mail.isNotEmpty) return mail;
    return userId;
  }
}

/// Whether the device gate is switched on right now.
class DeviceEnforcement {
  final bool enabled;
  final DateTime? updatedAt;
  final String? updatedBy;

  const DeviceEnforcement({
    required this.enabled,
    this.updatedAt,
    this.updatedBy,
  });

  factory DeviceEnforcement.fromJson(Map<String, dynamic> json) =>
      DeviceEnforcement(
        enabled: json['enabled'] == true,
        updatedAt: _parseTime(json['updated_at']),
        updatedBy: _nullableString(json['updated_by']),
      );
}

/// The whole diagnostics document for one account.
class AccountSecurityOverview {
  final SecurityAccount account;
  final DeviceEnforcement enforcement;
  final List<TrustedDevice> devices;
  final List<SecurityEvent> events;
  final List<LoginLockout> lockouts;

  /// The caveats the server states about itself, shown verbatim so the
  /// person reading the timeline sees them next to it.
  final List<String> cannotAnswer;

  final DateTime? generatedAt;

  const AccountSecurityOverview({
    required this.account,
    required this.enforcement,
    required this.devices,
    required this.events,
    required this.lockouts,
    required this.cannotAnswer,
    required this.generatedAt,
  });

  factory AccountSecurityOverview.fromJson(Map<String, dynamic> json) {
    final account = json['account'];
    return AccountSecurityOverview(
      account: SecurityAccount.fromJson(
        account is Map ? Map<String, dynamic>.from(account) : const {},
      ),
      enforcement: DeviceEnforcement.fromJson(_map(json['enforcement'])),
      devices: _list(json['devices'], TrustedDevice.fromJson),
      events: _list(json['otp_challenges'], SecurityEvent.fromJson),
      lockouts: _list(json['lockouts'], LoginLockout.fromJson),
      cannotAnswer: (json['cannot_answer'] is List)
          ? (json['cannot_answer'] as List)
                .map((e) => e?.toString() ?? '')
                .where((e) => e.isNotEmpty)
                .toList()
          : const [],
      generatedAt: _parseTime(json['generated_at']),
    );
  }

  /// Devices whose requests the gate will refuse — see [TrustedDevice.hasSecret].
  List<TrustedDevice> get devicesWithoutCredential =>
      devices.where((d) => !d.hasSecret).toList();

  /// Events that represent a code having been emailed to this account.
  List<SecurityEvent> get codeEmails => events.where((e) => e.isCodeSent).toList();

  /// Lockouts still in force.
  List<LoginLockout> activeLockoutsAt(DateTime now) =>
      lockouts.where((l) => l.isLocked && l.isActiveAt(now)).toList();

  // ── the diagnosis ────────────────────────────────────────────────
  //
  // Ordered most-urgent first. Two rules shape the output:
  //
  //   • A finding that makes the device gate IRRELEVANT suppresses the
  //     gate findings. If enforcement is off, "this device has no
  //     credential" is true but is not why the customer cannot get in,
  //     and leading with it sends support down the wrong path.
  //   • Findings we cannot support are never emitted. There is no
  //     "this phone was denied" finding, because a denied phone is not
  //     recorded anywhere.
  List<SecurityFinding> findingsAt(DateTime now) {
    final found = <SecurityFinding>[];

    // 1. A live lockout is the most likely real cause of "can't get in",
    //    and it has nothing to do with the device gate.
    for (final lock in activeLockoutsAt(now)) {
      found.add(
        SecurityFinding(
          code: 'password_lockout',
          severity: SecuritySeverity.blocking,
          headline: 'Locked out after failed password attempts',
          detail:
              'The account is locked until ${_stamp(lock.lockedUntil)}'
              '${lock.attemptCount != null ? ' after ${lock.attemptCount} failed attempts' : ''}. '
              'This blocks sign-in before the device step-up is ever reached, so it '
              'is a likelier cause than anything on this page.',
          action:
              'Have them wait for the lock to expire or reset the password, then '
              'retry. A password reset also ends the lockout.',
        ),
      );
    }

    // 2. An unconfirmed address means no code can be verified, so the
    //    step-up has no way to complete on a new device.
    if (!account.emailConfirmed) {
      found.add(
        const SecurityFinding(
          code: 'email_unconfirmed',
          severity: SecuritySeverity.blocking,
          headline: 'Email address was never confirmed',
          detail:
              'No sign-in code can be verified for this account, so a new device '
              'can never clear the step-up. On the sign-in screen this surfaces as '
              "an `email_not_confirmed` error rather than a code prompt.",
          action:
              'Send them a confirmation code (or confirm the address) and have '
              'them sign in again.',
        ),
      );
    }

    // 3. With the gate switched OFF, no device is being denied by it.
    if (!enforcement.enabled) {
      found.add(
        SecurityFinding(
          code: 'enforcement_off',
          severity: SecuritySeverity.info,
          headline: 'The device gate is switched off',
          detail:
              'Server-side device enforcement is currently disabled'
              '${enforcement.updatedAt != null ? ' (last changed ${_stamp(enforcement.updatedAt)})' : ''}, '
              'so no device is being refused its data by it. The credential state '
              'below is real, but it is not what is blocking this account today.',
          action:
              'Look at the lockout state and the timeline instead — or switch '
              'enforcement on if you are testing it.',
        ),
      );
      return found;
    }

    // 4. A listed device that holds no credential: the app shows it as
    //    trusted while the server refuses its requests.
    final credentialless = devicesWithoutCredential;
    if (credentialless.isNotEmpty) {
      final names = credentialless.map((d) => d.displayLabel).join(', ');
      found.add(
        SecurityFinding(
          code: 'device_without_credential',
          severity: SecuritySeverity.warning,
          headline: credentialless.length == 1
              ? 'A recorded device holds no credential'
              : '${credentialless.length} recorded devices hold no credential',
          detail:
              'The gate will deny these devices every private table, while the app '
              'still lists them as trusted: $names. A row like this was written by '
              'an app version from before the credential existed — the current '
              'sign-in path writes the device row and its credential together.',
          action:
              'Have them sign in again on that phone and enter the emailed code. '
              'That re-mints the credential on the same device row.',
        ),
      );
    }

    // 5. No devices at all: nothing has ever cleared the step-up here.
    if (devices.isEmpty) {
      found.add(
        const SecurityFinding(
          code: 'no_trusted_devices',
          severity: SecuritySeverity.warning,
          headline: 'No device has cleared the step-up for this account',
          detail:
              'There is no device on record. A phone that never finished a code '
              'challenge leaves no row at all — the device row and its credential '
              'are written in the same call — so this only tells you that the '
              'step-up has never succeeded here, not that a phone was rejected.',
          action:
              'Have them sign in and complete the emailed-code step-up. It records '
              'the device and mints its credential in one step.',
        ),
      );
    } else if (credentialless.isEmpty) {
      // 6. Everything on record is healthy, so the phone in the ticket is
      //    simply not on record.
      found.add(
        SecurityFinding(
          code: 'all_devices_credentialed',
          severity: SecuritySeverity.info,
          headline: 'Every recorded device holds a working credential',
          detail:
              'All ${devices.length} recorded device(s) still hold the credential the '
              'gate checks, so the phone in this ticket is one the step-up has never '
              'completed. Devices that were refused are not recorded, and failed '
              'attempts are not recorded either.',
          action:
              'Have them sign in on that phone and enter the emailed code — the '
              'step-up is what is missing.',
        ),
      );
    }

    // 7. A missing profile row is an anomaly worth flagging regardless.
    if (!account.hasProfile) {
      found.add(
        const SecurityFinding(
          code: 'no_profile_row',
          severity: SecuritySeverity.warning,
          headline: 'The account has no profile row',
          detail:
              'The auth account exists but nothing is in `profiles`, so parts of the '
              'app will render as a nameless, role-less user. This is worth fixing '
              'before blaming the device gate.',
          action: 'Backfill the profile row for this user id.',
        ),
      );
    }

    // Stable sort by severity, so the list reads blocking → warning → info
    // regardless of the order the rules happen to be written in. [headline]
    // is therefore always the most urgent thing on the page.
    found.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return found;
  }

  /// The single most urgent finding, or null when nothing is flagged.
  SecurityFinding? headlineFindingAt(DateTime now) {
    final found = findingsAt(now);
    return found.isEmpty ? null : found.first;
  }

  /// The findings that mean something is actually WRONG — everything except
  /// plain context.
  ///
  /// The distinction matters because some rules are informative by design:
  /// "every recorded device holds a credential" is the correct answer to a
  /// ticket and still an observation, not a fault. Treating it as a fault
  /// would leave the green "nothing would block this account" state
  /// unreachable for any account that has ever signed in.
  List<SecurityFinding> problemsAt(DateTime now) => findingsAt(
    now,
  ).where((f) => f.severity != SecuritySeverity.info).toList();

  /// True when nothing on record would block or is likely blocking this
  /// account. Context findings do not make an account unhealthy.
  bool isHealthyAt(DateTime now) => problemsAt(now).isEmpty;
}

// ── parsing helpers ────────────────────────────────────────────────

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

String? _nullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime? _parseTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

List<T> _list<T>(dynamic value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => parse(Map<String, dynamic>.from(e)))
      .toList();
}

String _stamp(DateTime? d) {
  if (d == null) return 'an unrecorded time';
  final local = d.toLocal();
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:$minute';
}
