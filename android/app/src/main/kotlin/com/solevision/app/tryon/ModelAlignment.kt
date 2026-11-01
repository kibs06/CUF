package com.solevision.app.tryon

/**
 * Pure alignment math for authored shoe meshes (V4.9 device fix).
 *
 * The renderer historically assumed every mesh is authored toe-on-+Z with its
 * length on the Z extent: the load transform scaled by the Z half-extent and
 * the per-frame yaw assumed a +Z-forward mesh. The catalogue disagrees —
 * Luna Loafers is authored toe-on-−X (`forward_axis: '-x'`, 270 mm on X vs
 * 102 mm on Z), so it rendered ~2.65× oversize and 90° off. JBC Crown
 * (`-z`) renders backwards for the same reason.
 *
 * Two pure functions, JVM-tested, no Android imports:
 *
 * - [yawOffsetForForwardAxis]: the Y-rotation that brings an axis-authored
 *   mesh onto the tracker's +Z-forward convention. Explicit per-model
 *   `yawOffsetDeg` (alignment_json) wins when present — it is a hand-tuned
 *   override, not a default to average with.
 * - [authoredLengthExtent]: the horizontal extent the authored length runs
 *   on. Length is whichever horizontal axis is longer — a Z-long mesh keeps
 *   the old behaviour exactly, an X-long mesh stops rendering 2.65× big.
 */
internal object ModelAlignment {

    /**
     * Yaw offset in degrees for a `product_models.forward_axis` value.
     *
     * The tracker's `placedYawDeg` assumes a +Z-forward mesh
     * (`R(yaw)·(0,0,1) = forward`), so:
     * - `+z` → 0 (the old assumption, unchanged);
     * - `-z` → 180 (toe on −Z renders backwards otherwise);
     * - `-x` → +90 (toe on −X: `R(yaw+90)·(−1,0,0) = forward`);
     * - `+x` → −90 (mirror case of the above).
     *
     * Unknown, null or blank input answers 0 — the old behaviour — rather
     * than refusing, because a mesh with no stated axis still has to draw.
     * Matching is case-insensitive with whitespace trimmed, mirroring the
     * Dart resolver's normalization.
     */
    fun yawOffsetForForwardAxis(forwardAxis: String?): Double {
        return when (forwardAxis?.trim()?.lowercase()) {
            "-z" -> 180.0
            "-x" -> 90.0
            "+x" -> -90.0
            else -> 0.0
        }
    }

    /**
     * Resolve the effective yaw offset: an explicit per-model override wins,
     * otherwise the axis-derived one. A null override is "absent" (every row
     * in the catalogue today); NaN/infinite is treated as absent too, since a
     * bad number must not rotate a shoe off a foot.
     */
    /**
     * The yaw offset when no `forward_axis` metadata exists — derived from
     * the mesh's own bounding box instead. An explicit per-model override
     * still wins; otherwise an X-long mesh (Luna's shape: 270 mm on X vs
     * 102 mm on Z) takes the `-x` quarter-turn, and anything else keeps the
     * old +Z assumption. The 1.2× ratio keeps near-square meshes (e.g. a
     * wide boot box) from flipping on noise.
     *
     * `extentX`/`extentZ` are half-extents in any unit — only the ratio
     * matters. Non-positive or non-finite inputs answer 0 (draw as-is).
     */
    fun autoYawFromExtents(
        explicitYawOffsetDeg: Double?,
        extentX: Float,
        extentZ: Float,
    ): Double {
        if (explicitYawOffsetDeg != null && explicitYawOffsetDeg.isFinite()) {
            return explicitYawOffsetDeg
        }
        if (!extentX.isFinite() || !extentZ.isFinite()) return 0.0
        if (extentX <= 0f || extentZ <= 0f) return 0.0
        return if (extentX > extentZ * 1.2f) 90.0 else 0.0
    }

    fun resolveYawOffsetDeg(explicitYawOffsetDeg: Double?, forwardAxis: String?): Double {
        if (explicitYawOffsetDeg != null &&
            explicitYawOffsetDeg.isFinite()
        ) {
            return explicitYawOffsetDeg
        }
        return yawOffsetForForwardAxis(forwardAxis)
    }

    /**
     * The mesh extent the declared authored length runs on, in the same units
     * as the extents. Length is the longer horizontal axis: vertical (Y) is
     * height, never length, and between X and Z the longer one is the foot's
     * long axis by construction of every authoring export in the catalogue.
     *
     * Non-positive or non-finite inputs answer 0 — the caller treats 0 as
     * "cannot correct" and draws unscaled, exactly like the old Z-only path
     * did when the box was missing.
     */
    fun authoredLengthExtent(extentX: Float, extentZ: Float): Float {
        if (!extentX.isFinite() || !extentZ.isFinite()) return 0f
        if (extentX <= 0f || extentZ <= 0f) return 0f
        return maxOf(extentX, extentZ)
    }
}
