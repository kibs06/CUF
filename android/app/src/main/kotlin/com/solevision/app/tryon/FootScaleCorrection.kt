package com.solevision.app.tryon

/**
 * **V4.3 — the ×N frame-scale correction: the shoe is drawn at the size the measured foot needs,
 * not at the size the selected chip assumes.**
 *
 * ## Why a correction exists at all
 *
 * Everything that decides the rendered size until now is a *claim* made in a different session:
 * the selected EU size, the seller's reference last, the size chart's 6.67 mm step. None of them
 * knows what is standing in front of the camera. The tracker measures it — a filtered floor-plane
 * heel→toe distance in metres ([FootPoseTracker.Anchor.lengthMeters]) — and when the claim and
 * the measurement disagree (a stale scan, a shared phone, a child using a parent's profile), a
 * shoe graded from the chip visibly overhangs or undersizes the foot it is anchored to. The
 * roadmap's acceptance sentence is the whole intent: *a foot measured at 200 mm must render a
 * shoe sized for 200 mm, not 265 mm*.
 *
 * ## The mapping is the fit engine's, mirrored rather than invented
 *
 * The fit engine (`lib/utils/fit_engine.dart`, architecture §2.6) is the one authority on what
 * "sized for a foot" means: a last fits when it leaves 8–14 mm of toe room ([TARGET_TOE_ROOM_MM]
 * is that band's midpoint, the same kind of workshop default the engine's own bands are). So the
 * last that suits a measured foot is `measured + TARGET_TOE_ROOM_MM`, and the correction is a
 * ratio of lasts:
 *
 * ```
 * N = (measuredMm + TARGET_TOE_ROOM_MM) / renderedLastMm
 * ```
 *
 * where `renderedLastMm` is the internal last the current render already grades to — the number
 * `setSize` turned into `sizeScale` (`lastLengthMm + (sizeEu − refSizeEu) × 6.67`).
 *
 * ⚠️ **The authored length cancels, and that is this formula's sanity check.** The render scale
 * is `authoredExternal / last(ref)` graded by size; multiplying by N leaves
 * `authoredExternal × (measured + toe room) / last(ref)` — i.e. the *external* size of a shoe
 * whose *internal* last fits this foot. The external/internal offset of the sample is respected
 * without this file ever knowing it. It also means the factor is chip-aware by construction: it
 * is computed against the size the customer selected, so changing the chip re-derives N against
 * the new last rather than stacking a correction on a correction.
 *
 * ## Refusals, not guesses
 *
 * A factor of 1.0 — the selected size, untouched — is returned for a missing anchor, a
 * non-finite or non-positive input, or a measurement outside the plausible bands the fit engine
 * already defines (`kPlausibleFootLengthMm` 110–360, `kPlausibleLastLength*` 120–360). A 60 mm
 * "foot" is a failed measurement, not a small foot, and the honest answer is the size chart.
 * Inside those bands the factor is clamped to [MIN_FACTOR]…[MAX_FACTOR]: the measurement is a
 * second opinion, not an oracle, and a detector whose toe point is occluded or foreshortened
 * must not be able to turn a shoe into a toy.
 *
 * ⚠️ **What this class does not do:** it does not decide *when* the factor applies (the view
 * applies it wherever an anchor is drawn, exactly like the position) and it does not touch the
 * lock — a correction that switched off at quality 0.44 would visibly resize a shoe mid-step.
 *
 * The three defaults ([TARGET_TOE_ROOM_MM], the clamp ends) are workshop defaults in the same
 * sense as the fit engine's bands: V4.9 reads `len=` and `scale=` off the QA heartbeat on real
 * feet and tunes them here, in one file.
 */
internal object FootScaleCorrection {

    /**
     * The toe room a last should leave for a foot it fits, in millimetres.
     *
     * 11 mm is the midpoint of the fit engine's true-to-size band (`FitBands`: `snugToeMm` 8 …
     * `trueToeMaxMm` 14) — the engine's own example line (`foot=265 last=275 why="…"`) is a
     * 10 mm case the engine calls true-to-size. Mirrored here rather than sent over the channel:
     * the phone would have to ask Dart for a number whose only consumer is this file, and the
     * native copy is recorded as debt exactly like the 6.67 mm step already is.
     */
    const val TARGET_TOE_ROOM_MM = 11.0

    /** Mirrors `kPlausibleFootLengthMm` / `kPlausibleFootLengthMaxMm` in `fit_engine.dart`. */
    const val MIN_PLAUSIBLE_FOOT_MM = 110.0
    const val MAX_PLAUSIBLE_FOOT_MM = 360.0

    /** Mirrors `kPlausibleLastLengthMm` / `kPlausibleLastLengthMaxMm` in `fit_engine.dart`. */
    const val MIN_PLAUSIBLE_LAST_MM = 120.0
    const val MAX_PLAUSIBLE_LAST_MM = 360.0

    /**
     * The clamp ends, as fractions of the size chart's own answer.
     *
     * ⚠️ Wide enough for the roadmap's case (a 200 mm foot against a 265 mm last is 0.796) and
     * narrow enough that a broken measurement cannot resize the shoe beyond recognition. The
     * lower end is the one to re-read on a device: 0.70 is a third smaller, which is the most a
     * mis-read toe should ever cost.
     */
    const val MIN_FACTOR = 0.70
    const val MAX_FACTOR = 1.30

    /**
     * The ×N for one drawn frame, or 1.0 when there is nothing to trust.
     *
     * [measuredLengthMeters] is the tracker's eased heel→toe distance (null before the first
     * accepted pose); [renderedLastMm] is the internal last the current `sizeScale` grades to
     * (null before `setSize`). Pure and total: every input combination answers a finite,
     * positive, clamped Double — this runs per frame, and a throw here would be a dropped frame.
     */
    fun factor(measuredLengthMeters: Double?, renderedLastMm: Double?): Double {
        if (measuredLengthMeters == null || renderedLastMm == null) return 1.0
        if (!measuredLengthMeters.isFinite() || !renderedLastMm.isFinite()) return 1.0
        if (measuredLengthMeters <= 0.0 || renderedLastMm <= 0.0) return 1.0

        val measuredMm = measuredLengthMeters * 1000.0
        if (measuredMm < MIN_PLAUSIBLE_FOOT_MM || measuredMm > MAX_PLAUSIBLE_FOOT_MM) return 1.0
        if (renderedLastMm < MIN_PLAUSIBLE_LAST_MM || renderedLastMm > MAX_PLAUSIBLE_LAST_MM) {
            return 1.0
        }

        val raw = (measuredMm + TARGET_TOE_ROOM_MM) / renderedLastMm
        return raw.coerceIn(MIN_FACTOR, MAX_FACTOR)
    }
}
