package com.solevision.app.arfoot

import android.app.Activity
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
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var currentView: ArFootSizingView? = null

    fun registerWith(flutterEngine: FlutterEngine) {
        Log.i(TAG, "registerWith called — registering '${PLATFORM_VIEW_TYPE}' view factory and '${METHOD_CHANNEL}' method channel")
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
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
        currentView?.dispose()
        currentView = null
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startSession" -> {
                result.success(true)
                sendEvent("session_started", emptyMap())
            }
            "stopSession" -> {
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

    fun setView(view: ArFootSizingView) {
        currentView = view
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
