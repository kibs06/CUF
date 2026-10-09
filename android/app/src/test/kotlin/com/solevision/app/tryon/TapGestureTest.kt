package com.solevision.app.tryon

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * **V3.4's tap rule, pinned on the JVM** (`:app:testDebugUnitTest`).
 *
 * A wrong answer here means a drag places a shoe, or a pinch does, or a tap is swallowed and the
 * customer can never place it by hand. [TapGesture] has no Android types, so no device is needed.
 *
 * ⚠️ What this file does **not** cover: whether the platform view receives AR-mode touches at all,
 * which only the V4.9 device session can show.
 */
class TapGestureTest {

    @Test
    fun aQuickStillTapIsATap() {
        val tap = TapGesture(slopPx = 16f, maxDurationMs = 300L)
        tap.onDown(100f, 200f, nowMs = 1_000L)
        assertTrue(tap.onUp(100f, 200f, nowMs = 1_120L))
    }

    @Test
    fun aSmallWobbleInsideTheSlopStillCountsAsATap() {
        val tap = TapGesture(slopPx = 16f, maxDurationMs = 300L)
        tap.onDown(100f, 200f, nowMs = 1_000L)
        tap.onMove(108f, 206f) // 10 px: inside the 16 px slop
        assertTrue(tap.onUp(108f, 206f, nowMs = 1_100L))
    }

    @Test
    fun aDragPastTheSlopIsNotATap() {
        val tap = TapGesture(slopPx = 16f, maxDurationMs = 300L)
        tap.onDown(100f, 200f, nowMs = 1_000L)
        tap.onMove(140f, 200f) // 40 px: a drag
        assertFalse(tap.onUp(140f, 200f, nowMs = 1_100L))
    }

    @Test
    fun aHoldLongerThanTheLimitIsNotATap() {
        val tap = TapGesture(slopPx = 16f, maxDurationMs = 300L)
        tap.onDown(100f, 200f, nowMs = 1_000L)
        assertFalse(tap.onUp(100f, 200f, nowMs = 1_400L))
    }

    @Test
    fun aSecondFingerTurnsTheGestureIntoAPinch() {
        val tap = TapGesture(slopPx = 16f, maxDurationMs = 300L)
        tap.onDown(100f, 200f, nowMs = 1_000L)
        tap.onPointerDown()
        assertFalse(tap.onUp(100f, 200f, nowMs = 1_100L))
    }

    @Test
    fun aCancelledGestureIsNotATap() {
        val tap = TapGesture(slopPx = 16f, maxDurationMs = 300L)
        tap.onDown(100f, 200f, nowMs = 1_000L)
        tap.cancel()
        assertFalse(tap.onUp(100f, 200f, nowMs = 1_100L))
    }

    @Test
    fun anUpWithoutADownIsNotATap() {
        val tap = TapGesture(slopPx = 16f, maxDurationMs = 300L)
        assertFalse(tap.onUp(100f, 200f, nowMs = 1_000L))
    }

    @Test
    fun aTapDoesNotLeakIntoTheNextGesture() {
        val tap = TapGesture(slopPx = 16f, maxDurationMs = 300L)
        tap.onDown(100f, 200f, nowMs = 1_000L)
        assertTrue(tap.onUp(100f, 200f, nowMs = 1_100L))
        // A finished tap is spent: an up with no new down must not count as a second tap.
        assertFalse(tap.onUp(100f, 200f, nowMs = 1_200L))
    }
}
