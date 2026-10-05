package com.solevision.app.tryon

/**
 * **V4.8: the QA heartbeat's thermal word, and nothing else.**
 *
 * The roadmap's perf/stability pass asks for a thermal check, and the only desk-buildable half of
 * one is the readout: a screenshot of the QA heartbeat from a phone with no `adb` has to carry the
 * device's thermal state next to the fps numbers, or a hot phone's fps gets blamed on the renderer.
 * `ArTryOnView` reads the platform value (`PowerManager.getCurrentThermalStatus`, API 29+) and
 * calls [label]; the mapping lives here because it is pure.
 *
 * `null` means "this platform cannot answer" (below Android 10) and reads as `n/a`, which is
 * deliberately distinct from an unknown value — an OEM build that returns an int we have no word
 * for says `unknown(n)` rather than being quietly mapped to `none`.
 */
object ThermalReport {

    /** [status] is `PowerManager.getCurrentThermalStatus`'s int, or null when unavailable. */
    fun label(status: Int?): String = when (status) {
        null -> "n/a"
        // android.os.PowerManager.THERMAL_STATUS_* — spelled here rather than imported, so this
        // file stays Android-free and the JVM tests can compile it (the same rule as
        // FootPoseTracker/FootScaleCorrection/FootMaskMesh).
        0 -> "none"
        1 -> "light"
        2 -> "moderate"
        3 -> "severe"
        4 -> "critical"
        5 -> "emergency"
        6 -> "shutdown"
        else -> "unknown($status)"
    }
}
