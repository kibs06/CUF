// ignore_for_file: avoid_print
/// Apply the LIVE project's auth e-mail configuration (ANQUI item 16, §R8).
///
/// Run: `dart run tool/apply_live_auth_mail.dart`
///
/// ## Why this file exists
///
/// The app verifies BOTH OTP flows with `verifyOtp`, which needs a 6-digit
/// `{{ .Token }}` in the mail. GoTrue's stock templates render only a
/// `{{ .ConfirmationURL }}` LINK, and the hosted project ignores
/// `supabase/config.toml` **and** the Edge Function secrets — its SMTP
/// settings and its mail templates live in the project's own auth config.
/// Measured Sep 17, 2026: a step-up mail really was delivered from
/// `noreply@mail.app.supabase.io`, with the stock "Your sign-in link" body
/// and NO code anywhere, so the verify screen had nothing to accept and the
/// new-device step-up could not complete for a real user.
///
/// Everything below is one `PATCH /v1/projects/{ref}/config/auth` call — the
/// same thing the dashboard's Authentication screens write. The dashboard is
/// the documented route (§R8 in `docs/fixes/GO_LIVE_PRELAUNCH_CHECKLIST.md`);
/// this tool is the repeatable one: idempotent, reviewable, and the shape to
/// re-run after the App Password is rotated.
///
/// ## Why Dart and not curl
///
/// Two of the fields carry the template FILES as their value, so the HTML has
/// to become a JSON string. Hand-escaping it is how a runbook silently ships
/// a link-only mail again — and the obvious helper, `jq -Rs`, is not present
/// on every machine this repo is built on (it is not on the one this was
/// written on), while the Dart SDK always is. `--print-curl` still emits
/// copy-paste `curl` commands for anyone who prefers them.
///
/// ## Usage
///
/// ```bash
/// dart run tool/apply_live_auth_mail.dart --check      # read + verify, write nothing
/// dart run tool/apply_live_auth_mail.dart --dry-run    # show the payload (secret masked)
/// dart run tool/apply_live_auth_mail.dart --print-curl # write payload, print curl
/// dart run tool/apply_live_auth_mail.dart              # apply it, then verify
/// ```
///
/// ## Trying it without touching the live project
///
/// `--api-base` points the whole tool at anything that speaks the same two
/// endpoints, so the apply path can be exercised locally: serve `GET` and
/// `PATCH` on `/v1/projects/{ref}/config/auth` from a throwaway mock seeded
/// with a real config read, then run the apply against it with the mock's
/// values for the three credentials. Verified that way on Oct 12, 2026 — a
/// `--check` against the broken values printed both ❌ destination rows and
/// exited 1; the apply run printed 14 ✅ and exited 0; and a mock answering
/// `403 {"message":"Missing required permission(s): auth_config_write,
/// project_admin_write"}` produced the scope advice below verbatim.
///
/// ## Credentials
///
/// Read from the environment when present, otherwise prompted for (the App
/// Password with terminal echo off where the platform supports it). Nothing
/// is ever printed back, and the payload file is written into
/// `supabase/.temp/`, which `supabase/.gitignore` already ignores.
///
/// * `SUPABASE_ACCESS_TOKEN` — Dashboard → Account → Access Tokens. Needs
///   `auth:write` (fine-grained: `auth_config_write` or `project_admin_write`).
/// * `GMAIL_SENDER` — the mailbox the Edge Functions already send from
///   (`send-approval-email` / `send-lockout-email`).
/// * `GMAIL_APP_PASSWORD` — its 16-character App Password (2FA → App
///   passwords). NOT the account password, which Gmail refuses here.
///
/// ## The reset link is part of this config
///
/// A recovery e-mail is the one auth mail whose LINK the customer has to
/// open, so its destination is written here too: `site_url` plus the
/// allow-list entries. Measured Oct 12, 2026 — the mailer was fixed and every
/// reset link STILL resolved to the project's shipped `http://localhost:3000`
/// default, i.e. `ERR_CONNECTION_REFUSED` on the customer's phone, with an
/// empty allow list meaning no explicit redirect could be honoured either.
///
/// The app's three reset call sites now send
/// `redirectTo: solvision://auth/recovery`, so the button opens CUFMAI and the
/// set-new-password screen finishes the reset in-process; the deployed
/// portal's `/account` page stays allow-listed (and stays the Site URL) so a
/// reset started on the WEBSITE — or one whose app redirect GoTrue will not
/// honour — still lands on a page that can set a password.
///
/// ## What it does NOT do
///
/// It does not turn the device gate on (`select public.set_device_enforcement(true)`
/// — a separate, deliberate step, architecture doc §3.9), and it does not send
/// test mail: that is §R8 Step 4, done from the app so the code is typed the
/// way a customer would.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// The live project (dashboard → Project Settings → General → Reference ID).
const String defaultProjectRef = 'psczvbfoybqhjeqssimw';
const String defaultApiBase = 'https://api.supabase.com';

/// Values that must agree with the app, or a code is minted that the UI cannot
/// accept: `EmailOtpPolicy.codeLength` / `expirySeconds`
/// (`lib/services/email_otp_service.dart`).
const int otpLength = 6;
const int otpExpirySeconds = 3600;

/// Mirror of `[auth.email.smtp]` + `[auth.email.template.*]` in
/// `supabase/config.toml`.
const String smtpHost = 'smtp.gmail.com';

/// Implicit TLS — what the Edge Functions already use. 587 + STARTTLS also
/// works, but the API types this field as a STRING.
const String smtpPort = '465';
const String smtpSenderName = 'CUFMAI';
const String subjectConfirmation = 'Confirm your CUFMAI email';
const String subjectMagicLink = 'Your CUFMAI sign-in code';

/// Saving custom SMTP replaces the built-in mailer's 2/hour ceiling with
/// `rate_limit_email_sent`, whose project default is 30/hour. Sign-up
/// confirmations and new-device step-up codes share that bucket and every
/// resend spends another, so 30 is too tight for a launch.
const int defaultEmailRateLimit = 100;

/// The app's sign-up confirmation button comes BACK TO THE APP, not to a web
/// page it cannot use. GoTrue only honours a redirect it has been told about
/// (`DeepLinkService.authConfirmRedirect` — three places must agree on this).
const String authConfirmRedirect = 'solvision://auth/confirm';

/// Where the app's PASSWORD-RESET button comes back to
/// (`DeepLinkService.authRecoveryRedirect`) — the same contract as the
/// confirmation link above, and the entry that must be present for a reset
/// mail to open the app at all instead of a browser.
const String authRecoveryRedirect = 'solvision://auth/recovery';

/// The deployed customer portal (`customer-portal/` in this repo).
///
/// ⚠️ Must match `AppConstants.customerPortalUrl` in the app — that constant
/// is what the reset calls send as `redirectTo`, and this is what gets
/// allow-listed. The contract test
/// `test/services/password_reset_redirect_test.dart` pins the two together.
const String customerPortalOrigin = 'https://cufmai-portal.vercel.app';

/// Where a reset e-mail must land: the portal's account page, whose
/// "Change password" form finishes the reset (the link signs the customer in
/// with a short-lived session, so the only thing left to do is set a new
/// password — and that page announces itself as the arrival point).
const String customerPortalResetRedirect = '$customerPortalOrigin/account';

/// The portal's own `npm run dev` origin (`customer-portal/vite.config.js`
/// keeps it off the admin portal's 5173). Allow-listed so a reset started
/// against a LOCAL portal can be tested end to end; without it GoTrue drops
/// the redirect and every local test lands on the deployed site instead.
const String customerPortalDevOrigin = 'http://localhost:5174';

/// The `/auth/v1/...` path this tool writes. Kept as one string so the READ
/// and the PATCH can never drift onto different endpoints.
const String configPathTemplate = '/v1/projects/{ref}/config/auth';

/// Never echoed, never listed by `--dry-run`.
const Set<String> secretKeys = <String>{'smtp_pass'};

final Directory _repoRoot = File(Platform.script.toFilePath()).parent.parent;
final Directory _templateDir = Directory('${_repoRoot.path}/supabase/templates');

/// supabase/.gitignore ignores `.temp`, which is the only reason the payload —
/// it carries the App Password — may sit here at all.
final File _payloadFile =
    File('${_repoRoot.path}/supabase/.temp/auth-mail-patch.json');

Future<void> main(List<String> argv) async {
  final _Args args = _Args.parse(argv);
  final String url = '${args.apiBase.replaceAll(RegExp(r'/+$'), '')}'
      '${configPathTemplate.replaceAll('{ref}', args.projectRef)}';

  final String sender = _credential(
    'GMAIL_SENDER',
    'Sending Gmail address (the one the Edge Functions already use): ',
  );

  // --check is a read: no App Password needed, and nothing is written.
  if (args.check) {
    final String token = _credential(
      'SUPABASE_ACCESS_TOKEN',
      'Supabase access token (Dashboard -> Account -> Access Tokens): ',
      secret: true,
    );
    // Said BEFORE the list, because the list alone is misread: five ✅ rows
    // next to a broken mailer, and a ❌ row that reappears on every run, both
    // look like a stuck write when nothing was ever written.
    print(
      '\n── READ-ONLY check (--check): nothing will be written ──',
    );
    exit(
      await _verify(url, token, sender, readOnly: true, siteUrl: args.siteUrl)
          ? 0
          : 1,
    );
  }

  final String appPassword = _credential(
    'GMAIL_APP_PASSWORD',
    'Gmail App Password (16 characters, not the account password): ',
    secret: true,
    // Gmail shows it in four groups of four; the spaces are not part of it.
  ).replaceAll(' ', '');
  if (appPassword.length != 16) {
    print(
      '⚠️  That App Password is ${appPassword.length} characters, not 16 — '
      'double-check it is an App Password and not the account password.',
    );
  }

  // Read FIRST, so `uri_allow_list` is MERGED instead of replaced: a PATCH
  // replaces the field wholesale, so a hand-built list would silently drop
  // whatever the project already relies on.
  final String token = _credential(
    'SUPABASE_ACCESS_TOKEN',
    'Supabase access token (Dashboard -> Account -> Access Tokens): ',
    secret: true,
  );
  final Map<String, dynamic> current = await _getConfig(url, token);
  final String currentList = '${current['uri_allow_list'] ?? ''}';
  final String currentSiteUrl = '${current['site_url'] ?? ''}';
  print('Current uri_allow_list: '
      '${currentList.isEmpty ? '(empty)' : currentList}');
  print('Current site_url:       '
      '${currentSiteUrl.isEmpty ? '(unset)' : currentSiteUrl}');

  final Map<String, dynamic> payload = _buildPayload(
    args,
    sender: sender,
    appPassword: appPassword,
    allowList: _mergeAllowList(currentList, args.siteUrl),
  );

  if (args.dryRun) {
    print('\n── Payload that WOULD be sent (nothing written) ──');
    print(_preview(payload));
    print('\nRe-run without --dry-run to apply it.');
    return;
  }

  if (args.printCurl) {
    await _printCurl(url, payload);
    return;
  }

  print('\n── Applying ──');
  print(_preview(payload));

  final http.Response response = await _patch(url, token, payload);
  if (response.statusCode != 200) {
    _fail(
      'The PATCH was rejected (HTTP ${response.statusCode}):\n${response.body}\n\n'
      // Name the scopes the API itself asks for. Measured Oct 12, 2026: a
      // fine-grained token that read the config fine was refused the write
      // with `{"message":"Missing required permission(s): auth_config_write,
      // project_admin_write"}`, so "lacks `auth:write`" sent its owner looking
      // for a permission that does not exist under that name. The wording here
      // must match the dashboard's own scope names.
      'A 401/403 means the token lacks the auth-config write scope — the API '
      'names what it wanted in `missing_permissions` above (normally '
      '`auth_config_write`, or the broader `project_admin_write`), and the '
      'token has to be CREATED with it; re-running cannot add it. A 400 '
      'usually names the offending field above.',
    );
  }

  print('\n✅ Applied.');
  final bool ok = await _verify(url, token, sender, siteUrl: args.siteUrl);
  print(
    '\nNext: send yourself one real code (sign up with a fresh address, or '
    'turn the device gate on and sign in from a cleared install) and check the '
    'mail: heading "Confirm it\'s you", a 6-digit number, and a From: of '
    '$sender — never `noreply@mail.app.supabase.io`. Full check list: '
    'docs/fixes/GO_LIVE_PRELAUNCH_CHECKLIST.md §R8 Step 4.'
    '\nThen click one reset link END TO END — sign-in screen → "Forgot '
    'password?" → the button in the mail must open the portal\'s account page '
    'with the "You followed a password reset link" banner, and a new password '
    'set there must sign in. That click is the only proof: /recover answering '
    '200 says nothing about where the link goes (§R8 Step 5).',
  );
  exit(ok ? 0 : 1);
}

// ── payload ──────────────────────────────────────────────────────────────────

Map<String, dynamic> _buildPayload(
  _Args args, {
  required String sender,
  required String appPassword,
  required String allowList,
}) {
  return <String, dynamic>{
    // ── Custom SMTP (Step 1) ───────────────────────────────────────────
    'smtp_host': smtpHost,
    'smtp_port': smtpPort, // the API types this as a STRING
    'smtp_user': sender,
    'smtp_pass': appPassword,
    // Gmail rewrites a `From` it does not own, so the envelope sender must be
    // the authenticated mailbox itself (or a Gmail alias registered on it).
    'smtp_admin_email': sender,
    'smtp_sender_name': smtpSenderName,

    // ── Rate limits (Step 2) ───────────────────────────────────────────
    'rate_limit_email_sent': args.rateLimit,

    // ── Confirmations + the numbers the app mirrors (Step 3) ───────────
    // "Confirm email" ON: `signUp` returns no session, and the `profiles` row
    // is written by the verify screen once verifyOTP establishes one.
    'mailer_autoconfirm': false,
    'mailer_otp_length': otpLength,
    'mailer_otp_exp': otpExpirySeconds,

    // ── The two templates that make a CODE exist (Step 3) ──────────────
    // `confirmation` is GoTrue's name for the sign-up mail — this must NOT be
    // the `signup` section name from config.toml, which GoTrue ignores.
    'mailer_subjects_confirmation': subjectConfirmation,
    'mailer_templates_confirmation_content': _readTemplate('confirmation.html'),
    'mailer_subjects_magic_link': subjectMagicLink,
    'mailer_templates_magic_link_content': _readTemplate('magic_link.html'),

    // ── Where every e-mail link lands (Step 3b) ────────────────────────
    // The Site URL is GoTrue's DEFAULT redirect — what a reset call with no
    // `redirectTo` resolves to (an older app build, or any future call site
    // that forgets it), so it must not stay on the `http://localhost:3000`
    // placeholder the project ships with. `uri_allow_list` is a separate
    // switch: GoTrue ignores an explicit redirect it has not been told about
    // and falls back to the site URL, so an entry here is what makes the
    // app's `redirectTo` work at all.
    'site_url': args.siteUrl,
    'uri_allow_list': allowList,
  };
}

/// The template body, WITHOUT the authoring HTML comment at the top.
///
/// Both files open with a `<!-- … -->` note that is not part of the e-mail.
/// Sending it is harmless but leaks the notes into a customer's message
/// source, so the body starts at the first `<div`. That is CHECKED rather than
/// trusted: a template that lost `{{ .Token }}` is exactly how this feature
/// ships broken, and nothing in the app can tell you why.
String _readTemplate(String name) {
  final File file = File('${_templateDir.path}/$name');
  if (!file.existsSync()) {
    _fail('Missing template ${file.path}. Run this from the repo checkout.');
  }

  final List<String> lines = file.readAsLinesSync();
  final int start = lines.indexWhere((String line) => line.startsWith('<div'));
  if (start == -1) {
    _fail('${file.path} has no `<div` to start the body from.');
  }

  final String body = '${lines.sublist(start).join('\n').trim()}\n';
  if (!body.contains('{{ .Token }}')) {
    _fail(
      '${file.path} no longer contains {{ .Token }} — that is the 6-digit '
      'code the verify screen accepts. Fix the template before applying it.',
    );
  }
  return body;
}

/// Append every link destination the app mails, keeping the entries already
/// configured.
///
/// A PATCH replaces this field wholesale, so anything already there has to be
/// carried over by hand — that is why the config is READ first. (The previous
/// SITE URL is deliberately not carried over, unlike everything else: the
/// payload repoints `site_url` itself, so an entry for the old value would only
/// keep a dead destination — this project's default `http://localhost:3000` —
/// allow-listed forever.)
///
/// Each entry added is one link, and each link is a different failure when it
/// is missing:
///   • the Site URL this payload writes, plus its wildcard — the fallback for
///     a reset call that carries no `redirectTo`;
///   • [customerPortalResetRedirect] — what the app's own reset calls send
///     (all three call sites), i.e. the link the customer actually clicks;
///   • [authConfirmRedirect] — the sign-up confirmation button, which comes
///     back to the APP (`DeepLinkService.authConfirmRedirect`);
///   • [authRecoveryRedirect] — the password-reset button, also back to the
///     APP (`DeepLinkService.authRecoveryRedirect`), where the set-new-
///     password screen finishes the reset;
///   • [customerPortalDevOrigin] and its wildcard — the local portal, so the
///     same flow can be tested against a dev server.
String _mergeAllowList(String current, String siteUrl) {
  final List<String> entries = current
      .split(',')
      .map((String e) => e.trim())
      .where((String e) => e.isNotEmpty)
      .toList();

  void add(String candidate) {
    if (candidate.isNotEmpty && !entries.contains(candidate)) {
      entries.add(candidate);
    }
  }

  add(siteUrl);
  add(_wildcard(siteUrl));
  add(customerPortalResetRedirect);
  add(_wildcard(customerPortalOrigin));
  add(authConfirmRedirect);
  add(authRecoveryRedirect);
  add(customerPortalDevOrigin);
  add(_wildcard(customerPortalDevOrigin));
  return entries.join(',');
}

/// `<origin>/**` — the documented wildcard form, and the only one that helps
/// here: GoTrue compiles these entries with `/` and `.` as separators, so a
/// single `*` never crosses a `/` and `**` does. One entry therefore covers
/// every client-side route of the portal (`/account`, `/auth/confirm`, …).
String _wildcard(String origin) {
  final String trimmed = origin.replaceAll(RegExp(r'/+$'), '');
  return trimmed.isEmpty ? '' : '$trimmed/**';
}

/// Whether [list] (GoTrue's comma-separated allow list) already holds an entry
/// covering [url].
///
/// Two shapes count, and both are checked because either is enough to make the
/// link work: the URL itself, and the wildcard form above. A plain substring
/// test would read the wildcard as a miss and report a missing entry that is
/// sitting right there in the list.
bool _allowListCovers(String list, String url) {
  for (final String raw in list.split(',')) {
    final String entry = raw.trim();
    if (entry.isEmpty) continue;
    if (entry == url) return true;
    if (entry.endsWith('/**') &&
        url.startsWith(entry.substring(0, entry.length - 2))) {
      return true;
    }
  }
  return false;
}

/// Trailing slashes are not meaningful for either compare below, and the
/// dashboard has been known to store the site URL with one.
String _trimSlashes(String value) => value.replaceAll(RegExp(r'/+$'), '');

Map<String, dynamic> _masked(Map<String, dynamic> payload) => <String, dynamic>{
      for (final MapEntry<String, dynamic> e in payload.entries)
        e.key: secretKeys.contains(e.key) ? '***' : e.value,
    };

/// Field summary — template bodies are shown as a size + a code check, never
/// pasted, so the terminal log of an apply stays readable.
String _preview(Map<String, dynamic> payload) {
  final List<String> lines = <String>[];
  _masked(payload).forEach((String key, dynamic value) {
    if (value is String && value.startsWith('<div')) {
      lines.add(
        '  ${key.padRight(44)} <html, ${value.length} chars, '
        '{{ .Token }} present>',
      );
    } else {
      lines.add('  ${key.padRight(44)} ${value is String ? "'$value'" : value}');
    }
  });
  return lines.join('\n');
}

// ── verification ─────────────────────────────────────────────────────────────

/// Read the config back and assert every field the app depends on.
///
/// [readOnly] says which mode called us, because the two need opposite advice
/// for the same ❌ row: an APPLY run whose fields did not stick points at a
/// rejected PATCH or a dashboard-managed field, while a `--check` run that
/// reports the same ❌ never wrote anything at all — so "re-run it" (the apply
/// advice) is nonsense there, and repeating it is exactly what makes a healthy
/// read-only check look like an error that will not go away.
Future<bool> _verify(
  String url,
  String token,
  String sender, {
  bool readOnly = false,
  required String siteUrl,
}) async {
  final Map<String, dynamic> config = await _getConfig(url, token);

  bool has(String field, String needle) =>
      '${config[field] ?? ''}'.contains(needle);
  int asInt(String field) => int.tryParse('${config[field] ?? ''}') ?? 0;

  // The two fields that decide where a mailed LINK lands, printed rather than
  // merely asserted: a ❌ row below says the destination is wrong, and these
  // are the values it is wrong about.
  final String allowList = '${config['uri_allow_list'] ?? ''}';
  final String liveSiteUrl = '${config['site_url'] ?? ''}';
  print('\nVerification (read back from the project):');
  print('  site_url:       '
      '${liveSiteUrl.isEmpty ? '(unset)' : liveSiteUrl}');
  print('  uri_allow_list: ${allowList.isEmpty ? '(empty)' : allowList}');

  final Map<String, bool> checks = <String, bool>{
    'custom SMTP is on Gmail': config['smtp_host'] == smtpHost,
    'port 465': '${config['smtp_port']}' == smtpPort,
    'smtp user is the sender': config['smtp_user'] == sender,
    'envelope sender is the sender': config['smtp_admin_email'] == sender,
    'sender name is CUFMAI': config['smtp_sender_name'] == smtpSenderName,
    'rate_limit_email_sent raised':
        asInt('rate_limit_email_sent') >= defaultEmailRateLimit,
    '"Confirm email" is ON': config['mailer_autoconfirm'] == false,
    'otp length is 6': asInt('mailer_otp_length') == otpLength,
    'otp expiry is 3600s': asInt('mailer_otp_exp') == otpExpirySeconds,
    'Confirm-signup carries a code':
        has('mailer_templates_confirmation_content', '{{ .Token }}'),
    'Magic-link carries a code':
        has('mailer_templates_magic_link_content', '{{ .Token }}'),
    'confirmation button returns to the app':
        has('uri_allow_list', authConfirmRedirect),
    'reset link returns to the app':
        has('uri_allow_list', authRecoveryRedirect),
    'site_url is the reset destination':
        _trimSlashes(liveSiteUrl) == _trimSlashes(siteUrl),
    'reset link can reach the portal account page':
        _allowListCovers(allowList, customerPortalResetRedirect),
  };

  checks.forEach((String name, bool ok) {
    print('  ${ok ? '✅' : '❌'} $name');
  });

  _printPasswordNote();

  if (checks.values.any((bool ok) => !ok)) {
    print(readOnly
        ? '\n⚠️  Read-only check: the ❌ rows above are the project\'s CURRENT '
            'values — nothing was written, so they will read exactly like this '
            'on every re-run until you run this command WITHOUT --check.'
        : '\n⚠️  Some fields did not read back as expected. Re-run, and if it '
            'persists check the dashboard\'s Authentication → SMTP Settings / '
            'Emails screens — the PATCH may have been rejected field-by-field.');
    return false;
  }
  return true;
}

/// The one check this tool can never make, said out loud on EVERY run.
///
/// A READ does return a `smtp_pass` field — as a **64-character opaque digest**,
/// measured Oct 12, 2026, where Gmail's App Password is 16 characters. So it can
/// be neither compared with the real password nor re-sent: PATCHing that digest
/// back would store the digest AS the password and break every send. It follows
/// that a wrong or rotated App Password leaves all five SMTP rows reading ✅
/// while every send still fails — a green check next to a dead mailer, the
/// single most misleading output this tool can produce. The only place the real
/// reason appears is the auth log, as Gmail's own SMTP reply. Measured Oct 12,
/// 2026 (legacy Gmail App Password `535 5.7.8`,
/// `docs/AI/FORGOT_PASSWORD_ARCHITECTURE.md`).
void _printPasswordNote() {
  print(
    '\nNote: `smtp_pass` is not readable — a READ returns a 64-character '
    'opaque digest, never the 16-character App Password — so these SMTP rows '
    'can all be ✅ while every send still fails. (Never PATCH that digest back; '
    'it would be stored as the password.) A wrong or rotated App Password shows '
    'up ONLY in the auth log (Dashboard → Logs → Auth), as'
    '\n  535 "5.7.8 Username and Password not accepted … - gsmtp"'
    '\non the request itself.',
  );
}

// ── curl mode ────────────────────────────────────────────────────────────────

Future<void> _printCurl(String url, Map<String, dynamic> payload) async {
  await _payloadFile.parent.create(recursive: true);
  await _payloadFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
  final String rel = _payloadFile.path
      .substring(_repoRoot.path.length + 1)
      .replaceAll(r'\', '/');

  print('\nPayload written to $rel');
  print(
    '⚠️  It contains the App Password. supabase/.temp is git-ignored — keep it '
    'that way, and delete the file when you are done.',
  );

  // A raw string keeps `$SUPABASE_ACCESS_TOKEN` literal: it must be expanded by
  // the SHELL that runs this, not by Dart.
  final List<String> curl = <String>[
    'curl -X PATCH "$url" \\',
    r'  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \',
    '  -H "Content-Type: application/json" \\',
    '  --data-binary @$rel',
  ];
  print('\n# 1) apply it');
  print(curl.join('\n'));
  print('\n# 2) or verify with this tool');
  print('dart run tool/apply_live_auth_mail.dart --check');
}

// ── HTTP ─────────────────────────────────────────────────────────────────────

Future<Map<String, dynamic>> _getConfig(String url, String token) async {
  final http.Response response = await _send(
    () => http.get(Uri.parse(url), headers: _headers(token)),
  );
  if (response.statusCode != 200) {
    _fail('Could not read the auth config (HTTP ${response.statusCode}): '
        '${response.body}');
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<http.Response> _patch(
  String url,
  String token,
  Map<String, dynamic> payload,
) =>
    _send(
      () => http.patch(
        Uri.parse(url),
        headers: _headers(token),
        body: jsonEncode(payload),
      ),
    );

Map<String, String> _headers(String token) => <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

Future<http.Response> _send(Future<http.Response> Function() call) async {
  try {
    return await call();
  } on SocketException catch (e) {
    _fail('Could not reach the Supabase Management API: ${e.message}');
  } on HandshakeException catch (e) {
    _fail('TLS handshake failed: ${e.message}');
  } on http.ClientException catch (e) {
    _fail('Could not reach the Supabase Management API: ${e.message}');
  }
}

// ── credentials + args ───────────────────────────────────────────────────────

/// Env var first (so it can come from a secret manager), prompt otherwise.
String _credential(String envName, String prompt, {bool secret = false}) {
  final String? fromEnv =
      Platform.environment[envName]?.trim().replaceAll('"', '');
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

  stdout.write(prompt);
  bool echoOff = false;
  if (secret) {
    try {
      // POSIX only; on Windows the prompt simply shows what is typed, which is
      // why the env var is the documented path for the App Password.
      stdin.echoMode = false;
      echoOff = true;
    } catch (_) {
      print('(your terminal shows what you type — paste, then press Enter)');
    }
  }
  final String? typed = stdin.readLineSync();
  if (echoOff) {
    stdin.echoMode = true;
    stdout.write('\n');
  }
  final String value = (typed ?? '').trim();
  if (value.isEmpty) _fail('$envName is required.');
  return value;
}

class _Args {
  final bool check;
  final bool dryRun;
  final bool printCurl;
  final String projectRef;
  final String apiBase;
  final int rateLimit;
  final String siteUrl;

  const _Args({
    required this.check,
    required this.dryRun,
    required this.printCurl,
    required this.projectRef,
    required this.apiBase,
    required this.rateLimit,
    required this.siteUrl,
  });

  static _Args parse(List<String> argv) {
    bool check = false;
    bool dryRun = false;
    bool printCurl = false;
    String projectRef = defaultProjectRef;
    String apiBase =
        Platform.environment['SUPABASE_API_BASE'] ?? defaultApiBase;
    int rateLimit =
        int.tryParse(Platform.environment['EMAIL_RATE_LIMIT'] ?? '') ??
            defaultEmailRateLimit;
    String siteUrl =
        Platform.environment['PORTAL_SITE_URL'] ?? customerPortalOrigin;

    for (int i = 0; i < argv.length; i++) {
      switch (argv[i]) {
        case '--check':
          check = true;
        case '--dry-run':
          dryRun = true;
        case '--print-curl':
          printCurl = true;
        case '--project-ref':
          projectRef = _value(argv, ++i, '--project-ref');
        case '--api-base':
          apiBase = _value(argv, ++i, '--api-base');
        case '--rate-limit':
          rateLimit = int.tryParse(_value(argv, ++i, '--rate-limit')) ??
              defaultEmailRateLimit;
        case '--site-url':
          siteUrl = _value(argv, ++i, '--site-url');
        case '--help':
        case '-h':
          print(_usageText());
          exit(0);
        default:
          _fail('Unknown argument: ${argv[i]}\n\n${_usageText()}');
      }
    }
    return _Args(
      check: check,
      dryRun: dryRun,
      printCurl: printCurl,
      projectRef: projectRef,
      apiBase: apiBase,
      rateLimit: rateLimit,
      siteUrl: siteUrl,
    );
  }

  static String _value(List<String> argv, int index, String flag) {
    if (index >= argv.length) _fail('$flag needs a value.');
    return argv[index];
  }

  static String _usageText() => '''
Apply the live project's auth e-mail config (ANQUI item 16, §R8).

  dart run tool/apply_live_auth_mail.dart [options]

  --check              read the config back and verify it; change nothing
  --dry-run            print the payload that would be sent (secret masked)
  --print-curl         write the payload JSON and print copy-paste curl instead
  --project-ref <ref>  default $defaultProjectRef
  --api-base <url>     default $defaultApiBase (or the SUPABASE_API_BASE env var)
  --rate-limit <n>     rate_limit_email_sent, default $defaultEmailRateLimit/hour
  --site-url <url>     Site URL — where a link with no explicit redirect lands,
                       default $customerPortalOrigin (or the
                       PORTAL_SITE_URL env var). The allow list is merged with
                       the app's two deep links (confirmation + password
                       reset), the portal's /account and the portal's dev
                       origin whatever this is set to.
  -h, --help           this text

Credentials come from the environment, or are prompted for:
  SUPABASE_ACCESS_TOKEN, GMAIL_SENDER, GMAIL_APP_PASSWORD
''';
}

/// Exits — never returns, which is what lets the callers above `_fail(...)`
/// without a `return`.
Never _fail(String message) {
  print('\n❌ $message');
  exit(1);
}
