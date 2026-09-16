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
