package com.solevision.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.solevision.app.arfoot.ArFootSizingPlugin
import com.solevision.app.arfoot.DiagRelay

class MainActivity : FlutterActivity() {

    private var arFootSizingPlugin: ArFootSizingPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register the ARCore foot scanning plugin
        arFootSizingPlugin = ArFootSizingPlugin(this)
        arFootSizingPlugin!!.registerWith(flutterEngine)
        // TEMPORARY (Phase 1b diagnostics) — remove with DiagRelay.kt.
        DiagRelay.log("activity", "configureFlutterEngine")
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // TEMPORARY (Phase 1b diagnostics) — remove with DiagRelay.kt.
        DiagRelay.log("activity", "cleanUpFlutterEngine (engine detaching)")
        arFootSizingPlugin?.unregister()
        arFootSizingPlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // ── TEMPORARY (Phase 1b diagnostics): activity lifecycle relay ──
    // isFinishing at onPause/onDestroy distinguishes "system finished the
    // task" (back-default behavior — the observed bug signature) from an
    // ordinary backgrounding. Remove with DiagRelay.kt.
    //
    // NOTE: there is deliberately NO app-level OnBackInvokedCallback or
    // system-navigation-observer registration here. The observer API is
    // @hide/@FlaggedApi in this SDK level (not callable from app code), and
    // registering a regular back callback could compete with Flutter's own
    // and CHANGE dispatch behavior during diagnosis — which is off-limits.

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DiagRelay.log("activity", "onCreate hasState=${savedInstanceState != null}")
    }

    override fun onResume() {
        super.onResume()
        DiagRelay.log("activity", "onResume")
    }

    override fun onPause() {
        DiagRelay.log("activity", "onPause isFinishing=$isFinishing")
        super.onPause()
    }

    override fun onDestroy() {
        DiagRelay.log("activity", "onDestroy isFinishing=$isFinishing")
        super.onDestroy()
    }
}
