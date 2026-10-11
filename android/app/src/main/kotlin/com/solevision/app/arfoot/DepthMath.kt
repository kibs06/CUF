package com.solevision.app.arfoot

/**
 * Pure math behind the depth-based measurement points used by the foot scan.
 *
 * Why depth: a floor-plane raycast lands on the floor *behind* the foot's
 * silhouette, so lengths and widths are projected onto the floor and skew with
 * foot height and camera angle. ARCore depth gives the distance to the foot's
 * own surface, so the point can be unprojected to 3D directly.
 *
 * Kept free of Android types so it can be unit-tested on the JVM.
 */

/** Shortest believable distance from the camera to a foot surface, in mm. */
const val MIN_FOOT_DEPTH_MM = 100

/** Longest believable distance from the camera to a foot surface, in mm. */
const val MAX_FOOT_DEPTH_MM = 2000

/** Valid depth neighbours required before a pixel's depth is trusted. */
const val MIN_DEPTH_NEIGHBOURS = 3

/**
 * ARCore DEPTH16 pixels: the lower 13 bits hold the depth in millimetres and
 * the upper 3 bits hold confidence. Only the depth is used here.
 */
fun depthMmFromRaw16(raw: Int): Int = raw and 0x1FFF

/**
 * Median of the plausible depth values (mm) in a small neighbourhood, or null
 * when fewer than [MIN_DEPTH_NEIGHBOURS] are plausible. The median rejects the
 * single-pixel noise that is common at object edges.
 */
fun medianPlausibleDepthMm(values: List<Int>): Int? {
    val valid = values.filter { it in MIN_FOOT_DEPTH_MM..MAX_FOOT_DEPTH_MM }.sorted()
    if (valid.size < MIN_DEPTH_NEIGHBOURS) return null
    return valid[valid.size / 2]
}

/**
 * Distance to the NEAREST plausible surface in the neighbourhood, in mm.
 *
 * The foot's measurement points sit on the silhouette edge, and a DEPTH16 pixel
 * straddling that edge holds a blend of the foot's own surface and whatever lies
 * beyond it — usually the floor, which is farther away. A median takes the
 * majority of the window, so at an edge it returns the surface *behind* the
 * foot: the point then unprojects past the foot, and both the measured length
 * and width come out proportionally too large.
 *
 * The surface worth measuring is the near one, because at a silhouette edge the
 * foot is in front of whatever shows around it. A low percentile (not the raw
 * minimum) keeps that while still ignoring a single wild pixel.
 */
fun nearestPlausibleDepthMm(values: List<Int>): Int? {
    val valid = values.filter { it in MIN_FOOT_DEPTH_MM..MAX_FOOT_DEPTH_MM }.sorted()
    if (valid.size < MIN_DEPTH_NEIGHBOURS) return null
    return valid[(valid.size - 1) / 4]
}

/**
 * Unprojects an image pixel with depth [depthM] (metres along the optical axis)
 * into ARCore camera space: +X right, +Y up, looking down -Z.
 *
 * Image pixels have their origin at the top-left with +Y downward, so the
 * vertical axis is negated.
 */
/**
 * How far below the floor plane a depth point may sit before it is rejected, in
 * metres. The floor plane itself carries a few cm of error, so a point must sit
 * clearly beneath it, not just at it.
 */
const val FLOOR_TOLERANCE_M = 0.01f

/**
 * True when a depth point lies below the floor by more than [toleranceM]. A
 * point under the floor cannot be on the foot: the depth read past the foot to
 * the surface behind it, and that point inflates the measured length.
 */
fun isBelowFloor(pointY: Float, floorY: Float, toleranceM: Float = FLOOR_TOLERANCE_M): Boolean =
    pointY < floorY - toleranceM

/**
 * Height above the floor of the foot's measured edge points, in metres. Used by
 * the no-depth fallback, which lifts a floor hit to this height. It is an
 * estimate: calibrate it against a foot of known length.
 */
const val FOOT_SILHOUETTE_HEIGHT_M = 0.03f

/**
 * Moves a floor hit along its camera ray to [heightM] above the floor.
 *
 * A ray through the foot's edge pixel strikes the floor [floorPoint] behind the
 * foot. Its true point lies on the same ray, [heightM] up, so the floor hit is
 * too far from the camera by the factor H / (H - heightM), where H is the
 * camera's height above the floor. Lifting the hit onto the foot-height plane
 * removes that factor using the real camera height and tilt, so it stays right
 * as the phone moves.
 *
 * Returns null when the camera is not above [heightM] (no valid ray to lift).
 */
fun liftAlongRayToHeight(
    camera: FloatArray,
    floorPoint: FloatArray,
    heightM: Float,
): FloatArray? {
    val cameraHeight = camera[1] - floorPoint[1]
    if (cameraHeight <= heightM) return null
    // Fraction of the way from the camera to the floor hit where the foot-height plane lies.
    val t = (cameraHeight - heightM) / cameraHeight
    return floatArrayOf(
        camera[0] + (floorPoint[0] - camera[0]) * t,
        camera[1] + (floorPoint[1] - camera[1]) * t,
        camera[2] + (floorPoint[2] - camera[2]) * t,
    )
}

fun unprojectToCameraSpace(
    imageX: Float,
    imageY: Float,
    depthM: Float,
    fx: Float,
    fy: Float,
    cx: Float,
    cy: Float,
): FloatArray = floatArrayOf(
    (imageX - cx) / fx * depthM,
    -(imageY - cy) / fy * depthM,
    -depthM,
)
