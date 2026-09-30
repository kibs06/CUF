package com.solevision.app.tryon

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.platform.PlatformViewRegistry

/** Method channel — the Dart twin is `kArTryOnMethodChannel` in `ar_try_on_channel.dart`. */
const val AR_TRY_ON_METHOD_CHANNEL = "com.solevision/ar_try_on"

/** Event channel — the Dart twin is `kArTryOnEventChannel`. */
const val AR_TRY_ON_EVENT_CHANNEL = "com.solevision/ar_try_on/events"

/** Platform-view type Dart embeds with `AndroidView(viewType: ...)`. */
const val AR_TRY_ON_VIEW_TYPE = "com.solevision/ar_try_on/view"

/**
 * **The inline 3D preview's own three names** ("view in 3D" on the product page, ahead of
 * "try on in AR"). Dart's twins are in `lib/services/shoe_preview_channel.dart`.
 *
 * ⚠️ They are separate channels and a separate view type rather than more methods on the AR
 * channel, and the reason is a real ordering case rather than tidiness: pushing the AR screen keeps
 * the product page — and therefore its preview view — alive underneath. On one channel the plugin
 * would hold two live views for one slot, and whichever was created last would silently receive the
 * other's model and size. Two slots cannot get each other's messages.
 */
const val SHOE_PREVIEW_METHOD_CHANNEL = "com.solevision/shoe_preview"

/** Event channel for the preview; its events never reach the AR screen's stream. */
const val SHOE_PREVIEW_EVENT_CHANNEL = "com.solevision/shoe_preview/events"

/** Platform-view type for the inline preview (`Mode.PREVIEW` on `ArTryOnView`). */
const val SHOE_PREVIEW_VIEW_TYPE = "com.solevision/shoe_preview/view"

/**
 * **V3.1 — the native half of the production try-on contract.**
 *
 * It is thin on purpose. The Dart controller
 * (`lib/providers/try_on/try_on_session_controller.dart`) owns the sequence and every degradation;
 * this class owns the three things only the native side can do: the **platform view's
 * registration**, the two **UI-thread preconditions** (camera permission, ARCore install), and the
 * **parking** that V0's findings F17–F19 demand.
 *
 * ## The parking, which is why this file is not five lines
 *
 *  • **`setModel` before the view exists is legal.** Dart hands the model over the moment it is
 *    verified, because waiting for a view is a race it can lose on a cold page. The payload is
 *    parsed here, parked, and replayed on view creation. (V0's plugin *dropped* a parked model;
 *    this project has the bug report to prove it.)
 *  • **`startSession` before the view exists used to deadlock into a 15 s timeout on every device**
 *    (F17). Dart now refuses to call it in that state, but the native side still has to behave: the
 *    result is parked, retried every 250 ms, and answered `{started:false, reason:"timeout"}` after
 *    15 s rather than left hanging — an unanswered `MethodChannel.Result` leaks and breaks the
 *    *next* call.
 *
 * ## What this file does not do
 *
 * No rendering, no session frames, no model loading: those are `ArTryOnView`, and the split is
 * deliberate. The view's work is per-frame and must stay on its own thread; everything here is
 * per-call and must stay on the UI thread (permission, Play install prompt, channel replies).
 *
 * The Dart side treats a build **without** this plugin as normal (`MissingPluginException` →
 * simulated screen), so registration is additive: if this class fails to load, try-on degrades and
 * nothing else in the app notices.
 */
class ArTryOnPlugin(private val activity: Activity) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private var view: ArTryOnView? = null

    // ── The inline preview's slot, kept apart from the AR view's on purpose ────────────────────
    private var previewMethodChannel: MethodChannel? = null
    private var previewEventChannel: EventChannel? = null
    private var previewEventSink: EventChannel.EventSink? = null
    private var previewView: ArTryOnView? = null
    private var parkedPreviewModel: ArTryOnView.ModelSpec? = null
    private var parkedPreviewSize: ArTryOnView.SizeSpec? = null
    private var parkedPreviewColor: Map<String, Any?>? = null

    /** Payloads that arrived before the platform view did (F18). */
    private var parkedModel: ArTryOnView.ModelSpec? = null
    private var parkedSize: ArTryOnView.SizeSpec? = null
    private var parkedColor: Map<String, Any?>? = null
    private var parkedMode: String? = null

    /** `startSession` calls waiting for a view, with the 15 s net the Dart side was promised. */
    private val pendingStarts = mutableListOf<PendingStart>()

    /** `requestInstall` needs to know whether this process already asked, or it re-asks forever. */
    private var installRequestInFlight = false

    private data class PendingStart(val result: MethodChannel.Result, val deadlineMs: Long)

    fun registerWith(flutterEngine: FlutterEngine) {
        Log.i(TAG, "registering '$AR_TRY_ON_VIEW_TYPE' + '$AR_TRY_ON_METHOD_CHANNEL'")
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val registry: PlatformViewRegistry = flutterEngine.platformViewsController.registry

        registry.registerViewFactory(
            AR_TRY_ON_VIEW_TYPE,
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                    val created = ArTryOnView(context, viewListener)
                    view = created
                    onViewAvailable(created)
                    return object : PlatformView {
                        override fun getView(): View = created

                        override fun dispose() {
                            // `this@ArTryOnPlugin.` is not decoration: inside a `PlatformView`,
                            // `view` resolves to this object's own `getView()` property, and the
                            // unqualified form is a "val cannot be reassigned" compile error.
                            if (this@ArTryOnPlugin.view === created) {
                                this@ArTryOnPlugin.view = null
                            }
                            created.dispose()
                        }
                    }
                }
            },
        )

        // ── The inline preview: same wiring, its own slot and its own listener ──────────────────
        registry.registerViewFactory(
            SHOE_PREVIEW_VIEW_TYPE,
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                    val created = ArTryOnView(context, previewListener, ArTryOnView.Mode.PREVIEW)
                    previewView = created
                    onPreviewViewAvailable(created)
                    return object : PlatformView {
                        override fun getView(): View = created

                        override fun dispose() {
                            if (this@ArTryOnPlugin.previewView === created) {
                                this@ArTryOnPlugin.previewView = null
                            }
                            created.dispose()
                        }
                    }
                }
            },
        )

        previewMethodChannel = MethodChannel(messenger, SHOE_PREVIEW_METHOD_CHANNEL).apply {
            setMethodCallHandler(previewCallHandler)
        }
        previewEventChannel = EventChannel(messenger, SHOE_PREVIEW_EVENT_CHANNEL).apply {
            setStreamHandler(previewStreamHandler)
        }

        methodChannel = MethodChannel(messenger, AR_TRY_ON_METHOD_CHANNEL).apply {
            setMethodCallHandler(this@ArTryOnPlugin)
        }
        eventChannel = EventChannel(messenger, AR_TRY_ON_EVENT_CHANNEL).apply {
            setStreamHandler(this@ArTryOnPlugin)
        }
    }

    fun unregister() {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        eventSink = null
        previewMethodChannel?.setMethodCallHandler(null)
        previewEventChannel?.setStreamHandler(null)
        previewMethodChannel = null
        previewEventChannel = null
        previewEventSink = null
        mainHandler.removeCallbacks(retryRunnable)
        for (pending in pendingStarts) {
            replyStart(pending.result, ArTryOnView.StartOutcome(false, "error", "plugin detached"))
        }
        pendingStarts.clear()
        view?.dispose()
        view = null
        previewView?.dispose()
        previewView = null
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Events: view → Dart
    // ════════════════════════════════════════════════════════════════════════════════════════

    private val viewListener = object : ArTryOnView.Listener {
        override fun onEvent(type: String, data: Map<String, Any?>) {
            // The view reports from its render thread; touching EventSink off the main thread is a
            // crash, not a warning.
            mainHandler.post { eventSink?.success(mapOf("type" to type, "data" to data)) }
        }

        override fun onError(reason: String, message: String?) {
            mainHandler.post {
                eventSink?.success(
                    mapOf(
                        "type" to "error",
                        "data" to mapOf("reason" to reason, "message" to message),
                    ),
                )
            }
        }
    }

    /**
     * The preview's own listener: it reports to the preview's event sink only.
     *
     * Mixing the two would be the same mistake as sharing the slot — the AR screen's controller
     * parses `modelLoaded` and `error` as facts about *its* session, and a preview underneath it
     * would be feeding it both.
     */
    private val previewListener = object : ArTryOnView.Listener {
        override fun onEvent(type: String, data: Map<String, Any?>) {
            mainHandler.post { previewEventSink?.success(mapOf("type" to type, "data" to data)) }
        }

        override fun onError(reason: String, message: String?) {
            mainHandler.post {
                previewEventSink?.success(
                    mapOf(
                        "type" to "error",
                        "data" to mapOf("reason" to reason, "message" to message),
                    ),
                )
            }
        }
    }

    /**
     * The preview on the same F18 parking contract as the AR view: Dart hands the model over the
     * moment the box is built, and the view may not exist yet (it is created by the framework on
     * the next frame), so the payload waits here and is replayed on creation.
     */
    private fun onPreviewViewAvailable(created: ArTryOnView) {
        parkedPreviewModel?.let(created::setModel)
        parkedPreviewSize?.let(created::setSize)
        parkedPreviewColor?.let(created::setColor)
        parkedPreviewModel = null
        parkedPreviewSize = null
        parkedPreviewColor = null
    }

    /** `setPreviewModel` / `setPreviewSize` / `setPreviewColor`, and nothing else. */
    private val previewCallHandler = MethodChannel.MethodCallHandler { call, result ->
        when (call.method) {
            "setPreviewModel" -> {
                val spec = parseModelSpec(call)
                if (spec == null) {
                    Log.w(TAG, "setPreviewModel: unusable payload ${call.arguments}")
                } else if (previewView == null) {
                    parkedPreviewModel = spec
                } else {
                    previewView?.setModel(spec)
                }
                result.success(null)
            }

            "setPreviewSize" -> {
                val spec = parseSizeSpec(call.arguments)
                if (previewView == null) parkedPreviewSize = spec else previewView?.setSize(spec)
                result.success(null)
            }

            "setPreviewColor" -> {
                val overrides = (call.arguments as? Map<*, *>)?.get("materialOverrides")
                val map = (overrides as? Map<*, *>)?.entries
                    ?.associate { (key, value) -> key.toString() to value }
                    ?: emptyMap()
                if (previewView == null) parkedPreviewColor = map else previewView?.setColor(map)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private val previewStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            previewEventSink = events
        }

        override fun onCancel(arguments: Any?) {
            previewEventSink = null
        }
    }

    private fun onViewAvailable(created: ArTryOnView) {
        parkedModel?.let(created::setModel)
        parkedSize?.let(created::setSize)
        parkedColor?.let(created::setColor)
        parkedMode?.let(created::setTryOnMode)
        parkedModel = null
        parkedSize = null
        parkedColor = null
        parkedMode = null
        // Any `startSession` that was waiting on the view can go now.
        flushPendingStarts()
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Method calls: Dart → native
    // ════════════════════════════════════════════════════════════════════════════════════════

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startSession" -> handleStartSession(result)

            "stopSession" -> {
                view?.pauseSession()
                result.success(null)
            }

            "setModel" -> {
                val spec = parseModelSpec(call)
                if (spec == null) {
                    // Not fatal: the Dart controller degrades on a missing model anyway, and saying
                    // so in the log beats a silent success.
                    Log.w(TAG, "setModel: unusable payload ${call.arguments}")
                } else if (view == null) {
                    parkedModel = spec
                } else {
                    view?.setModel(spec)
                }
                result.success(null)
            }

            "setSize" -> {
                val spec = parseSizeSpec(call.arguments)
                if (view == null) parkedSize = spec else view?.setSize(spec)
                result.success(null)
            }

            "setColor" -> {
                val overrides = (call.arguments as? Map<*, *>)?.get("materialOverrides")
                val map = (overrides as? Map<*, *>)?.entries
                    ?.associate { (key, value) -> key.toString() to value }
                    ?: emptyMap()
                if (view == null) parkedColor = map else view?.setColor(map)
                result.success(null)
            }

            "placeShoe" -> {
                val x = call.argument<Number>("x")?.toDouble()
                val y = call.argument<Number>("y")?.toDouble()
                if (x != null && y != null) view?.placeShoe(x, y)
                result.success(null)
            }

            "captureScreenshot" -> {
                val target = view
                if (target == null) {
                    result.success(null)
                } else {
                    target.captureScreenshot { bytes -> result.success(bytes) }
                }
            }

            "setTryOnMode" -> {
                val mode = call.argument<String>("mode")
                if (view == null) parkedMode = mode else mode?.let { view?.setTryOnMode(it) }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * The session start: the two UI-thread preconditions, then the view's session.
     *
     * The order is the shipped scan's and it matters: **permission**, then **ARCore install state**,
     * then the session. Checking them the other way round is how an app ends up showing a Play
     * install prompt for a device that could never run the feature.
     */
    private fun handleStartSession(result: MethodChannel.Result) {
        if (!hasCameraPermission()) {
            Log.i(TAG, "startSession: camera permission not granted")
            replyStart(result, ArTryOnView.StartOutcome(false, "error", "camera_permission_denied"))
            return
        }

        when (val availability = ArCoreApk.getInstance().checkAvailability(activity)) {
            ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE -> {
                replyStart(
                    result,
                    ArTryOnView.StartOutcome(false, "unsupported_device", "ARCore not supported"),
                )
                return
            }

            ArCoreApk.Availability.UNKNOWN_CHECKING,
            ArCoreApk.Availability.UNKNOWN_TIMED_OUT,
            -> {
                // Transient. A verdict now would be a lie in one direction or the other, so it is
                // reported as a retryable failure rather than as a fact about the device.
                replyStart(
                    result,
                    ArTryOnView.StartOutcome(false, "error", "arcore_availability_${availability.name}"),
                )
                return
            }

            else -> Unit
        }

        try {
            // `requestInstall` is what shows the Play prompt, and it must run on the UI thread.
            val status = ArCoreApk.getInstance().requestInstall(activity, installRequestInFlight)
            if (status == ArCoreApk.InstallStatus.INSTALL_REQUESTED) {
                installRequestInFlight = true
                replyStart(
                    result,
                    ArTryOnView.StartOutcome(false, "needs_install", "ARCore install requested"),
                )
                return
            }
            installRequestInFlight = false
        } catch (e: UnavailableUserDeclinedInstallationException) {
            replyStart(result, ArTryOnView.StartOutcome(false, "user_opted_out", e.message))
            return
        } catch (e: Exception) {
            // `requestInstall` also throws `UnavailableArcoreNotInstalledException` on some OEM
            // builds, and a Play Services failure lands here too.
            replyStart(result, ArTryOnView.StartOutcome(false, "needs_install", e.message))
            return
        }

        val target = view
        if (target == null) {
            // F17: park and retry rather than hang. Dart refuses to get here, so a real occurrence
            // means a platform-view regression worth seeing in the log.
            Log.w(TAG, "startSession before the platform view exists; parking up to ${START_TIMEOUT_MS}ms")
            pendingStarts.add(
                PendingStart(result, System.currentTimeMillis() + START_TIMEOUT_MS),
            )
            scheduleStartRetry()
            return
        }
        target.startSession { outcome -> replyStart(result, outcome) }
    }

    private val retryRunnable = Runnable { flushPendingStarts() }

    private fun scheduleStartRetry() {
        mainHandler.removeCallbacks(retryRunnable)
        mainHandler.postDelayed(retryRunnable, START_RETRY_MS)
    }

    /** Answers every parked start: the view if there is one now, otherwise the 15 s net. */
    private fun flushPendingStarts() {
        if (pendingStarts.isEmpty()) return
        val now = System.currentTimeMillis()
        val target = view
        val iterator = pendingStarts.iterator()
        while (iterator.hasNext()) {
            val pending = iterator.next()
            if (target != null) {
                iterator.remove()
                target.startSession { outcome -> replyStart(pending.result, outcome) }
            } else if (now >= pending.deadlineMs) {
                iterator.remove()
                Log.w(TAG, "startSession timed out waiting for the platform view")
                replyStart(
                    pending.result,
                    ArTryOnView.StartOutcome(false, "timeout", "platform view not created"),
                )
            }
        }
        if (pendingStarts.isNotEmpty()) scheduleStartRetry()
    }

    private fun replyStart(result: MethodChannel.Result, outcome: ArTryOnView.StartOutcome) {
        mainHandler.post {
            val payload = HashMap<String, Any?>()
            payload["started"] = outcome.started
            outcome.reason?.let { payload["reason"] = it }
            outcome.message?.let { payload["message"] = it }
            runCatching { result.success(payload) }
                .onFailure { Log.w(TAG, "startSession result already answered", it) }
        }
    }

    private fun hasCameraPermission(): Boolean =
        // `Context.checkSelfPermission` (API 23) rather than `ContextCompat`: fewer dependencies on
        // the classpath of a class that must compile in every build variant.
        activity.checkSelfPermission(android.Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    private fun parseModelSpec(call: MethodCall): ArTryOnView.ModelSpec? {
        val path = call.argument<String>("path") ?: return null
        val modelId = call.argument<Number>("modelId")?.toLong() ?: return null
        val alignment = call.argument<Map<*, *>>("alignmentJson")
        return ArTryOnView.ModelSpec(
            path = path,
            modelId = modelId,
            sha256 = call.argument<String>("sha256") ?: "",
            authoredLengthMm = call.argument<Number>("authoredLengthMm")?.toDouble(),
            yawOffsetDeg = (alignment?.get("yawOffsetDeg") as? Number)?.toDouble(),
            // ⚠️ Only the preview's `setPreviewModel` ever sends this (`SHOE_PREVIEW_ALLOW_LEVEL1`),
            // and the view honours it only in a debuggable build — see
            // `ArTryOnView.allowsUnsupportedRenderer`. Absent or non-true means "refuse as usual".
            allowUnsupportedRenderer =
                call.argument<Boolean>("allowUnsupportedRenderer") == true,
            // The other half of the same QA question, with the same two locks: build/lower the
            // engine at `FEATURE_LEVEL_1` instead of only tolerating it. See
            // `ArTryOnView.shouldLowerEngineToLevel1`.
            lowerEngineToLevel1 =
                call.argument<Boolean>("lowerEngineToLevel1") == true,
        )
    }

    private fun parseSizeSpec(arguments: Any?): ArTryOnView.SizeSpec {
        val map = arguments as? Map<*, *> ?: return ArTryOnView.SizeSpec(null, null, null)
        return ArTryOnView.SizeSpec(
            sizeEu = parseEu(map["sizeEu"]),
            refSizeEu = (map["refSizeEu"] as? Number)?.toDouble(),
            lastLengthMm = (map["lastLengthMm"] as? Number)?.toDouble(),
        )
    }

    /** `43` and `"EU 43"` both arrive here; the Dart side does not promise which. */
    private fun parseEu(value: Any?): Double? = when (value) {
        is Number -> value.toDouble()
        is String -> value.filter { it.isDigit() || it == '.' }.toDoubleOrNull()
        else -> null
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // EventChannel
    // ════════════════════════════════════════════════════════════════════════════════════════

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private companion object {
        const val TAG = "ArTryOnPlugin"

        /** F17's safety net: what Dart is promised when the view never appears. */
        const val START_TIMEOUT_MS = 15_000L
        const val START_RETRY_MS = 250L
    }
}
