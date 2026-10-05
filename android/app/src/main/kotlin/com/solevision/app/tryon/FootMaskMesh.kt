package com.solevision.app.tryon

/**
 * The mask→geometry step of **V4.4's occlusion**, pure Kotlin so it can be
 * unit-tested without a GPU, an engine or a device.
 *
 * `lib/utils/foot_mask.dart` sends a 32×32 byte mask (row-major, top-down,
 * 0–255) in the detection's own normalized image space — the space the
 * heel/toe points are expressed in. This turns that field into the quads
 * [FootMaskOverlay] draws: mask-shaped geometry with the camera's own material,
 * painted *after* the shoe, which is what makes the foot read as inside it.
 *
 * **Why quads and not a stencil buffer.** Filament exposes per-instance stencil
 * state, so a stencil route exists — but it needs a stencil-capable swap chain
 * (a change to how this view's surface is created, unverifiable from a desk)
 * and a stencil test on the *shoe's* material instances, which belong to glTF's
 * provider rather than to us. Painting the camera's pixels back over the shoe
 * through a mask-shaped mesh ends in the same pixels with none of that: the
 * mask quads sample the very texture the full-screen feed samples, so the
 * colour under the shoe is identical to the colour around it by construction.
 *
 * Three steps, each one testable on its own:
 *
 *  1. **Threshold** at [FOREGROUND_BYTE]. Out-of-range bytes decode through
 *     `and 0xFF` — a Kotlin `Byte` is signed, and 200 and 255 both arrive
 *     negative.
 *  2. **Dilate** by [DILATE_CELLS] (8-connected max filter, clamped at the
 *     edges). A segmentation mask ends at the skin's edge; the shoe's shadow
 *     and the mesh's own coverage mean the occlusion should be slightly
 *     *bigger* than the foot, not exactly it — §2.10's "dilated slightly".
 *  3. **Upsample ×[UPSAMPLE]** with a bilinear sample of the binary field at
 *     each sub-cell centre; a sub-cell is drawn when that sample reaches
 *     [COVERAGE_THRESHOLD]. Bilinear + threshold is what rounds the 32×32
 *     staircase into a silhouette, and the arithmetic keeps every originally
 *     lit cell: its four sub-cells sample at 0.5625 when surrounded by
 *     background — above the threshold — so the upsampler never erodes the
 *     foot it was given.
 *
 * Everything is in **normalized upright-image space**: `u = x / maskSize`,
 * `v = y / maskSize`, top-down. `FootMaskOverlay` maps those bounds to the
 * viewport with the same upright-image→viewport mapping the heel and toe rays
 * are cast through, so the occlusion cannot drift from the anchor.
 */
internal object FootMaskMesh {

    /** The wire mask's side — `kFootMaskSize` in `foot_mask.dart`. */
    const val MASK_SIZE = 32

    /** Sub-cells per mask cell. 2 doubles the silhouette's resolution. */
    const val UPSAMPLE = 2

    /** Dilation radius in mask cells (~1/32 of the image per pass). */
    const val DILATE_CELLS = 1

    /** A byte at or above this (0–255) is foreground. */
    const val FOREGROUND_BYTE = 128

    /** Bilinear coverage at which a sub-cell is drawn. */
    const val COVERAGE_THRESHOLD = 0.5f

    /** The largest geometry [build] can return: every sub-cell lit. */
    const val MAX_QUADS = MASK_SIZE * UPSAMPLE * MASK_SIZE * UPSAMPLE

    /**
     * Quads in normalized upright-image space: one `[u0, v0, u1, v1]` per drawn
     * sub-cell, `[count]` of them, in row-major order (top-down). The caller
     * builds the two triangles from the four corners.
     */
    class Quads(val bounds: FloatArray, val count: Int) {
        val isEmpty: Boolean get() = count == 0

        companion object {
            val EMPTY = Quads(FloatArray(0), 0)
        }
    }

    /**
     * Builds the mask geometry, or [Quads.EMPTY] for a mask with nothing to
     * draw. Never throws: a null, short or empty mask is "no occlusion this
     * frame", which is the same answer a stale mask gets.
     *
     * [maskSize] is a parameter rather than the constant so the arithmetic can
     * be tested at sizes where the interesting cases are visible; the wire
     * always sends [MASK_SIZE].
     */
    fun build(mask: ByteArray?, maskSize: Int = MASK_SIZE): Quads {
        if (mask == null || maskSize <= 0) return Quads.EMPTY
        if (mask.size < maskSize * maskSize) return Quads.EMPTY

        // 1. Threshold. `and 0xFF` is not decoration: a signed Byte of value
        // 200 decodes as -56, and comparing it raw would call a confident foot
        // empty.
        val foreground = BooleanArray(maskSize * maskSize)
        var any = false
        for (i in foreground.indices) {
            if ((mask[i].toInt() and 0xFF) >= FOREGROUND_BYTE) {
                foreground[i] = true
                any = true
            }
        }
        if (!any) return Quads.EMPTY

        // 2. Dilate.
        val field = if (DILATE_CELLS > 0) dilate(foreground, maskSize) else foreground

        // 3. Upsample with a bilinear sample at each sub-cell centre.
        val side = maskSize * UPSAMPLE
        val cells = BooleanArray(side * side)
        var count = 0
        for (sy in 0 until side) {
            for (sx in 0 until side) {
                // In mask-cell units, with integer values at *cell centres*
                // (0.5, 1.5, …), so 0.0 sits on the boundary between cells.
                val x = (sx + 0.5f) / UPSAMPLE - 0.5f
                val y = (sy + 0.5f) / UPSAMPLE - 0.5f
                if (bilinear(field, maskSize, x, y) >= COVERAGE_THRESHOLD) {
                    cells[sy * side + sx] = true
                    count++
                }
            }
        }
        if (count == 0) return Quads.EMPTY

        val bounds = FloatArray(count * 4)
        var w = 0
        for (sy in 0 until side) {
            for (sx in 0 until side) {
                if (!cells[sy * side + sx]) continue
                bounds[w++] = sx.toFloat() / side
                bounds[w++] = sy.toFloat() / side
                bounds[w++] = (sx + 1).toFloat() / side
                bounds[w++] = (sy + 1).toFloat() / side
            }
        }
        return Quads(bounds, count)
    }

    /** One 8-connected max-filter pass per dilation cell, edges clamped. */
    private fun dilate(source: BooleanArray, maskSize: Int): BooleanArray {
        var current = source
        repeat(DILATE_CELLS) {
            val next = BooleanArray(current.size)
            for (y in 0 until maskSize) {
                for (x in 0 until maskSize) {
                    if (!current[y * maskSize + x]) continue
                    for (dy in -1..1) {
                        for (dx in -1..1) {
                            val nx = x + dx
                            val ny = y + dy
                            if (nx < 0 || ny < 0 || nx >= maskSize || ny >= maskSize) continue
                            next[ny * maskSize + nx] = true
                        }
                    }
                }
            }
            current = next
        }
        return current
    }

    /**
     * Bilinear sample of a binary field at ([x], [y]) in mask-cell units where
     * integer coordinates are cell centres. Coordinates outside the field clamp
     * to its edge, which is what keeps a foot touching the frame border from
     * losing its outline.
     */
    private fun bilinear(field: BooleanArray, maskSize: Int, x: Float, y: Float): Float {
        val x0 = kotlin.math.floor(x).toInt().coerceIn(0, maskSize - 1)
        val y0 = kotlin.math.floor(y).toInt().coerceIn(0, maskSize - 1)
        val x1 = (x0 + 1).coerceAtMost(maskSize - 1)
        val y1 = (y0 + 1).coerceAtMost(maskSize - 1)
        val fx = (x - x0).coerceIn(0f, 1f)
        val fy = (y - y0).coerceIn(0f, 1f)

        fun at(cx: Int, cy: Int): Float = if (field[cy * maskSize + cx]) 1f else 0f

        val top = at(x0, y0) * (1f - fx) + at(x1, y0) * fx
        val bottom = at(x0, y1) * (1f - fx) + at(x1, y1) * fx
        return top * (1f - fy) + bottom * fy
    }
}
