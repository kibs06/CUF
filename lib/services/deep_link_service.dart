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

  /// Whether a link is one of our GCash return links.
  static bool isGcashReturn(Uri uri) =>
      uri.scheme == 'solvision' &&
      uri.host == 'checkout' &&
      uri.path.startsWith('/gcash');

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
