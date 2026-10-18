package com.solevision.app.tryon

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * **The still-capture pose: where a foot points and how it tilts, from one heel and toe pair.**
 *
 * The live mode projects the foot onto the floor plane and places the shoe yaw-only, because it
 * has no reliable height for the toe. A still capture measures both endpoints from depth, so the
 * toe's height is known and the foot's tilt can be read as well. This file is that reading, kept
 * pure (no Android imports) so it can be pinned on the JVM without a device.
 *
 * Coordinates are world metres, y-up, the same space as [FootPoseTracker.Sample.heel].
 */
internal object FootSnapshot {

    /**
     * The same foot range the live sample gate uses (`ArTryOnView.MIN_PLAUSIBLE_FOOT_M` and
     * `MAX_PLAUSIBLE_FOOT_M`). Kept as a copy here, not a reference, so this file stays free of
     * the view's Android types. Nothing enforces that the two stay equal, so a change to either
     * one has to be made to both.
     */
    const val MIN_LENGTH_M = 0.20
    const val MAX_LENGTH_M = 0.34

    /** Consecutive agreeing samples a capture needs before it is accepted. */
    const val REQUIRED_SAMPLES = 5

    /** How far a sample's yaw may sit from the streak's anchor and still agree. */
    const val YAW_TOLERANCE_DEG = 8.0

    /** How far a sample's 3D length may sit from the streak's median and still agree. */
    const val LENGTH_TOLERANCE_M = 0.010

    /**
     * The heel position in world metres, and the foot's direction and tilt.
     *
     * [yawDeg] turns the model's +Z onto the foot's floor-plane direction, matching
     * [FootPoseTracker]'s `atan2(forwardX, forwardZ)`.
     *
     * [pitchDeg] is the foot's tilt: positive when the toe is higher than the heel.
     *
     * [lengthMeters] is the full 3D heel-to-toe distance. It is the physical foot length, so it
     * is what the shoe should be sized to. The floor-plane distance is shorter on a tilted foot
     * by `cos(pitch)`, which would undersize the shoe.
     */
    data class Pose(
        val heelX: Double,
        val heelY: Double,
        val heelZ: Double,
        val yawDeg: Double,
        val pitchDeg: Double,
        val lengthMeters: Double,
    )

    /**
     * The pose for one heel and toe pair, or null when the reading is not a foot.
     *
     * Null covers a short array, any non-finite coordinate, a degenerate pair (heel and toe at
     * the same point, so there is no direction), and a length outside [MIN_LENGTH_M] to
     * [MAX_LENGTH_M]. A null here means "do not capture", and it is never clamped into range.
     */
    fun pose(heel: DoubleArray, toe: DoubleArray): Pose? {
        if (heel.size < 3 || toe.size < 3) return null
        if (!heel.all { it.isFinite() } || !toe.all { it.isFinite() }) return null

        val dx = toe[0] - heel[0]
        val dy = toe[1] - heel[1]
        val dz = toe[2] - heel[2]
        val horizontal = sqrt(dx * dx + dz * dz)
        val length = sqrt(dx * dx + dy * dy + dz * dz)
        if (length < MIN_LENGTH_M || length > MAX_LENGTH_M) return null

        return Pose(
            heelX = heel[0],
            heelY = heel[1],
            heelZ = heel[2],
            yawDeg = Math.toDegrees(atan2(dx, dz)),
            pitchDeg = Math.toDegrees(atan2(dy, horizontal)),
            lengthMeters = length,
        )
    }

    /** Wraps an angle difference into (-180, 180]. */
    internal fun wrapDeg(deg: Double): Double {
        var value = deg % 360.0
        if (value > 180.0) value -= 360.0
        if (value <= -180.0) value += 360.0
        return value
    }
}

/**
 * **Accepts a still capture only after several consecutive samples agree.**
 *
 * One depth reading can be wrong in two ways that the single-sample pose cannot see:
 *
 *  1. **The heel and toe are labelled the other way round.** The reversed pair is the same foot,
 *     but its yaw is 180° off, so a shoe placed from it points the wrong way. Each sample is
 *     oriented to agree with the streak's first sample before it is compared, so a flipped label
 *     is corrected rather than read as movement.
 *  2. **A single frame is noise.** A sample must agree with the streak's yaw and length, so a
 *     one-frame glitch restarts the streak instead of becoming the capture.
 *
 * A refused reading (out of the foot range, or not a foot) breaks the streak. The samples must
 * be consecutive, not just several.
 *
 * Accepting returns the **median** of the streak, so the capture is not one frame's value.
 *
 * ⚠️ Orientation is consistent within a streak, but the first sample's labelling is taken as
 * given. Nothing here can tell from the points alone which end is the heel. That is a
 * device question, and the log shows it as a yaw that holds steady rather than one that flips.
 */
internal class FootSnapshotStabilizer(
    private val requiredSamples: Int = FootSnapshot.REQUIRED_SAMPLES,
    private val yawToleranceDeg: Double = FootSnapshot.YAW_TOLERANCE_DEG,
    private val lengthToleranceM: Double = FootSnapshot.LENGTH_TOLERANCE_M,
) {

    /** How many samples agree so far, and the accepted pose once there are enough. */
    data class Reading(val count: Int, val pose: FootSnapshot.Pose?)

    private val streak = ArrayList<FootSnapshot.Pose>()
    private var anchorYawDeg = 0.0

    /**
     * Feeds one heel and toe pair, in world metres.
     *
     * Returns the streak's count, and the accepted median pose once the count reaches the
     * required number. A pair that is not a foot resets the streak and returns a count of zero.
     */
    fun offer(heel: DoubleArray, toe: DoubleArray): Reading {
        val raw = FootSnapshot.pose(heel, toe)
        if (raw == null) {
            reset()
            return Reading(0, null)
        }

        var sample = raw
        if (streak.isNotEmpty() &&
            abs(FootSnapshot.wrapDeg(raw.yawDeg - anchorYawDeg)) > 90.0
        ) {
            // The labels are the other way round: the same foot, read from its other end.
            // The reversed pair is valid whenever the original was, because the length is the same.
            sample = FootSnapshot.pose(toe, heel) ?: run {
                reset()
                return Reading(0, null)
            }
        }

        if (streak.isNotEmpty()) {
            val yawDelta = FootSnapshot.wrapDeg(sample.yawDeg - anchorYawDeg)
            val lengthDelta = sample.lengthMeters - medianOf(streak.map { it.lengthMeters })
            if (abs(yawDelta) > yawToleranceDeg || abs(lengthDelta) > lengthToleranceM) {
                streak.clear()
            }
        }
        if (streak.isEmpty()) anchorYawDeg = sample.yawDeg
        streak.add(sample)

        return Reading(streak.size, accepted())
    }

    /** Forgets the streak. Called when the session ends, or a reading is refused elsewhere. */
    fun reset() {
        streak.clear()
    }

    /** The median pose of the streak once it has [requiredSamples] samples; otherwise null. */
    private fun accepted(): FootSnapshot.Pose? {
        if (streak.size < requiredSamples) return null
        val yawDeltas = streak.map { FootSnapshot.wrapDeg(it.yawDeg - anchorYawDeg) }
        return FootSnapshot.Pose(
            heelX = medianOf(streak.map { it.heelX }),
            heelY = medianOf(streak.map { it.heelY }),
            heelZ = medianOf(streak.map { it.heelZ }),
            yawDeg = FootSnapshot.wrapDeg(anchorYawDeg + medianOf(yawDeltas)),
            pitchDeg = medianOf(streak.map { it.pitchDeg }),
            lengthMeters = medianOf(streak.map { it.lengthMeters }),
        )
    }

    private fun medianOf(values: List<Double>): Double {
        val sorted = values.sorted()
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 1) sorted[mid] else (sorted[mid - 1] + sorted[mid]) / 2.0
    }
}
