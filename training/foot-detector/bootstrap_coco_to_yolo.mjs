// Bootstrap YOLO-pose labels from the public shoe COCO boxes.
//
// The public set has no keypoints — but per image it has a foot box
// (left_foot/right_foot) plus tiny heel + toe boxes. The box CENTERS make
// honest v=2 heel/toe points: they were human-clicked, just stored as
// 5px boxes instead of points. This gives a 535-image day-one training
// set; your 51 dim/blurry photos still need hand labels (Roboflow loop).
//
// Usage: node training/foot-detector/bootstrap_coco_to_yolo.mjs
// Output: training/foot-detector/datasets/foot/{images,labels}/{train,val}/
//   train = public train split (276) + held-out nothing from raw
//   val   = public validation split (146); public test (113) stays untouched
//   Your raw/ photos are COPIED into images/train-unlabeled/ for the label loop.
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const pubDir = join(here, 'datasets', 'public')
const outRoot = join(here, 'datasets', 'foot')

const FOOT_IDS = new Set([3, 5]) // left_foot, right_foot
const HEEL_ID = 2
const TOE_ID = 6

function loadSplit(split) {
  const tag = split === 'train' ? 'train' : split
  const annPath = join(pubDir, `shoes_coco_${tag}__annotations.coco.json`)
  const imgDir = join(pubDir, 'shoes_coco', split === 'train' ? 'train' : split)
  return { ann: JSON.parse(readFileSync(annPath, 'utf8')), imgDir }
}

function center(bbox) {
  return [bbox[0] + bbox[2] / 2, bbox[1] + bbox[3] / 2]
}

let trainN = 0
let valN = 0
let skipped = 0

for (const split of ['train', 'validation']) {
  const { ann, imgDir } = loadSplit(split)
  const outSplit = split === 'train' ? 'train' : 'val'
  const imgOut = join(outRoot, 'images', outSplit)
  const lblOut = join(outRoot, 'labels', outSplit)
  mkdirSync(imgOut, { recursive: true })
  mkdirSync(lblOut, { recursive: true })

  const imgById = new Map(ann.images.map((im) => [im.id, im]))
  const annsByImg = new Map()
  for (const a of ann.annotations) {
    if (!annsByImg.has(a.image_id)) annsByImg.set(a.image_id, [])
    annsByImg.get(a.image_id).push(a)
  }

  for (const [imgId, list] of annsByImg) {
    const im = imgById.get(imgId)
    if (!im) { skipped++; continue }
    const feet = list.filter((a) => FOOT_IDS.has(a.category_id))
    const heels = list.filter((a) => a.category_id === HEEL_ID)
    const toes = list.filter((a) => a.category_id === TOE_ID)
    if (!feet.length || !heels.length || !toes.length) { skipped++; continue }
    // One label row per foot box, matched to nearest heel/toe center.
    const rows = []
    for (const f of feet) {
      const [fx, fy, fw, fh] = f.bbox
      if (!(fw > 4 && fh > 4)) continue
      const fcx = fx + fw / 2
      const fcy = fy + fh / 2
      const near = (pts) => {
        let best = null
        let bestD = Infinity
        for (const p of pts) {
          const [px, py] = center(p.bbox)
          const d = (px - fcx) ** 2 + (py - fcy) ** 2
          if (d < bestD) { bestD = d; best = [px, py] }
        }
        return best
      }
      const h = near(heels)
      const t = near(toes)
      if (!h || !t) continue
      const xc = (fx + fw / 2) / im.width
      const yc = (fy + fh / 2) / im.height
      const w = fw / im.width
      const hh = fh / im.height
      const fmt = (n) => (Number.isFinite(n) ? n.toFixed(6) : '0.000000')
      rows.push(
        `0 ${fmt(xc)} ${fmt(yc)} ${fmt(w)} ${fmt(hh)} ${fmt(h[0] / im.width)} ${fmt(h[1] / im.height)} 2 ${fmt(t[0] / im.width)} ${fmt(t[1] / im.height)} 2`,
      )
    }
    if (!rows.length) { skipped++; continue }
    const src = join(imgDir, im.file_name)
    if (!existsSync(src)) { skipped++; continue }
    copyFileSync(src, join(imgOut, im.file_name))
    writeFileSync(join(lblOut, im.file_name.replace(/\.[^.]+$/, '.txt')), rows.join('\n') + '\n')
    if (outSplit === 'train') trainN++
    else valN++
  }
}

// Your 51 own photos → images/train-unlabeled/ for the Roboflow loop.
const unlabeledOut = join(outRoot, 'images', 'train-unlabeled')
mkdirSync(unlabeledOut, { recursive: true })
let unlabeled = 0
for (const sess of ['2026-10-18-blurry', '2026-10-18-dim-room']) {
  const { readdirSync } = await import('node:fs')
  const dir = join(here, 'datasets', 'raw', sess)
  let files = []
  try { files = readdirSync(dir).filter((f) => /\.jpe?g$/i.test(f)) } catch { continue }
  for (const f of files) {
    const dest = join(unlabeledOut, `${sess}__${f}`)
    if (!existsSync(dest)) copyFileSync(join(dir, f), dest)
    unlabeled++
  }
}

console.log(`[bootstrap] train=${trainN} val=${valN} skipped=${skipped} unlabeled=${unlabeled}`)
console.log('[bootstrap] next: label images/train-unlabeled/ in Roboflow, export txt to labels/train/, then run the Colab train.')
