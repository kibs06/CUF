package com.solevision.app.tryon

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.exp
import kotlin.math.sqrt

/**
 * **V4.2/V4.3 — the native half of foot tracking: 2D observations become a world anchor, and the
 * foot's measured length comes with it.**
 *
 * Dart's detection loop publishes ~5 Hz pose observations
 * (`setFootPose` in `ArTryOnView`, payload `{heelUv, toeUv, widthUv, confidence, footSide}` —
 * architecture §2.8). This class is what turns them into the one thing the renderer needs: a
 * *world-space anchor* — where the heel is, and which way the foot points — smooth enough to
 * draw at 60 fps and honest enough to say "I lost it".
 *
 * ## Why the work is split this way (design D3)
 *
 * The detector itself stays in Dart: it is 43 KB of tuned, tested logic, and porting it to Kotlin
 * would create a second implementation to keep in step. What cannot stay in Dart is everything
 * that needs ARCore's world: `Frame.hitTest` projects a screen point onto a tracked plane, and
 * only native code can call it. So the split is exactly:
 *
 *  • **Dart decides *what* it saw** — normalized upright-image UV points, with a combined
 *    `qualityScore` and the consecutive-positive gate already applied ([TemporalFootGate] there).
 *  • **Native decides *where that is*** — two hit tests per observation, a floor-plane basis, and
 *    the filtering below. `hitTestBatch` in the architecture is this step.
 *
 * ## The filter, and why it is not just an average
 *
 * A foot is either still (and the detector jitters by a few millimetres per frame) or moving (and
 * a lagging filter is a shoe that swims behind the foot). A fixed low-pass must choose which of
 * those to be bad at. The **one-euro filter** — Casiez et al., the same family used for AR pose
 * smoothing — raises its cutoff when the signal moves fast and lowers it when it is still, which
 * is why it is the architecture's named choice (§2.4). One filter per component: heel x/y/z, the
 * forward direction's x/z, and the quality score.
 *
 * The quality filter is smoothed for a second reason: §2.9's lock hysteresis compares against 0.7
 * and 0.45, and feeding raw per-frame scores into a threshold would flicker a lock on and off
 * across one bad frame. Native is the lock's only authority — Dart mirrors `footLock` and does not
 * re-derive it — so this is the one place the enter/leave rule exists.
 *
 * ## Interpolation
 *
 * Observations arrive at ~5 Hz; the display refreshes at 30–60. Filtered *targets* are updated on
 * observations only, and every render frame eases the displayed anchor toward them
 * ([onFrame]). That is the architecture's sentence made real: "Dart publishes observations;
 * native interpolates".
 *
 * ## What this class deliberately does not do
 *
 *  • **No full basis.** The architecture's basis is `{forward, up, lateral}`, but placement applies
 *    **yaw only** — the rule V3's `placeShoe` already follows, because a shoe tipped by a plane's
 *    full rotation reads as broken. `up` is therefore the world's +Y (floors are gravity-aligned)
 *    and `lateral` follows from it; neither is stored.
 *  • **No scale policy.** §2.5.2's size grading is applied by the view, and so is V4.3's
 *    frame-scale correction — this class only *measures* it: the filtered heel→toe distance rides
 *    on [Anchor] as [Anchor.lengthMeters], and [FootScaleCorrection] turns it into the ×N the
 *    renderer multiplies in. What is compared against the size chart's last, and what is
 *    refused, is that file's decision, so it can be pinned without a handset.
 *  • **No Android imports.** Pure Kotlin on purpose, so the math could move under a JVM test the
 *    day this module has one (`android/app/src/test` does not exist yet — the instrumentation
 *    tests under `androidTest` need a device, and this file needs none).
 */
internal class FootPoseTracker {

    /**
     * One observation as it arrived from Dart, in its own space.
     *
     * The UV endpoint coordinates are **normalized upright-image UV** (0–1) — the space the
     * detector's `FootPoint` uses and the space ARCore's `hitTest` does *not* take, which is why
     * the view converts them before this class ever sees a world point.
     */
    data class Observation(
        val heelU: Double,
        val heelV: Double,
        val toeU: Double,
        val toeV: Double,
        val confidence: Double,
        val side: String?,
    )

    /**
     * One observation after the view's hit tests: metres, world space, y-up.
     *
     * [forward] is `toe − heel` in the floor plane (`y` ignored on purpose — the shoe stays flat);
     * it is a direction, not a length, and [observe] normalizes it.
     *
     * [lengthMeters] is the floor-plane heel→toe **distance** — the measurement V4.3's frame
     * scale is made of, filtered here and carried on [Anchor]. A non-finite or non-positive
     * length is not a sample: a zero-length foot would scale a shoe to nothing, and a NaN would
     * poison the filter for the rest of the session.
     */
    data class Sample(
        val heel: DoubleArray,
        val forward: DoubleArray,
        val lengthMeters: Double,
        val quality: Double,
        val side: String?,
    )

    /**
     * Where to draw the shoe: heel position, the yaw that points the model's +Z along the foot,
     * and the measured heel→toe length the shoe should be sized to (V4.3, metres).
     */
    data class Anchor(
        val x: Double,
        val y: Double,
        val z: Double,
        val yawDeg: Double,
        val lengthMeters: Double,
    )

    /** A lock transition worth telling Dart about — emitted on edges only, never per frame. */
    data class LockChange(val locked: Boolean, val quality: Double, val side: String?)

    /**
     * The live measurement V4.6's fit verdict is built from: the eased heel→toe length (metres),
     * the smoothed quality, and the lock state at that instant.
     *
     * A snapshot rather than three getters on purpose — a length read before a frame's ease and a
     * quality read after it would describe two different moments, and the verdict card is entitled
     * to one coherent reading.
     */
    data class Measure(val lengthMeters: Double, val quality: Double, val locked: Boolean)

    // ── State (render thread only, like everything else in this renderer) ────────────────────

    private val heelX = OneEuroFilter()
    private val heelY = OneEuroFilter()
    private val heelZ = OneEuroFilter()
    private val forwardX = OneEuroFilter()
    private val forwardZ = OneEuroFilter()
    private val measuredLength = OneEuroFilter()
    private val quality = OneEuroFilter()

    /** Smoothed targets, and the eased values actually drawn. Both metres / degrees. */
    private val target = DoubleArray(3)
    private val displayed = DoubleArray(3)
    private var targetYawDeg = 0.0
    private var displayedYawDeg = 0.0
    private var targetLengthM = 0.0
    private var displayedLengthM = 0.0

    private var seeded = false
    private var lastSampleMs = 0L
    private var lastStepMs = 0L

    /** Locked state, its authoritative quality, and the last side the detector was sure of. */
    var locked = false
        private set
    var lockQuality = 0.0
        private set
    var side: String? = null
        private set

    /** True once a sample has been accepted: there is somewhere to draw the shoe. */
    val hasAnchor: Boolean get() = seeded

    /**
     * Filters one world sample and updates the lock.
     *
     * Returns a [LockChange] **only when the lock state flipped** — the caller emits `footLock`
     * then and not otherwise; a per-frame event stream would be 60 messages a second for a value
     * Dart already knows how to hold.
     */
    fun observe(sample: Sample, nowMs: Long): LockChange? {
        // ⚠️ Non-finite input is rejected as "not a sample", not filtered. A NaN would poison the
        // one-euro state permanently (`filter` propagates it through every later call), and a NaN
        // anchor is a transform Filament cannot draw — the shoe would vanish with no clue why. The
        // pose fields cross a channel, which is where a bad number is most easily born; the length
        // is measured here instead, but it is a distance between two projected points and the same
        // rule costs it nothing (V4.3). Non-positive joins non-finite: a zero-length foot would
        // scale a shoe to nothing.
        if (!sample.quality.isFinite() ||
            !sample.forward.all { it.isFinite() } ||
            !sample.heel.all { it.isFinite() } ||
            !sample.lengthMeters.isFinite() ||
            sample.lengthMeters <= 0.0
        ) {
            return null
        }

        val (fx, fz) = normalizeForward(sample.forward) ?: return null

        // ── Re-anchor on drift (architecture §2.4) ──────────────────────────────────────────
        // A raw heel far from the filtered one is not movement, it is a new placement: the foot
        // left and came back, the phone was moved, or the customer walked. Running it through the
        // filter would draw the shoe *travelling* there over a second, which reads as a glitch;
        // snapping and re-seeding is what the tracker is supposed to do.
        if (seeded) {
            val dx = sample.heel[0] - target[0]
            val dy = sample.heel[1] - target[1]
            val dz = sample.heel[2] - target[2]
            if (sqrt(dx * dx + dy * dy + dz * dz) > REANCHOR_METERS) {
                // ⚠️ Filters only — **not** the lock. A re-anchor is the same foot in a new place,
                // and dropping the lock here would flash "lost" on every re-seed without an edge
                // the caller ever emitted. The hysteresis below still sees the fresh quality, so a
                // genuinely bad frame unlocks the way it always does.
                resetFilters()
            }
        }

        val x = heelX.filter(sample.heel[0], nowMs)
        val y = heelY.filter(sample.heel[1], nowMs)
        val z = heelZ.filter(sample.heel[2], nowMs)
        val sx = forwardX.filter(fx, nowMs)
        val sz = forwardZ.filter(fz, nowMs)
        val q = quality.filter(sample.quality.coerceIn(0.0, 1.0), nowMs)
        val length = measuredLength.filter(sample.lengthMeters, nowMs)

        target[0] = x
        target[1] = y
        target[2] = z
        targetYawDeg = Math.toDegrees(atan2(sx, sz))
        targetLengthM = length
        if (!seeded) seedDisplayed()
        seeded = true

        lastSampleMs = nowMs
        lockQuality = q
        sample.side?.let { side = it }
        return applyHysteresis(q)
    }

    /**
     * Per-render-frame work: ease the drawn anchor toward the filtered target, and let a silent
     * detector lose the lock. The measured length is eased with the position, so V4.3's size
     * correction is drawn as the shoe growing or shrinking rather than as a jump between two
     * frames.
     *
     * **Staleness is not paranoia.** The Dart loop stops after five consecutive failures by design
     * (its own `kFootTrackFailureLimit`), and a camera that stops moving *without* the loop saying
     * so looks identical from here. Feeding zero quality once the samples are older than
     * [STALE_MS] is what turns "the publisher went quiet" into a `footLock {locked=false}` instead
     * of a shoe frozen on a foot that walked away — the same decay-to-unlock a low-confidence
     * detector produces, by the same thresholds.
     */
    fun onFrame(nowMs: Long): LockChange? {
        if (!seeded) return null

        val dtSeconds = if (lastStepMs == 0L) 0.0
        else ((nowMs - lastStepMs).coerceAtLeast(0L)) / 1000.0
        lastStepMs = nowMs

        // Critically-damped ease: `1 − e^(−dt/τ)`. Bounded by construction (the factor is in
        // (0, 1] for every dt ≥ 0), and it cannot overshoot the target the way a spring can.
        if (dtSeconds > 0.0) {
            val factor = 1.0 - exp(-dtSeconds / EASE_TAU_SECONDS)
            for (i in 0..2) displayed[i] += (target[i] - displayed[i]) * factor
            displayedYawDeg += normalizeYawDelta(targetYawDeg - displayedYawDeg) * factor
            displayedYawDeg = normalizeYaw(displayedYawDeg)
            displayedLengthM += (targetLengthM - displayedLengthM) * factor
        }

        if (lastSampleMs == 0L || nowMs - lastSampleMs < STALE_MS) return null
        // Silence: decay the quality through the same filter, so the unlock crosses 0.45 exactly
        // the way a bad detection would.
        lockQuality = quality.filter(0.0, nowMs)
        return applyHysteresis(lockQuality)
    }

    /** The eased world anchor, or null before any sample. */
    fun anchor(): Anchor? =
        if (!seeded) {
            null
        } else {
            Anchor(displayed[0], displayed[1], displayed[2], displayedYawDeg, displayedLengthM)
        }

    /**
     * The reading to publish to Dart, or null before any sample.
     *
     * The length is the **eased** one ([Anchor.lengthMeters]) — the same number V4.3's frame-scale
     * correction draws with — so the shoe on screen and the verdict beside it can never be sized
     * from two different readings of the same foot.
     */
    fun measure(): Measure? {
        val anchor = anchor() ?: return null
        return Measure(anchor.lengthMeters, lockQuality, locked)
    }

    /**
     * Forgets everything **including** the lock — used on teardown and when QA switches to `floor`
     * mode. (A drift re-anchor uses [resetFilters] instead, precisely to keep the lock.)
     *
     * Returns whether the lock was held, so the caller can emit the unlock edge the UI needs
     * rather than leaving a coach card saying "locked" for a session that ended.
     */
    fun reset(): Boolean {
        val wasLocked = locked
        resetFilters()
        lockQuality = 0.0
        locked = false
        side = null
        return wasLocked
    }

    /** Forgets the signal but not the lock state — the drift re-anchor's half of [reset]. */
    private fun resetFilters() {
        heelX.reset(); heelY.reset(); heelZ.reset()
        forwardX.reset(); forwardZ.reset(); measuredLength.reset(); quality.reset()
        seeded = false
        lastSampleMs = 0L
        lastStepMs = 0L
    }

    /** One heartbeat token — the QA readout's `foot=` field, not an event. */
    fun describe(): String = when {
        !seeded -> "idle"
        locked -> "locked ${fmt(lockQuality)}"
        else -> "lost ${fmt(lockQuality)}"
    }

    // ── Internals ───────────────────────────────────────────────────────────────────────────

    private fun seedDisplayed() {
        displayed[0] = target[0]
        displayed[1] = target[1]
        displayed[2] = target[2]
        displayedYawDeg = targetYawDeg
        displayedLengthM = targetLengthM
    }

    /**
     * §2.9's hysteresis, in one place: enter at ≥ 0.7, leave below 0.45.
     *
     * The gap between the two is the feature — a single score hovering at 0.69 must not unlock a
     * shoe, and a single 0.71 must not lock one that is wobbling.
     */
    private fun applyHysteresis(q: Double): LockChange? {
        val wasLocked = locked
        when {
            !locked && q >= ENTER_QUALITY -> locked = true
            locked && q < LEAVE_QUALITY -> locked = false
        }
        if (locked == wasLocked) return null
        return LockChange(locked, q, side)
    }

    /** Unit forward in the floor plane, or null for a degenerate axis (heel and toe coincided). */
    private fun normalizeForward(forward: DoubleArray): Pair<Double, Double>? {
        val x = forward[0]
        val z = forward[2]
        val length = sqrt(x * x + z * z)
        if (length < MIN_FORWARD_LENGTH) return null
        return Pair(x / length, z / length)
    }

    private fun normalizeYaw(deg: Double): Double {
        var value = deg % 360.0
        if (value > 180.0) value -= 360.0
        if (value < -180.0) value += 360.0
        return value
    }

    private fun normalizeYawDelta(delta: Double): Double {
        var value = delta % 360.0
        if (value > 180.0) value -= 360.0
        if (value < -180.0) value += 360.0
        return value
    }

    private fun fmt(value: Double): String = String.format(java.util.Locale.US, "%.2f", value)

    /**
     * The one-euro filter (Casiez, Roussel & Vogel 2012), scalar form.
     *
     * `alpha = 1 / (1 + τ/dt)` with `τ = 1/(2π·cutoff)`: the standard derivation, written out
     * rather than quoted, because the interesting part is that the cutoff is *adaptive* —
     * `minCutoff + beta · |smoothed derivative|` — which is what makes one filter usable for both
     * "still" and "moving" without an if-statement choosing between them.
     */
    private class OneEuroFilter(
        private val minCutoff: Double = MIN_CUTOFF,
        private val beta: Double = BETA,
        private val derivativeCutoff: Double = DERIVATIVE_CUTOFF,
    ) {
        private var lastValue = 0.0
        private var lastDerivative = 0.0
        private var lastMs = 0L
        private var started = false

        fun filter(value: Double, nowMs: Long): Double {
            if (!started) {
                started = true
                lastValue = value
                lastMs = nowMs
                return value
            }
            // Floor the step at 1 ms: two calls in the same millisecond are a clock artefact, and
            // dividing by zero here would poison the derivative for every later sample.
            val dt = ((nowMs - lastMs).coerceAtLeast(1L)) / 1000.0
            val derivative = (value - lastValue) / dt
            val aD = alpha(derivativeCutoff, dt)
            val smoothedDerivative = aD * derivative + (1.0 - aD) * lastDerivative
            val cutoff = minCutoff + beta * abs(smoothedDerivative)
            val aV = alpha(cutoff, dt)
            val filtered = aV * value + (1.0 - aV) * lastValue
            lastValue = filtered
            lastDerivative = smoothedDerivative
            lastMs = nowMs
            return filtered
        }

        fun reset() {
            started = false
            lastDerivative = 0.0
            lastValue = 0.0
            lastMs = 0L
        }

        private fun alpha(cutoff: Double, dt: Double): Double {
            val tau = 1.0 / (2.0 * Math.PI * cutoff)
            return 1.0 / (1.0 + tau / dt)
        }
    }

    internal companion object {
        /**
         * §2.9's lock thresholds. Enter and leave are deliberately different numbers; see
         * [applyHysteresis].
         */
        const val ENTER_QUALITY = 0.7
        const val LEAVE_QUALITY = 0.45

        /**
         * How long a silent detector may stay silent before the lock starts decaying.
         *
         * ⚠️ Must stay comfortably above the publisher's own period: Dart publishes every 200 ms
         * when it is healthy, so 700 ms is "two and a half missed ticks" — a hiccup does not
         * unlock a shoe, a stopped loop does.
         */
        const val STALE_MS = 700L

        /**
         * How far the raw heel may jump and still be called movement of the same foot.
         *
         * 30 cm is about a shoe-and-a-half: real drift accumulates over a long session and is
         * exactly what §2.4's "re-anchors on drift" is for, while a walking step would leave a
         * filtered shoe swimming behind it. Anything past this re-seeds the filter instead.
         */
        const val REANCHOR_METERS = 0.30

        /** Below this, heel and toe hit the same floor point and there is no axis to build. */
        const val MIN_FORWARD_LENGTH = 1e-4

        /** One-euro parameters: slow cutoff for stillness, small beta for a foot's speeds. */
        const val MIN_CUTOFF = 1.0
        const val BETA = 0.02
        const val DERIVATIVE_CUTOFF = 1.0

        /**
         * The interpolation time constant: the displayed anchor closes ~63% of the remaining gap
         * in this time, so a 5 Hz observation stream is drawn as continuous movement with ~60 ms
         * of added lag — below the threshold where a shoe reads as detached from a foot.
         */
        const val EASE_TAU_SECONDS = 0.06
    }
}
