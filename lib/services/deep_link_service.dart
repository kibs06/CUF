import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Listens for the app's deep links (`solvision://checkout/gcash/*`) —
/// the return path from PayMongo's hosted GCash checkout.
///
/// The return link is INFORMATIONAL ONLY: neither this service nor any
/// UI ever marks a payment paid from a link. The link merely triggers a
/// re-check of the authoritative order status (see GcashPaymentScreen's
/// polling), because the server-side webhook is the only source of truth.
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  /// Where the sign-up confirmation e-mail sends the user back to.
  ///
  /// Passed as `emailRedirectTo` on sign-up (and on a resend), which is what
  /// GoTrue embeds as `redirect_to` in `{{ .ConfirmationURL }}`. Tapping that
  /// button then lands HERE with the session in the URI instead of on a web
  /// page the app cannot use.
  ///
  /// ⚠️ Three places must agree or the button silently falls back to the web
  /// redirect (GoTrue refuses a redirect it has not been told about):
  ///  1. this constant,
  ///  2. the `solvision`/`auth` intent-filter in `AndroidManifest.xml`
  ///     (iOS only matches the `solvision` scheme, already registered in
  ///     `Info.plist`),
  ///  3. the LIVE project's Authentication → URL Configuration → **Redirect
  ///     URLs** allow-list.
  /// `test/services/deep_link_service_test.dart` pins 1 against 2.
  static const String authConfirmRedirect = 'solvision://auth/confirm';

  /// Where a PASSWORD-RESET e-mail sends the customer back to.
  ///
  /// The same mechanism as [authConfirmRedirect], for the same reason and with
  /// the same three-place contract: the mail's button is an
  /// `https://…/auth/v1/verify` link that 302s to the `redirect_to` it was
  /// given, so `resetPasswordForEmail(..., redirectTo: authRecoveryRedirect)`
  /// lands the customer IN the app rather than on a web page. The recovery
  /// session rides in the URI fragment (`#access_token=…&type=recovery`),
  /// supabase_flutter's own observer stores it, and the only thing left to do
  /// is choose a new password — see `ResetPasswordScreen`.
  ///
  /// ⚠️ Three places must agree, exactly as for the confirmation link:
  ///  1. this constant,
  ///  2. the `solvision`/`auth` intent-filter in `AndroidManifest.xml` (iOS
  ///     matches the `solvision` scheme alone),
  ///  3. the LIVE project's Authentication → URL Configuration → **Redirect
  ///     URLs** allow-list, which `tool/apply_live_auth_mail.dart` writes.
  /// `test/services/deep_link_service_test.dart` and
  /// `test/services/password_reset_redirect_test.dart` pin the three.
  static const String authRecoveryRedirect = 'solvision://auth/recovery';

  /// Where a Supabase hosted-OAuth return lands (`solvision://auth/callback`).
  ///
  /// Same three-place contract as the e-mail links: this constant, the
  /// `solvision`/`auth` intent-filter in `AndroidManifest.xml` (iOS matches
  /// the `solvision` scheme alone), and the LIVE project's Authentication →
  /// URL Configuration → **Redirect URLs** allow-list. Supabase's own
  /// deep-link observer adopts the session from the link's `code` (PKCE) or
  /// `#access_token` fragment — this constant is only the routing predicate
  /// so the app knows a social return arrived.
  static const String oauthCallbackRedirect = 'solvision://auth/callback';

  /// Whether [uri] is a Supabase hosted-OAuth return (see
  /// [oauthCallbackRedirect]).
  static bool isOAuthCallbackLink(Uri uri) {
    final expected = Uri.parse(oauthCallbackRedirect);
    return uri.scheme == expected.scheme &&
        uri.host == expected.host &&
        uri.path.startsWith(expected.path);
  }

  /// Whether a link is one of our GCash return links.
  static bool isGcashReturn(Uri uri) =>
      uri.scheme == 'solvision' &&
      uri.host == 'checkout' &&
      uri.path.startsWith('/gcash');

  /// Whether [uri] is the return from the sign-up confirmation e-mail
  /// (see [authConfirmRedirect]).
  ///
  /// Matched on scheme + host + path, not merely the scheme: the app owns
  /// other `solvision://` links, and each one has a different handler.
  static bool isAuthConfirmLink(Uri uri) {
    final expected = Uri.parse(authConfirmRedirect);
    return uri.scheme == expected.scheme &&
        uri.host == expected.host &&
        uri.path.startsWith(expected.path);
  }

  /// Whether [uri] is the return from a password-reset e-mail (see
  /// [authRecoveryRedirect]).
  ///
  /// Matched on scheme + host + PATH, not merely the scheme: this link and
  /// [authConfirmRedirect] share a host and differ only in that path, and
  /// routing a reset into the sign-up completion (or the reverse) is the
  /// silent failure — the app opens, and acts on the wrong thing.
  static bool isAuthRecoveryLink(Uri uri) {
    final expected = Uri.parse(authRecoveryRedirect);
    return uri.scheme == expected.scheme &&
        uri.host == expected.host &&
        uri.path.startsWith(expected.path);
  }

  /// The reason GoTrue itself refused a recovery link — `otp_expired` for one
  /// that was already used or sat in the inbox past its hour — else null.
  ///
  /// A refusal arrives on the SAME link with a query instead of a fragment
  /// (`…solvision://auth/recovery?error=access_denied&error_code=otp_expired`),
  /// and it carries no session, so the recovery handler has nothing to open.
  /// Read here rather than in the handler because it is a property of the LINK,
  /// and because a silent nothing is what makes a customer report "the button
  /// in the e-mail is broken".
  static String? recoveryLinkRefusal(Uri uri) {
    if (!isAuthRecoveryLink(uri)) return null;
    return uri.queryParameters['error_code'] ??
        uri.queryParameters['error_description'] ??
        uri.queryParameters['error'];
  }

  /// The product ID when [uri] is a product share link, else null.
  ///
  /// Accepts both shapes so the handler is future-proof:
  ///   1. the current edge-function URL
  ///      https://…supabase.co/functions/v1/product-preview/{id}
  ///   2. a future custom-domain clean link `https://<domain>/p/{id}`
  ///
  /// The ID is validated loosely (alphanumeric + dashes, ≤ 64 chars) — the
  /// fetch itself is the real authority; anything else yields null.
  static String? productIdFromLink(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    String? id;
    if (segments.length == 2 && segments[0] == 'p') {
      id = segments[1];
    } else if (segments.length == 4 &&
        segments[0] == 'functions' &&
        segments[1] == 'v1' &&
        segments[2] == 'product-preview') {
      id = segments[3];
    }
    if (id == null || id.isEmpty || id.length > 64) return null;
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(id)) return null;
    return id;
  }

  /// Whether [uri] is a product share link (see [productIdFromLink]).
  static bool isProductLink(Uri uri) => productIdFromLink(uri) != null;

  /// The host of the app's OWN product link — `solvision://product/{id}`.
  ///
  /// The customer widget's product rows are the only producer. A widget cannot
  /// push a screen: it attaches a `PendingIntent` per row, and the only thing that
  /// can carry across that boundary is a URI this app already knows how to open.
  /// So each row carries this, and the tap lands on the product the row showed.
  ///
  /// ⚠️ A contract with Kotlin. `SellerWidgetProvider` builds the string itself
  /// (a widget row is drawn with no Dart running), so the scheme and this host are
  /// spelled in two languages and `seller_widget_contract_test.dart` pins them
  /// against each other — a rename on one side alone opens the app on a product
  /// screen it never reaches, silently.
  static const String productHost = 'product';

  /// The link a widget row carries for [productId].
  static String productAppLink(String productId) =>
      'solvision://$productHost/$productId';

  /// The product ID when [uri] is the app's own product link, else null.
  ///
  /// Deliberately separate from [productIdFromLink], which matches the *shared*
  /// https link a customer sends to someone else. Two different links with the
  /// same destination, because they come from two different places: one is opened
  /// by another app, the other by our own launcher tile. Merging them would mean
  /// the share handler had to accept a scheme it was never meant to see.
  ///
  /// The ID is validated to the same shape a product id has (alphanumeric +
  /// dashes, ≤ 64 chars) and anything else is null — the fetch is the real
  /// authority, and a malformed link must not reach it.
  static String? productIdFromAppLink(Uri uri) {
    if (uri.scheme != 'solvision' || uri.host != productHost) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 1) return null;
    final id = segments.first;
    if (id.isEmpty || id.length > 64) return null;
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(id)) return null;
    return id;
  }

  /// Live stream of in-app deep links (broadcast — multiple listeners OK).
  Stream<Uri> get uriStream => _appLinks.uriLinkStream;

  /// Start listening. [onLink] fires for the cold-start initial link (if
  /// any) and for every subsequent link.
  Future<void> init({required void Function(Uri uri) onLink}) async {
    try {
      final initial = await _appLinks.getInitialLink();
      _sub = _appLinks.uriLinkStream.listen(onLink);
      if (initial != null) onLink(initial);
    } catch (e) {
      debugPrint('[DEEP-LINK] init failed: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
