package com.solevision.app.artryon

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.ar.core.exceptions.UnavailableApkTooOldException
import com.google.ar.core.exceptions.UnavailableArcoreNotInstalledException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableSdkTooOldException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.platform.PlatformViewRegistry

/**
 * V0 renderer spike for virtual fitting — **not a shipping feature**.
 *
 * Its only job is to answer the questions in
 * `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V0: does a glTF shoe render in AR
 * on real hardware at a usable frame rate, how long does a model take to load,
 * and what does the renderer cost in APK size? Everything it proves is
 * recorded in `docs/RoadMap/AR_TRY_ON_SPIKE_FINDINGS.md`.
 *
 * Deliberately kept separate from `com.solevision.app.arfoot` (the shipped foot
 * scan) so the one feature customers depend on cannot regress: new package, new
 * view type, new channels, nothing shared but the pattern.
 *
 * Channel surface mirrors a subset of the planned production contract in
 * `VIRTUAL_FITTING_ARCHITECTURE.md` §2.8 so the Dart side can be lifted into
 * `ShoeModelService` / `TryOnSessionController` later.
 */
class ArTryOnSpikePlugin(private val activity: Activity) {

    companion object {
        private const val TAG = "ArTryOnSpike"

        const val METHOD_CHANNEL = "com.solevision/ar_try_on_spike"
        const val EVENT_CHANNEL = "com.solevision/ar_try_on_spike/events"
        const val VIEW_TYPE = "ar_try_on_spike"

        /**
         * A MethodChannel.Result must ALWAYS be answered or Flutter leaks it and
         * the next call trips "Reply already submitted" — same safety net (and
         * the same 15 s budget) as the shipped AR plugin.
         */
        private const val SESSION_START_TIMEOUT_MS = 15_000L

        /**
         * Maps an ARCore failure onto the reason vocabulary the shipped foot
         * scan already uses (`ArSessionStartResult` in `ar_core_channel.dart`),
         * so Flutter can handle both screens with one code path.
         */
        fun reasonFor(t: Throwable): String = when (t) {
            is UnavailableArcoreNotInstalledException -> "needs_install"
            is UnavailableUserDeclinedInstallationException -> "user_opted_out"
            is UnavailableDeviceNotCompatibleException -> "unsupported_device"
            is UnavailableApkTooOldException -> "unsupported"
            is UnavailableSdkTooOldException -> "unsupported"
            else -> "error"
        }
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var currentView: ArTryOnSpikeView? = null

    // Parked model state. The AR view only exists once Dart renders the platform
    // view, and Dart hands the model over before that can happen — so a
    // `setModel` / `setModelScale` arriving early must be remembered and applied
    // to the view when it is created. (Without this the calls silently became
    // no-ops and the spike rendered an empty scene forever.)
    private var pendingModelPath: String? = null
    private var pendingModelScale: Float? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    // Parked startSession replies. ARCore session creation is driven by the
    // Compose view entering composition, so a `startSession` call can arrive
    // before any outcome exists — hold the Result until the session resumes,
    // fails, or the timeout fires.
    private var pendingStart: MethodChannel.Result? = null
    private val startTimeout = Runnable {
        answerStart(started = false, reason = "timeout", message = "AR session did not start within $SESSION_START_TIMEOUT_MS ms")
    }

    fun registerWith(flutterEngine: FlutterEngine) {
        Log.i(TAG, "registering '$VIEW_TYPE' view factory + '$METHOD_CHANNEL' channel")
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val registry: PlatformViewRegistry = flutterEngine.platformViewsController.registry

        registry.registerViewFactory(VIEW_TYPE, object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
            override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                val view = ArTryOnSpikeView(context, activity, this@ArTryOnSpikePlugin)
                currentView = view
                pendingModelPath?.let(view::setModel)
                pendingModelScale?.let(view::setModelScale)
                return view
            }
        })

        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).apply {
            setMethodCallHandler { call, result -> handleMethodCall(call, result) }
        }

        eventChannel = EventChannel(messenger, EVENT_CHANNEL).apply {
            setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }
    }

    fun unregister() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
        mainHandler.removeCallbacks(startTimeout)
        pendingStart = null
        pendingModelPath = null
        pendingModelScale = null
        currentView?.dispose()
        currentView = null
    }

    // ── Channel plumbing ────────────────────────────────────────────────────

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startSession" -> parkStart(result)

            "stopSession" -> {
                // Session teardown is owned by PlatformView disposal (the
                // Compose composition leaving). Nothing to do beyond acking.
                result.success(true)
            }

            "setModel" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("bad_args", "setModel requires a non-empty 'path'", null)
                } else {
                    pendingModelPath = path
                    currentView?.setModel(path)
                    result.success(true)
                }
            }

            "setModelScale" -> {
                val scale = call.argument<Double>("scale")?.toFloat()
                if (scale == null || scale <= 0f) {
                    result.error("bad_args", "setModelScale requires a positive 'scale'", null)
                } else {
                    pendingModelScale = scale
                    currentView?.setModelScale(scale)
                    result.success(true)
                }
            }

            "getStatus" -> result.success(currentView?.statusMap() ?: mapOf("phase" to "no_view"))

            else -> result.notImplemented()
        }
    }

    /** Called by the view when its composition is disposed. */
    fun clearView(view: ArTryOnSpikeView) {
        if (currentView === view) currentView = null
    }

    /** One-shot event to Dart. Safe to call from any main-thread callback. */
    fun emit(type: String, data: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(mapOf("type" to type, "data" to data)) }
    }

    // ── Session outcomes ────────────────────────────────────────────────────

    private fun parkStart(result: MethodChannel.Result) {
        // Never leave an older call unanswered.
        if (pendingStart != null) {
            answerStart(started = false, reason = "error", message = "superseded by a newer startSession call")
        }
        if (currentView?.sessionResumed == true) {
            result.success(mapOf("started" to true, "reason" to null, "message" to null))
            return
        }
        pendingStart = result
        mainHandler.postDelayed(startTimeout, SESSION_START_TIMEOUT_MS)
    }

    fun onSessionResumed() {
        emit("status", mapOf("phase" to "ready"))
        if (pendingStart != null) {
            answerStart(started = true, reason = null, message = null)
        }
    }

    fun onSessionFailed(exception: Throwable) {
        val reason = reasonFor(exception)
        val message = exception.message ?: exception::class.java.simpleName
        Log.w(TAG, "AR session failed: $reason — $message")
        emit("status", mapOf("phase" to "failed", "reason" to reason, "message" to message))
        answerStart(started = false, reason = reason, message = message)
    }

    private fun answerStart(started: Boolean, reason: String?, message: String?) {
        mainHandler.removeCallbacks(startTimeout)
        val parked = pendingStart ?: return
        pendingStart = null
        parked.success(mapOf("started" to started, "reason" to reason, "message" to message))
    }
}
