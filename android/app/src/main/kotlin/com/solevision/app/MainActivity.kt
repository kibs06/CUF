package com.solevision.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.solevision.app.arfoot.ArFootSizingPlugin
import com.solevision.app.arfoot.DiagRelay
import com.solevision.app.artryon.ArTryOnSpikePlugin
import com.solevision.app.tryon.ArTryOnPlugin

class MainActivity : FlutterActivity() {

    private var arFootSizingPlugin: ArFootSizingPlugin? = null

    // V0 virtual-fitting renderer spike (dev-only; no Dart entry point unless
    // built with --dart-define=AR_TRY_ON_SPIKE=true). Registered here and not
    // worked into ArFootSizingPlugin, so the shipped scan cannot be affected.
    private var arTryOnSpikePlugin: ArTryOnSpikePlugin? = null

    // V3 production try-on (docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md V3.1/V3.2): the platform view,
    // the ARCore session and the Filament-direct renderer. The Dart side gates every entry behind
    // AppConstants.tryOnV3Enabled, so registering it here costs a build with the flag off nothing
    // but the registration — there is no Dart call site until the flag is on.
    private var arTryOnPlugin: ArTryOnPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register the ARCore foot scanning plugin
        arFootSizingPlugin = ArFootSizingPlugin(this)
        arFootSizingPlugin!!.registerWith(flutterEngine)

        arTryOnSpikePlugin = ArTryOnSpikePlugin(this)
        arTryOnSpikePlugin!!.registerWith(flutterEngine)

        arTryOnPlugin = ArTryOnPlugin(this)
        arTryOnPlugin!!.registerWith(flutterEngine)
        // TEMPORARY (Phase 1b diagnostics) — remove with DiagRelay.kt.
        DiagRelay.log("activity", "configureFlutterEngine")
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // TEMPORARY (Phase 1b diagnostics) — remove with DiagRelay.kt.
        DiagRelay.log("activity", "cleanUpFlutterEngine (engine detaching)")
        arFootSizingPlugin?.unregister()
        arFootSizingPlugin = null
        arTryOnSpikePlugin?.unregister()
        arTryOnSpikePlugin = null
        arTryOnPlugin?.unregister()
        arTryOnPlugin = null
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
