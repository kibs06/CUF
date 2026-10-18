package com.solevision.app.tryon

import kotlin.math.sqrt

/**
 * **Detection dots: the proof the app sees a foot, before any shoe is drawn (V4.13).**
 *
 * Two small white dots — heel and toe — drawn as Android overlay views on top of the AR surface.
 * They answer "is it actually detecting my foot" without needing a floor plane, a lock, or a shoe:
 * every accepted detector observation (~5 Hz) moves them, and they persist briefly between
 * observations so they read as anchors rather than flicker.
 *
 * Why overlay views and not Filament geometry: a Filament dot needs a material and a mesh, and a
 * material/mesh mismatch against the ubershader is a process abort (F16) — the wrong price for a
 * debug indicator. An overlay view cannot crash the renderer, and [ArTryOnView] is already a
 * `FrameLayout`, so the dots compose for free.
 *
 * Why no floor is needed: the 3D position comes from ARCore depth ([ArTryOnView.depthWorldPoint]
 * measures the foot's own surface) with a camera-ray fallback at [FALLBACK_DISTANCE_M] when depth
 * is unavailable. The floor hit-test — the thing that rejects most observations — is never
 * consulted. A dot therefore shows in exactly the cases the shoe does not: foot on a bed, no
 * tracked plane yet, session still young.
 *
 * Pure Kotlin, no Android imports, so the projection math is pinned on the JVM.
 */
internal object DetectionDots {

    /**
     * Camera-space distance used when depth has no answer for the pixel. A foot held in front of
     * the camera lives roughly here; the dot is an indicator, not a measurement, so an approximate
     * depth is honest as long as the direction is exact.
     */
    const val FALLBACK_DISTANCE_M = 0.6f

    /**
     * **A fix older than this is a hold, not a measurement (ms).**
     *
     * Past this the dots fade to [HELD_ALPHA] and the placement stops re-reading depth: the pose
     * stream is the only thing that knows where the foot is, and a UV the foot has already left
     * measures whatever is behind it.
     */
    const val STALE_MS = 1000L

    /**
     * **How long a held fix may live while the foot is still being seen (ms).**
     *
     * The partial-foot case: the detector's own gate keeps confirming a foot (so the presence ring
     * is up) while the heel/toe axis is unusable — a foot at an angle, a sock, a toe occluded by the
     * shoe already on it. Three seconds is two presence refreshes past the last pose: long enough
     * for a brief miss to read as tracking, short enough that a foot which has moved on is not
     * chased across the room.
     */
    const val COAST_MS = 3000L

    /**
     * **How long a held fix may live with nothing arriving at all (ms).**
     *
     * Deliberately the ring's own window ([PRESENCE_STALE_MS]): when the customer has left the
     * frame entirely, the held anchors and the ring let go together rather than one indicator
     * disagreeing with the other.
     */
    const val SILENT_COAST_MS = 1500L

    /** Alpha a dot is drawn at while its fix is held rather than measured. */
    const val HELD_ALPHA = 0.45f

    /** Whether a detection fix is current, held, or gone. */
    enum class Fix { LIVE, COAST, LOST }

    /**
     * **The one hold rule the dots and the detection-placed shoe both follow (V4.17).**
     *
     * A gap in the pose stream is not the foot leaving: the detector runs a few times a second and
     * its gate needs consecutive frames to change its mind, so a single miss must not take the
     * anchors down. This says which of the three states the fix is in; the caller draws and holds
     * accordingly.
     *
     * Pure and total — it runs per frame on two monotonic timestamps and a flag, so every input
     * combination answers a state instead of throwing. Both bounds are inclusive, and liveness is
     * the *ring's* own expiry, so a presence frame that has just aged out cannot leave a hold
     * running on a foot nobody has seen for a second and a half.
     */
    fun holdState(
        nowMs: Long,
        lastPoseMs: Long,
        lastPresenceMs: Long,
        hasFix: Boolean,
    ): Fix {
        if (!hasFix) return Fix.LOST
        val age = nowMs - lastPoseMs
        if (age <= STALE_MS) return Fix.LIVE
        val seen = nowMs - lastPresenceMs in 0..PRESENCE_STALE_MS
        return if (age <= if (seen) COAST_MS else SILENT_COAST_MS) Fix.COAST else Fix.LOST
    }

    /**
     * **Whether the optical-flow carry may move a held fix this frame (V4.19).**
     *
     * One writer per state, by construction: LIVE re-measures from fresh poses itself (the dots'
     * own `RECOMPUTE_MS` throttle), LOST has nothing to move, and only COAST holds worlds that
     * would otherwise sit still. Throttled by the same [RECOMPUTE_MS] as the LIVE re-measure —
     * each refresh is two depth-image acquires, and depth images are ~30 Hz, so per-frame would
     * be waste with the same value.
     *
     * Pure like [holdState], for the same reason: the rule that decides whether a held shoe moves
     * is pinned on the JVM, not negotiated per frame on a device.
     */
    fun heldCarryDue(nowMs: Long, lastCarryMs: Long, fix: Fix, hasFix: Boolean): Boolean =
        hasFix && fix == Fix.COAST && nowMs - lastCarryMs >= RECOMPUTE_MS

    /** Minimum time between dot re-projections: depth images are ~30 Hz, so faster is waste (ms). */
    const val RECOMPUTE_MS = 100L

    /**
     * How long the presence ring survives without a refresh (ms). Past Dart's ~1 Hz
     * refresh with margin, so a live ring never flickers, while a stalled loop lets go.
     */
    const val PRESENCE_STALE_MS = 1500L

    /** Foot-length band a detection placement trusts, in metres (same feet as the gates). */
    const val MIN_PLACEMENT_AXIS_M = 0.20
    const val MAX_PLACEMENT_AXIS_M = 0.34

    /** Where the shoe goes from a detection fix: yaw, and the heel→toe axis it was read from. */
    data class DetectionPlacement(
        val yawDeg: Double,
        val axisMeters: Double,
    )

    /**
     * Shoe placement from a detection heel/toe pair — no floor, lock, or tracker needed.
     *
     * Yaw-only like the tracker's anchor (a tipped shoe reads as broken), with the model's +Z
     * turned onto the foot's floor-plane direction — the same `atan2(x, z)` convention
     * [FootPoseTracker] uses, so a handover from detection placement to a tracked anchor never
     * visibly spins the shoe.
     *
     * **[DetectionPlacement.axisMeters] is handed back rather than scaled here, and that is the
     * point:** the axis is the same heel→toe measurement the tracker takes, so it belongs in the
     * *same* size pipeline (`ArTryOnView.effectiveScaleFor` — selected size × authored length ×
     * the measured-foot correction). A second scaling formula in this file would be a shoe that
     * changes size the moment the tracker takes over, which is the one thing an anchor swap must
     * not do.
     *
     * Null means "do not place": a degenerate axis, an unfootlike length, or a non-finite input —
     * never a clamped guess. The band is the garbage-depth guard the scale clamp used to be: a
     * 3 m "foot" is a bad depth read, not a foot.
     */
    fun detectionPlacement(heel: FloatArray, toe: FloatArray): DetectionPlacement? {
        if (heel.size < 3 || toe.size < 3) return null
        if (!heel.all { it.isFinite() } || !toe.all { it.isFinite() }) return null
        val dx = (toe[0] - heel[0]).toDouble()
        val dz = (toe[2] - heel[2]).toDouble()
        val axis = sqrt(dx * dx + dz * dz)
        if (axis < MIN_PLACEMENT_AXIS_M || axis > MAX_PLACEMENT_AXIS_M) return null
        return DetectionPlacement(
            yawDeg = Math.toDegrees(kotlin.math.atan2(dx, dz)),
            axisMeters = axis,
        )
    }

    /**
     * Camera-space ray direction through an image pixel, in the same OpenGL convention
     * [unprojectToCameraSpace][com.solevision.app.arfoot.unprojectToCameraSpace] uses
     * (x right, y up, −z forward). Unit depth: scale with [pointAlongRay].
     */
    fun rayDirection(
        imageX: Float,
        imageY: Float,
        fx: Float,
        fy: Float,
        cx: Float,
        cy: Float,
    ): FloatArray = floatArrayOf((imageX - cx) / fx, -(imageY - cy) / fy, -1f)

    /** Camera-space point at [distM] metres along [dir]. */
    fun pointAlongRay(dir: FloatArray, distM: Float): FloatArray {
        val n = sqrt(dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2])
        require(n > 1e-9f) { "degenerate ray direction" }
        val s = distM / n
        return floatArrayOf(dir[0] * s, dir[1] * s, dir[2] * s)
    }

    /**
     * Column-major 4×4 product C = A·B, so a view-projection is `mul4(projection, view)`
     * from the two matrices ARCore hands out.
     */
    fun mul4(a: FloatArray, b: FloatArray): FloatArray {
        require(a.size >= 16 && b.size >= 16) { "need 4x4 matrices" }
        val out = FloatArray(16)
        for (col in 0 until 4) {
            for (row in 0 until 4) {
                var sum = 0f
                for (k in 0 until 4) sum += a[k * 4 + row] * b[col * 4 + k]
                out[col * 4 + row] = sum
            }
        }
        return out
    }

    /**
     * Column-major 4×4 inverse (GLU-style adjugate), or null when singular — a camera pose is
     * always invertible, so null here means a malformed input, never a state to smooth over.
     */
    fun invert4(m: FloatArray): FloatArray? {
        require(m.size >= 16) { "need a 4x4 matrix" }
        val inv = FloatArray(16)
        inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] +
            m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10]
        inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] -
            m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10]
        inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] +
            m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9]
        inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] -
            m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9]
        inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] -
            m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10]
        inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] +
            m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10]
        inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] -
            m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9]
        inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] +
            m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9]
        inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] +
            m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6]
        inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] -
            m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6]
        inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] +
            m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5]
        inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] -
            m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5]
        inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] -
            m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6]
        inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] +
            m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6]
        inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] -
            m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5]
        inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] +
            m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5]
        var det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12]
        if (det == 0f) return null
        det = 1f / det
        for (i in 0 until 16) inv[i] *= det
        return inv
    }

    /**
     * A world point → surface pixels through a combined view-projection matrix, or null when the
     * point is behind the camera (w ≤ 0) — a dot for a point the camera cannot see would be a lie
     * about where the foot is.
     */
    fun projectToPixels(
        world: FloatArray,
        viewProj: FloatArray,
        widthPx: Int,
        heightPx: Int,
    ): Pair<Float, Float>? {
        require(world.size >= 3 && viewProj.size >= 16) { "need a point and a 4x4 matrix" }
        val x = viewProj[0] * world[0] + viewProj[4] * world[1] + viewProj[8] * world[2] + viewProj[12]
        val y = viewProj[1] * world[0] + viewProj[5] * world[1] + viewProj[9] * world[2] + viewProj[13]
        val w = viewProj[3] * world[0] + viewProj[7] * world[1] + viewProj[11] * world[2] + viewProj[15]
        if (w <= 1e-6f) return null
        val ndcX = x / w
        val ndcY = y / w
        return Pair(
            (ndcX * 0.5f + 0.5f) * widthPx,
            (1f - (ndcY * 0.5f + 0.5f)) * heightPx,
        )
    }

    /** Lowest camera zoom the slider offers: a wider view of the same sensor frame. */
    const val MIN_CAMERA_ZOOM = 0.7f

    /** Highest camera zoom the slider offers: twice as close, same alignment. */
    const val MAX_CAMERA_ZOOM = 2.0f

    /**
     * **Camera zoom, coerced (V4.22).**
     *
     * A digital zoom is a view-only transform: the detector, the tracker, the hit-tests and
     * depth all keep working in unzoomed world space, while the background quad and the render
     * projection narrow together — so the shoe, the dots, the ring and the mask stay glued to
     * the foot at any zoom. Non-finite input (a malformed channel payload) answers 1x rather
     * than throwing, for the same reason a malformed pose is dropped, never fatal.
     */
    fun coerceCameraZoom(zoom: Float): Float =
        if (zoom.isFinite()) zoom.coerceIn(MIN_CAMERA_ZOOM, MAX_CAMERA_ZOOM) else 1f

    /**
     * **Narrows a GL perspective projection for [zoom], in place (V4.22).**
     *
     * Multiplying the two focal entries by the zoom is a narrower field of view with the same
     * principal point — exactly what a digital zoom is. Applied to the Filament camera's custom
     * projection (the world-anchored shoe) and to every `projectToPixels` projection (dots,
     * ring, placement readout), so all three agree with the zoomed background about where the
     * world is. The `proj00/proj11` ratio the probe check asserts is invariant under this: both
     * entries scale by the same factor.
     */
    fun applyZoomToProjection(proj: FloatArray, zoom: Float) {
        require(proj.size >= 16) { "need a 4x4 matrix" }
        val z = coerceCameraZoom(zoom)
        proj[0] *= z
        proj[5] *= z
    }

    /**
     * **Zoom-in crop of texture UVs, in place (V4.22).**
     *
     * Shrinks each (u, v) pair toward the texture centre by `1/zoom`: at 2x the quad samples the
     * middle quarter of the sensor frame, magnified to fullscreen. Only valid for `zoom >= 1` —
     * expanding past the texture edge is the letterbox path ([zoomBandRect]), not a crop.
     * Absolute gets/puts, so the caller's buffer position is undisturbed.
     */
    fun applyZoomCropToUvs(uvs: java.nio.FloatBuffer, zoom: Float) {
        val z = coerceCameraZoom(zoom).coerceAtLeast(1f)
        val s = 1f / z
        var i = 0
        while (i + 1 < uvs.capacity()) {
            uvs.put(i, 0.5f + (uvs.get(i) - 0.5f) * s)
            uvs.put(i + 1, 0.5f + (uvs.get(i + 1) - 0.5f) * s)
            i += 2
        }
    }

    /**
     * **Zoom-out widening of texture UVs, in place (V4.22 fix).**
     *
     * Below 1x there is no wider sensor region to crop *and keep the height*: the 1x crop
     * already spans one texture axis fully, so a uniform expansion would overflow it (the first
     * build sampled the same width × a shorter height — a vertical crop; the second hardcoded
     * the u axis and stretched on rotation). Instead the *cropped* span widens about its own
     * midpoint by `1/zoom` while the full span is untouched — the sampled region's aspect
     * widens exactly as much as the letterbox band's ([zoomBandRect]), so the picture genuinely
     * widens with no stretch. The axis is chosen by span, never assumed: under display rotation
     * the texture axes need not match the view axes, but the cropped span is always the short
     * one. Drawn on the band quad, whose bars are the rows the wider aspect cannot fill. At
     * `zoom >= 1` this is a no-op (zoom-in is [applyZoomCropToUvs]). Absolute gets/puts.
     */
    fun applyZoomOutToUvs(uvs: java.nio.FloatBuffer, zoom: Float) {
        val z = coerceCameraZoom(zoom)
        if (z >= 1f) return
        var minU = Float.MAX_VALUE
        var maxU = -Float.MAX_VALUE
        var minV = Float.MAX_VALUE
        var maxV = -Float.MAX_VALUE
        var i = 0
        while (i + 1 < uvs.capacity()) {
            val u = uvs.get(i)
            val v = uvs.get(i + 1)
            if (u < minU) minU = u
            if (u > maxU) maxU = u
            if (v < minV) minV = v
            if (v > maxV) maxV = v
            i += 2
        }
        val s = 1f / z
        if (maxU - minU <= maxV - minV) {
            val c = (minU + maxU) / 2f
            i = 0
            while (i + 1 < uvs.capacity()) {
                uvs.put(i, c + (uvs.get(i) - c) * s)
                i += 2
            }
        } else {
            val c = (minV + maxV) / 2f
            i = 1
            while (i < uvs.capacity()) {
                uvs.put(i, c + (uvs.get(i) - c) * s)
                i += 2
            }
        }
    }

    /**
     * **Letterbox band for zoom-out, in view-normalized coords (V4.22).**
     *
     * Below 1x there is no wider sensor region to crop — the texture already spans the frame —
     * so the quad shrinks instead: full width, `zoom` of the height, centred, with thin dark bars
     * top and bottom. Returns `[left, top, right, bottom]` in the `VIEW_NORMALIZED` convention
     * the feed's quad corners use (top-left origin, v down). At `zoom >= 1` the full quad: zoom-in
     * is a UV crop ([applyZoomCropToUvs]), never a band.
     */
    fun zoomBandRect(zoom: Float): FloatArray {
        val z = coerceCameraZoom(zoom)
        if (z >= 1f) return floatArrayOf(0f, 0f, 1f, 1f)
        val top = (1f - z) / 2f
        return floatArrayOf(0f, top, 1f, top + z)
    }

    /**
     * **An unzoomed screen point in zoomed screen space (V4.22).**
     *
     * The exact counterpart of the two paths above, for screen-space values computed outside the
     * zoomed projection — the probe self-check's `heelView`, which maps the detection UV through
     * the unzoomed view geometry. Zoom-in magnifies about the screen centre; letterbox shrinks
     * the y axis about the centre while x stays full-width. The centre itself is the fixed point
     * of both, which is why screen-centre auto-placement needs no mapping at all.
     */
    fun zoomScreenPoint(
        px: Float,
        py: Float,
        widthPx: Int,
        heightPx: Int,
        zoom: Float,
    ): Pair<Float, Float> {
        val z = coerceCameraZoom(zoom)
        val cx = widthPx / 2f
        val cy = heightPx / 2f
        return if (z >= 1f) {
            Pair(cx + (px - cx) * z, cy + (py - cy) * z)
        } else {
            Pair(px, cy + (py - cy) * z)
        }
    }
}
