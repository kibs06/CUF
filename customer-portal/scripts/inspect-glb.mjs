// GLB orientation inspector — dev tool only, never shipped to customers.
//
// Usage:
//   node scripts/inspect-glb.mjs <path-or-url> [more ...]
//   node scripts/inspect-glb.mjs --audit > docs/model-orientation-audit.md
//
// For each .glb it applies the same orientation fix the try-on viewer
// applies (`rotation.z = PI`, sole-side-up), then prints bounding box,
// longest horizontal axis, and a toe-direction estimate from three
// independent signals (height profile, width profile, vertex density).
// Slide sandals: the strap/upper sits at the TOE end — tall geometry at
// one end marks the toe.
//
// Requires @gltf-transform/core (devDependency). Pure Node, no DOM.
import { readFile } from 'node:fs/promises'
import { NodeIO } from '@gltf-transform/core'
import { mat4, vec3 } from './inspect-math.mjs'

async function loadBytes(target) {
  if (/^https?:\/\//.test(target)) {
    const res = await fetch(target)
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${target}`)
    return new Uint8Array(await res.arrayBuffer())
  }
  return new Uint8Array(await readFile(target))
}

// Compose world matrices by walking the scene graph.
function collectPositions(doc) {
  const root = doc.getRoot()
  const positions = []
  const identity = mat4Identity()
  for (const scene of root.listScenes()) {
    for (const node of scene.listChildren()) walkNode(node, identity, positions)
  }
  return positions
}

function mat4Identity() {
  return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
}

function walkNode(node, parentMatrix, out) {
  const local = node.getMatrix()
  const world = mat4Multiply(parentMatrix, local)
  const mesh = node.getMesh()
  if (mesh) {
    for (const prim of mesh.listPrimitives()) {
      const pos = prim.getAttribute('POSITION')
      if (!pos) continue
      const array = pos.getArray()
      const v = [0, 0, 0]
      for (let i = 0; i < pos.getCount(); i++) {
        v[0] = array[i * 3]
        v[1] = array[i * 3 + 1]
        v[2] = array[i * 3 + 2]
        // Viewer applies rotation.z = PI (sole-side-up) before measuring.
        // Rotation about Z by PI: (x, y) -> (-x, -y).
        const rotated = [-v[0], -v[1], v[2]]
        out.push(mat4TransformPoint(world, rotated))
      }
    }
  }
  for (const child of node.listChildren()) walkNode(child, world, out)
}

function mat4Multiply(a, b) {
  return mat4.multiply(a, b)
}

function mat4TransformPoint(m, p) {
  const out = [0, 0, 0]
  vec3.transformMat4(out, p, m)
  return out
}

function boundsOf(points) {
  const min = [Infinity, Infinity, Infinity]
  const max = [-Infinity, -Infinity, -Infinity]
  for (const p of points) {
    for (let i = 0; i < 3; i++) {
      if (p[i] < min[i]) min[i] = p[i]
      if (p[i] > max[i]) max[i] = p[i]
    }
  }
  const size = [max[0] - min[0], max[1] - min[1], max[2] - min[2]]
  const center = [(min[0] + max[0]) / 2, (min[1] + max[1]) / 2, (min[2] + max[2]) / 2]
  return { min, max, size, center }
}

// Toe-direction signals along the long horizontal axis (0=x, 2=z).
function toeSignals(points, axis) {
  const cross = axis === 0 ? 2 : 0
  const lo = Math.min(...points.map((p) => p[axis]))
  const hi = Math.max(...points.map((p) => p[axis]))
  const span = hi - lo || 1
  const low = points.filter((p) => (p[axis] - lo) / span < 1 / 3)
  const high = points.filter((p) => (p[axis] - lo) / span > 2 / 3)
  const mean = (arr, fn) => arr.reduce((a, p) => a + fn(p), 0) / Math.max(1, arr.length)
  const spread = (arr) => {
    const xs = arr.map((p) => p[cross])
    return Math.max(...xs) - Math.min(...xs)
  }
  const lowH = mean(low, (p) => p[1])
  const highH = mean(high, (p) => p[1])
  const lowW = spread(low)
  const highW = spread(high)
  return {
    height: { low: lowH, high: highH, toeAt: lowH < highH ? 'low' : 'high' },
    width: { low: lowW, high: highW, toeAt: lowW > highW ? 'low' : 'high' },
    density: {
      low: low.length,
      high: high.length,
      toeAt: high.length >= low.length ? 'high' : 'low',
    },
  }
}

async function inspect(target) {
  const bytes = await loadBytes(target)
  const io = new NodeIO()
  const doc = await io.readBinary(bytes)
  const points = collectPositions(doc)
  if (points.length === 0) return { target, error: 'no POSITION vertices found' }
  const { min, max, size, center } = boundsOf(points)
  const longAxis = size[0] >= size[2] ? 'x' : 'z'
  const axisIdx = longAxis === 'x' ? 0 : 2
  const signals = toeSignals(points, axisIdx)
  const votes = [signals.height.toeAt, signals.width.toeAt, signals.density.toeAt]
  const forLow = votes.filter((v) => v === 'low').length
  const toeEnd = forLow >= 2 ? '-end' : '+end'
  const agree = forLow === 0 || forLow === 3 ? 'agree' : 'disagree'
  const forwardAxis = longAxis === 'z' ? (toeEnd === '+end' ? '+z' : '-z') : toeEnd === '+end' ? '+x' : '-x'
  return {
    target,
    vertices: points.length,
    min: min.map((n) => +n.toFixed(4)),
    max: max.map((n) => +n.toFixed(4)),
    size: size.map((n) => +n.toFixed(4)),
    center: center.map((n) => +n.toFixed(4)),
    longAxis,
    signals,
    toeEnd,
    confidence: agree,
    forwardAxis,
  }
}

function printReport(r) {
  console.log(`\n## ${r.target}`)
  if (r.error) {
    console.log(`- error: ${r.error}`)
    return
  }
  console.log(`- vertices: ${r.vertices}`)
  console.log(`- size (x,y,z): [${r.size.join(', ')}]`)
  console.log(`- min: [${r.min.join(', ')}] max: [${r.max.join(', ')}]`)
  console.log(`- center: [${r.center.join(', ')}]`)
  console.log(`- longest horizontal axis: ${r.longAxis}`)
  console.log(
    `- height: low=${r.signals.height.low.toFixed(4)} high=${r.signals.height.high.toFixed(4)} → toe at ${r.signals.height.toeAt}`,
  )
  console.log(
    `- width: low=${r.signals.width.low.toFixed(4)} high=${r.signals.width.high.toFixed(4)} → toe at ${r.signals.width.toeAt}`,
  )
  console.log(
    `- density: low=${r.signals.density.low} high=${r.signals.density.high} → toe at ${r.signals.density.toeAt}`,
  )
  console.log(`- suggested forward_axis: ${r.forwardAxis} (confidence: ${r.confidence})`)
}

const targets = process.argv.slice(2).filter((a) => a !== '--audit')
if (targets.length === 0) {
  console.error('usage: node scripts/inspect-glb.mjs <file-or-url> [...]')
  process.exit(1)
}
for (const t of targets) {
  try {
    printReport(await inspect(t))
  } catch (err) {
    console.log(`\n## ${t}\n- error: ${err.message}`)
  }
}
