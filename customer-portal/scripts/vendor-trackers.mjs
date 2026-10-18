// Vendors the foot-tracker's heavy downloads into `public/vendor/mediapipe`
// so the try-on serves them same-origin with immutable caching (see
// `vercel.json`) instead of depending on third-party CDNs per visit.
//
// - The wasm runtime is copied from the installed
//   `@mediapipe/tasks-vision` package, so it always matches the bundle
//   version — a dependency upgrade automatically re-vendors the matching
//   runtime. The script asserts the expected loader layout and fails the
//   build loudly if a new package version rearranges it.
// - The pose model is downloaded from its pinned bundle path and verified
//   by exact byte size, so a truncated download can never ship.
//
// Idempotent: files whose byte size already matches are skipped, making
// `predev`/`prebuild` cheap after the first run. Generated output is
// gitignored — Vercel runs this during the build.
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const portalRoot = join(here, '..')

// Read by path, not by package subpath: the package's `exports` map does
// not expose `./package.json` to `require`.
const { version: visionVersion } = JSON.parse(
  readFileSync(
    join(portalRoot, 'node_modules', '@mediapipe', 'tasks-vision', 'package.json'),
    'utf8',
  ),
)
const wasmDir = join(portalRoot, 'node_modules', '@mediapipe', 'tasks-vision', 'wasm')
const outDir = join(portalRoot, 'public', 'vendor', 'mediapipe')

// The loaders `FilesetResolver` can request: classic + ESM module builds,
// each in SIMD and no-SIMD variants. The worker always takes the module
// build; the main thread picks by capability at runtime.
const WASM_FILES = [
  'vision_wasm_internal.js',
  'vision_wasm_internal.wasm',
  'vision_wasm_module_internal.js',
  'vision_wasm_module_internal.wasm',
  'vision_wasm_nosimd_internal.js',
  'vision_wasm_nosimd_internal.wasm',
]

const MODEL_URL =
  'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task'
const MODEL_FILE = 'pose_landmarker_lite.task'
// Exact bytes measured 2026-10-18; the `/1/` bundle path is pinned, so any
// change means the upstream republished and deserves a human look.
const MODEL_BYTES = 5777746

function sizeOf(path) {
  try {
    return statSync(path).size
  } catch {
    return -1
  }
}

// Vercel rejects the deploy on an invalid vercel.json (JSON has no
// comments), so validate it here while the failure is still local.
try {
  JSON.parse(readFileSync(join(portalRoot, 'vercel.json'), 'utf8'))
} catch (err) {
  throw new Error(`[vendor-trackers] vercel.json is invalid JSON: ${err.message}`)
}

mkdirSync(outDir, { recursive: true })

for (const file of WASM_FILES) {
  const src = join(wasmDir, file)
  if (!existsSync(src)) {
    throw new Error(
      `[vendor-trackers] @mediapipe/tasks-vision@${visionVersion} has no wasm/${file} — ` +
        'the package rearranged its loaders; update WASM_FILES to match.',
    )
  }
  const dest = join(outDir, file)
  if (sizeOf(dest) === sizeOf(src)) {
    console.log(`[vendor-trackers] skip ${file} (already vendored)`)
    continue
  }
  copyFileSync(src, dest)
  console.log(`[vendor-trackers] copied ${file} (${sizeOf(dest)} bytes)`)
}

const modelDest = join(outDir, MODEL_FILE)
if (sizeOf(modelDest) === MODEL_BYTES) {
  console.log('[vendor-trackers] skip pose model (already vendored)')
} else {
  console.log(`[vendor-trackers] downloading pose model (${MODEL_URL})…`)
  const res = await fetch(MODEL_URL)
  if (!res.ok) throw new Error(`[vendor-trackers] model download failed: HTTP ${res.status}`)
  const bytes = new Uint8Array(await res.arrayBuffer())
  if (bytes.byteLength !== MODEL_BYTES) {
    throw new Error(
      `[vendor-trackers] model is ${bytes.byteLength} bytes, expected ${MODEL_BYTES} — ` +
        'upstream republished or the download truncated; update MODEL_BYTES after review.',
    )
  }
  writeFileSync(modelDest, bytes)
  console.log(`[vendor-trackers] saved ${MODEL_FILE} (${bytes.byteLength} bytes)`)
}

console.log('[vendor-trackers] done')
