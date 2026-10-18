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
    fun planarAxisIgnoresHeightAndMeasuresTheFloorRun() {
        // A 3-4-5 run on the floor is 0.5 m, whatever the height of either end.
        val heel = floatArrayOf(0f, 0f, 0f)
        assertEquals(0.5, planarFootAxisMeters(heel, floatArrayOf(0.3f, 0f, 0.4f)), 1e-6)
        assertEquals(0.5, planarFootAxisMeters(heel, floatArrayOf(0.3f, 0.5f, 0.4f)), 1e-6)
    }

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
    fun nearSurfaceWinsWhenAnEdgeWindowStraddlesFootAndFloor() {
        // A 3x3 window on the silhouette edge: four pixels are the foot at
        // ~400 mm, five are the floor behind it at ~460 mm. The median returns
        // the floor (so the point unprojects PAST the foot); the near reading
        // returns the foot, which is the surface the point is meant to be on.
        val window = listOf(400, 405, 460, 400, 462, 458, 402, 459, 461)
        assertEquals(458, medianPlausibleDepthMm(window))
        assertEquals(402, nearestPlausibleDepthMm(window))
    }

    @Test
    fun nearSurfaceStillIgnoresImplausibleAndNeedsNeighbours() {
        // One wild near pixel (30 mm, below the foot floor) cannot drag the
        // reading below the plausible band.
        assertEquals(400, nearestPlausibleDepthMm(listOf(30, 400, 410, 420)))
        assertNull(nearestPlausibleDepthMm(listOf(400, 0, 0, 0, 0, 0, 0, 0, 0)))
    }

    @Test
    fun aSolidFootWindowReadsTheSameBothWays() {
        assertEquals(410, medianPlausibleDepthMm(listOf(400, 410, 420, 405, 415, 410, 420, 400, 405)))
        assertEquals(405, nearestPlausibleDepthMm(listOf(400, 410, 420, 405, 415, 410, 420, 400, 405)))
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
    fun liftPutsTheHitOnTheFootHeightPlane() {
        // Camera 0.30 m up over the origin; floor hit 0.30 m away at 45 degrees.
        val lifted = liftAlongRayToHeight(
            floatArrayOf(0f, 0.30f, 0f),
            floatArrayOf(0f, 0f, -0.30f),
            0.03f,
        )!!
        assertEquals(0.03f, lifted[1], 1e-6f)
        assertEquals(0f, lifted[0], 1e-6f)
        // Same ray: the horizontal reach shrinks by (H - h) / H = 0.27 / 0.30.
        assertEquals(-0.27f, lifted[2], 1e-6f)
    }

    @Test
    fun liftCorrectsA27cmFootSeenFrom30cmAsItsFloorHitsSuggest() {
        // A true 27 cm foot whose edge points sit 3 cm up, seen from 30 cm up.
        // Its edge points are at x = ±0.135 m; the floor hits behind them are at
        // ±0.135 / 0.9 = ±0.15 m, which reads 30 cm unlifted. Lifting must recover 27 cm.
        val camera = floatArrayOf(0f, 0.30f, 0f)
        val heel = liftAlongRayToHeight(camera, floatArrayOf(-0.15f, 0f, 0f), 0.03f)!!
        val toe = liftAlongRayToHeight(camera, floatArrayOf(0.15f, 0f, 0f), 0.03f)!!
        val lengthM = Math.sqrt(
            ((toe[0] - heel[0]) * (toe[0] - heel[0]) +
                (toe[1] - heel[1]) * (toe[1] - heel[1]) +
                (toe[2] - heel[2]) * (toe[2] - heel[2])).toDouble(),
        )
        assertEquals(0.27, lengthM, 1e-3)
    }

    @Test
    fun liftRejectsACameraTooLowToLift() {
        assertNull(
            liftAlongRayToHeight(
                floatArrayOf(0f, 0.02f, 0f),
                floatArrayOf(0f, 0f, -0.1f),
                0.03f,
            ),
        )
    }

    @Test
    fun aPointWellBelowTheFloorIsRejected() {
        // Floor at y = 0; a depth point 4 cm under it read past the foot.
        assertEquals(true, isBelowFloor(-0.04f, 0f))
    }

    @Test
    fun aPointOnOrAboveTheFloorIsKept() {
        assertEquals(false, isBelowFloor(0.0f, 0f))
        assertEquals(false, isBelowFloor(0.02f, 0f))
    }

    @Test
    fun floorErrorWithinToleranceIsNotRejected() {
        // 0.5 cm below the floor is within the plane's error, so it is kept.
        assertEquals(false, isBelowFloor(-0.005f, 0f))
        // Just past the tolerance is rejected.
        assertEquals(true, isBelowFloor(-0.0105f, 0f))
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
