package com.solevision.app.tryon

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * **V4.2's tracker, pinned on the JVM** (`:app:testDebugUnitTest`).
 *
 * This file exists because [FootPoseTracker] is the one part of the foot-tracking work that cannot
 * be verified by compiling: its outputs are filtered numbers and lock edges, and a wrong cutoff or
 * a missing unlock is invisible until a device is held in a hand. It is deliberately Android-free
 * (no `Frame`, no `hitTest`, no `SystemClock` — the caller passes time in) so these tests need
 * neither a device nor Robolectric.
 *
 * ⚠️ What this file does **not** cover: anything that needs ARCore. Whether a UV point lands on
 * the right floor point — the centre-crop mapping and the plane filter in `ArTryOnView` — is
 * exactly the half no JVM test can reach, and is the first thing a device session should look at.
 */
class FootPoseTrackerTest {

    private fun sample(
        hx: Double,
        hy: Double,
        hz: Double,
        quality: Double,
        fx: Double = 0.0,
        fz: Double = 1.0,
        side: String? = null,
        lengthMeters: Double = 0.265,
    ) = FootPoseTracker.Sample(
        heel = doubleArrayOf(hx, hy, hz),
        forward = doubleArrayOf(fx, 0.0, fz),
        lengthMeters = lengthMeters,
        quality = quality,
        side = side,
    )

    @Test
    fun aFirstConfidentSampleSeedsTheAnchorAndLocks() {
        val tracker = FootPoseTracker()
        val change = tracker.observe(sample(0.10, 0.20, 0.30, quality = 0.8, side = "right"), 1_000L)

        assertNotNull("0.8 is above the enter threshold", change)
        assertTrue(change!!.locked)
        assertTrue(tracker.locked)
        assertEquals("right", change.side)

        val anchor = tracker.anchor()
        assertNotNull(anchor)
        assertEquals(0.10, anchor!!.x, 1e-9)
        assertEquals(0.20, anchor.y, 1e-9)
        assertEquals(0.30, anchor.z, 1e-9)
        assertEquals("forward +Z is yaw 0", 0.0, anchor.yawDeg, 1e-9)
    }

    @Test
    fun yawFollowsTheFootsForwardAxis() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, quality = 0.9, fx = 1.0, fz = 0.0), 1_000L)

        // +X in world means the model's +Z (the toe) must be turned 90°.
        assertEquals(90.0, tracker.anchor()!!.yawDeg, 1e-9)
    }

    @Test
    fun theBandBetweenLeaveAndEnterDoesNotFlickerTheLock() {
        val tracker = FootPoseTracker()
        assertNotNull(tracker.observe(sample(0.0, 0.0, 0.0, 0.8), 1_000L))
        assertNull("0.6 is inside the hysteresis band", tracker.observe(sample(0.0, 0.0, 0.0, 0.6), 1_200L))
        assertNull(tracker.observe(sample(0.0, 0.0, 0.0, 0.5), 1_400L))

        assertTrue(tracker.locked)
    }

    @Test
    fun sustainedLowQualityEventuallyUnlocks() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.8), 1_000L)

        var unlock: FootPoseTracker.LockChange? = null
        var now = 1_200L
        repeat(6) {
            tracker.observe(sample(0.0, 0.0, 0.0, 0.2), now)?.let { unlock = it }
            now += 200L
        }

        assertNotNull("a sustained drop must cross the leave threshold", unlock)
        assertFalse(unlock!!.locked)
        assertFalse(tracker.locked)
    }

    @Test
    fun aSilentDetectorDecaysTheLock() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9), 1_000L)

        // Still inside the stale window: the frame is eased, never unlocked.
        assertNull(tracker.onFrame(1_600L))

        var unlock: FootPoseTracker.LockChange? = null
        var now = 1_750L
        repeat(40) {
            tracker.onFrame(now)?.let { unlock = it }
            now += 50L
        }

        assertNotNull("a stopped publisher must lose the lock", unlock)
        assertFalse(unlock!!.locked)
        assertFalse(tracker.locked)
        assertTrue("the shoe keeps its last anchor through an unlock", tracker.hasAnchor)
    }

    @Test
    fun aDistantJumpReAnchorsWithoutUnlocking() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9), 1_000L)

        val change = tracker.observe(sample(1.5, 0.0, 0.0, 0.9), 1_200L)

        assertNull("a re-anchor is not a lock edge", change)
        assertTrue(tracker.locked)
        assertEquals("1.5 m is a new placement, not a movement to draw", 1.5, tracker.anchor()!!.x, 1e-9)
    }

    @Test
    fun aMovingTargetIsEasedNotSnapped() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9), 1_000L)
        tracker.onFrame(1_016L) // establishes the step clock

        tracker.observe(sample(0.0, 0.0, 0.05, 0.9), 1_200L)
        tracker.onFrame(1_216L)

        val z = tracker.anchor()!!.z
        assertTrue("the anchor should be heading to 0.05, not already there", z > 0.0 && z < 0.05)
    }

    @Test
    fun aDegenerateAxisIsNotASample() {
        val tracker = FootPoseTracker()
        val change = tracker.observe(sample(0.0, 0.0, 0.0, 0.9, fx = 0.0, fz = 0.0), 1_000L)

        assertNull(change)
        assertNull(tracker.anchor())
        assertFalse(tracker.locked)
    }

    @Test
    fun aNonFiniteSampleIsRejectedRatherThanPoisoningTheFilters() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9), 1_000L)

        val nan = Double.NaN
        assertNull(tracker.observe(sample(nan, 0.0, 0.0, 0.9), 1_200L))
        assertNull(tracker.observe(sample(0.0, 0.0, 0.0, nan), 1_400L))
        assertNull(tracker.observe(sample(0.0, 0.0, 0.0, 0.9, fz = nan), 1_600L))

        // The good sample's anchor is still finite and still the same one.
        val anchor = tracker.anchor()!!
        assertTrue(anchor.x.isFinite() && anchor.yawDeg.isFinite())
        assertTrue(tracker.lockQuality.isFinite())
    }

    @Test
    fun resetReportsWhetherALockWasHeldAndClearsIt() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9), 1_000L)

        assertTrue("the caller needs the edge to emit `footLock {locked=false}`", tracker.reset())
        assertFalse(tracker.locked)
        assertNull(tracker.anchor())
        assertFalse(tracker.reset())
    }

    // ── V4.3: the measured length the frame-scale correction is made of ──────────────────────

    @Test
    fun aFirstSampleCarriesItsMeasuredFootLength() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.213), 1_000L)

        assertEquals(0.213, tracker.anchor()!!.lengthMeters, 1e-9)
    }

    @Test
    fun theMeasuredLengthIsEasedLikeTheAnchor() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.213), 1_000L)
        tracker.onFrame(1_016L) // establishes the step clock

        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.265), 1_200L)
        tracker.onFrame(1_216L)

        val measured = tracker.anchor()!!.lengthMeters
        assertTrue(
            "the length should be heading to 0.265, not already there",
            measured > 0.213 && measured < 0.265,
        )
    }

    @Test
    fun aNonFiniteMeasuredLengthIsRejectedRatherThanPoisoningTheFilter() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.213), 1_000L)

        assertNull(tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = Double.NaN), 1_200L))

        assertEquals("the refused frame changed nothing", 0.213, tracker.anchor()!!.lengthMeters, 1e-9)
        assertTrue(tracker.locked)
    }

    @Test
    fun aNonPositiveMeasuredLengthIsNotASample() {
        val tracker = FootPoseTracker()

        assertNull(tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.0), 1_000L))
        assertNull(tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = -0.2), 1_200L))

        assertFalse(tracker.hasAnchor)
        assertFalse(tracker.locked)
    }

    @Test
    fun aSilentDetectorKeepsTheMeasuredLength() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.213), 1_000L)

        var now = 1_750L
        repeat(40) {
            tracker.onFrame(now)
            now += 50L
        }

        assertFalse("the decay is the lock's, not the measurement's", tracker.locked)
        assertEquals(0.213, tracker.anchor()!!.lengthMeters, 1e-9)
    }

    @Test
    fun aDriftReAnchorReSeedsTheMeasuredLength() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.213), 1_000L)

        tracker.observe(sample(1.5, 0.0, 0.0, 0.9, lengthMeters = 0.265), 1_200L)

        assertTrue(tracker.locked)
        assertEquals(
            "a new placement is measured afresh, not filtered from the old one",
            0.265,
            tracker.anchor()!!.lengthMeters,
            1e-9,
        )
    }

    @Test
    fun resetClearsTheMeasuredLengthToo() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.213), 1_000L)

        tracker.reset()

        assertNull(tracker.anchor())
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.265), 1_200L)
        assertEquals(0.265, tracker.anchor()!!.lengthMeters, 1e-9)
    }

    // ── V4.6: the live measurement Dart's fit verdict is built from ───────────────────────────

    @Test
    fun measureIsNullUntilTheFirstSample() {
        val tracker = FootPoseTracker()

        assertNull(tracker.measure())

        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.25), 1_000L)

        val measure = tracker.measure()
        assertNotNull(measure)
        assertEquals(0.25, measure!!.lengthMeters, 1e-9)
        assertEquals(0.9, measure.quality, 1e-9)
        assertTrue(measure.locked)
    }

    @Test
    fun measureKeepsTheEasedLengthThroughAnUnlock() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.25), 1_000L)

        var now = 1_750L
        repeat(40) {
            tracker.onFrame(now)
            now += 50L
        }

        val measure = tracker.measure()!!
        assertFalse("the lock is gone", measure.locked)
        assertEquals(
            "the measurement is not — the same rule as the drawn shoe",
            0.25,
            measure.lengthMeters,
            1e-9,
        )
    }

    @Test
    fun measureIsTheAnchorsOwnEasedLength() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.213), 1_000L)
        tracker.onFrame(1_016L) // establishes the step clock

        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.265), 1_200L)
        tracker.onFrame(1_216L)

        val measure = tracker.measure()!!
        assertEquals(
            "the verdict and the shoe must never be sized from two readings",
            tracker.anchor()!!.lengthMeters,
            measure.lengthMeters,
            1e-12,
        )
        assertTrue(
            "eased, not the raw sample",
            measure.lengthMeters > 0.213 && measure.lengthMeters < 0.265,
        )
    }

    @Test
    fun resetTakesTheMeasurementWithIt() {
        val tracker = FootPoseTracker()
        tracker.observe(sample(0.0, 0.0, 0.0, 0.9, lengthMeters = 0.25), 1_000L)

        tracker.reset()

        assertNull(tracker.measure())
    }
}
