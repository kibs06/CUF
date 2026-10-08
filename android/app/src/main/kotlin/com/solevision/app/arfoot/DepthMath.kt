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
 * Unprojects an image pixel with depth [depthM] (metres along the optical axis)
 * into ARCore camera space: +X right, +Y up, looking down -Z.
 *
 * Image pixels have their origin at the top-left with +Y downward, so the
 * vertical axis is negated.
 */
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
