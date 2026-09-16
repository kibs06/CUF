import 'dart:io';

import 'package:app/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cover for the app's deep links, and the cross-artifact CONTRACT behind the
/// newest one: the return from the sign-up confirmation e-mail
/// (`solvision://auth/confirm`).
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
  });

  group('authConfirmRedirect agreement', () {
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
