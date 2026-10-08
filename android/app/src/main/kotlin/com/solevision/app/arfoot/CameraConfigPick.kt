package com.solevision.app.arfoot

/**
 * The sizes of one ARCore camera config, as the scorer sees them.
 *
 * [index] is the config's position in the list the session offered, so the
 * caller can apply the chosen one.
 */
data class CameraConfigShape(
    val index: Int,
    val textureWidth: Int,
    val textureHeight: Int,
    val imageWidth: Int,
    val imageHeight: Int,
)

/**
 * The share of the cropped axis that is visible when a texture fills a display
 * with a centre crop (ARCore's default fill). 1.0 means nothing is cropped.
 */
fun visibleFraction(textureAspect: Double, displayAspect: Double): Double =
    if (textureAspect > displayAspect) displayAspect / textureAspect
    else textureAspect / displayAspect

/**
 * Index of the config to apply, or null when there is nothing to choose from.
 *
 * Why this exists: ARCore fills the view with the camera texture and crops what
 * does not fit. On a tall phone the usual 16:9 stream shows only part of the
 * width, which reads as a zoomed-in feed next to the normal camera app. A 4:3
 * stream from the same camera shows more of the width.
 *
 * Priority:
 * 1. Configs whose CPU image and GL texture share an aspect. The foot scan maps
 *    the detector's normalised points through the CPU image, so a mismatch would
 *    put the points off the drawn foot.
 * 2. The widest visible view on this display.
 * 3. Texture area, for sharpness, when the views are equally wide.
 */
fun pickWidestCameraConfig(
    candidates: List<CameraConfigShape>,
    displayAspect: Double,
): Int? {
    if (candidates.isEmpty() || displayAspect <= 0.0) return null
    return candidates
        .maxWithOrNull(
            compareBy<CameraConfigShape>(
                { if (sameAspect(it)) 1 else 0 },
                { visibleFraction(it.textureWidth.toDouble() / it.textureHeight, displayAspect) },
                { it.textureWidth.toLong() * it.textureHeight },
            ),
        )
        ?.index
}

/** Whether the CPU image and GL texture of [shape] have the same aspect ratio. */
fun sameAspect(shape: CameraConfigShape): Boolean {
    if (shape.textureHeight <= 0 || shape.imageHeight <= 0) return false
    val texture = shape.textureWidth.toLong() * shape.imageHeight
    val image = shape.imageWidth.toLong() * shape.textureHeight
    // Compare w1/h1 == w2/h2 by cross-multiplying, so no floating-point rounding.
    return texture == image
}
