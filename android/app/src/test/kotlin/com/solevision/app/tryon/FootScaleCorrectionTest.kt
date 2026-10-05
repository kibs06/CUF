package com.solevision.app.tryon

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * **V4.3's ×N, pinned on the JVM** (`:app:testDebugUnitTest`).
 *
 * [FootScaleCorrection] is a file of its own precisely so this test can exist: the correction is
 * the one part of the frame-scale work whose wrongness is visible on a customer's screen and
 * invisible in a compile, and its inputs are two numbers — a measured foot and a graded last —
 * that need neither ARCore nor a device.
 *
 * ⚠️ What this file does **not** cover: whether the tracker's measurement is *right* — whether a
 * toe UV point lands on the real toe — is a device question (V4.9), and the QA heartbeat's
 * `len=`/`scale=` pair is the reading that session needs.
 */
class FootScaleCorrectionTest {

    @Test
    fun theRoadmapsExampleSizesTheShoeForTheMeasuredFoot() {
        // A 200 mm foot against a 265 mm last: (200 + 11) / 265 = 0.796, inside the clamp.
        val factor = FootScaleCorrection.factor(0.200, 265.0)

        assertEquals(211.0 / 265.0, factor, 1e-9)
        assertTrue("the shoe must shrink toward the measured foot", factor < 1.0)
        assertTrue("...without hitting the floor", factor > FootScaleCorrection.MIN_FACTOR)
    }

    @Test
    fun aFootThatMatchesTheSizeLeavesTheChartAlone() {
        // 265 mm foot, last 276 mm: exactly the toe room the fit engine calls true-to-size.
        assertEquals(1.0, FootScaleCorrection.factor(0.265, 276.0), 1e-9)
    }

    @Test
    fun aFootLargerThanTheSelectedSizeGrowsTheShoe() {
        val factor = FootScaleCorrection.factor(0.280, 276.0)

        assertEquals(291.0 / 276.0, factor, 1e-9)
        assertTrue(factor > 1.0)
    }

    @Test
    fun theFactorIsClampedAtBothEnds() {
        // A small foot against the largest last: (110 + 11) / 360 = 0.336 → the floor.
        assertEquals(FootScaleCorrection.MIN_FACTOR, FootScaleCorrection.factor(0.110, 360.0), 1e-9)
        // A large foot against the smallest last: (360 + 11) / 120 = 3.09 → the ceiling.
        assertEquals(FootScaleCorrection.MAX_FACTOR, FootScaleCorrection.factor(0.360, 120.0), 1e-9)
    }

    @Test
    fun implausibleMeasurementsAreRefusedRatherThanClamped() {
        // 60 mm is a failed measurement, not a child's foot (the fit engine's own band).
        assertEquals(1.0, FootScaleCorrection.factor(0.060, 276.0), 1e-9)
        assertEquals(1.0, FootScaleCorrection.factor(0.400, 276.0), 1e-9)
    }

    @Test
    fun anImplausibleLastIsRefused() {
        assertEquals(1.0, FootScaleCorrection.factor(0.265, 100.0), 1e-9)
        assertEquals(1.0, FootScaleCorrection.factor(0.265, 400.0), 1e-9)
    }

    @Test
    fun missingOrNonFiniteInputsLeaveTheSelectedSizeAlone() {
        assertEquals(1.0, FootScaleCorrection.factor(null, 276.0), 1e-9)
        assertEquals(1.0, FootScaleCorrection.factor(0.265, null), 1e-9)
        assertEquals(1.0, FootScaleCorrection.factor(Double.NaN, 276.0), 1e-9)
        assertEquals(1.0, FootScaleCorrection.factor(0.265, Double.NaN), 1e-9)
        assertEquals(1.0, FootScaleCorrection.factor(0.0, 276.0), 1e-9)
        assertEquals(1.0, FootScaleCorrection.factor(-0.2, 276.0), 1e-9)
        assertEquals(1.0, FootScaleCorrection.factor(0.265, -1.0), 1e-9)
    }

    @Test
    fun thePlausibleBandsAreInclusiveAtTheirEnds() {
        // Exactly at each edge the measurement is still honoured...
        assertEquals(121.0 / 120.0, FootScaleCorrection.factor(0.110, 120.0), 1e-9)
        assertEquals(371.0 / 360.0, FootScaleCorrection.factor(0.360, 360.0), 1e-9)
        // ...and a fraction past it the selected size stays.
        assertEquals(1.0, FootScaleCorrection.factor(0.1099, 276.0), 1e-9)
        assertEquals(1.0, FootScaleCorrection.factor(0.3601, 276.0), 1e-9)
        assertEquals(1.0, FootScaleCorrection.factor(0.265, 119.99), 1e-9)
        assertEquals(1.0, FootScaleCorrection.factor(0.265, 360.01), 1e-9)
    }

    @Test
    fun largerMeasuredFeetNeverShrinkTheFactor() {
        var previous = 0.0
        var footMm = FootScaleCorrection.MIN_PLAUSIBLE_FOOT_MM
        while (footMm <= FootScaleCorrection.MAX_PLAUSIBLE_FOOT_MM + 1e-9) {
            val factor = FootScaleCorrection.factor(footMm / 1000.0, 276.0)
            assertTrue("factor must not fall as the measured foot grows", factor >= previous)
            previous = factor
            footMm += 5.0
        }
    }
}
