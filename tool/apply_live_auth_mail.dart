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
    exit(await _verify(url, token, sender) ? 0 : 1);
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
  final String siteUrl = '${current['site_url'] ?? ''}';
  print('Current uri_allow_list: '
      '${currentList.isEmpty ? '(empty)' : currentList}');
  print('Current site_url:       ${siteUrl.isEmpty ? '(unset)' : siteUrl}');

  final Map<String, dynamic> payload = _buildPayload(
    args,
    sender: sender,
    appPassword: appPassword,
    allowList: _mergeAllowList(currentList, siteUrl),
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
      'A 401/403 means the token lacks `auth:write`; a 400 usually names the '
      'offending field above.',
    );
  }

  print('\n✅ Applied.');
  final bool ok = await _verify(url, token, sender);
  print(
    '\nNext: send yourself one real code (sign up with a fresh address, or '
    'turn the device gate on and sign in from a cleared install) and check the '
    'mail: heading "Confirm it\'s you", a 6-digit number, and a From: of '
    '$sender — never `noreply@mail.app.supabase.io`. Full check list: '
    'docs/fixes/GO_LIVE_PRELAUNCH_CHECKLIST.md §R8 Step 4.',
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

    // ── Where the confirmation BUTTON returns (Step 3b) ────────────────
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

/// Append what the app needs, keeping every entry already configured.
///
/// `site_url` is kept in the list on purpose: the app sends no `redirectTo`
/// for password resets, so those links resolve to the site URL, and a
/// non-empty allow list is what decides whether that redirect is honoured.
String _mergeAllowList(String current, String siteUrl) {
  final List<String> entries = current
      .split(',')
      .map((String e) => e.trim())
      .where((String e) => e.isNotEmpty)
      .toList();
  for (final String candidate in <String>[siteUrl, authConfirmRedirect]) {
    if (candidate.isNotEmpty && !entries.contains(candidate)) {
      entries.add(candidate);
    }
  }
  return entries.join(',');
}

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
Future<bool> _verify(String url, String token, String sender) async {
  final Map<String, dynamic> config = await _getConfig(url, token);

  bool has(String field, String needle) =>
      '${config[field] ?? ''}'.contains(needle);
  int asInt(String field) => int.tryParse('${config[field] ?? ''}') ?? 0;

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
  };

  print('\nVerification (read back from the project):');
  checks.forEach((String name, bool ok) {
    print('  ${ok ? '✅' : '❌'} $name');
  });

  // `smtp_pass` is deliberately not asserted: the API does not return the
  // secret, so a wrong App Password shows up as a failed SEND, not here.
  if (checks.values.any((bool ok) => !ok)) {
    print(
      '\n⚠️  Some fields did not read back as expected. Re-run, and if it '
      'persists check the dashboard\'s Authentication → SMTP Settings / Emails '
      'screens — the PATCH may have been rejected field-by-field.',
    );
    return false;
  }
  return true;
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

  const _Args({
    required this.check,
    required this.dryRun,
    required this.printCurl,
    required this.projectRef,
    required this.apiBase,
    required this.rateLimit,
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
