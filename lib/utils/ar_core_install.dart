import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Package name of Google Play Services for AR (ARCore).
const String kArCorePackageName = 'com.google.ar.core';

/// Opens the Google Play listing for Google Play Services for AR (ARCore).
///
/// Tries `market://` first (lands directly in the Play Store app) and falls
/// back to the https listing when the market scheme isn't handled — some
/// devices and the occasional emulator only resolve the web URL.
///
/// Returns whether a store page was launched. Note that on devices Play
/// refuses to serve, the listing opens and says the app isn't available, so
/// callers must not treat `true` as "the install will succeed".
Future<bool> openArCoreInstallPage() async {
  final candidates = <Uri>[
    Uri.parse('market://details?id=$kArCorePackageName'),
    Uri.parse(
      'https://play.google.com/store/apps/details?id=$kArCorePackageName',
    ),
  ];

  for (final uri in candidates) {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return true;
    } catch (e) {
      debugPrint('[ArCoreInstall] Could not launch $uri: $e');
    }
  }
  return false;
}
