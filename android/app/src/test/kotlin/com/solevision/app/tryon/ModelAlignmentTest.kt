package com.solevision.app.tryon

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * **V4.9 device fix, pinned on the JVM** (`:app:testDebugUnitTest`).
 *
 * Luna Loafers rendered ~2.65× oversize because the load transform scaled by
 * the Z half-extent while the mesh's 270 mm run on X (`forward_axis: '-x'`,
 * bbox 0.270 × 0.159 × 0.102 m). These tests pin the two halves of the fix:
 * the yaw offset per axis and the longer-horizontal-axis extent — plus the
 * rule that Z-long meshes keep the old behaviour exactly.
 */
class ModelAlignmentTest {

    @Test
    fun plusZMeshesKeepTheOldBehaviour() {
        assertEquals(0.0, ModelAlignment.yawOffsetForForwardAxis("+z"), 1e-9)
        assertEquals(0.0, ModelAlignment.yawOffsetForForwardAxis(null), 1e-9)
        assertEquals(0.0, ModelAlignment.yawOffsetForForwardAxis(""), 1e-9)
        assertEquals(0.0, ModelAlignment.yawOffsetForForwardAxis("sideways"), 1e-9)
    }

    @Test
    fun minusZMeshesTurnHalfAround() {
        assertEquals(180.0, ModelAlignment.yawOffsetForForwardAxis("-z"), 1e-9)
    }

    @Test
    fun xAuthoredMeshesTurnAQuarter() {
        // Luna Loafers: toe on −X.
        assertEquals(90.0, ModelAlignment.yawOffsetForForwardAxis("-x"), 1e-9)
        assertEquals(-90.0, ModelAlignment.yawOffsetForForwardAxis("+x"), 1e-9)
    }

    @Test
    fun axisMatchingIgnoresCaseAndWhitespace() {
        assertEquals(180.0, ModelAlignment.yawOffsetForForwardAxis("  -Z "), 1e-9)
        assertEquals(90.0, ModelAlignment.yawOffsetForForwardAxis("-X"), 1e-9)
    }

    @Test
    fun explicitPerModelOverrideWinsOverTheAxis() {
        assertEquals(
            12.5,
            ModelAlignment.resolveYawOffsetDeg(12.5, "-x"),
            1e-9,
        )
        assertEquals(
            90.0,
            ModelAlignment.resolveYawOffsetDeg(null, "-x"),
            1e-9,
        )
        assertEquals(
            0.0,
            ModelAlignment.resolveYawOffsetDeg(Double.NaN, "+z"),
            1e-9,
        )
    }

    @Test
    fun zLongMeshesKeepTheOldExtent() {
        // The old path read halfExtent[2] × 2; Z-long is identical.
        assertEquals(0.27f, ModelAlignment.authoredLengthExtent(0.10f, 0.27f))
    }

    @Test
    fun xLongMeshesMeasureOnX() {
        // Luna's box: 270 mm on X, 102 mm on Z — the 2.65× bug reads 0.102.
        assertEquals(0.27f, ModelAlignment.authoredLengthExtent(0.27f, 0.102f))
    }

    @Test
    fun autoYawFollowsTheLongAxis() {
        // Luna's box: X-long with no override → the -x quarter-turn.
        assertEquals(90.0, ModelAlignment.autoYawFromExtents(null, 0.27f, 0.102f), 1e-9)
        // Z-long keeps the old assumption.
        assertEquals(0.0, ModelAlignment.autoYawFromExtents(null, 0.10f, 0.27f), 1e-9)
        // Near-square boxes do not flip on noise.
        assertEquals(0.0, ModelAlignment.autoYawFromExtents(null, 0.12f, 0.11f), 1e-9)
        // An explicit override always wins, even over an X-long mesh.
        assertEquals(12.5, ModelAlignment.autoYawFromExtents(12.5, 0.27f, 0.102f), 1e-9)
        // Degenerate boxes draw as-is.
        assertEquals(0.0, ModelAlignment.autoYawFromExtents(null, 0f, 0.27f), 1e-9)
        assertEquals(0.0, ModelAlignment.autoYawFromExtents(null, Float.NaN, 0.27f), 1e-9)
    }

    @Test
    fun degenerateExtentsAnswerZero() {
        assertEquals(0f, ModelAlignment.authoredLengthExtent(0f, 0.27f))
        assertEquals(0f, ModelAlignment.authoredLengthExtent(-1f, 0.27f))
        assertEquals(0f, ModelAlignment.authoredLengthExtent(Float.NaN, 0.27f))
    }
}
