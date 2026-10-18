package com.solevision.app.tryon

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * **The still-capture pose and its stabilizer, pinned on the JVM** (`:app:testDebugUnitTest`).
 *
 * [FootSnapshot] is pure math over two world points, so each case below is a foot whose yaw,
 * tilt and length can be worked out by hand.
 */
class FootSnapshotTest {

    private val heel = doubleArrayOf(0.0, 0.0, 0.0)

    /** A flat foot of [length] metres, its toe at [yawDeg] from +Z, heel at the origin. */
    private fun footAt(yawDeg: Double, length: Double = 0.25): Pair<DoubleArray, DoubleArray> {
        val rad = Math.toRadians(yawDeg)
        val toe = doubleArrayOf(length * Math.sin(rad), 0.0, length * Math.cos(rad))
        return Pair(heel, toe)
    }

    @Test
    fun aFlatFootPointingDownZHasNoTiltAndTheMeasuredLength() {
        // 0.25 m straight along +Z, on the floor: yaw 0 (the model's +Z already faces it), tilt 0.
        val pose = FootSnapshot.pose(heel, doubleArrayOf(0.0, 0.0, 0.25))

        assertNotNull(pose)
        assertEquals(0.0, pose!!.yawDeg, 1e-9)
        assertEquals(0.0, pose.pitchDeg, 1e-9)
        assertEquals(0.25, pose.lengthMeters, 1e-9)
    }

    @Test
    fun aFootPointingAlongPlusXTurnsNinetyDegreesOfYaw() {
        val pose = FootSnapshot.pose(heel, doubleArrayOf(0.25, 0.0, 0.0))

        assertNotNull(pose)
        assertEquals(90.0, pose!!.yawDeg, 1e-9)
    }

    @Test
    fun aToeRaisedAboveTheHeelReadsAsPositivePitch() {
        // 3-4-5 triangle: horizontal 0.24 m (z), vertical 0.07 m (y). The 3D length is 0.25 m.
        val toe = doubleArrayOf(0.0, 0.07, 0.24)
        val pose = FootSnapshot.pose(heel, toe)

        assertNotNull(pose)
        assertEquals(Math.toDegrees(Math.atan2(0.07, 0.24)), pose!!.pitchDeg, 1e-9)
        assertTrue(pose.pitchDeg > 0.0)
    }

    @Test
    fun theLengthIsTheFull3DDistanceNotTheFloorPlaneOne() {
        // The same 0.24 m horizontal foot, tilted: the physical foot is 0.25 m, not 0.24 m.
        val pose = FootSnapshot.pose(heel, doubleArrayOf(0.0, 0.07, 0.24))

        assertNotNull(pose)
        assertEquals(0.25, pose!!.lengthMeters, 1e-9)
    }

    @Test
    fun thePoseCarriesTheHeelPosition() {
        val pose = FootSnapshot.pose(doubleArrayOf(0.1, 0.2, 0.3), doubleArrayOf(0.1, 0.2, 0.55))

        assertNotNull(pose)
        assertEquals(0.1, pose!!.heelX, 1e-9)
        assertEquals(0.2, pose.heelY, 1e-9)
        assertEquals(0.3, pose.heelZ, 1e-9)
    }

    @Test
    fun aLengthOutsideTheFootRangeIsRefusedNotClamped() {
        assertNull(FootSnapshot.pose(heel, doubleArrayOf(0.0, 0.0, 0.19)))
        assertNull(FootSnapshot.pose(heel, doubleArrayOf(0.0, 0.0, 0.35)))
    }

    @Test
    fun theRangeEndsAreAccepted() {
        assertNotNull(FootSnapshot.pose(heel, doubleArrayOf(0.0, 0.0, FootSnapshot.MIN_LENGTH_M)))
        assertNotNull(FootSnapshot.pose(heel, doubleArrayOf(0.0, 0.0, FootSnapshot.MAX_LENGTH_M)))
    }

    @Test
    fun aNonFiniteOrDegenerateReadingIsNotAFoot() {
        assertNull(FootSnapshot.pose(heel, doubleArrayOf(Double.NaN, 0.0, 0.25)))
        assertNull(FootSnapshot.pose(heel, doubleArrayOf(0.0, Double.POSITIVE_INFINITY, 0.25)))
        // Heel and toe at one point: there is no direction to read.
        assertNull(FootSnapshot.pose(heel, doubleArrayOf(0.0, 0.0, 0.0)))
    }

    @Test
    fun aShortArrayIsRefusedRatherThanIndexedOutOfBounds() {
        assertNull(FootSnapshot.pose(doubleArrayOf(0.0, 0.0), doubleArrayOf(0.0, 0.0, 0.25)))
    }

    // ── The stabilizer: several consistent samples before a capture is accepted ────────────

    @Test
    fun theCaptureIsAcceptedOnlyAfterTheRequiredConsistentSamples() {
        val stabilizer = FootSnapshotStabilizer(requiredSamples = 5)
        val (h, t) = footAt(20.0)

        for (count in 1..4) {
            val reading = stabilizer.offer(h, t)
            assertEquals(count, reading.count)
            assertNull(reading.pose)
        }
        val fifth = stabilizer.offer(h, t)
        assertEquals(5, fifth.count)
        assertNotNull(fifth.pose)
        assertEquals(20.0, fifth.pose!!.yawDeg, 1e-6)
    }

    @Test
    fun aHeelAndToeLabelledTheOtherWayRoundIsOrientedNotReadAsATurn() {
        // Alternate the labels: the same foot, read from both ends. Without the fix this reads as
        // a 180° turn on every other frame and never settles.
        val stabilizer = FootSnapshotStabilizer(requiredSamples = 5)
        val (h, t) = footAt(40.0)

        var last: FootSnapshotStabilizer.Reading? = null
        for (i in 0 until 5) {
            last = if (i % 2 == 0) stabilizer.offer(h, t) else stabilizer.offer(t, h)
        }

        assertEquals(5, last!!.count)
        assertNotNull(last.pose)
        assertEquals(40.0, last.pose!!.yawDeg, 1e-6)
        assertTrue(
            "the accepted heel must stay at the original heel, not the swapped one",
            kotlin.math.abs(last.pose!!.heelX) < 1e-9 && kotlin.math.abs(last.pose!!.heelZ) < 1e-9,
        )
    }

    @Test
    fun aYawJumpRestartsTheStreakRatherThanBeingAveraged() {
        val stabilizer = FootSnapshotStabilizer(requiredSamples = 5)
        repeat(3) { stabilizer.offer(footAt(0.0).first, footAt(0.0).second) }

        // 30° away is outside the 8° tolerance: the streak restarts at one.
        val jumped = stabilizer.offer(footAt(30.0).first, footAt(30.0).second)
        assertEquals(1, jumped.count)
        assertNull(jumped.pose)
    }

    @Test
    fun aLengthJumpRestartsTheStreak() {
        val stabilizer = FootSnapshotStabilizer(requiredSamples = 5)
        repeat(3) { stabilizer.offer(footAt(0.0, 0.25).first, footAt(0.0, 0.25).second) }

        // 30 mm longer is outside the 10 mm tolerance.
        val resized = stabilizer.offer(footAt(0.0, 0.28).first, footAt(0.0, 0.28).second)
        assertEquals(1, resized.count)
    }

    @Test
    fun aRefusedReadingBreaksTheStreakSoSamplesMustBeConsecutive() {
        val stabilizer = FootSnapshotStabilizer(requiredSamples = 5)
        repeat(3) { stabilizer.offer(footAt(0.0).first, footAt(0.0).second) }

        // A pair that is not a foot (too short) resets the streak to zero.
        assertEquals(0, stabilizer.offer(heel, doubleArrayOf(0.0, 0.0, 0.10)).count)

        var reading: FootSnapshotStabilizer.Reading? = null
        repeat(4) { reading = stabilizer.offer(footAt(0.0).first, footAt(0.0).second) }
        assertEquals(4, reading!!.count)
        assertNull("four good samples after a break must not be enough", reading!!.pose)
    }

    @Test
    fun theAcceptedPoseIsTheMedianNotOneFrame() {
        val stabilizer = FootSnapshotStabilizer(requiredSamples = 5)
        // Length jitter inside the 10 mm tolerance; the median is the middle value, 250 mm.
        val lengths = doubleArrayOf(0.250, 0.252, 0.248, 0.251, 0.249)
        var reading: FootSnapshotStabilizer.Reading? = null
        for (length in lengths) {
            val (h, t) = footAt(0.0, length)
            reading = stabilizer.offer(h, t)
        }

        assertNotNull(reading!!.pose)
        assertEquals(0.250, reading.pose!!.lengthMeters, 1e-9)
    }
}
