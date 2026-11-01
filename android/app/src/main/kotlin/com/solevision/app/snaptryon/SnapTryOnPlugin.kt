package com.solevision.app.snaptryon

import android.content.Intent
import com.snap.camerakit.support.app.CameraActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Method channel — the Dart twin is `kSnapTryOnMethodChannel` in `snap_try_on_channel.dart`. */
const val SNAP_TRY_ON_METHOD_CHANNEL = "com.solevision/snap_try_on"

/** Request code for the Camera Kit activity; nothing else in MainActivity uses startActivityForResult. */
private const val SNAP_TRY_ON_REQUEST_CODE = 1401

/**
 * Native Snap try-on (Phase 1): full-screen Camera Kit activity instead of Chrome.
 *
 * Thin on purpose, like `ArTryOnPlugin`: this class owns the two things only the
 * native side can do — building the Camera Kit intent through Snap's own
 * contract and forwarding the result back to the parked Dart call. Everything
 * else (credentials, fallback, gating) is Dart.
 *
 * Legacy result API on purpose: FlutterActivity extends android.app.Activity,
 * not ComponentActivity, so registerForActivityResult does not exist here.
 * The contract object still builds/parses everything — MainActivity forwards
 * onActivityResult into [handleActivityResult].
 *
 * Credentials arrive per call, never from the manifest: the API token must not
 * be committed, so it travels `--dart-define` → Dart → this call, exactly like
 * the other keys in `dart_defines.json`. Empty credentials are refused here
 * (and skipped in Dart first), so an unconfigured build behaves exactly like a
 * build without this plugin: the web lens opens instead.
 */
class SnapTryOnPlugin(private val activity: FlutterActivity) : MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null

    fun registerWith(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SNAP_TRY_ON_METHOD_CHANNEL)
        channel?.setMethodCallHandler(this)
    }

    fun unregister() {
        channel?.setMethodCallHandler(null)
        channel = null
        pendingResult = null
    }

    /**
     * Called from MainActivity.onActivityResult. Returns true when the result
     * was ours (answered or dropped), so the activity knows whether to pass it on.
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SNAP_TRY_ON_REQUEST_CODE) return false
        val res = pendingResult
        pendingResult = null
        if (res == null) return true
        val parsed = try {
            CameraActivity.Capture.parseResult(resultCode, data)
        } catch (_: Exception) {
            null
        }
        res.success(parsed is CameraActivity.Capture.Result.Success)
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "launchSnapTryOn") {
            result.notImplemented()
            return
        }
        if (pendingResult != null) {
            result.error("busy", "Snap try-on is already open", null)
            return
        }
        val apiToken = call.argument<String>("apiToken").orEmpty()
        val lensGroupId = call.argument<String>("lensGroupId").orEmpty()
        val lensId = call.argument<String>("lensId").orEmpty()
        if (apiToken.isBlank() || lensGroupId.isBlank()) {
            result.error("not-configured", "Camera Kit API token or lens group ID is missing", null)
            return
        }
        pendingResult = result
        try {
            val intent = CameraActivity.Capture.createIntent(
                activity,
                CameraActivity.Configuration.WithLenses(
                    lensGroupIds = setOf(lensGroupId),
                    cameraKitApiToken = apiToken,
                    applyLensById = lensId.ifBlank { null },
                ),
            )
            activity.startActivityForResult(intent, SNAP_TRY_ON_REQUEST_CODE)
        } catch (e: Exception) {
            pendingResult = null
            result.error("launch-failed", e.message, null)
        }
    }
}
