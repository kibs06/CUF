package com.solevision.app.tryon

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

class FootFlowTest {

    /**
     * A smooth texture with no large flat regions, so every patch has gradient to lock onto.
     * Its frequency is kept low on purpose: a fine pattern aliases at the coarse pyramid levels once
     * the move is more than a few pixels, and skin and shoe surfaces are not that fine at the
     * tracker's working resolution.
     */
    private fun pattern(x: Float, y: Float): Float =
        128f + 50f * sin(0.12f * x) * cos(0.09f * y) + 30f * sin(0.07f * (x + y))

    private fun image(width: Int, height: Int, shiftX: Float, shiftY: Float): GrayImage {
        val bytes = ByteArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val v = pattern(x - shiftX, y - shiftY).coerceIn(0f, 255f)
                bytes[y * width + x] = v.toInt().toByte()
            }
        }
        return GrayImage(width, height, bytes)
    }

    @Test
    fun trackFollowsAShiftedPatchToTheRightPosition() {
        val prev = FootFlow.pyramid(image(256, 192, 0f, 0f))
        val next = FootFlow.pyramid(image(256, 192, 3f, 2f))

        // (60, 45) has texture in both directions. A point on a one-directional edge would be an
        // aperture-limited patch, which the tracker is right to refuse.
        val tracked = FootFlow.track(prev, next, 60f, 45f)

        assertNotNull(tracked)
        assertEquals(63f, tracked!!.first, 0.5f)
        assertEquals(47f, tracked.second, 0.5f)
    }

    @Test
    fun trackFollowsALargerMoveThroughThePyramid() {
        val prev = FootFlow.pyramid(image(320, 240, 0f, 0f))
        val next = FootFlow.pyramid(image(320, 240, 14f, -9f))

        val tracked = FootFlow.track(prev, next, 160f, 120f)

        assertNotNull(tracked)
        assertEquals(174f, tracked!!.first, 1.0f)
        assertEquals(111f, tracked.second, 1.0f)
    }

    @Test
    fun trackRefusesAFlatPatchInsteadOfGuessing() {
        val flat = GrayImage(128, 96, ByteArray(128 * 96) { 128.toByte() })
        val prev = FootFlow.pyramid(flat)
        val next = FootFlow.pyramid(flat)

        assertNull(FootFlow.track(prev, next, 64f, 48f))
    }

    @Test
    fun sharpnessIsZeroForAFlatImageAndHigherForDetail() {
        val flat = GrayImage(64, 48, ByteArray(64 * 48) { 90.toByte() })
        val checker = GrayImage(
            64,
            48,
            ByteArray(64 * 48) { i -> if (((i % 64) + (i / 64)) % 2 == 0) 0.toByte() else 255.toByte() },
        )
        val smooth = image(64, 48, 0f, 0f)

        assertEquals(0f, FootFlow.sharpness(flat), 0f)
        assertTrue(FootFlow.sharpness(checker) > FootFlow.sharpness(smooth))
    }

    @Test
    fun decimateTakesOnePixelPerBlock() {
        val width = 8
        val height = 8
        val bytes = ByteArray(width * height) { i -> (i % 256).toByte() }
        val buffer = java.nio.ByteBuffer.wrap(bytes)

        val small = FootFlow.decimate(buffer, width, height, width, 1, 4)

        assertEquals(2, small.width)
        assertEquals(2, small.height)
        assertEquals(0f, small.at(0, 0), 0f)
        assertEquals(4f, small.at(1, 0), 0f)
        assertEquals(32f, small.at(0, 1), 0f)
    }
}
