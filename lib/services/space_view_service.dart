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
///      another application: missing ARCore, no handler, or a denied launch
///      all answer `false`, and the caller says so in a `SnackBar`.
///
/// This sits *alongside* the native foot-tracking AR screen, not in place of
/// it: the floor is where a customer decides, the foot is where they fit.
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public-read bucket that `product_models.storage_path` points into —
/// the same bucket `ShoeModelService` downloads from and the portal draws.
const String kSpaceViewBucket = 'shoe-models';

/// Whether there is a public file to point Scene Viewer at.
///
/// Trims, because a row with only whitespace in `storage_path` is the same
/// state as no row: nothing to fetch.
bool hasSpaceView(String? storagePath) =>
    (storagePath?.trim().isNotEmpty ?? false);

/// The Scene Viewer URL for an already-public `.glb` URL.
///
/// `mode=ar_only` skips the 3D fallback Scene Viewer would otherwise offer —
/// the app already has a 3D box, and this door is the floor. Pure so it can
/// be tested without a device.
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
/// never hand-built), then hands the Scene Viewer URL to the OS. Returns
/// `true` when another application took it, `false` for every other outcome,
/// including a blank path (rule 1) and a refused launch (rule 2).
///
/// [launch] is the `url_launcher` call, injectable so tests never leave the
/// harness; [publicUrlFor] is the bucket read, injectable for the same
/// reason.
Future<bool> launchSpaceView(
  String? storagePath, {
  Future<bool> Function(Uri uri)? launch,
  String Function(String storagePath)? publicUrlFor,
}) async {
  final path = storagePath?.trim() ?? '';
  if (path.isEmpty) return false;

  final doLaunch =
      launch ?? (Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

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
