package com.solevision.app.tryon

import java.nio.ByteBuffer
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Carries the heel and toe points from one camera frame to the next (V4.11).
 *
 * Why this exists: the foot detector runs a few times a second, and between its results the shoe
 * had nothing to follow — when the customer moved the foot, it stayed where it was. Tracking the
 * same points in the camera image closes that gap, so the shoe moves with the foot between
 * detections.
 *
 * The tracker works on a decimated grayscale copy of the camera image (a quarter of the resolution),
 * so the per-frame cost stays small. It is pure Kotlin so it can be unit-tested on the JVM.
 */

/** An 8-bit grayscale image, row-major. */
class GrayImage(val width: Int, val height: Int, private val pixels: ByteArray) {
    fun at(x: Int, y: Int): Float = (pixels[y * width + x].toInt() and 0xFF).toFloat()

    /** Bilinear sample, clamped to the image border. */
    fun sampleAt(x: Float, y: Float): Float {
        val cx = x.coerceIn(0f, (width - 1).toFloat())
        val cy = y.coerceIn(0f, (height - 1).toFloat())
        val x0 = cx.toInt()
        val y0 = cy.toInt()
        val x1 = min(x0 + 1, width - 1)
        val y1 = min(y0 + 1, height - 1)
        val fx = cx - x0
        val fy = cy - y0
        val top = at(x0, y0) * (1 - fx) + at(x1, y0) * fx
        val bottom = at(x0, y1) * (1 - fx) + at(x1, y1) * fx
        return top * (1 - fy) + bottom * fy
    }
}

object FootFlow {

    /** How far the tracker's patch reaches from the point it follows, in pixels of its level. */
    const val PATCH_HALF = 7

    /** Gauss-Newton iterations per level. */
    const val ITERATIONS = 12

    /**
     * Smallest eigenvalue of the patch's gradient matrix. A patch with too little texture (a flat
     * sock, a blank wall) cannot be located, so the tracker refuses it rather than guessing.
     */
    const val MIN_EIGEN = 300f

    /** Largest mean absolute brightness error after tracking a patch; above this, the match is gone. */
    const val MAX_RESIDUAL = 25f

    /** Pyramid levels: the base plus two halvings. */
    const val LEVELS = 3

    /**
     * Builds the tracking base image from an 8-bit Y plane by taking one pixel per [decimate] block.
     * Point sampling (not averaging) keeps the per-frame cost to a single pass over a quarter of the
     * pixels.
     */
    fun decimate(
        buffer: ByteBuffer,
        width: Int,
        height: Int,
        rowStride: Int,
        pixelStride: Int,
        decimate: Int,
    ): GrayImage {
        val w = width / decimate
        val h = height / decimate
        val out = ByteArray(w * h)
        for (y in 0 until h) {
            val rowBase = y * decimate * rowStride
            for (x in 0 until w) {
                out[y * w + x] = buffer.get(rowBase + x * decimate * pixelStride)
            }
        }
        return GrayImage(w, h, out)
    }

    /**
     * How sharp a tracking image is: the variance of its Laplacian (V4.12). Blur flattens the second
     * derivative, so a low value means the image is too soft to track or to measure from.
     */
    fun sharpness(image: GrayImage): Float {
        if (image.width < 3 || image.height < 3) return 0f
        var sum = 0.0
        var sumSq = 0.0
        var n = 0
        for (y in 1 until image.height - 1) {
            for (x in 1 until image.width - 1) {
                val lap = (4f * image.at(x, y) - image.at(x - 1, y) - image.at(x + 1, y) -
                    image.at(x, y - 1) - image.at(x, y + 1)).toDouble()
                sum += lap
                sumSq += lap * lap
                n++
            }
        }
        val mean = sum / n
        return (sumSq / n - mean * mean).toFloat()
    }

    /** The image and its halved copies, finest first. */
    fun pyramid(base: GrayImage, levels: Int = LEVELS): List<GrayImage> {
        val out = ArrayList<GrayImage>(levels)
        out.add(base)
        var current = base
        for (level in 1 until levels) {
            current = halve(current)
            out.add(current)
        }
        return out
    }

    private fun halve(image: GrayImage): GrayImage {
        val w = max(1, image.width / 2)
        val h = max(1, image.height / 2)
        val out = ByteArray(w * h)
        for (y in 0 until h) {
            for (x in 0 until w) {
                val sx = min(x * 2, image.width - 1)
                val sy = min(y * 2, image.height - 1)
                val sum = image.at(sx, sy) + image.at(min(sx + 1, image.width - 1), sy) +
                    image.at(sx, min(sy + 1, image.height - 1)) +
                    image.at(min(sx + 1, image.width - 1), min(sy + 1, image.height - 1))
                out[y * w + x] = (sum / 4f).toInt().toByte()
            }
        }
        return GrayImage(w, h, out)
    }

    /**
     * Where the point at ([x], [y]) in [prev] has moved to in [next], in the base image's pixels, or
     * null when the point cannot be followed (too little texture, or the match is lost).
     *
     * Coarse to fine: the estimate from each level seeds the next, finer one, so a fast move that
     * would leave the patch behind at full resolution is still found at the coarse level.
     */
    fun track(prev: List<GrayImage>, next: List<GrayImage>, x: Float, y: Float): Pair<Float, Float>? {
        val levels = min(prev.size, next.size)
        if (levels == 0) return null
        var guessX = x / (1 shl (levels - 1))
        var guessY = y / (1 shl (levels - 1))
        var result: Pair<Float, Float>? = null
        for (level in levels - 1 downTo 0) {
            val scale = 1 shl level
            val px = x / scale
            val py = y / scale
            val tracked = trackAtLevel(prev[level], next[level], px, py, guessX, guessY) ?: return null
            result = tracked
            guessX = tracked.first * 2f
            guessY = tracked.second * 2f
        }
        return result?.let { Pair(it.first, it.second) }
    }

    private fun trackAtLevel(
        prev: GrayImage,
        next: GrayImage,
        px: Float,
        py: Float,
        guessX: Float,
        guessY: Float,
    ): Pair<Float, Float>? {
        val half = PATCH_HALF
        val size = 2 * half + 1
        val n = size * size
        val template = FloatArray(n)
        val gx = FloatArray(n)
        val gy = FloatArray(n)
        var gxx = 0f
        var gxy = 0f
        var gyy = 0f
        var k = 0
        for (dy in -half..half) {
            for (dx in -half..half) {
                val x = px + dx
                val y = py + dy
                template[k] = prev.sampleAt(x, y)
                gx[k] = (prev.sampleAt(x + 1, y) - prev.sampleAt(x - 1, y)) * 0.5f
                gy[k] = (prev.sampleAt(x, y + 1) - prev.sampleAt(x, y - 1)) * 0.5f
                gxx += gx[k] * gx[k]
                gxy += gx[k] * gy[k]
                gyy += gy[k] * gy[k]
                k++
            }
        }
        val det = gxx * gyy - gxy * gxy
        val trace = gxx + gyy
        val minEigen = (trace - sqrt(max(0f, trace * trace - 4f * det))) / 2f
        if (minEigen < MIN_EIGEN || det <= 1e-6f) return null

        var nx = guessX
        var ny = guessY
        for (iteration in 0 until ITERATIONS) {
            var bx = 0f
            var by = 0f
            k = 0
            for (dy in -half..half) {
                for (dx in -half..half) {
                    val diff = template[k] - next.sampleAt(nx + dx, ny + dy)
                    bx += diff * gx[k]
                    by += diff * gy[k]
                    k++
                }
            }
            val stepX = (gyy * bx - gxy * by) / det
            val stepY = (-gxy * bx + gxx * by) / det
            nx += stepX
            ny += stepY
            if (abs(stepX) < 0.01f && abs(stepY) < 0.01f) break
        }

        // Residual check: after tracking, the patch must still look like the patch it came from.
        var residual = 0f
        k = 0
        for (dy in -half..half) {
            for (dx in -half..half) {
                residual += abs(template[k] - next.sampleAt(nx + dx, ny + dy))
                k++
            }
        }
        if (residual / n > MAX_RESIDUAL) return null
        return Pair(nx, ny)
    }
}
