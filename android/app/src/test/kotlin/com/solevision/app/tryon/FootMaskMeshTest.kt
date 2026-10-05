package com.solevision.app.tryon

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `FootMaskMesh` — V4.4's mask→geometry arithmetic, pinned without a GPU.
 *
 * What a device would otherwise have to tell us, and what each group here decides instead:
 *
 *  1. **Orientation.** Bounds are row-major and top-down in normalized image space, the same
 *     space the pose points use. A flipped axis here is an occlusion drawn upsidedown or mirrored
 *     on a phone — a desk answer, not a field one.
 *  2. **Thresholding through signed bytes.** A Kotlin `Byte` of 200 is `-56`; comparing it raw
 *     would call almost every real mask empty.
 *  3. **Dilation, and what it does to the edges.** One lit cell becomes a 3×3 block, and its
 *     emitted bounds are exactly that block's — the arithmetic is exact on purpose
 *     (36 sub-cells for one cell at 32×32 with `UPSAMPLE = 2`), so a change in the thresholds or
 *     the filter cannot silently erode the foot.
 *  4. **Totality.** Null, short, empty and all-background masks all answer "nothing to draw"
 *     rather than throwing: the mask is an auxiliary draw and one dropped frame is legal.
 */
class FootMaskMeshTest {

    private fun maskOf(vararg lit: Pair<Int, Int>, size: Int = FootMaskMesh.MASK_SIZE): ByteArray {
        val mask = ByteArray(size * size)
        for ((x, y) in lit) mask[y * size + x] = 0xFF.toByte()
        return mask
    }

    /** A `ByteArray` whose cells can hold 0–255 without sign confusion. */
    private fun maskWith(
        vararg cells: Triple<Int, Int, Int>,
        size: Int = FootMaskMesh.MASK_SIZE,
    ): ByteArray {
        val mask = ByteArray(size * size)
        for ((x, y, value) in cells) mask[y * size + x] = value.toByte()
        return mask
    }

    private fun FootMaskMesh.Quads.hasQuad(u0: Float, v0: Float, u1: Float, v1: Float): Boolean {
        for (q in 0 until count) {
            if (bounds[q * 4] == u0 && bounds[q * 4 + 1] == v0 &&
                bounds[q * 4 + 2] == u1 && bounds[q * 4 + 3] == v1
            ) {
                return true
            }
        }
        return false
    }

    // ── Totality ────────────────────────────────────────────────────────────────────────────

    @Test
    fun `null and short masks have nothing to draw`() {
        assertTrue(FootMaskMesh.build(null).isEmpty)
        assertTrue(FootMaskMesh.build(ByteArray(0)).isEmpty)
        assertTrue(FootMaskMesh.build(ByteArray(31 * 31), 32).isEmpty)
    }

    @Test
    fun `an all-background mask has nothing to draw`() {
        assertTrue(FootMaskMesh.build(ByteArray(32 * 32)).isEmpty)
    }

    // ── Threshold ───────────────────────────────────────────────────────────────────────────

    @Test
    fun `the threshold is inclusive at FOREGROUND_BYTE`() {
        val below = maskWith(Triple(16, 16, FootMaskMesh.FOREGROUND_BYTE - 1))
        val at = maskWith(Triple(16, 16, FootMaskMesh.FOREGROUND_BYTE))

        assertTrue("127 is background", FootMaskMesh.build(below).isEmpty)
        assertTrue("128 is foreground", !FootMaskMesh.build(at).isEmpty)
    }

    @Test
    fun `high bytes decode through the sign bit`() {
        // 200 and 255 are negative as Kotlin Bytes; both are plainly foreground on the wire.
        val mask = maskWith(Triple(16, 16, 200), Triple(20, 20, 255))
        val quads = FootMaskMesh.build(mask)

        assertTrue("a signed compare would have found no foreground at all", !quads.isEmpty)
        assertTrue("both cells contribute", quads.count > 36)
    }

    // ── Geometry ────────────────────────────────────────────────────────────────────────────

    @Test
    fun `one lit cell becomes the dilated block, exactly`() {
        val quads = FootMaskMesh.build(maskOf(16 to 16))

        // 3×3 dilated cells, UPSAMPLE 2 → six sub-cells per axis.
        assertEquals(36, quads.count)
        // Cell 16's block runs from cell 15 to cell 18; 64 sub-cells across the image.
        var minU = 1f
        var maxU = 0f
        var minV = 1f
        var maxV = 0f
        for (q in 0 until quads.count) {
            minU = minOf(minU, quads.bounds[q * 4])
            minV = minOf(minV, quads.bounds[q * 4 + 1])
            maxU = maxOf(maxU, quads.bounds[q * 4 + 2])
            maxV = maxOf(maxV, quads.bounds[q * 4 + 3])
        }
        assertEquals(30f / 64f, minU, 0f)
        assertEquals(30f / 64f, minV, 0f)
        assertEquals(36f / 64f, maxU, 0f)
        assertEquals(36f / 64f, maxV, 0f)
    }

    @Test
    fun `the originally lit cell is covered by its own four sub-cells`() {
        val quads = FootMaskMesh.build(maskOf(16 to 16))

        // Cell 16 spans [16/32, 17/32]; its four sub-cells are at 16.0, 16.5 on each axis.
        val u0 = 32f / 64f
        val u1 = 33f / 64f
        val u2 = 34f / 64f
        assertTrue(quads.hasQuad(u0, u0, u1, u1))
        assertTrue(quads.hasQuad(u1, u0, u2, u1))
        assertTrue(quads.hasQuad(u0, u1, u1, u2))
        assertTrue(quads.hasQuad(u1, u1, u2, u2))
    }

    @Test
    fun `orientation is top-down and row-major`() {
        val topLeft = FootMaskMesh.build(maskOf(0 to 0))
        val bottomRight = FootMaskMesh.build(maskOf(31 to 31))

        // Top-left corner: the block runs down-right from the origin, and the first quad is its
        // top-left sub-cell.
        assertTrue("top-left starts at the origin", topLeft.bounds[0] == 0f && topLeft.bounds[1] == 0f)
        var maxU = 0f
        for (q in 0 until topLeft.count) maxU = maxOf(maxU, topLeft.bounds[q * 4 + 2])
        assertTrue("top-left stays in the top-left", maxU < 0.25f)

        // Bottom-right corner: everything is in the far quadrant.
        var minU = 1f
        var minV = 1f
        for (q in 0 until bottomRight.count) {
            minU = minOf(minU, bottomRight.bounds[q * 4])
            minV = minOf(minV, bottomRight.bounds[q * 4 + 1])
        }
        assertTrue("bottom-right stays in the bottom-right", minU > 0.75f && minV > 0.75f)
    }

    @Test
    fun `a mask that touches the frame edge does not fall off it`() {
        val quads = FootMaskMesh.build(maskOf(0 to 0))

        // The 3×3 block is clamped at the border (cells 0..1), and the sub-cells covering it are
        // four per axis — bounds never go below zero and stop at the block's edge.
        assertEquals(16, quads.count)
        for (q in 0 until quads.count) {
            assertTrue(quads.bounds[q * 4] >= 0f)
            assertTrue(quads.bounds[q * 4 + 1] >= 0f)
            assertTrue(quads.bounds[q * 4 + 2] <= 4f / 64f)
            assertTrue(quads.bounds[q * 4 + 3] <= 4f / 64f)
        }
    }

    @Test
    fun `a fully lit mask covers the image, quad for quad`() {
        val quads = FootMaskMesh.build(ByteArray(32 * 32) { 0xFF.toByte() })

        assertEquals(FootMaskMesh.MAX_QUADS, quads.count)
        assertEquals(FootMaskMesh.MAX_QUADS * 4, quads.bounds.size)
        // First and last quads pin the corners and the sub-cell size.
        assertTrue(quads.hasQuad(0f, 0f, 1f / 64f, 1f / 64f))
        assertTrue(quads.hasQuad(63f / 64f, 63f / 64f, 1f, 1f))
    }

    @Test
    fun `every quad is well formed and inside the image`() {
        val quads = FootMaskMesh.build(maskOf(10 to 10, 11 to 10, 10 to 11, 11 to 11))

        assertTrue(!quads.isEmpty)
        assertEquals(quads.count * 4, quads.bounds.size)
        for (q in 0 until quads.count) {
            val u0 = quads.bounds[q * 4]
            val v0 = quads.bounds[q * 4 + 1]
            val u1 = quads.bounds[q * 4 + 2]
            val v1 = quads.bounds[q * 4 + 3]
            assertTrue("u0 < u1", u0 < u1)
            assertTrue("v0 < v1", v0 < v1)
            assertTrue("inside the image", u0 >= 0f && v0 >= 0f && u1 <= 1f && v1 <= 1f)
        }
    }

    @Test
    fun `maskSize scales the arithmetic, not just the input`() {
        val quads = FootMaskMesh.build(maskOf(0 to 0, size = 4), maskSize = 4)

        // 4×4 mask, UPSAMPLE 2 → 8 sub-cells per axis, each 1/8 of the image. The clamped 3×3
        // block at the origin is covered by sub-cells 0..3, i.e. the first half of the image.
        assertEquals(16, quads.count)
        var maxU = 0f
        for (q in 0 until quads.count) {
            val u0 = quads.bounds[q * 4]
            val u1 = quads.bounds[q * 4 + 2]
            assertTrue("sub-cell width is 1/8", u1 - u0 == 1f / 8f)
            assertTrue("inside the image", u1 <= 1f)
            maxU = maxOf(maxU, u1)
        }
        assertEquals(1f / 2f, maxU, 0f)
    }
}
