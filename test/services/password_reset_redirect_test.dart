import 'dart:io';

import 'package:app/constants/app_constants.dart';
import 'package:app/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cover for the password-reset LINK — the one sign-in e-mail link a customer
/// has to open for the flow to work at all, and the one whose destination is
/// decided by server-side config that no compiler checks.
///
/// Measured Oct 12, 2026: the mailer was repaired and the reset STILL could not
/// be completed, because the button resolved to the project's shipped
/// `http://localhost:3000` Site URL — `ERR_CONNECTION_REFUSED` on the
/// customer's phone. There are now two destinations on purpose:
///
///  * the **app**, for a reset started in the app
///    (`DeepLinkService.authRecoveryRedirect` → `ResetPasswordScreen`);
///  * the customer **portal**'s account page, for a reset started on the
///    website and as the Site URL fallback (`AppConstants.customerPortalUrl`).
///
/// Five places have to agree, and this file pins four of them to each other:
///
///   1. the Dart constants;
///   2. the three call sites that must send the APP link — one of them is the
///      lockout overlay's "Reset password", a different screen and therefore a
///      different place to forget it;
///   3. `tool/apply_live_auth_mail.dart`, which writes the Site URL and the
///      allow-list entries that make GoTrue honour either redirect;
///   4. the runbook a human follows for the dashboard route
///      (`docs/fixes/GO_LIVE_PRELAUNCH_CHECKLIST.md` §R8);
///   5. the LIVE project's own config — API/dashboard state, so it cannot be
///      asserted here. `dart run tool/apply_live_auth_mail.dart --check` reads
///      it back: it prints `site_url` / `uri_allow_list` and three rows
///      ("site_url is the reset destination", "reset link returns to the app",
///      "reset link can reach the portal account page").
///
/// The deep-link side of the contract (the constant against
/// `AndroidManifest.xml`, and the routing predicate) lives in
/// `test/services/deep_link_service_test.dart`.
void main() {
  const appConstantsPath = 'lib/constants/app_constants.dart';
  const authServicePath = 'lib/services/auth_service.dart';
  const supabaseServicePath = 'lib/services/supabase_service.dart';
  const portalAuthPath = 'customer-portal/src/lib/auth.js';
  const toolPath = 'tool/apply_live_auth_mail.dart';
  const runbookPath = 'docs/fixes/GO_LIVE_PRELAUNCH_CHECKLIST.md';

  String read(String path) {
    final File file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path should exist');
    return file.readAsStringSync();
  }

  int occurrences(String source, String needle) =>
      needle.allMatches(source).length;

  group('the reset destinations are pages that can finish a reset', () {
    test('the app link is the recovery path on the app scheme', () {
      final Uri link = Uri.parse(DeepLinkService.authRecoveryRedirect);
      expect(link.scheme, 'solvision');
      expect(link.host, 'auth');
      expect(link.path, '/recovery');
      expect(
        DeepLinkService.authRecoveryRedirect,
        isNot(DeepLinkService.authConfirmRedirect),
        reason: 'the two e-mail links share a host; routing a reset into the '
            'sign-up completion (or the reverse) is the silent failure this '
            'pair of constants exists to prevent',
      );
    });

    test('every reset call site sends the APP link', () {
      // The CALL, not the bare method name: the same name also appears in the
      // doc comments, and a count that drifts with prose is a test nobody
      // trusts.
      const call = 'auth.resetPasswordForEmail(';
      const redirect = 'redirectTo: DeepLinkService.authRecoveryRedirect';
      final authService = read(authServicePath);
      final supabaseService = read(supabaseServicePath);

      expect(
        occurrences(authService, call),
        2,
        reason: 'resetPassword (the sign-in screen) and '
            'sendLockoutNotificationEmail (the lockout overlay) are the two '
            'senders in AuthService',
      );
      expect(
        occurrences(authService, redirect),
        2,
        reason: 'BOTH AuthService senders must carry the app redirect — the '
            'lockout overlay is a different screen, hence a separate place to '
            'forget it',
      );
      expect(
        occurrences(supabaseService, call),
        1,
        reason: 'the path the sign-in screen actually takes '
            '(AuthProvider.resetPassword → SupabaseService.resetPassword)',
      );
      expect(
        occurrences(supabaseService, redirect),
        1,
        reason: 'SupabaseService.resetPassword must carry the app redirect, or '
            'the customer is sent to a browser instead of the reset screen',
      );
    });

    test('the tool writes the same destinations and allow-lists them', () {
      final tool = read(toolPath);

      expect(
        tool,
        contains("'${AppConstants.customerPortalUrl}'"),
        reason: 'the tool writes the live Site URL and the allow list; its '
            'origin literal must be the origin the runbook and the portal '
            'deployment agree on',
      );
      expect(
        tool,
        contains(
          r"const String authRecoveryRedirect = 'solvision://auth/recovery';",
        ),
        reason: 'the allow-list entry has to be the EXACT deep link the app '
            'sends; GoTrue drops an unknown redirect and falls back to the '
            'site URL',
      );
      expect(
        tool,
        contains('add(authRecoveryRedirect);'),
        reason: 'declaring the constant is not enough — it must be merged into '
            'uri_allow_list, which is what actually lets GoTrue honour it',
      );
      expect(
        tool,
        contains(
          r"customerPortalResetRedirect = '$customerPortalOrigin/account'",
        ),
        reason: 'the portal half must stay allow-listed: a reset started on the '
            'website returns to /account, and that page is also the fallback '
            'when an app redirect cannot be honoured',
      );
      expect(
        tool,
        contains("'site_url'"),
        reason: 'the Site URL is GoTrue’s fallback destination for a reset call '
            'with no redirectTo (an older build). Leaving the project default '
            'is what made the mailed link open localhost:3000',
      );
    });

    test('the portal implements the page its own resets return to', () {
      // The other half of the contract: pointing website resets at /account is
      // only a fix while /account can set a password.
      final portalAuth = read(portalAuthPath);
      expect(portalAuth, contains('resetPasswordForEmail'));
      expect(portalAuth, contains('/account'));
      expect(
        portalAuth,
        contains('updateUser({ password: newPassword })'),
        reason: 'the page a recovery link lands on must be able to set the new '
            'password with the session that link establishes',
      );
    });

    test('the runbook names both destinations for the dashboard route', () {
      // Not assertable from here: the live fields. Recorded as an operational
      // step in §R8, and pinned here as a reminder rather than a check.
      final runbook = read(runbookPath);
      expect(
        runbook,
        contains(AppConstants.customerPortalUrl),
        reason: 'if the portal (the Site URL) changes, the runbook step changes '
            'with it — and that step is the only place these fields are written '
            'down for a human',
      );
      expect(
        runbook,
        contains(DeepLinkService.authRecoveryRedirect),
        reason: 'the app deep link is the entry that makes the reset button '
            'open CUFMAI; a runbook that omits it sends the reader to the '
            'dashboard without the one value the app now depends on',
      );
    });
  });

  test('the app constants file carries the origin the tool writes', () {
    // Guards the one thing every assertion above depends on: that the values
    // come from the shipped constants rather than from a copy in this file.
    expect(read(appConstantsPath), contains(AppConstants.customerPortalUrl));
  });
}
