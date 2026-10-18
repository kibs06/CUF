package com.solevision.app.tryon

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Pins [DetectionDots]' projection math on the JVM (`:app:testDebugUnitTest`).
 *
 * A wrong sign here is a dot mirrored across the screen or a dot drawn for a foot behind the
 * camera — the exact "it detects but the dots lie" report this test exists to prevent.
 */
class DetectionDotsTest {

    private fun assertNear(expected: Float, actual: Float, eps: Float = 1e-4f) {
        assertTrue("expected $expected, was $actual", abs(expected - actual) <= eps)
    }

    // ── Ray direction ─────────────────────────────────────────────────────────

    @Test
    fun opticalCentreLooksStraightAhead() {
        val dir = DetectionDots.rayDirection(320f, 240f, 500f, 500f, 320f, 240f)
        assertNear(0f, dir[0])
        assertNear(0f, dir[1])
        assertNear(-1f, dir[2])
    }

    @Test
    fun offCentrePixelTiltsTheRay() {
        // Right of centre → +x; below centre in image rows → −y is up in GL convention.
        val dir = DetectionDots.rayDirection(420f, 240f, 500f, 500f, 320f, 240f)
        assertTrue(dir[0] > 0f)
        assertNear(0f, dir[1])
    }

    @Test
    fun pointAlongRayReachesTheRequestedDistance() {
        val dir = DetectionDots.rayDirection(320f, 240f, 500f, 500f, 320f, 240f)
        val p = DetectionDots.pointAlongRay(dir, 0.6f)
        assertNear(0f, p[0])
        assertNear(0f, p[1])
        assertNear(-0.6f, p[2])
    }

    // ── Matrix helpers ────────────────────────────────────────────────────────

    @Test
    fun identityInvertsToItself() {
        val id = FloatArray(16) { if (it % 5 == 0) 1f else 0f }
        val inv = DetectionDots.invert4(id)
        assertNotNull(inv)
        for (i in 0 until 16) assertNear(id[i], inv!![i])
    }

    @Test
    fun translationInvertsToNegation() {
        val m = FloatArray(16) { if (it % 5 == 0) 1f else 0f }
        m[12] = 2f
        m[13] = -3f
        m[14] = 5f
        val back = DetectionDots.mul4(m, DetectionDots.invert4(m)!!)
        for (i in 0 until 16) assertNear(if (i % 5 == 0) 1f else 0f, back[i], 1e-3f)
    }

    @Test
    fun singularMatrixAnswersNull() {
        assertNull(DetectionDots.invert4(FloatArray(16)))
    }

    // ── Projection ────────────────────────────────────────────────────────────

    /** Orthographic-ish view-projection mapping world [-1,1]² to NDC directly. */
    private fun ortho(): FloatArray = FloatArray(16).also {
        it[0] = 1f
        it[5] = 1f
        it[10] = -1f
        it[15] = 1f
    }

    @Test
    fun centreProjectsToCentre() {
        val p = DetectionDots.projectToPixels(floatArrayOf(0f, 0f, 0f), ortho(), 1080, 2400)
        assertNotNull(p)
        assertNear(540f, p!!.first)
        assertNear(1200f, p.second)
    }

    @Test
    fun topLeftWorldLandsTopLeftPixels() {
        val p = DetectionDots.projectToPixels(floatArrayOf(-1f, 1f, 0f), ortho(), 1080, 2400)
        assertNotNull(p)
        assertNear(0f, p!!.first)
        assertNear(0f, p.second)
    }

    @Test
    fun behindCameraProjectsToNull() {
        // Negative w: a view-projection whose w row flips the sign.
        val m = ortho()
        m[3] = -1f
        m[15] = 0f
        assertNull(DetectionDots.projectToPixels(floatArrayOf(0f, 0f, 1f), m, 1080, 2400))
    }

    // ── Detection placement ───────────────────────────────────────────────────

    @Test
    fun toeAheadPlacesYawZeroAndReportsTheAxis() {
        val heel = floatArrayOf(0f, -0.4f, -0.5f)
        val toe = floatArrayOf(0f, -0.38f, -0.23f) // 270 mm ahead on +Z
        val p = DetectionDots.detectionPlacement(heel, toe)
        assertNotNull(p)
        assertNear(0f, p!!.yawDeg.toFloat(), 0.5f)
        assertNear(0.27f, p.axisMeters.toFloat())
    }

    @Test
    fun toeRightPlacesYawNinety() {
        val heel = floatArrayOf(0f, -0.4f, -0.5f)
        val toe = floatArrayOf(0.27f, -0.4f, -0.5f)
        val p = DetectionDots.detectionPlacement(heel, toe)
        assertNotNull(p)
        assertNear(90f, p!!.yawDeg.toFloat(), 0.5f)
    }

    /**
     * The axis is the *flat* heel→toe length, the same quantity the tracker measures and the same
     * one `planarFootAxisMeters` reports — so a foot read from a low or a high angle, or one whose
     * toe sits 5 cm above its heel (a foot on a raised surface), grades the shoe identically. Two
     * formulas for "how long is this foot" is how the shoe ends up changing size on an anchor
     * swap.
     */
    @Test
    fun axisIsFlatSoHeightDoesNotChangeTheGrade() {
        val heel = floatArrayOf(0f, 0f, 0f)
        val p = DetectionDots.detectionPlacement(heel, floatArrayOf(0.162f, 0.05f, 0.216f))
        assertNotNull(p)
        assertNear(0.27f, p!!.axisMeters.toFloat())
    }

    @Test
    fun shortAndLongAxesAreRefused() {
        val heel = floatArrayOf(0f, 0f, 0f)
        assertNull(DetectionDots.detectionPlacement(heel, floatArrayOf(0f, 0f, 0.10f)))
        assertNull(DetectionDots.detectionPlacement(heel, floatArrayOf(0f, 0f, 0.40f)))
        // Degenerate: heel and toe coincide, so there is no direction.
        assertNull(DetectionDots.detectionPlacement(heel, floatArrayOf(0f, 0f, 0f)))
    }

    @Test
    fun nonFiniteInputIsRefused() {
        val heel = floatArrayOf(0f, 0f, 0f)
        assertNull(
            DetectionDots.detectionPlacement(heel, floatArrayOf(Float.NaN, 0f, 0.27f)),
        )
        assertNull(
            DetectionDots.detectionPlacement(floatArrayOf(0f, Float.POSITIVE_INFINITY, 0f), heel),
        )
    }

    // ── The hold rule ─────────────────────────────────────────────────────

    /**
     * V4.17. A gap in the pose stream is not the foot leaving, so the anchors hold: live while a
     * pose is current, held through a brief miss, gone only after a real loss. Each boundary below
     * is asserted from both sides, because an off-by-one here is a shoe that lets go one frame
     * early — i.e. exactly the flicker this rule exists to remove.
     */
    @Test
    fun aCurrentPoseIsLiveAndNoFixIsLost() {
        assertEquals(
            DetectionDots.Fix.LIVE,
            DetectionDots.holdState(10_000L, 10_000L, 0L, hasFix = true),
        )
        // No fix at all is lost whatever the clocks say: there is nothing to hold.
        assertEquals(
            DetectionDots.Fix.LOST,
            DetectionDots.holdState(10_000L, 10_000L, 10_000L, hasFix = false),
        )
    }

    @Test
    fun theStalenessBoundaryIsInclusive() {
        val now = 10_000L
        assertEquals(
            DetectionDots.Fix.LIVE,
            DetectionDots.holdState(now, now - DetectionDots.STALE_MS, 0L, hasFix = true),
        )
        assertEquals(
            DetectionDots.Fix.COAST,
            DetectionDots.holdState(now, now - DetectionDots.STALE_MS - 1, now, hasFix = true),
        )
    }

    @Test
    fun aFootStillSeenHoldsToTheCoastBound() {
        val now = 20_000L
        // The partial-foot case: presence refreshed 200 ms ago, no useful pose for 2.9 s.
        assertEquals(
            DetectionDots.Fix.COAST,
            DetectionDots.holdState(now, now - DetectionDots.COAST_MS, now - 200, hasFix = true),
        )
        assertEquals(
            DetectionDots.Fix.LOST,
            DetectionDots.holdState(now, now - DetectionDots.COAST_MS - 1, now - 200, hasFix = true),
        )
    }

    @Test
    fun withNothingArrivingTheHoldMatchesTheRing() {
        val now = 30_000L
        assertEquals(
            DetectionDots.Fix.COAST,
            DetectionDots.holdState(now, now - DetectionDots.SILENT_COAST_MS, 0L, hasFix = true),
        )
        assertEquals(
            DetectionDots.Fix.LOST,
            DetectionDots.holdState(now, now - DetectionDots.SILENT_COAST_MS - 1, 0L, hasFix = true),
        )
    }

    @Test
    fun aPresenceThatHasAgedOutIsNotLiveness() {
        val now = 40_000L
        // A presence frame older than the ring's own window cannot extend a hold: the foot has
        // not been seen for 1.5 s, so the silent bound is the one that applies.
        assertEquals(
            DetectionDots.Fix.LOST,
            DetectionDots.holdState(
                now,
                now - DetectionDots.COAST_MS,
                now - DetectionDots.PRESENCE_STALE_MS - 1,
                hasFix = true,
            ),
        )
    }

    @Test
    fun theHoldIsOrderedAndAHeldAnchorIsDimmed() {
        assertTrue(DetectionDots.STALE_MS < DetectionDots.SILENT_COAST_MS)
        assertTrue(DetectionDots.SILENT_COAST_MS < DetectionDots.COAST_MS)
        // Held anchors are visible but must not read as a live measurement.
        assertTrue(DetectionDots.HELD_ALPHA in 0.05f..0.9f)
    }

    // ── The held-carry gate (V4.19) ──────────────────────────────────────────

    /**
     * Only a held fix moves under the carry: LIVE re-measures from fresh poses itself, LOST has
     * nothing to move, and no fix at all is never due whatever the clocks say.
     */
    @Test
    fun onlyACoastFixIsCarried() {
        val now = 50_000L
        assertTrue(DetectionDots.heldCarryDue(now, 0L, DetectionDots.Fix.COAST, hasFix = true))
        assertFalse(DetectionDots.heldCarryDue(now, 0L, DetectionDots.Fix.LIVE, hasFix = true))
        assertFalse(DetectionDots.heldCarryDue(now, 0L, DetectionDots.Fix.LOST, hasFix = true))
        assertFalse(DetectionDots.heldCarryDue(now, 0L, DetectionDots.Fix.COAST, hasFix = false))
    }

    @Test
    fun theCarryThrottleMatchesTheLiveRemeasure() {
        val now = 60_000L
        // Just refreshed: not due. A full recompute interval later: due. Boundary inclusive,
        // like the hold rule's own boundaries above.
        assertFalse(
            DetectionDots.heldCarryDue(now, now, DetectionDots.Fix.COAST, hasFix = true),
        )
        assertFalse(
            DetectionDots.heldCarryDue(
                now,
                now - DetectionDots.RECOMPUTE_MS + 1,
                DetectionDots.Fix.COAST,
                hasFix = true,
            ),
        )
        assertTrue(
            DetectionDots.heldCarryDue(
                now,
                now - DetectionDots.RECOMPUTE_MS,
                DetectionDots.Fix.COAST,
                hasFix = true,
            ),
        )
    }

    @Test
    fun dotsConstantsAreSane() {
        assertEquals(0.6f, DetectionDots.FALLBACK_DISTANCE_M)
        assertEquals(1000L, DetectionDots.STALE_MS)
        assertTrue(DetectionDots.RECOMPUTE_MS < DetectionDots.STALE_MS)
    }

    // ── Camera zoom (V4.22) ──────────────────────────────────────────────────

    @Test
    fun zoomCoercionKeepsTheSliderRangeAndRefusesGarbage() {
        assertEquals(0.7f, DetectionDots.coerceCameraZoom(0.7f))
        assertEquals(2.0f, DetectionDots.coerceCameraZoom(2.0f))
        assertEquals(1f, DetectionDots.coerceCameraZoom(1f))
        // Out of range clamps; non-finite answers 1x rather than throwing.
        assertEquals(0.7f, DetectionDots.coerceCameraZoom(0.1f))
        assertEquals(2.0f, DetectionDots.coerceCameraZoom(9f))
        assertEquals(1f, DetectionDots.coerceCameraZoom(Float.NaN))
        assertEquals(1f, DetectionDots.coerceCameraZoom(Float.POSITIVE_INFINITY))
    }

    @Test
    fun zoomScalesBothFocalEntriesAndKeepsTheirRatio() {
        val proj = FloatArray(16) { 0f }.also { it[0] = 3.344f; it[5] = 1.543f }
        DetectionDots.applyZoomToProjection(proj, 1.5f)
        assertNear(3.344f * 1.5f, proj[0])
        assertNear(1.543f * 1.5f, proj[5])
        // The ratio the probe self-check asserts is invariant: zoom narrows the
        // field of view, it never skews it.
        assertNear(3.344f / 1.543f, proj[0] / proj[5])
    }

    @Test
    fun zoomCropIsIdentityAtOneAndHalvesOffsetsAtTwo() {
        val atOne = java.nio.FloatBuffer.wrap(floatArrayOf(0f, 0f, 1f, 1f))
        DetectionDots.applyZoomCropToUvs(atOne, 1f)
        assertNear(0f, atOne.get(0))
        assertNear(1f, atOne.get(2))

        val atTwo = java.nio.FloatBuffer.wrap(floatArrayOf(0f, 0f, 1f, 1f, 0.5f, 0.5f))
        DetectionDots.applyZoomCropToUvs(atTwo, 2f)
        // Corners move halfway to the centre; the centre itself never moves.
        assertNear(0.25f, atTwo.get(0))
        assertNear(0.25f, atTwo.get(1))
        assertNear(0.75f, atTwo.get(2))
        assertNear(0.5f, atTwo.get(4))
        assertNear(0.5f, atTwo.get(5))
    }

    @Test
    fun zoomBandIsFullQuadAtOneAndCentredStripBelow() {
        val full = DetectionDots.zoomBandRect(1f)
        assertNear(0f, full[0]); assertNear(0f, full[1])
        assertNear(1f, full[2]); assertNear(1f, full[3])

        val band = DetectionDots.zoomBandRect(0.7f)
        // Full width, 70% of the height, centred: 15% bars top and bottom.
        assertNear(0f, band[0]); assertNear(0.15f, band[1])
        assertNear(1f, band[2]); assertNear(0.85f, band[3])
    }

    @Test
    fun zoomOutWidensUWhileKeepingFullHeight() {
        val uvs = java.nio.FloatBuffer.wrap(floatArrayOf(0.375f, 0f, 0.625f, 1f))
        // 0.7 is the slider's floor (MIN_CAMERA_ZOOM): u offsets widen by 1/0.7 about the
        // centre — 0.5 ± 0.125/0.7 — while v is untouched at the full height.
        DetectionDots.applyZoomOutToUvs(uvs, 0.7f)
        assertNear(0.3214f, uvs.get(0))
        assertNear(0f, uvs.get(1))
        assertNear(0.6786f, uvs.get(2))
        assertNear(1f, uvs.get(3))
    }

    @Test
    fun zoomOutWidensWhicheverAxisIsCropped() {
        // Rotated mapping: v is the cropped span, so v widens by 1/0.7 and u is untouched.
        val rotated = java.nio.FloatBuffer.wrap(floatArrayOf(0f, 0.375f, 1f, 0.625f))
        DetectionDots.applyZoomOutToUvs(rotated, 0.7f)
        assertNear(0f, rotated.get(0))
        assertNear(0.3214f, rotated.get(1))
        assertNear(1f, rotated.get(2))
        assertNear(0.6786f, rotated.get(3))
    }

    @Test
    fun zoomOutIsANoOpAtOneAndAbove() {
        val uvs = java.nio.FloatBuffer.wrap(floatArrayOf(0.2f, 0.3f))
        DetectionDots.applyZoomOutToUvs(uvs, 1f)
        DetectionDots.applyZoomOutToUvs(uvs, 2f)
        assertNear(0.2f, uvs.get(0))
        assertNear(0.3f, uvs.get(1))
    }

    @Test
    fun zoomScreenPointFixesTheCentreInBothPaths() {
        // Zoom-in magnifies about the centre.
        val zin = DetectionDots.zoomScreenPoint(600f, 1200f, 1080, 2340, 2f)
        assertNear(540f + (600f - 540f) * 2f, zin.first)
        assertNear(1170f + (1200f - 1170f) * 2f, zin.second)
        // Letterbox shrinks y about the centre; x is full-width either way.
        val zout = DetectionDots.zoomScreenPoint(600f, 1200f, 1080, 2340, 0.7f)
        assertNear(600f, zout.first)
        assertNear(1170f + (1200f - 1170f) * 0.7f, zout.second)
        // The centre itself never moves, which is why screen-centre
        // auto-placement needs no mapping.
        val centre = DetectionDots.zoomScreenPoint(540f, 1170f, 1080, 2340, 1.6f)
        assertNear(540f, centre.first)
        assertNear(1170f, centre.second)
    }
}
