package com.solevision.app.arfoot

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Pins the depth math on the JVM (`:app:testDebugUnitTest`). These need no
 * ARCore or device; whether the depth is correct on a real phone is still a
 * device check against tape measurements.
 */
class DepthMathTest {

    @Test
    fun lowerThirteenBitsAreTheDepthInMillimetres() {
        // 0b101_0000001100100 = confidence bits 5, depth 100 mm.
        val raw = (5 shl 13) or 100
        assertEquals(100, depthMmFromRaw16(raw))
        assertEquals(0, depthMmFromRaw16(0))
    }

    @Test
    fun medianIgnoresImplausibleAndNoisyValues() {
        // 0 (no depth) and 9000 (far background) are dropped; median of 400,410,420 is 410.
        assertEquals(410, medianPlausibleDepthMm(listOf(0, 400, 9000, 420, 410)))
    }

    @Test
    fun medianNeedsAMinimumNumberOfValidNeighbours() {
        assertNull(medianPlausibleDepthMm(listOf(400, 0, 0, 0, 0, 0, 0, 0, 0)))
    }

    @Test
    fun centreOfImageUnprojectsOntoTheOpticalAxis() {
        // Pixel at the principal point: x and y are zero, depth lies on -Z.
        val p = unprojectToCameraSpace(320f, 240f, 0.5f, 500f, 500f, 320f, 240f)
        assertEquals(0f, p[0], 1e-6f)
        assertEquals(0f, p[1], 1e-6f)
        assertEquals(-0.5f, p[2], 1e-6f)
    }

    @Test
    fun rightAndDownInImageMapToPlusXAndMinusY() {
        // One focal length to the right at depth 1 m moves +1 m in X.
        val right = unprojectToCameraSpace(820f, 240f, 1f, 500f, 500f, 320f, 240f)
        assertEquals(1f, right[0], 1e-6f)
        // Image y grows downward; camera-space Y grows upward.
        val down = unprojectToCameraSpace(320f, 740f, 1f, 500f, 500f, 320f, 240f)
        assertEquals(-1f, down[1], 1e-6f)
    }
}
