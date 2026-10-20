/**
 * Per-model orientation for the foot try-on — pure, no Three.js import.
 *
 * The workshop authors models inconsistently: most put the toe on +Z, but
 * at least one production model (JBC Crown, byte-identical to
 * `qa_partner_shoe_v1.glb`) points its toe at −Z with all three audit
 * signals agreeing (`customer-portal/docs/model-orientation-audit.md`).
 * Normalizing every model by `size.z` with no yaw therefore wears some
 * shoes heel/toe swapped.
 *
 * Data flow (the viewer's order of operations — this function assumes it):
 *   1. `model.rotation.z = PI` (sole-side-up fix, pre-existing),
 *   2. `model.rotation.y = yawRadians` from here (forward-axis yaw),
 *   3. `model.updateMatrixWorld(true)`,
 *   4. measure `Box3.setFromObject(model)` → the `box` argument below.
 *
 * Because the box is measured AFTER the yaw, the forward direction is
 * always +Z in the measured frame and the heel is always at min.z — the
 * same contract `yawGroup` already assumes (heel at origin, toe at +1, so
 * `yawGroup.scale = lengthPx` spans heel→toe). Deciding which axis is the
 * long one is the *inspector's* job (`scripts/inspect-glb.mjs`), not a
 * runtime heuristic: the answer arrives as per-model metadata.
 *
 * Coordinate frame: glTF Y-up. Yaw signs derived from the right-hand rule
 * and pinned by tests: rotation about +Y by θ maps
 * (x,z) → (x·cosθ + z·sinθ, −x·sinθ + z·cosθ), so a toe on +X needs
 * θ = −π/2 to land on +Z, and a toe on −X needs +π/2.
 */

/** Allowed `forward_axis` values (`product_models.forward_axis`). */
export const FORWARD_AXES = ['+z', '-z', '+x', '-x']

/** Yaw about +Y that carries each authored forward onto +Z. */
export const FORWARD_YAW = {
  '+z': 0,
  '-z': Math.PI,
  '+x': -Math.PI / 2,
  '-x': Math.PI / 2,
}

/** Default when the row predates the column, is null, or holds garbage. */
export const DEFAULT_FORWARD_AXIS = '+z'

/** Multiplier applied on top of the user's live trim (1 = no change). */
export const DEFAULT_MODEL_SCALE = 1

/**
 * Normalize a possibly-unknown forward-axis value to a known one.
 * Anything unrecognized becomes the legacy assumption (`+z`), so old
 * rows render exactly as before.
 */
export function normalizeForwardAxis(value) {
  return FORWARD_AXES.includes(value) ? value : DEFAULT_FORWARD_AXIS
}

/** Clamp a per-model scale into its sane range, defaulting on garbage.
 * Missing (null/undefined/'') means the row predates the column — default,
 * not the clamp floor (`Number(null)` is 0, which must not become 0.5). */
export function normalizeModelScale(value) {
  if (value === null || value === undefined || value === '') return DEFAULT_MODEL_SCALE
  const n = Number(value)
  if (!Number.isFinite(n)) return DEFAULT_MODEL_SCALE
  return Math.min(3, Math.max(0.5, n))
}

/**
 * Where the shoe goes inside its unit box, from the post-yaw bounding box.
 *
 * @param {{size:{x,y,z}, center:{x,y,z}, min:{x,y,z}}} box measured AFTER
 *   the sole-side-up fix and the forward-axis yaw have been applied.
 * @param {string} forwardAxis one of `+z -z +x -x` (default `+z`).
 * @param {number} defaultScale per-model multiplier (default 1).
 * @returns null on a degenerate box, else
 *   `{ yawRadians, forwardAxis, length, uniformScale, offset: {x,y,z} }`
 *   with heel at the origin and toe at +1 along +Z.
 */
export function computeModelNormalization(box, forwardAxis = DEFAULT_FORWARD_AXIS, defaultScale = DEFAULT_MODEL_SCALE) {
  const axis = normalizeForwardAxis(forwardAxis)
  const scale = normalizeModelScale(defaultScale)
  const size = box?.size ?? {}
  const center = box?.center ?? {}
  const min = box?.min ?? {}
  const length = Number(size.z)
  if (!(length > 0)) return null
  if (![size.x, size.y, size.z, center.x, center.y, center.z, min.x, min.y, min.z].every(Number.isFinite)) {
    return null
  }
  const s = scale / length
  // `+ 0`: centered boxes produce `-0` offsets, which fail strict
  // equality downstream and in tests — normalize them to `0` here.
  const offset = { x: -center.x * s + 0, y: -min.y * s + 0, z: -min.z * s + 0 }
  return {
    yawRadians: FORWARD_YAW[axis],
    forwardAxis: axis,
    length,
    uniformScale: s,
    offset,
  }
}
