import 'dart:io';

import 'package:app/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cover for the app's deep links, and the cross-artifact CONTRACT behind the
/// two e-mail returns: sign-up confirmation (`solvision://auth/confirm`) and
/// password recovery (`solvision://auth/recovery`) — the same mechanism, two
/// paths that must never be mistaken for each other.
///
/// Incoming links all look alike to the OS, so a link is routed by matching
/// scheme + host + path. Getting that predicate wrong is silent in the worst
/// way: the app opens (the scheme matched) and then does nothing, which reads
/// as "the button in the e-mail is broken".
///
/// The redirect value itself lives in THREE places that no compiler compares —
/// the Dart constant, the Android intent-filter, and the LIVE project's
/// Redirect URLs allow-list (dashboard-only, so it cannot be asserted here and
/// is called out in the reason string instead). A rename in any of them falls
/// back to GoTrue's site-URL redirect, i.e. the browser dead end this feature
/// exists to remove. These assertions read the real files under test.
void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  const infoPlistPath = 'ios/Runner/Info.plist';
  const authServicePath = 'lib/services/auth_service.dart';
  const emailOtpServicePath = 'lib/services/email_otp_service.dart';

  Uri uri(String raw) => Uri.parse(raw);

  group('link routing', () {
    test('the GCash return is only the checkout host', () {
      expect(
        DeepLinkService.isGcashReturn(uri('solvision://checkout/gcash/abc')),
        isTrue,
      );
      expect(
        DeepLinkService.isGcashReturn(uri('solvision://auth/confirm')),
        isFalse,
      );
    });

    test('the auth confirm link is only the auth/confirm path', () {
      expect(
        DeepLinkService.isAuthConfirmLink(uri('solvision://auth/confirm')),
        isTrue,
      );
      // GoTrue appends the session to the fragment, and a trailing slash is
      // what a hand-edited link tends to look like — both must still match.
      expect(
        DeepLinkService.isAuthConfirmLink(
          uri('solvision://auth/confirm#access_token=t&refresh_token=r'),
        ),
        isTrue,
      );
      expect(
        DeepLinkService.isAuthConfirmLink(uri('solvision://auth/confirm/')),
        isTrue,
      );
    });

    test('a confirm link never matches the other handlers', () {
      // The scheme alone is NOT the link: the app owns several, and each has
      // its own handler. A predicate that matched on scheme only would route a
      // confirmation into the payment flow.
      expect(DeepLinkService.isAuthConfirmLink(uri('solvision://checkout/gcash')),
          isFalse);
      expect(DeepLinkService.isAuthConfirmLink(uri('solvision://auth/reset')),
          isFalse);
      expect(
        DeepLinkService.isAuthConfirmLink(uri('https://example.com/auth/confirm')),
        isFalse,
      );
      expect(DeepLinkService.isGcashReturn(uri('solvision://auth/confirm')),
          isFalse);
    });

    test('the auth recovery link is only the auth/recovery path', () {
      expect(
        DeepLinkService.isAuthRecoveryLink(uri('solvision://auth/recovery')),
        isTrue,
      );
      // The recovery session rides in the fragment exactly as the
      // confirmation one does, and a trailing slash is what a hand-edited
      // link tends to look like — both must still match.
      expect(
        DeepLinkService.isAuthRecoveryLink(
          uri('solvision://auth/recovery#access_token=t&type=recovery'),
        ),
        isTrue,
      );
      expect(
        DeepLinkService.isAuthRecoveryLink(uri('solvision://auth/recovery/')),
        isTrue,
      );
    });

    test('a refused recovery link carries its reason', () {
      // What a customer gets for tapping the same mail twice, or one that sat in
      // the inbox past its hour: the link, with `error_code` and no session.
      expect(
        DeepLinkService.recoveryLinkRefusal(
          uri('solvision://auth/recovery?error=access_denied'
              '&error_code=otp_expired&error_description=Email+link+is+invalid'),
        ),
        'otp_expired',
      );
      // A working link has nothing to report, and neither does anything that
      // is not a recovery link at all.
      expect(
        DeepLinkService.recoveryLinkRefusal(
          uri('solvision://auth/recovery#access_token=t&type=recovery'),
        ),
        isNull,
      );
      expect(
        DeepLinkService.recoveryLinkRefusal(uri('solvision://auth/confirm')),
        isNull,
      );
    });

    test('the OAuth callback link is only the auth/callback path', () {
      expect(
        DeepLinkService.isOAuthCallbackLink(
          uri('solvision://auth/callback'),
        ),
        isTrue,
      );
      // PKCE returns the code in the query; implicit in the fragment — both
      // must still route here.
      expect(
        DeepLinkService.isOAuthCallbackLink(
          uri('solvision://auth/callback?code=abc'),
        ),
        isTrue,
      );
      expect(
        DeepLinkService.isOAuthCallbackLink(
          uri('solvision://auth/callback#access_token=t'),
        ),
        isTrue,
      );
      expect(
        DeepLinkService.isOAuthCallbackLink(uri('solvision://auth/confirm')),
        isFalse,
      );
      expect(
        DeepLinkService.isOAuthCallbackLink(uri('solvision://auth/recovery')),
        isFalse,
      );
      expect(
        DeepLinkService.isAuthConfirmLink(uri('solvision://auth/callback')),
        isFalse,
      );
      expect(
        DeepLinkService.isAuthRecoveryLink(uri('solvision://auth/callback')),
        isFalse,
      );
    });

    test('the two auth e-mail links never match each other', () {
      // Same scheme, same host, different path — so a predicate that matched on
      // the scheme (or on the host alone) would send a reset into the sign-up
      // completion, which is silent: the app opens and does the wrong thing.
      expect(
        DeepLinkService.isAuthRecoveryLink(uri('solvision://auth/confirm')),
        isFalse,
      );
      expect(
        DeepLinkService.isAuthConfirmLink(uri('solvision://auth/recovery')),
        isFalse,
      );
      expect(
        DeepLinkService.isAuthRecoveryLink(uri('solvision://checkout/gcash')),
        isFalse,
      );
      expect(
        DeepLinkService.isAuthRecoveryLink(
          uri('https://example.com/auth/recovery'),
        ),
        isFalse,
      );
      expect(
        DeepLinkService.isGcashReturn(uri('solvision://auth/recovery')),
        isFalse,
      );
    });
  });

  group('the e-mail returns agree with the Android manifest', () {
    late String manifest;
    late String plist;
    late String authService;
    late String emailOtpService;

    setUpAll(() {
      for (final path in [
        manifestPath,
        infoPlistPath,
        authServicePath,
        emailOtpServicePath,
      ]) {
        expect(File(path).existsSync(), isTrue, reason: '$path should exist');
      }
      manifest = File(manifestPath).readAsStringSync();
      plist = File(infoPlistPath).readAsStringSync();
      authService = File(authServicePath).readAsStringSync();
      emailOtpService = File(emailOtpServicePath).readAsStringSync();
    });

    test('the constant is the scheme/host/path Android declares', () {
      final redirect = uri(DeepLinkService.authConfirmRedirect);
      expect(redirect.scheme, 'solvision');
      expect(redirect.host, 'auth');
      expect(redirect.path, '/confirm');

      // The intent-filter Android needs for the OS to hand us this link.
      expect(
        manifest,
        contains(
          'android:scheme="${redirect.scheme}" '
          'android:host="${redirect.host}" '
          'android:pathPrefix="${redirect.path}"',
        ),
        reason: 'AndroidManifest must declare the redirect the app signs up '
            'with, or the e-mail button opens a browser instead of the app',
      );
    });

    test('the RECOVERY constant is the scheme/host/path Android declares', () {
      final redirect = uri(DeepLinkService.authRecoveryRedirect);
      expect(redirect.scheme, 'solvision');
      expect(redirect.host, 'auth');
      expect(redirect.path, '/recovery');

      // The intent-filter Android needs for the reset button to open the app.
      // Both paths sit in ONE filter, because Android matches a cross-product
      // of its <data> elements.
      expect(
        manifest,
        contains(
          'android:scheme="${redirect.scheme}" '
          'android:host="${redirect.host}" '
          'android:pathPrefix="${redirect.path}"',
        ),
        reason: 'without this path the reset mail opens a browser, which cannot '
            'follow solvision:// and cannot set the password',
      );
    });

    test('a reset asks GoTrue to come back to the app', () {
      // The app-side half of the contract; the tool, the runbook and the
      // portal are pinned in password_reset_redirect_test.dart.
      expect(
        authService,
        contains('redirectTo: DeepLinkService.authRecoveryRedirect'),
        reason: 'without a redirect the mailed link carries the Site URL and '
            'the app never sees the tap',
      );
    });

    test('the OAUTH-CALLBACK constant is the scheme/host/path Android declares',
        () {
      final redirect = uri(DeepLinkService.oauthCallbackRedirect);
      expect(redirect.scheme, 'solvision');
      expect(redirect.host, 'auth');
      expect(redirect.path, '/callback');
      expect(
        manifest,
        contains(
          'android:scheme="${redirect.scheme}" '
          'android:host="${redirect.host}" '
          'android:pathPrefix="${redirect.path}"',
        ),
        reason: 'without this path the OAuth browser return opens a browser '
            'instead of the app',
      );
    });

    test('iOS registers the scheme (it matches on scheme alone)', () {
      expect(
        plist,
        contains('<string>solvision</string>'),
        reason: 'another reason the redirect must stay on the solvision '
            'scheme: iOS has no per-path filter, only this registration',
      );
    });

    test('sign-up asks GoTrue to come back to the app', () {
      expect(
        authService,
        contains('emailRedirectTo: DeepLinkService.authConfirmRedirect'),
        reason: 'without emailRedirectTo the confirmation e-mail carries the '
            'site-URL redirect and the app never sees the link',
      );
    });

    test('a RESENT confirmation comes back to the app too', () {
      // The link in a resent e-mail is built from the RESEND call, not from
      // the original signUp — so this is a separate place to forget, and it
      // fails only for users who had to ask for a second code.
      expect(
        emailOtpService,
        contains('emailRedirectTo: DeepLinkService.authConfirmRedirect'),
        reason: 'the resend path builds its own link; leaving it out sends '
            'resent confirmations to the browser',
      );
    });

    test('the live project must allow-list the redirect too', () {
      // Not assertable from here: GoTrue refuses a redirect_to it does not
      // recognise and falls back to the site URL. Recorded as an operational
      // step (dashboard → Authentication → URL Configuration → Redirect URLs)
      // in the runbook, and pinned here as a reminder rather than a check.
      const runbookPath = 'docs/fixes/GO_LIVE_PRELAUNCH_CHECKLIST.md';
      final runbook = File(runbookPath).readAsStringSync();
      expect(
        runbook,
        contains(DeepLinkService.authConfirmRedirect),
        reason: 'the R8 runbook is where the dashboard step lives — if the '
            'redirect changes, that step changes with it',
      );
    });
  });
}
