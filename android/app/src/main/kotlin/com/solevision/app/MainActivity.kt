package com.solevision.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.solevision.app.arfoot.ArFootSizingPlugin

class MainActivity : FlutterActivity() {

    private var arFootSizingPlugin: ArFootSizingPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register the ARCore foot scanning plugin
        arFootSizingPlugin = ArFootSizingPlugin(this)
        arFootSizingPlugin!!.registerWith(flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        arFootSizingPlugin?.unregister()
        arFootSizingPlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
