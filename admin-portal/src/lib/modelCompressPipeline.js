// ─── The compression pipeline itself, inside the worker ────────────
//
// Two stages, and the order matters:
//
//   1. **weld + simplify** (`@gltf-transform/core` + `functions`, with
//      `meshoptimizer`'s WASM simplifier) — this is the only stage that can
//      remove *geometry*, and the reference normalizer cannot do it at all.
//      Its header says so: `prepare_shoe_model.dart` "has no decimation
//      capability", which is why the 90 MB export that prompted this step could
//      not be repaired by the CLI either without a manual `gltf-transform
//      simplify` first.
//   2. **the reference normalizer** (`glb_normalizer.gen.js`) — re-axes,
//      re-grounds, rescales to the declared length, re-bakes textures, renames
//      materials, splits the sole band. Same function the CLI runs.
//
// ⚠️ **Plain, uncompressed glTF comes out of stage 1 on purpose.** The contract
// refuses Draco, meshopt and KTX2 (`UNAPPROVED_COMPRESSION_EXTENSIONS`) because
// the shipped renderer has no proven support for them, so the compression is
// used as a *tool* and never as an output format: `simplify` writes ordinary
// triangles and the meshopt WASM is the simplifier, not the encoder. That
// distinction is the whole reason a browser can do this at all.
//
// **Stage 1's output is throwaway.** It exists to be smaller; stage 2 rebuilds
// the container from scratch, so anything stage 1 got wrong about the file
// (extension declarations, node transforms, leftover accessors) is discarded
// with it. The bytes that reach the bucket are always stage 2's.
//
// Everything here is a function of its arguments, and the IO is injected so the
// test can drive it with `NodeIO`: `WebIO` is what the worker uses and the two
// are not importable in the other's environment.

import { WebIO } from '@gltf-transform/core'
import { simplify, weld } from '@gltf-transform/functions'
import { MeshoptSimplifier } from 'meshoptimizer'

import { soleVisionNormalize } from './glb_normalizer.gen.js'
import { SIMPLIFY_ERROR } from './modelCompress.js'

/** Extensions this pipeline cannot read back — the same set the normalizer
 *  refuses (`kNormalizerUnsupportedCompression`), checked here as well so the
 *  refusal arrives in a second instead of after a 90 MB round trip.
 *
 *  ⚠️ This is a **tool capability** check, not an authoring rule: it asks "can
 *  this route decode the file", not "does the file pass the contract". The
 *  normalizer still runs its own check and is the authority — if the two ever
 *  drift, this one can only become more permissive, and stage 2 refuses with
 *  its own sentence. */
const UNREADABLE_COMPRESSION = [
  'KHR_draco_mesh_compression',
  'EXT_meshopt_compression',
  'KHR_texture_basisu',
]

/** Reads the JSON chunk of a GLB, or null when there is not one. Used only for
 *  the refusal above — the normalizer parses the file properly. */
function jsonChunkOf(bytes) {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  if (view.length < 20) return null
  const header = new DataView(view.buffer, view.byteOffset, view.byteLength)
  let offset = 12
  while (offset + 8 <= view.length) {
    const length = header.getUint32(offset, true)
    const type = header.getUint32(offset + 4, true)
    if (offset + 8 + length > view.length) return null
    if (type === 0x4e4f534a) {
      try {
        return JSON.parse(new TextDecoder().decode(view.subarray(offset + 8, offset + 8 + length)))
      } catch {
        return null
      }
    }
    offset += 8 + length
  }
  return null
}

/** Refuses a file whose geometry or textures this pipeline cannot decode. */
function refuseUnreadable(bytes) {
  const json = jsonChunkOf(bytes)
  if (json === null) return

  // ⚠️ `Array.isArray(x ?? [])` is always true, so the ternary would hand back
  // the original `undefined` and spreading it throws. The nullish check has to
  // be the ternary's *result*, not its test.
  const declared = new Set([
    ...(Array.isArray(json.extensionsUsed) ? json.extensionsUsed : []),
    ...(Array.isArray(json.extensionsRequired) ? json.extensionsRequired : []),
  ])
  const compression = UNREADABLE_COMPRESSION.filter((name) => declared.has(name))
  if (compression.length > 0) {
    throw new Error(
      `${compression.join(', ')} cannot be undone here — re-export the model uncompressed ` +
        '("Export → Compression: off", guide §C8).',
    )
  }

  for (const image of Array.isArray(json.images) ? json.images : []) {
    const mime = String(image?.mimeType ?? '')
    if (mime.includes('ktx') || mime.includes('basis')) {
      throw new Error(
        'KTX2/Basis textures are not approved and cannot be decoded here — re-export with ' +
          'plain PNG or JPEG textures (guide §C8).',
      )
    }
  }
}

/**
 * Decimate, then normalize. Returns the bytes that should be uploaded, the
 * normalizer's change log, and its before/after metrics.
 *
 * @param {object} args
 * @param {Uint8Array} args.bytes          the raw export
 * @param {object} args.plan               from `planCompression`
 * @param {object} [args.io]               a gltf-transform IO; `WebIO` by default
 * @param {(stage: string) => void} [args.onStage]  progress, for the modal
 */
export async function compressShoeModel({ bytes, plan, io = null, onStage = () => {} }) {
  const input = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  refuseUnreadable(input)

  const ratio = plan?.ratio ?? null

  // `simplify` needs the WASM module compiled before it can do anything, and
  // the promise is memoized inside meshoptimizer — awaiting it twice is free.
  if (ratio !== null) await MeshoptSimplifier.ready

  const reader = io ?? new WebIO()
  onStage('reading')
  const document = await reader.readBinary(input)

  if (ratio !== null) {
    onStage('simplifying')
    await document.transform(
      weld(),
      simplify({ simplifier: MeshoptSimplifier, ratio, error: SIMPLIFY_ERROR }),
    )
  }

  onStage('writing')
  const decimated = await reader.writeBinary(document)

  onStage('normalizing')
  const result = soleVisionNormalize(decimated, JSON.stringify(plan?.options ?? {}))
  if (!result.ok) {
    // The normalizer's refusals are written to be forwarded to whoever sent the
    // model, so they travel as-is — the same way the server's verdict does.
    throw new Error(result.error)
  }

  return {
    bytes: result.bytes instanceof Uint8Array ? result.bytes : new Uint8Array(result.bytes),
    changes: JSON.parse(result.changes),
    before: JSON.parse(result.before),
    after: JSON.parse(result.after),
    decimatedBytes: decimated.length,
  }
}