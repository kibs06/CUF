package com.solevision.app.arfoot

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins the phone-tilt math on the JVM (`:app:testDebugUnitTest`). No ARCore
 * or device needed: each case is a known camera orientation.
 */
class PhoneTiltTest {

    private val delta = 1e-3

    @Test
    fun identityRotationLooksLevelSoTiltIsNinetyDegrees() {
        // Identity: the camera looks along -Z, which is horizontal.
        assertEquals(90.0, tiltFromDownDegrees(0f, 0f, 0f, 1f), delta)
    }

    @Test
    fun cameraPointingStraightDownIsZeroDegrees() {
        // Rotate -90 degrees about X: the optical axis points at the floor.
        // Float rounding of sqrt(0.5) leaves the cosine a hair under 1, and acos
        // amplifies that to ~0.008 degrees, so this uses float-quaternion precision.
        val s = Math.sqrt(0.5).toFloat()
        assertEquals(0.0, tiltFromDownDegrees(-s, 0f, 0f, s), 0.05)
    }

    @Test
    fun thirtyDegreesOffDownIsThirtyDegrees() {
        // Rotate -60 degrees about X: the optical axis is 30 degrees from down.
        val half = Math.toRadians(-30.0)
        val qx = Math.sin(half).toFloat()
        val qw = Math.cos(half).toFloat()
        assertEquals(30.0, tiltFromDownDegrees(qx, 0f, 0f, qw), delta)
    }

    @Test
    fun outOfRangeRoundingDoesNotProduceNaN() {
        // A slightly over-unit component from float rounding must clamp, not NaN.
        val tilt = tiltFromDownDegrees(0f, 0.8f, 0.8f, 0f)
        assertEquals(false, tilt.isNaN())
    }
}
