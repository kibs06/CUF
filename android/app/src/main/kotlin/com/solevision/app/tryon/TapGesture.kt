package com.solevision.app.tryon

import kotlin.math.sqrt

/**
 * Recognises a single-finger tap for AR placement (V3.4's tap-to-place).
 *
 * A tap is one pointer that goes down and comes up within [slopPx] of where it started, inside
 * [maxDurationMs]. A second finger, a drag past the slop, a long press or a cancelled gesture all
 * make it not a tap. Pure Kotlin with no Android types, so [TapGestureTest] pins it on the JVM.
 *
 * ⚠️ What this does not cover: whether the platform view actually receives the AR-mode touches on
 * a device, which only a V4.9 device session can show.
 */
internal class TapGesture(
    private val slopPx: Float = 16f,
    private val maxDurationMs: Long = 300L,
) {
    private var active = false
    private var downX = 0f
    private var downY = 0f
    private var downAtMs = 0L

    /** A pointer went down. Starts a candidate tap at this spot. */
    fun onDown(x: Float, y: Float, nowMs: Long) {
        active = true
        downX = x
        downY = y
        downAtMs = nowMs
    }

    /** A second pointer went down: the gesture is a pinch, never a tap. */
    fun onPointerDown() {
        active = false
    }

    /** The pointer moved. Past the slop, the candidate tap is a drag. */
    fun onMove(x: Float, y: Float) {
        if (active && distance(x, y) > slopPx) active = false
    }

    /** The gesture was cancelled by the system. */
    fun cancel() {
        active = false
    }

    /** The pointer came up. Returns true only when the whole gesture was a tap. */
    fun onUp(x: Float, y: Float, nowMs: Long): Boolean {
        val tap = active && nowMs - downAtMs <= maxDurationMs && distance(x, y) <= slopPx
        active = false
        return tap
    }

    private fun distance(x: Float, y: Float): Float {
        val dx = x - downX
        val dy = y - downY
        return sqrt(dx * dx + dy * dy)
    }
}
