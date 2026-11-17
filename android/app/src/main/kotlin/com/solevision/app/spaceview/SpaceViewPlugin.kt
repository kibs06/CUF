package com.solevision.app.spaceview

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Method channel — the Dart twin is `kSpaceViewMethodChannel` in `space_view_service.dart`. */
const val SPACE_VIEW_METHOD_CHANNEL = "com.solevision/space_view"

/** Google Play Services for AR; Scene Viewer's AR-only entry point. */
private const val ARCORE_PACKAGE = "com.google.ar.core"

/**
 * **"View in your space"** — hands a Scene Viewer URL to the ARCore package.
 *
 * Thin on purpose: the URL, the public bucket path and the customer sentence
 * all live in Dart. This class owns the one thing a browser launch cannot do:
 * an explicit intent to `com.google.ar.core`, which is the documented way to
 * use `mode=ar_only`.
 *
 * Google's Scene Viewer docs are explicit that `ar_only` must not be sent to
 * the Google app, and `url_launcher` only knows how to open a URL in whatever
 * app resolves it. Launching `https://arvr.google.com/scene-viewer/...` that
 * way leaves the outcome to the browser: it can open a web page, fall through
 * to a 3D view, or do nothing, while `launchUrl` still answers `true` because
 * a browser handled it. Here the package is named, so a missing or out-of-date
 * ARCore answers `ActivityNotFoundException` and Dart shows its honest
 * sentence instead of a successful no-op.
 */
class SpaceViewPlugin(private val activity: FlutterActivity) : MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null

    fun registerWith(flutterEngine: FlutterEngine) {
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SPACE_VIEW_METHOD_CHANNEL,
        )
        channel?.setMethodCallHandler(this)
    }

    fun unregister() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "launchSceneViewer") {
            result.notImplemented()
            return
        }

        val url = call.argument<String>("url").orEmpty()
        if (url.isBlank()) {
            result.success(false)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            setPackage(ARCORE_PACKAGE)
        }

        try {
            activity.startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            // No ARCore, or a package without Scene Viewer's activity: the
            // caller turns false into "Could not open the space view...".
            result.success(false)
        } catch (_: Exception) {
            result.success(false)
        }
    }
}
