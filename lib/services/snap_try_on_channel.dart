/// Native Snap try-on bridge (Phase 1: full-screen Camera Kit activity).
///
/// The Dart half only. The native side is `SnapTryOnPlugin` (own channel, per
/// the rule documented in `ArTryOnPlugin.kt`: parked payloads must never cross
/// slots, so this is not another method on the AR channel).
///
/// On a build with no native plugin every call throws [SnapTryOnUnavailable]
/// (via `MissingPluginException`) — which is not a bug to guard against but
/// the expected answer on iOS and unconfigured builds: the caller falls back
/// to the web lens.
library;

import 'package:flutter/services.dart';

/// `MethodChannel` name; the native twin is `SNAP_TRY_ON_METHOD_CHANNEL`.
const String kSnapTryOnMethodChannel = 'com.solevision/snap_try_on';

/// Staging credentials from `--dart-define` (never committed — see
/// `dart_defines.json.example`, same rule as every other key there). Empty
/// means "not configured", and the pill stays on the web lens.
const String kCameraKitApiToken = String.fromEnvironment('CAMERAKIT_API_TOKEN');
const String kCameraKitLensGroupId =
    String.fromEnvironment('CAMERAKIT_LENS_GROUP_ID');

/// The footwear lens applied on open; empty falls back to the group's
/// carousel (the group is expected to hold the product lens).
const String kCameraKitLensId = String.fromEnvironment('CAMERAKIT_LENS_ID');

/// The native camera did not open (no plugin, no credentials, or it refused).
/// The caller opens the web lens instead — a refused launch is a sentence
/// there, never a throw (same rule as the space-view entry).
class SnapTryOnUnavailable implements Exception {
  final String reason;
  const SnapTryOnUnavailable(this.reason);
}

class SnapTryOnChannel {
  const SnapTryOnChannel();

  static const MethodChannel _channel =
      MethodChannel(kSnapTryOnMethodChannel);

  /// Opens the native Camera Kit camera. True when it opened (what the
  /// customer does inside is the activity's business, not the return value).
  /// Throws [SnapTryOnUnavailable] whenever there is no native camera to
  /// open — the caller falls back to the web lens.
  Future<bool> launchSnapTryOn({
    required String apiToken,
    required String lensGroupId,
    required String lensId,
  }) async {
    if (apiToken.isEmpty || lensGroupId.isEmpty) {
      throw const SnapTryOnUnavailable('not-configured');
    }
    try {
      final opened = await _channel.invokeMethod<bool>('launchSnapTryOn', {
        'apiToken': apiToken,
        'lensGroupId': lensGroupId,
        'lensId': lensId,
      });
      if (opened == true) return true;
      throw const SnapTryOnUnavailable('not-opened');
    } on MissingPluginException {
      throw const SnapTryOnUnavailable('no-plugin');
    } on PlatformException catch (e) {
      throw SnapTryOnUnavailable(e.code);
    }
  }
}
