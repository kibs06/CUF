/// Platform-channel wrapper for the **inline 3D preview** — the product page's
/// "view in 3D" box, which sits above a "Try On in AR" button rather than
/// replacing it.
///
/// **Why this is not the AR channel.** `ar_try_on_channel.dart` drives a session:
/// permission, ARCore availability, `startSession`, placement taps, an event
/// stream whose `modelLoaded`/`error` the session controller reads as facts about
/// *its* run. The preview has none of that — no session is ever created, and the
/// camera is driven by a finger. It also lives somewhere the AR view never does:
/// **inline on the product page**, where it stays mounted while the AR screen is
/// pushed on top of it. Two views on one channel would mean one slot in
/// `ArTryOnPlugin` and one event stream shared by both, so the screen on top
/// would receive the view underneath's events. Hence three names of its own
/// (`SHOE_PREVIEW_*` in `ArTryOnPlugin.kt`) and this file as their Dart twin.
///
/// **What is shared is the renderer and the payload.** The native side is the
/// same `ArTryOnView` in `Mode.PREVIEW` — same Filament engine, same glTF
/// loader, same lights, same authored-length correction — so the model handover
/// is the same [`TryOnModelSpec`], and it is handed over the same way: Dart sends
/// it the moment the box is built, and the native side parks it if its view does
/// not exist yet (F18).
///
/// **Every call is best-effort.** A build with no native plugin — and every iOS
/// build, where there is no renderer at all — answers `MissingPluginException`,
/// which is the expected answer rather than a failure: the caller that decided to
/// mount this box already knows the platform, and a preview that cannot draw is
/// not allowed to break a product page.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import 'ar_try_on_channel.dart';

/// Method channel name, beside the AR channel's `com.solevision/ar_try_on`.
const String kShoePreviewMethodChannel = 'com.solevision/shoe_preview';

/// Event channel for the preview's own reports (`modelLoaded`, `perf`, `error`).
///
/// Nothing listens on it today: the box has no phases to drive and the model
/// either appears or it does not, which is the page's problem to ignore. It is
/// declared because the native side sends to it, and because "the preview is
/// silent" should be a fact about the Dart side rather than a missing wire.
const String kShoePreviewEventChannel = 'com.solevision/shoe_preview/events';

/// Platform-view type the native side registers (`SHOE_PREVIEW_VIEW_TYPE` in
/// `ArTryOnPlugin.kt`), and the string the page's `AndroidView` embeds.
const String kShoePreviewViewType = 'com.solevision/shoe_preview/view';

/// **The one native reason that takes the whole 3D surface off the page.**
///
/// ⚠️ It is not a tidy-up, it is a guard against a crash that was reproduced on
/// 2026-09-29. A renderer that comes up at `FEATURE_LEVEL_1` — any phone whose
/// ceiling is OpenGL ES 3.0, which is the class of device this market is most
/// likely to hold — cannot resolve a glTF's materials through the ubershader
/// provider at all (finding F14), and the attempt is not reliably catchable: on
/// the Pixel_4 emulator it was a **SIGSEGV inside `libfilament-jni.so`, 126 ms
/// after `Engine.create()`**, which killed the app on the product page.
///
/// So `ArTryOnView` refuses to load an asset below feature level 2 and reports
/// this reason, and the section removes itself — box *and* button, because on
/// such a phone the AR path cannot draw the shoe either. The string is spelled
/// once here and once in `ArTryOnView.kt`, and
/// `product_detail_shoe_preview_contract_test` fails if they drift: a reason the
/// Dart side does not know is a section that stays on screen over a crash.
const String kRendererUnsupportedReason = 'renderer_feature_level_unsupported';

/// The three calls the preview answers, and nothing else.
///
/// No `startSession` (there is no session), no `placeShoe` (the shoe is not
/// placed, it is framed), no `captureScreenshot` (the preview has no share
/// affordance): a method this class could not call is a contract with no second
/// half, which is the rule `ar_try_on_channel.dart` states for the V4 methods it
/// deliberately leaves out.
class ShoePreviewChannel {
  const ShoePreviewChannel({MethodChannel? methodChannel})
      : _method = methodChannel ?? const MethodChannel(kShoePreviewMethodChannel);

  final MethodChannel _method;

  /// Hand the verified local `.glb` over. Safe before the view exists.
  ///
  /// ⚠️ **Both QA switches ride on this payload, and on this one only.**
  /// `AppConstants.shoePreviewAllowLevel1` is sent as a bare `false` in every
  /// customer build, and the native side additionally refuses to honour a `true`
  /// outside a debuggable build; the request is deliberately *not* a field of
  /// [`TryOnModelSpec`], because the AR session hands over the same shape and
  /// must not be able to ask a crashing load into existence. See `ArTryOnView
  /// .allowsUnsupportedRenderer` for the guard it relaxes.
  ///
  /// `AppConstants.shoePreviewLowerEngineToLevel1` travels the same way for the
  /// other half of the same question — it asks the renderer to come up at
  /// `FEATURE_LEVEL_1` rather than only to tolerate it — and carries the same two
  /// locks (`ArTryOnView.shouldLowerEngineToLevel1`), because an engine lowered on
  /// a customer's phone would be a product decision rather than a measurement.
  Future<void> setModel(TryOnModelSpec spec) =>
      _invoke('setPreviewModel', <String, Object?>{
        ...spec.toMap(),
        'allowUnsupportedRenderer': AppConstants.shoePreviewAllowLevel1,
        'lowerEngineToLevel1': AppConstants.shoePreviewLowerEngineToLevel1,
      });

  /// Grade the mesh to a selected EU size — the same 6.67 mm step the AR path
  /// uses, because the box shows the size the customer just tapped.
  Future<void> setSize({
    required double? sizeEu,
    required double? refSizeEu,
    required double? lastLengthMm,
  }) =>
      _invoke('setPreviewSize', <String, Object?>{
        'sizeEu': sizeEu,
        'refSizeEu': refSizeEu,
        'lastLengthMm': lastLengthMm,
      });

  /// A colour's per-part material overrides, already decided by the Dart side
  /// (the native side knows no colour names).
  Future<void> setColor(Map<String, Object?> materialOverrides) =>
      _invoke('setPreviewColor', <String, Object?>{
        'materialOverrides': materialOverrides,
      });

  /// Native → Dart reports for the preview (`modelLoaded`, `perf`, `error`).
  ///
  /// Nothing is *driven* by these except [kRendererUnsupportedReason]: the box has
  /// no phases, and a model that never appears is indistinguishable from one that
  /// has not arrived, which is the truth for both. The stream exists so the one
  /// case that must change the page — this renderer cannot draw at all — has
  /// somewhere to arrive.
  Stream<Map<String, dynamic>> get events =>
      const EventChannel(kShoePreviewEventChannel)
          .receiveBroadcastStream()
          .map((event) => event is Map
              ? Map<String, dynamic>.from(event)
              : const <String, dynamic>{})
          .handleError((Object _) {
        // No plugin, no handler, a dead channel: silence is the answer, not an
        // error a product page has to handle.
      });

  Future<void> _invoke(String method, Object? arguments) async {
    try {
      await _method.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Normal on a build without the plugin, and expected on iOS. The preview
      // simply does not draw; nothing else on the page is affected.
    } on PlatformException catch (e) {
      debugPrint('[ShoePreview] $method failed: ${e.code} ${e.message}');
    }
  }
}
