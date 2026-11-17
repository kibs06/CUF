/// **"View in your space"** — the portal's space-AR door, now in the app.
///
/// The customer portal places the workshop's verified `.glb` on the floor
/// through `<model-viewer>`'s platform viewer (Scene Viewer / WebXR). The
/// app's 3D box cannot do that: its model lives on disk behind a loopback
/// server, and the Google app that renders Scene Viewer cannot reach
/// `http://127.0.0.1`. So this service goes around the box rather than
/// through it — the `shoe-models` bucket is public-read on purpose (a model
/// is catalogue content, like a photograph), and Scene Viewer fetches the
/// same public object URL the portal draws.
///
/// Two rules, both about not showing a button that opens nothing:
///
///   1. **No path, no button.** A product with no `storage_path` has no public
///      file, and the caller hides the entry rather than launching a viewer
///      at a 404 ([hasSpaceView]).
///   2. **A failed launch is a sentence, not a crash.** Scene Viewer is
///      another application: missing ARCore, no handler, or a refused launch
///      all answer `false`, and the caller says so in a `SnackBar`.
///
/// The launch goes through [SpaceViewChannel], an explicit `ACTION_VIEW`
/// intent to `com.google.ar.core`. That is the documented path for
/// `mode=ar_only`; handing the URL to a browser only proves a browser exists,
/// not that Scene Viewer or ARCore is installed.
///
/// This sits *alongside* the native foot-tracking AR screen, not in place of
/// it: the floor is where a customer decides, the foot is where they fit.
library;

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Public-read bucket that `product_models.storage_path` points into —
/// the same bucket `ShoeModelService` downloads from and the portal draws.
const String kSpaceViewBucket = 'shoe-models';

/// Method channel owned by `SpaceViewPlugin.kt` (Android).
const String kSpaceViewMethodChannel = 'com.solevision/space_view';

/// Whether there is a public file to point Scene Viewer at.
///
/// Trims, because a row with only whitespace in `storage_path` is the same
/// state as no row: nothing to fetch.
bool hasSpaceView(String? storagePath) =>
    (storagePath?.trim().isNotEmpty ?? false);

/// The Scene Viewer URL for an already-public `.glb` URL.
///
/// `mode=ar_only` skips the 3D fallback Scene Viewer would otherwise offer —
/// the app already has a 3D box, and this door is the floor. Google's docs
/// require that mode to be launched as an explicit intent to
/// `com.google.ar.core`, which is what [SpaceViewChannel] does. Pure so it
/// can be tested without a device.
Uri sceneViewerUrl(String publicGlbUrl, {String title = 'CUFMAI 3D'}) {
  return Uri.parse(
    'https://arvr.google.com/scene-viewer/1.0'
    '?file=${Uri.encodeComponent(publicGlbUrl)}'
    '&mode=ar_only'
    '&title=${Uri.encodeComponent(title)}',
  );
}

/// Opens the workshop's model on the customer's floor.
///
/// Resolves the public URL through the Supabase client (the single source —
/// never hand-built), then hands the Scene Viewer URL to [SpaceViewChannel].
/// Returns `true` only when Android started the ARCore intent, `false` for
/// every other outcome, including a blank path (rule 1) and a refused launch
/// (rule 2).
///
/// [launch] is the channel call, injectable so tests never leave the harness;
/// [publicUrlFor] is the bucket read, injectable for the same reason.
Future<bool> launchSpaceView(
  String? storagePath, {
  Future<bool> Function(Uri uri)? launch,
  String Function(String storagePath)? publicUrlFor,
}) async {
  final path = storagePath?.trim() ?? '';
  if (path.isEmpty) return false;

  final doLaunch = launch ?? const SpaceViewChannel().launch;

  late final String publicUrl;
  try {
    publicUrl = publicUrlFor != null
        ? publicUrlFor(path)
        : Supabase.instance.client.storage
              .from(kSpaceViewBucket)
              .getPublicUrl(path);
  } catch (_) {
    return false;
  }
  if (publicUrl.isEmpty) return false;

  try {
    return await doLaunch(sceneViewerUrl(publicUrl));
  } catch (_) {
    return false;
  }
}

/// **The Android half of the space view** — an explicit Scene Viewer intent.
///
/// The native side is deliberately unaware of products, buckets and copy: it
/// receives the already-built URL and starts it under
/// `com.google.ar.core`. Every transport failure is `false`; the caller owns
/// the sentence. iOS and tests have no handler, which is the same `false` and
/// never an exception a product page has to catch.
class SpaceViewChannel {
  const SpaceViewChannel({MethodChannel? methodChannel})
    : _method = methodChannel ?? const MethodChannel(kSpaceViewMethodChannel);

  final MethodChannel _method;

  Future<bool> launch(Uri uri) async {
    try {
      return await _method.invokeMethod<bool>(
            'launchSceneViewer',
            <String, Object?>{'url': uri.toString()},
          ) ??
          false;
    } on MissingPluginException {
      // Normal off Android, and in a test without a native side.
      return false;
    } on PlatformException {
      return false;
    }
  }
}
