import 'dart:io' show Platform;

import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../constants/app_constants.dart';
import 'diag_logger.dart';

/// **The box's WebView, mounted the way the phone that cannot draw it needs.**
///
/// ## The fault this answers, measured
///
/// On 2026-10-07 the owner's **P30 Pro** was read over adb for the first time, and
/// the WebView engine failed in a way nothing in the page could see: the page
/// reported `gl:webgl2` and `<model-viewer>` reported **`loaded box=424x672`** —
/// every line a working page prints — while a screenshot of the glass measured the
/// box region as **91.2% exactly `#FFFFFF`** (161,417 of 176,904 sampled pixels)
/// with only **15** pixels of the `#F5F5F5` stage the page paints inline on the
/// element itself. The page rendered and **its surface never reached the screen**.
/// The same model, same session, drew on the **native** engine and on the
/// **customer portal** in a browser (`Product3DViewer.jsx` mounts the very same
/// library) — so the library, the model and the phone's 3D stack are all fine, and
/// the difference is the *embedding*.
///
/// ## Why the embedding is the difference
///
/// `model_viewer_plus` mounts its WebView through `WebViewWidget`, and
/// `webview_flutter_android` defaults that to **`displayWithHybridComposition:
/// false`** — an **Android `SurfaceTexture`** ("Texture Layer" mode) whose own
/// documentation names the limitation: the reason to choose the other mode is that
/// it *"doesn't have the limitation of rendering to an Android SurfaceTexture"*.
/// In that mode Flutter draws from a texture the platform view hands it; if that
/// texture stays empty, the page's pixels are nowhere and nothing above reports an
/// error — which is exactly the state above. The portal has no such mode: the
/// browser composites its own page.
///
/// ⚠️ **The mode is the package's default and the package exposes no switch**, so
/// the switch lives here: `WebViewPlatform` is a four-method interface, and the
/// only one that decides composition is `createPlatformWebViewWidget`. Wrapping the
/// registered platform and rebuilding *that one* value as an
/// [AndroidWebViewWidget] with `displayWithHybridComposition: true` puts the
/// WebView's own surface into the Flutter scene (Flutter's
/// `initExpensiveAndroidView` path) while leaving the controller, the navigation
/// delegate, the cookie manager, the page, the loopback server and every
/// `<model-viewer>` attribute exactly as the package built them.
///
/// ## The trade, stated
///
/// Hybrid composition is the mode Flutter's own docs call more expensive: the
/// view's contents are copied into the Flutter scene as the view changes, where
/// the texture path hands Flutter a handle. For a box this is the right side of
/// that trade — the alternative cost is a blank box on a phone in the field, and
/// the box is one quiescent 424x672 surface rather than a scrolling list of them.
///
/// **How it is turned off:** `--dart-define=SHOE_PREVIEW_HYBRID=false` (see
/// [AppConstants.shoePreviewHybridComposition]), which restores the package's own
/// default for every WebView in this app — the rollback every other switch in this
/// feature is held to as well.
///
/// ⚠️ **The ladder stays in place underneath this.** If a phone still cannot draw
/// after this, the box's own pixel reading (`blank:`) moves the box to the native
/// renderer, so this is the cause being cured *and* the net still under it.
class HybridCompositionWebViewPlatform extends WebViewPlatform {
  /// Creates a platform that behaves exactly like [inner] except that every
  /// WebView widget it builds is mounted with hybrid composition.
  HybridCompositionWebViewPlatform(this.inner);

  /// The platform this one delegates everything except composition to — in the
  /// app that is `AndroidWebViewPlatform`, the instance
  /// `webview_flutter_android` registers.
  final WebViewPlatform inner;

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) =>
      inner.createPlatformCookieManager(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      inner.createPlatformNavigationDelegate(params);

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) =>
      inner.createPlatformWebViewController(params);

  /// **The one method this class exists for.** The same controller, the same
  /// gestures, the same layout direction — and `displayWithHybridComposition:
  /// true`, which is the whole of the difference between a box that draws on the
  /// P30 Pro and one that does not.
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      AndroidWebViewWidget(
        AndroidWebViewWidgetCreationParams(
          key: params.key,
          controller: params.controller,
          layoutDirection: params.layoutDirection,
          gestureRecognizers: params.gestureRecognizers,
          displayWithHybridComposition: true,
        ),
      );
}

/// **Installs [HybridCompositionWebViewPlatform] over whatever platform is
/// registered.** Answers whether it changed anything.
///
/// Called once from `main`, after the binding exists and **before any
/// `WebViewController` is built** — `webview_flutter_android` registers its own
/// platform as a plugin, so the instance is already there by then.
///
/// ⚠️ **Every argument is injectable and every refusal is quiet, because this runs
/// during launch.** A no-op has three legitimate causes — not Android (iOS has no
/// platform views and no need for this), the switch is off, or the platform was
/// already wrapped by an earlier call — and none of them is an error. The reason it
/// could not be installed is logged, because a launch that silently did nothing is
/// indistinguishable from one that worked until the box is opened.
///
/// Returns true when the instance changed, so a test can assert the
/// once-only behaviour rather than trusting a comment.
bool installHybridCompositionWebViews({
  bool? isAndroid,
  bool? enabled,
  WebViewPlatform? current,
}) {
  final android = isAndroid ?? Platform.isAndroid;
  if (!android) return false;
  if (!(enabled ?? AppConstants.shoePreviewHybridComposition)) return false;

  final inner = current ?? WebViewPlatform.instance;
  if (inner == null) {
    navDiag('[preview-web] hybrid composition NOT installed — no WebViewPlatform');
    return false;
  }
  if (inner is HybridCompositionWebViewPlatform) return false;

  WebViewPlatform.instance = HybridCompositionWebViewPlatform(inner);
  navDiag('[preview-web] platform view wrapped: displayWithHybridComposition=true');
  return true;
}
