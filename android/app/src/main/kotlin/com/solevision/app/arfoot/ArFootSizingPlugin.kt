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

    private val mainHandler = Handler(Looper.getMainLooper())

    fun registerWith(flutterEngine: FlutterEngine) {
        Log.i(TAG, "registerWith called — registering '${PLATFORM_VIEW_TYPE}' view factory and '${METHOD_CHANNEL}' method channel")
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
                result.success(currentView?.hitTest(x, y))
            }
            "hitTestBatch" -> {
                @Suppress("UNCHECKED_CAST")
                val points = call.argument<List<Map<String, Double>>>("points") ?: emptyList()
                result.success(currentView?.hitTestBatch(points))
            }
            "acquireCameraFrame" -> {
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
