package com.solevision.app.arfoot

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.platform.PlatformViewRegistry

class ArFootSizingPlugin(private val activity: Activity) {

    companion object {
        private const val TAG = "ArFootSizingPlugin"
        private const val METHOD_CHANNEL = "com.solevision/ar_foot_sizing"
        private const val EVENT_CHANNEL = "com.solevision/ar_foot_sizing/events"
        private const val PLATFORM_VIEW_TYPE = "ar_foot_scan"

        // Safety net for parked startSession replies: a MethodChannel.Result
        // must ALWAYS eventually be answered or Flutter leaks it ("Reply already
        // submitted" on the next call). Covers pathological cases where the
        // platform view is never created or session creation hangs forever.
        private const val SESSION_START_TIMEOUT_MS = 15000L

        // Availability probe (`checkAvailability`): the ARCore compatibility
        // check can go remote on Android 11+ (first call answers
        // UNKNOWN_CHECKING), so the probe polls on the main looper instead of
        // blocking a thread, and reports whatever state is current after this
        // cap. ~3 s is enough for the Play verification round-trip.
        private const val AVAILABILITY_POLL_DELAY_MS = 250L
        private const val AVAILABILITY_MAX_POLLS = 12
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var currentView: ArFootSizingView? = null

    // ── D3 fix: old-view teardown gate ──
    // ARCore supports one Session per process. During a screen transition the
    // outgoing screen's platform view can still be tearing down while the
    // incoming screen's view starts creating its own session — that overlap is
    // exactly what killed the process (Hypothesis D, log sessions 3/4 show
    // three stacked create/dispose cycles). Views register their teardown here;
    // a new view's async createSession() BLOCKS on this counter reaching zero
    // before touching ARCore. Explicit sequencing — no sleeps.
    private val teardownLock = Object()
    private var pendingTeardowns = 0

    // ── E3 fix: honest startSession state ──
    // The ARCore session is created ASYNCHRONOUSLY by the PlatformView factory
    // (ArFootSizingView.createSession on a background executor), so a
    // `startSession` method call can arrive before any outcome exists. Park the
    // reply until onSessionStarted/onSessionFailed resolves it.
    // All mutations happen on the main thread: handleMethodCall runs there,
    // resolvePendingStart posts there, and the timeout fires there.
    private val pendingStartResults = mutableListOf<MethodChannel.Result>()

    // Last terminal outcome reported by createSession(). Reset per view (see
    // setView) so a stale success from a previous screen entry can't satisfy a
    // new startSession call for a session that doesn't exist yet.
    private var lastSessionOutcome: Map<String, Any>? = null

    // Engine attachment state + a generation token for in-flight availability
    // polls. unregister() flips both so a poll that outlives its engine can
    // never answer a torn-down channel.
    private var registered = false
    private var availabilityPollToken = 0

    private val mainHandler = Handler(Looper.getMainLooper())

    fun registerWith(flutterEngine: FlutterEngine) {
        Log.i(TAG, "registerWith called — registering '${PLATFORM_VIEW_TYPE}' view factory and '${METHOD_CHANNEL}' method channel")
        registered = true
        // TEMPORARY (Phase 1b diagnostics) — remove with DiagRelay.kt.
        DiagRelay.log("plugin", "registerWith (engine attached)")
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val registry: PlatformViewRegistry =
            flutterEngine.platformViewsController.registry
        registry.registerViewFactory(PLATFORM_VIEW_TYPE, ArFootSizingViewFactory(activity, this))

        methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        eventChannel = EventChannel(messenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    fun unregister() {
        // TEMPORARY (Phase 1b diagnostics) — remove with DiagRelay.kt.
        DiagRelay.log("plugin", "unregister (engine detaching)")
        registered = false
        availabilityPollToken++
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
        // Answer any parked startSession replies before tearing down — a
        // MethodChannel.Result left unanswered trips Flutter's assertion.
        val parked = ArrayList(pendingStartResults)
        pendingStartResults.clear()
        for (r in parked) {
            r.success(mapOf(
                "started" to false,
                "reason" to "error",
                "message" to "AR plugin was unregistered"
            ))
        }
        lastSessionOutcome = null
        currentView?.dispose()
        currentView = null
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // TEMPORARY (Phase 1b diagnostics): Dart hands over the nav log
            // path so native events land in the same file. Remove with
            // DiagRelay.kt.
            "setDiagLogFile" -> {
                DiagRelay.setFile(call.argument<String>("path"))
                result.success(null)
            }
            "startSession" -> handleStartSession(result)
            "retrySession" -> handleRetrySession(result)
            "checkAvailability" -> handleCheckAvailability(result)
            "stopSession" -> {
                // D1 fix: Dart NO LONGER calls this on screen transitions.
                // Native view/session teardown is single-owned by Flutter's
                // PlatformView disposal (the engine disposes the view when its
                // widget unmounts on pop/pushReplacement). Keeping the handler
                // only as a defensive safety net — it must never fire during
                // normal navigation, where disposing `currentView` could hit
                // the INCOMING screen's brand-new view (the D1 crash).
                DiagRelay.log("plugin", "stopSession method call → disposing view")
                currentView?.dispose()
                currentView = null
                result.success(null)
            }
            "hitTest" -> {
                val x = (call.argument<Any>("x") as? Number)?.toFloat() ?: 0.5f
                val y = (call.argument<Any>("y") as? Number)?.toFloat() ?: 0.5f
                val preferDepth = call.argument<Boolean>("preferDepth") ?: false
                result.success(currentView?.hitTest(x, y, preferDepth))
            }
            "hitTestBatch" -> {
                @Suppress("UNCHECKED_CAST")
                val points = call.argument<List<Map<String, Double>>>("points") ?: emptyList()
                val preferDepth = call.argument<Boolean>("preferDepth") ?: false
                result.success(currentView?.hitTestBatch(points, preferDepth))
            }
            "acquireCameraFrame" -> {
                currentView?.requestCameraFrame()
                val view = currentView
                if (view != null && view.hasCachedCameraFrame()) {
                    result.success(mapOf(
                        "bytes" to view.getCachedCameraFrameBytes(),
                        "width" to view.getCachedCameraFrameWidth(),
                        "height" to view.getCachedCameraFrameHeight(),
                        "rotationDegrees" to view.getCachedCameraFrameRotationDegrees()
                    ))
                } else {
                    result.success(null)
                }
            }
            "getTrackingState" -> result.success(currentView?.getTrackingState() ?: "paused")
            "getMeanLuma" -> result.success(currentView?.getMeanLuma())
            "setTorch" -> {
                currentView?.setTorch(call.argument<Boolean>("enabled") ?: false)
                result.success(null)
            }
            "getFloorPlane" -> result.success(currentView?.getFloorPlane())
            "getFloorDistance" -> result.success(currentView?.getFloorDistance())
            else -> result.notImplemented()
        }
    }

    fun sendEvent(type: String, data: Map<String, Any>) {
        activity.runOnUiThread {
            try {
                eventSink?.success(mapOf("type" to type, "data" to data))
            } catch (e: Exception) {
                Log.e(TAG, "Error sending event: $type", e)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // SESSION OUTCOME (E3 fix — single source of truth)
    //
    // ArFootSizingView.createSession() reports its terminal outcome here.
    // Each method does exactly two things: emit the corresponding event AND
    // resolve any startSession replies parked in [pendingStartResults]. There
    // is no other `session_started` / session-outcome emission site, so Dart
    // can never see a "started" signal that precedes a real session.
    // ═══════════════════════════════════════════════════════════════

    /** Called by [ArFootSizingView] when the ARCore session is created + resumed. */
    fun onSessionStarted() {
        Log.i(TAG, "Session started — resolving parked startSession replies")
        // TEMPORARY (Phase 1b diagnostics) — remove with DiagRelay.kt.
        DiagRelay.log("plugin", "onSessionStarted")
        sendEvent("session_started", emptyMap())
        resolvePendingStart(mapOf("started" to true))
    }

    /**
     * Called by [ArFootSizingView] when session creation fails terminally.
     * [reason] mirrors the `error` event's reason codes: `unsupported_device`,
     * `user_opted_out`, `needs_install`, `timeout`, `unsupported`, `error`.
     */
    fun onSessionFailed(reason: String, message: String?) {
        Log.w(TAG, "Session failed (reason=$reason): $message")
        // TEMPORARY (Phase 1b diagnostics) — remove with DiagRelay.kt.
        DiagRelay.log("plugin", "onSessionFailed reason=$reason message=$message")
        val eventData = mutableMapOf<String, Any>("reason" to reason)
        if (message != null) eventData["message"] = message
        sendEvent("error", eventData)
        resolvePendingStart(mapOf(
            "started" to false,
            "reason" to reason,
            "message" to (message ?: "Failed to initialize AR")
        ))
    }

    private fun resolvePendingStart(outcome: Map<String, Any>) {
        mainHandler.post {
            lastSessionOutcome = outcome
            val parked = ArrayList(pendingStartResults)
            pendingStartResults.clear()
            for (r in parked) r.success(outcome)
        }
    }

    /**
     * Reply to `startSession` with the REAL session state:
     * `{ started: Bool, reason: String?, message: String? }`.
     *
     * - Session already up → reply immediately with success.
     * - Terminal outcome already known → reply with it (covers a failed view).
     * - Still initializing → park the reply until the outcome arrives, guarded
     *   by a timeout so the reply is always answered.
     */
    private fun handleStartSession(result: MethodChannel.Result) {
        val view = currentView
        if (view != null && view.isSessionStarted()) {
            result.success(mapOf("started" to true))
            return
        }
        lastSessionOutcome?.let { outcome ->
            result.success(outcome)
            return
        }
        parkStartResult(result)
    }

    /**
     * Parks a `startSession`/`retrySession` reply until the view reports a
     * terminal outcome, guarded by a timeout so it is always answered.
     */
    private fun parkStartResult(result: MethodChannel.Result) {
        pendingStartResults.add(result)
        mainHandler.postDelayed({
            // Identity removal: only fire if THIS reply is still parked
            // (resolvePendingStart may have cleared it meanwhile).
            if (pendingStartResults.remove(result)) {
                result.success(mapOf(
                    "started" to false,
                    "reason" to "timeout",
                    "message" to "AR session initialization timed out"
                ))
            }
        }, SESSION_START_TIMEOUT_MS)
    }

    // ═══════════════════════════════════════════════════════════════
    // ARCORE AVAILABILITY (pre-flight probe for the setup screen)
    // ═══════════════════════════════════════════════════════════════

    /**
     * `checkAvailability` — lets Dart ask whether this device can run ARCore
     * BEFORE it opens the camera flow.
     *
     * Without this, an unsupported device walks into the scan screen, the
     * platform view asks Play to install ARCore, and Play answers "The device
     * is not supported." (observed on a vivo V2022: com.google.ar.core is a
     * version-0 stub and Finsky refuses the install) — leaving the customer on
     * a camera screen that can never recover. Reporting the same availability
     * enum the view already uses keeps one source of truth for the reason
     * codes.
     */
    private fun handleCheckAvailability(result: MethodChannel.Result) {
        availabilityPollToken++
        pollAvailability(availabilityPollToken, AVAILABILITY_MAX_POLLS, result)
    }

    private fun pollAvailability(
        token: Int,
        attemptsLeft: Int,
        result: MethodChannel.Result
    ) {
        if (!registered || token != availabilityPollToken) return
        val availability = try {
            com.google.ar.core.ArCoreApk.getInstance().checkAvailability(activity)
        } catch (e: Exception) {
            Log.e(TAG, "checkAvailability threw", e)
            answerAvailability(result, "UNKNOWN_ERROR", supported = false, installed = false)
            return
        }
        if (availability == com.google.ar.core.ArCoreApk.Availability.UNKNOWN_CHECKING &&
            attemptsLeft > 0
        ) {
            // Remote compatibility check in flight — poll without blocking the
            // main thread (the view's own loop already does this on its
            // background session executor).
            mainHandler.postDelayed({
                pollAvailability(token, attemptsLeft - 1, result)
            }, AVAILABILITY_POLL_DELAY_MS)
            return
        }
        Log.i(TAG, "Availability probe: $availability")
        answerAvailability(
            result,
            availability.toString(),
            supported = availability.isSupported,
            installed = availability == com.google.ar.core.ArCoreApk.Availability.SUPPORTED_INSTALLED
        )
    }

    private fun answerAvailability(
        result: MethodChannel.Result,
        availability: String,
        supported: Boolean,
        installed: Boolean
    ) {
        try {
            result.success(mapOf(
                "availability" to availability,
                "supported" to supported,
                "installed" to installed
            ))
        } catch (e: Exception) {
            // Channel torn down mid-probe (engine detach) — nothing to answer.
            Log.w(TAG, "Availability result dropped: ${e.message}")
        }
    }

    /**
     * `retrySession` — a REAL restart for the failure sheet's Retry action.
     *
     * `startSession` answers from [lastSessionOutcome] once a terminal outcome
     * exists, so retrying after a `needs_install` failure used to replay the
     * cached failure instantly: the one recovery the user can perform (install
     * ARCore, come back, retry) could never succeed. This drops the cache, asks
     * the current view to create a fresh session, and parks the reply on the
     * same machinery `startSession` uses.
     */
    private fun handleRetrySession(result: MethodChannel.Result) {
        val view = currentView
        if (view == null || !registered) {
            result.success(mapOf(
                "started" to false,
                "reason" to "error",
                "message" to "AR view is not mounted"
            ))
            return
        }
        lastSessionOutcome = null
        if (!view.retryCreateSession()) {
            // Disposed, or a session already exists — report instead of
            // parking a reply that can never be resolved.
            val outcome = mapOf<String, Any>(
                "started" to false,
                "reason" to "error",
                "message" to "AR session is no longer available"
            )
            lastSessionOutcome = outcome
            result.success(outcome)
            return
        }
        parkStartResult(result)
    }

    fun setView(view: ArFootSizingView) {
        // TEMPORARY (Phase 1b diagnostics) — remove with DiagRelay.kt.
        DiagRelay.log("plugin", "setView")
        currentView = view
        // Fresh view ⇒ fresh session lifecycle. Without this reset, a stale
        // outcome from a previous screen entry would instantly satisfy (or
        // wrongly fail) the new screen's startSession call before its own
        // createSession() has run.
        lastSessionOutcome = null
    }

    // ── Teardown gate (D3 fix — see field docs above) ──

    /** Called by a view when its [ArFootSizingView.dispose] begins. */
    fun beginViewTeardown() {
        synchronized(teardownLock) { pendingTeardowns++ }
    }

    /** Called by a view when its dispose fully completes; wakes any waiter. */
    fun endViewTeardown() {
        synchronized(teardownLock) {
            pendingTeardowns--
            if (pendingTeardowns <= 0) teardownLock.notifyAll()
        }
    }

    /**
     * Blocks the CALLING thread until every in-flight view teardown completes.
     * Runs on each view's background session executor (never the main thread),
     * so blocking is safe: the main thread stays free to run the dispose that
     * will eventually release the gate.
     */
    fun awaitViewTeardowns() {
        synchronized(teardownLock) {
            while (pendingTeardowns > 0) teardownLock.wait()
        }
    }
}

class ArFootSizingViewFactory(
    private val activity: Activity,
    private val plugin: ArFootSizingPlugin
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: android.content.Context, viewId: Int, args: Any?): io.flutter.plugin.platform.PlatformView {
        val view = ArFootSizingView(activity, plugin, viewId)
        plugin.setView(view)
        return view
    }
}
