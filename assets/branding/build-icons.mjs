#!/usr/bin/env node
/**
 * Regenerates the shipped brand assets from the single source render.
 *
 *   node assets/branding/build-icons.mjs [path/to/source.png]
 *
 * Input : assets/branding/source/cufmai-c-mark-1254.png  (the AI render, RGBA)
 * Output: assets/branding/cufmai-c-mark-1024.png                    launcher source
 *         assets/branding/cufmai-c-mark-adaptive-foreground-1024.png  Android FG layer
 *         assets/branding/cufmai-c-mark-adaptive-background-1024.png  Android BG layer
 *
 * Why this exists: the render arrives with baked rounded corners on a
 * transparent canvas. iOS rejects alpha in AppIcon, and Android's adaptive icon
 * wants the art and the background as two separate layers. Both problems are
 * solved here so `flutter_launcher_icons` only ever sees clean 1024 squares.
 *
 * No third-party dependencies — Node's zlib is enough.
 */
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const SRC = args[0] ?? 'assets/branding/source/cufmai-c-mark-1254.png';
const OUT = 'assets/branding';

// ---------------------------------------------------------------- PNG codec

function decodePng(file) {
  const buf = fs.readFileSync(file);
  const w = buf.readUInt32BE(16), h = buf.readUInt32BE(20);
  if (buf[25] !== 6 || buf[24] !== 8 || buf[28] !== 0) {
    throw new Error(`${file}: only 8-bit RGBA non-interlaced PNGs are supported`);
  }
  let off = 8; const idat = [];
  while (off < buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.slice(off + 4, off + 8).toString('ascii');
    if (type === 'IDAT') idat.push(buf.slice(off + 8, off + 8 + len));
    off += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const bpp = 4, stride = w * bpp, px = Buffer.alloc(h * stride);
  let pos = 0;
  for (let y = 0; y < h; y++) {
    const ft = raw[pos++], line = raw.slice(pos, pos + stride); pos += stride;
    const prev = y === 0 ? Buffer.alloc(stride) : px.slice((y - 1) * stride, y * stride);
    const cur = px.slice(y * stride, (y + 1) * stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? cur[x - bpp] : 0;
      const b = prev[x];
      const c = x >= bpp ? prev[x - bpp] : 0;
      let v = line[x];
      if (ft === 1) v += a;
      else if (ft === 2) v += b;
      else if (ft === 3) v += (a + b) >> 1;
      else if (ft === 4) {
        const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      }
      cur[x] = v & 0xff;
    }
  }
  return { w, h, px };
}

let CRC_TABLE = null;
function crc32(bytes) {
  if (!CRC_TABLE) {
    CRC_TABLE = [];
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      CRC_TABLE[n] = c >>> 0;
    }
  }
  let c = 0xffffffff;
  for (const b of bytes) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function encodePng({ w, h, px }, { opaque = false } = {}) {
  // Colour type 2 (RGB) with no alpha channel at all — that is what iOS wants;
  // a fully-opaque RGBA tile is still rejected by App Store validation.
  const bpp = opaque ? 3 : 4;
  const stride = w * bpp, raw = Buffer.alloc(h * (stride + 1));
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const s = (y * w + x) * 4, d = y * (stride + 1) + 1 + x * bpp;
      raw[d] = px[s]; raw[d + 1] = px[s + 1]; raw[d + 2] = px[s + 2];
      if (!opaque) raw[d + 3] = px[s + 3];
    }
  }
  const chunks = [];
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
    chunks.push(len, td, crc);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = opaque ? 2 : 6;
  chunk('IHDR', ihdr);
  chunk('IDAT', zlib.deflateSync(raw, { level: 9 }));
  chunk('IEND', Buffer.alloc(0));
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), ...chunks]);
}

// ------------------------------------------------------------ image helpers

const luma = (r, g, b) => 0.299 * r + 0.587 * g + 0.114 * b;
const ASCII = ' .:-=+*#%@';

/** Resample an arbitrary source rect into a dw x dh image. Correct on alpha. */
function resample(src, rect, dw, dh) {
  const { w, h, px } = src;
  const out = Buffer.alloc(dw * dh * 4);
  const sx = rect.w / dw, sy = rect.h / dh;
  for (let dy = 0; dy < dh; dy++) {
    const y0 = rect.y + dy * sy, y1 = y0 + sy;
    for (let dx = 0; dx < dw; dx++) {
      const x0 = rect.x + dx * sx, x1 = x0 + sx;
      let r = 0, g = 0, b = 0, a = 0, weight = 0;
      if (sx <= 1.0001 && sy <= 1.0001) {
        // upscale: bilinear at the pixel centre, in premultiplied space
        const [pr, pg, pb, pa] = bilinear(src, x0 + sx / 2 - 0.5, y0 + sy / 2 - 0.5);
        r = pr; g = pg; b = pb; a = pa; weight = 1;
      } else {
        // downscale: exact box average, weighted by each source pixel's coverage
        const iy0 = Math.max(0, Math.floor(y0)), iy1 = Math.min(h - 1, Math.ceil(y1) - 1);
        const ix0 = Math.max(0, Math.floor(x0)), ix1 = Math.min(w - 1, Math.ceil(x1) - 1);
        for (let y = iy0; y <= iy1; y++) {
          const wy = Math.min(y1, y + 1) - Math.max(y0, y);
          if (wy <= 0) continue;
          for (let x = ix0; x <= ix1; x++) {
            const wx = Math.min(x1, x + 1) - Math.max(x0, x);
            if (wx <= 0) continue;
            const wt = wx * wy, o = (y * w + x) * 4;
            const al = px[o + 3] / 255;
            r += px[o] * al * wt; g += px[o + 1] * al * wt; b += px[o + 2] * al * wt;
            a += al * wt; weight += wt;
          }
        }
      }
      const o = (dy * dw + dx) * 4;
      if (weight === 0 || a === 0) { out[o + 3] = 0; continue; }
      const alpha = a / weight;
      out[o] = Math.min(255, Math.round(r / weight / alpha));
      out[o + 1] = Math.min(255, Math.round(g / weight / alpha));
      out[o + 2] = Math.min(255, Math.round(b / weight / alpha));
      out[o + 3] = Math.round(alpha * 255);
    }
  }
  return { w: dw, h: dh, px: out };
}

function bilinear(src, fx, fy) {
  const { w, h, px } = src;
  const cx = Math.min(w - 1, Math.max(0, fx)), cy = Math.min(h - 1, Math.max(0, fy));
  const x0 = Math.floor(cx), y0 = Math.floor(cy);
  const x1 = Math.min(w - 1, x0 + 1), y1 = Math.min(h - 1, y0 + 1);
  const tx = cx - x0, ty = cy - y0;
  const at = (x, y) => { const o = (y * w + x) * 4; const a = px[o + 3] / 255; return [px[o] * a, px[o + 1] * a, px[o + 2] * a, a]; };
  const p = [at(x0, y0), at(x1, y0), at(x0, y1), at(x1, y1)];
  const mix = (i) => (p[0][i] * (1 - tx) + p[1][i] * tx) * (1 - ty) + (p[2][i] * (1 - tx) + p[3][i] * tx) * ty;
  return [mix(0), mix(1), mix(2), mix(3)];
}

/** Separable box blur over a Float32 field. */
function boxBlur(field, w, h, radius) {
  const tmp = new Float32Array(w * h), out = new Float32Array(w * h);
  for (let y = 0; y < h; y++) {
    let sum = 0;
    for (let x = -radius; x <= radius; x++) sum += field[y * w + Math.min(w - 1, Math.max(0, x))];
    for (let x = 0; x < w; x++) {
      tmp[y * w + x] = sum / (2 * radius + 1);
      sum += field[y * w + Math.min(w - 1, x + radius + 1)] - field[y * w + Math.max(0, x - radius)];
    }
  }
  for (let x = 0; x < w; x++) {
    let sum = 0;
    for (let y = -radius; y <= radius; y++) sum += tmp[Math.min(h - 1, Math.max(0, y)) * w + x];
    for (let y = 0; y < h; y++) {
      out[y * w + x] = sum / (2 * radius + 1);
      sum += tmp[Math.min(h - 1, y + radius + 1) * w + x] - tmp[Math.max(0, y - radius) * w + x];
    }
  }
  return out;
}

/** Separable square max filter, used to find each pixel's local brightness ceiling. */
function maxFilter(field, w, h, radius) {
  const tmp = new Float32Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let m = -Infinity;
    for (let k = -radius; k <= radius; k++) {
      const v = field[y * w + Math.min(w - 1, Math.max(0, x + k))];
      if (v > m) m = v;
    }
    tmp[y * w + x] = m;
  }
  const out = new Float32Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let m = -Infinity;
    for (let k = -radius; k <= radius; k++) {
      const v = tmp[Math.min(h - 1, Math.max(0, y + k)) * w + x];
      if (v > m) m = v;
    }
    out[y * w + x] = m;
  }
  return out;
}

// ----------------------------------------------------------------- the build

const src = decodePng(SRC);
const { w: W, h: H } = src;

// 1. the tile: the opaque bounding box inside the transparent canvas
let minX = W, minY = H, maxX = -1, maxY = -1;
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  if (src.px[(y * W + x) * 4 + 3] > 128) {
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (y < minY) minY = y; if (y > maxY) maxY = y;
  }
}
const tile = { x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1 };
const tileCx = tile.x + tile.w / 2, tileCy = tile.y + tile.h / 2;
console.log(`source      ${W}x${H}  ->  tile ${tile.w}x${tile.h} at ${tile.x},${tile.y}`);

const alphaAt = (x, y) => src.px[(y * W + x) * 4 + 3];

// 2. Every row's opaque span, and each row's nearest neighbour that has one.
//    Anything at right angles to the tile edge is filled by extending these
//    spans outwards, which keeps the tile's own gradient going instead of
//    inventing a corner colour.
const rowFirst = new Int32Array(H).fill(-1), rowLast = new Int32Array(H).fill(-1);
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  if (alphaAt(x, y) >= 250) { if (rowFirst[y] < 0) rowFirst[y] = x; rowLast[y] = x; }
}
const nearestRow = new Int32Array(H).fill(-1);
for (let y = 0, last = -1; y < H; y++) { if (rowFirst[y] >= 0) last = y; nearestRow[y] = last; }
for (let y = H - 1, last = -1; y >= 0; y--) {
  if (rowFirst[y] >= 0) last = y;
  if (nearestRow[y] < 0 || (last >= 0 && y - nearestRow[y] > last - y)) nearestRow[y] = last;
}
/** Snap a coordinate onto the nearest pixel that is actually inside the tile. */
function clampToTile(x, y) {
  let sy = Math.min(H - 1, Math.max(0, y));
  if (rowFirst[sy] < 0) sy = Math.max(0, Math.min(H - 1, nearestRow[sy]));
  return [Math.min(rowLast[sy], Math.max(rowFirst[sy], x)), sy];
}

// How much of the tile the rounded corners eat. Reported, not used for cropping:
// the mark runs to within a few pixels of the tile edge, so cropping inwards to
// dodge the corners would take the C's outer sweep with it.
const cornersOpaque = (size) => {
  const x0 = Math.round(tileCx - size / 2), y0 = Math.round(tileCy - size / 2);
  for (const [cx, cy] of [[0, 0], [size - 1, 0], [0, size - 1], [size - 1, size - 1]]) {
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      if (alphaAt(Math.min(W - 1, Math.max(0, x0 + cx + dx)), Math.min(H - 1, Math.max(0, y0 + cy + dy))) < 250) return false;
    }
  }
  return true;
};
let lo = 16, hi = Math.min(tile.w, tile.h);
while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (cornersOpaque(mid)) lo = mid; else hi = mid; }
console.log(`corners     ~${Math.round((Math.min(tile.w, tile.h) - lo) / 2)}px radius, i.e. only the inner ${(100 * lo / Math.min(tile.w, tile.h)).toFixed(0)}% is corner-free`);

// 3. The launcher square is the full tile, squared off and forced opaque. iOS
//    rejects alpha, and both platforms apply their own corner mask, so the
//    filled corners are never actually seen — they only have to be plausible.
const side = Math.max(tile.w, tile.h);
const crop = { x: tileCx - side / 2, y: tileCy - side / 2, w: side, h: side };
function flattenTile() {
  const S = Math.round(side);
  const out = Buffer.alloc(S * S * 4);
  for (let dy = 0; dy < S; dy++) for (let dx = 0; dx < S; dx++) {
    const [sx, sy] = clampToTile(Math.round(crop.x + dx), Math.round(crop.y + dy));
    const s = (sy * W + sx) * 4, d = (dy * S + dx) * 4;
    out[d] = src.px[s]; out[d + 1] = src.px[s + 1]; out[d + 2] = src.px[s + 2]; out[d + 3] = 255;
  }
  return { w: S, h: S, px: out };
}
/** Same extrapolation, applied to the gradient so the background layer is clean. */
function extendToTile(img) {
  const out = Buffer.alloc(W * H * 4);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const [sx, sy] = clampToTile(x, y);
    const s = (sy * W + sx) * 4, d = (y * W + x) * 4;
    out[d] = img.px[s]; out[d + 1] = img.px[s + 1]; out[d + 2] = img.px[s + 2]; out[d + 3] = 255;
  }
  return { w: W, h: H, px: out };
}

// 4. flat-field background estimate, in two passes. A single low-percentile
//    pass lands *below* the background mean, which leaves a faint haze of false
//    ink across the whole tile. So pass 1 finds the background, then the field
//    is re-fit using only the pixels pass 1 agreed were background. What falls
//    out is both an accurate matte and a mark-free gradient for Android.
const srcLuma = new Float32Array(W * H);
for (let i = 0; i < W * H; i++) srcLuma[i] = luma(src.px[i * 4], src.px[i * 4 + 1], src.px[i * 4 + 2]);

function upsampleGrid(grid, N) {
  const img = { w: W, h: H, px: Buffer.alloc(W * H * 4) };
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const gx = x * N / W - 0.5, gy = y * N / H - 0.5;
    const x0 = Math.min(N - 1, Math.max(0, Math.floor(gx))), y0 = Math.min(N - 1, Math.max(0, Math.floor(gy)));
    const x1 = Math.min(N - 1, x0 + 1), y1 = Math.min(N - 1, y0 + 1);
    const tx = Math.min(1, Math.max(0, gx - x0)), ty = Math.min(1, Math.max(0, gy - y0));
    const o = (y * W + x) * 4;
    for (let c = 0; c < 3; c++) {
      const a = grid[(y0 * N + x0) * 3 + c], b = grid[(y0 * N + x1) * 3 + c];
      const d = grid[(y1 * N + x0) * 3 + c], e = grid[(y1 * N + x1) * 3 + c];
      img.px[o + c] = Math.round((a * (1 - tx) + b * tx) * (1 - ty) + (d * (1 - tx) + e * tx) * ty);
    }
    img.px[o + 3] = 255;
  }
  return img;
}
function smoothField(img, radius) {
  for (let c = 0; c < 3; c++) {
    const plane = new Float32Array(W * H);
    for (let i = 0; i < W * H; i++) plane[i] = img.px[i * 4 + c];
    const blurred = boxBlur(plane, W, H, radius);
    for (let i = 0; i < W * H; i++) img.px[i * 4 + c] = Math.round(blurred[i]);
  }
  return img;
}
function blocks(N, fill) {
  const grid = new Float32Array(N * N * 3);
  for (let gy = 0; gy < N; gy++) for (let gx = 0; gx < N; gx++) {
    const x0 = Math.floor(gx * W / N), x1 = Math.min(W, Math.ceil((gx + 1) * W / N));
    const y0 = Math.floor(gy * H / N), y1 = Math.min(H, Math.ceil((gy + 1) * H / N));
    fill(grid, (gy * N + gx) * 3, x0, x1, y0, y1);
  }
  return grid;
}

// pass 1 — the block's 25th percentile, picked whole so the hue survives
const coarse = smoothField(upsampleGrid(blocks(24, (grid, gi, x0, x1, y0, y1) => {
  const picks = [];
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) picks.push(x + y * W);
  picks.sort((a, b) => srcLuma[a] - srcLuma[b]);
  const o = picks[Math.floor(picks.length * 0.25)] * 4;
  grid[gi] = src.px[o]; grid[gi + 1] = src.px[o + 1]; grid[gi + 2] = src.px[o + 2];
}), 24), 5);
const coarseLuma = new Float32Array(W * H);
for (let i = 0; i < W * H; i++) coarseLuma[i] = luma(coarse.px[i * 4], coarse.px[i * 4 + 1], coarse.px[i * 4 + 2]);
const localPeak = maxFilter(srcLuma, W, H, 10);
const coarseMatte = new Float32Array(W * H);
for (let i = 0; i < W * H; i++) {
  const denom = Math.max(localPeak[i], coarseLuma[i]) - coarseLuma[i];
  coarseMatte[i] = denom < 12 ? 0 : Math.min(1, Math.max(0, (srcLuma[i] - coarseLuma[i]) / denom));
}

// pass 2 — average only what pass 1 called background, so the field is a true
// mean rather than a low percentile. Pixels within a few px of the mark are
// excluded outright rather than threshold-tested: the render's soft rim bleeds
// into its neighbours, and averaging that in is exactly what puts a ghost of the
// C into the background layer.
const coarseInk = new Float32Array(W * H);
for (let i = 0; i < W * H; i++) coarseInk[i] = coarseMatte[i] > 0.12 ? 1 : 0;
const nearInk = boxBlur(coarseInk, W, H, 5);

const N2 = 32;
const fineGrid = new Float32Array(N2 * N2 * 3);
const usable = new Uint8Array(N2 * N2);
for (let gy = 0; gy < N2; gy++) for (let gx = 0; gx < N2; gx++) {
  const x0 = Math.floor(gx * W / N2), x1 = Math.min(W, Math.ceil((gx + 1) * W / N2));
  const y0 = Math.floor(gy * H / N2), y1 = Math.min(H, Math.ceil((gy + 1) * H / N2));
  let r = 0, g = 0, b = 0, n = 0, seen = 0;
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    seen++;
    const i = y * W + x;
    if (nearInk[i] > 0) continue;
    r += src.px[i * 4]; g += src.px[i * 4 + 1]; b += src.px[i * 4 + 2]; n++;
  }
  const gi = (gy * N2 + gx) * 3;
  if (n > seen * 0.15) {
    fineGrid[gi] = r / n; fineGrid[gi + 1] = g / n; fineGrid[gi + 2] = b / n;
    usable[gy * N2 + gx] = 1;
  }
}
// A block the mark covers outright has no clean pixels of its own, so it takes
// the value of the nearest block that did.
const queue = [];
for (let i = 0; i < N2 * N2; i++) if (usable[i]) queue.push(i);
if (!queue.length) throw new Error('every background block touches the mark');
const seed = fineGrid.slice();
for (let qi = 0; qi < queue.length; qi++) {
  const i = queue[qi], bx = i % N2, by = (i / N2) | 0;
  for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
    const nx = bx + dx, ny = by + dy;
    if (nx < 0 || ny < 0 || nx >= N2 || ny >= N2) continue;
    const j = ny * N2 + nx;
    if (usable[j]) continue;
    usable[j] = 1;
    for (let c = 0; c < 3; c++) fineGrid[j * 3 + c] = seed[i * 3 + c];
    queue.push(j);
  }
}
const interpolated = N2 * N2 - queue.length;
if (interpolated > 0) console.log(`field       ${interpolated} block(s) fully covered by the mark, taken from neighbours`);
// A wide blur on the way out: the grid is ~39px per block, so without it the
// block seams survive into the background layer as a faint quilt.
const field = smoothField(upsampleGrid(fineGrid, N2), 14);
const fieldLuma = new Float32Array(W * H);
for (let i = 0; i < W * H; i++) fieldLuma[i] = luma(field.px[i * 4], field.px[i * 4 + 1], field.px[i * 4 + 2]);

// 5. matte. The mark's own local peak is the foreground reference, so the core
//    of a stroke lands on alpha 1 and only the anti-aliased rim ramps.

const matte = new Float32Array(W * H);
const mark = { w: W, h: H, px: Buffer.alloc(W * H * 4) };
for (let i = 0; i < W * H; i++) {
  const bg = fieldLuma[i], peak = Math.max(localPeak[i], bg);
  const denom = peak - bg;
  // below the noise floor there is nothing but the tile's own grain
  let a = denom < 14 || srcLuma[i] - bg < 5 ? 0 : (srcLuma[i] - bg) / denom;
  a = Math.min(1, Math.max(0, a));
  if (a < 0.18) a = 0;
  if (a > 0.92) a = 1;
  // The transparent canvas has no defined colour, and the tile's own
  // anti-aliased rim is not part of the mark. Neither should become ink.
  if (src.px[i * 4 + 3] < 230) a = 0;
  // un-premultiply so anti-aliased edges do not carry a dark fringe
  if (a > 0) for (let c = 0; c < 3; c++) {
    const v = (src.px[i * 4 + c] - (1 - a) * field.px[i * 4 + c]) / a;
    mark.px[i * 4 + c] = Math.min(255, Math.max(0, Math.round(v)));
  }
  mark.px[i * 4 + 3] = Math.round(a * 255);
  matte[i] = a;
}

// Speckle removal. A real stroke is surrounded by ink; a stray gradient residual
// is a few pixels alone in the dark. Measuring the local ink density separates
// the two cleanly, where a brightness threshold alone cannot.
const inkMask = new Float32Array(W * H);
for (let i = 0; i < W * H; i++) inkMask[i] = matte[i] > 0.15 ? 1 : 0;
const support = boxBlur(inkMask, W, H, 2);
let speckle = 0;
for (let i = 0; i < W * H; i++) {
  if (matte[i] > 0 && support[i] < 0.25) { matte[i] = 0; mark.px[i * 4 + 3] = 0; speckle++; }
}
console.log(`cleanup     dropped ${speckle}px of speckle not attached to the mark`);

let covered = 0, faint = 0;
for (let i = 0; i < matte.length; i++) {
  if (matte[i] > 0) covered++;
  if (matte[i] > 0 && matte[i] < 0.5) faint++;
}
console.log(`matte       ${(100 * covered / matte.length).toFixed(1)}% of the canvas is ink, ${(100 * faint / Math.max(1, covered)).toFixed(0)}% of that is only partly opaque`);

if (process.argv.includes('--debug')) {
  // Where is the ink? One character per 26px block; blank means no ink at all.
  const N = 48, lines = [];
  for (let gy = 0; gy < N; gy++) {
    let row = '';
    for (let gx = 0; gx < N; gx++) {
      const x0 = Math.floor(gx * W / N), x1 = Math.floor((gx + 1) * W / N);
      const y0 = Math.floor(gy * H / N), y1 = Math.floor((gy + 1) * H / N);
      let c = 0, n = 0;
      for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { n++; if (matte[y * W + x] > 0.2) c++; }
      const f = c / n;
      row += f === 0 ? ' ' : f < 0.02 ? '.' : f < 0.1 ? ':' : f < 0.3 ? '+' : f < 0.6 ? '*' : '#';
    }
    lines.push(row);
  }
  console.log('\nink density (blank = none):\n' + lines.join('\n'));
  const strong = (t) => {
    let x0 = W, y0 = H, x1 = -1, y1 = -1, n = 0;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (matte[y * W + x] > t) {
      n++; if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
    }
    return `${n}px  bbox ${x1 - x0 + 1}x${y1 - y0 + 1} at ${x0},${y0}`;
  };
  console.log(`\nalpha > 0.2   ${strong(0.2)}`);
  console.log(`alpha > 0.5   ${strong(0.5)}`);
  console.log(`alpha > 0.9   ${strong(0.9)}`);

  // The background layer must be a smooth gradient. If this map ever traces the
  // C, the field has swallowed the mark and the adaptive icon will show it twice.
  const M = 40, rows = [];
  let mn = Infinity, mx = -Infinity;
  for (let i = 0; i < W * H; i++) {
    const l = luma(field.px[i * 4], field.px[i * 4 + 1], field.px[i * 4 + 2]);
    if (l < mn) mn = l; if (l > mx) mx = l;
  }
  for (let gy = 0; gy < M; gy++) {
    let row = '';
    for (let gx = 0; gx < M; gx++) {
      let sum = 0, n = 0;
      for (let y = Math.floor(gy * H / M); y < Math.floor((gy + 1) * H / M); y++)
        for (let x = Math.floor(gx * W / M); x < Math.floor((gx + 1) * W / M); x++, n++)
          sum += luma(field.px[(y * W + x) * 4], field.px[(y * W + x) * 4 + 1], field.px[(y * W + x) * 4 + 2]);
      const t = (sum / n - mn) / Math.max(1, mx - mn);
      row += ASCII[Math.min(9, Math.floor(t * 9.99))];
    }
    rows.push(row);
  }
  console.log(`\nbackground field luma ${mn.toFixed(0)}..${mx.toFixed(0)} (dark=blank, bright=@):\n` + rows.join('\n'));
}

// 6. write the launcher source: the full-bleed square, no transparency at all
const flattened = flattenTile();
const launcher = resample(flattened, { x: 0, y: 0, w: flattened.w, h: flattened.h }, 1024, 1024);
fs.writeFileSync(path.join(OUT, 'cufmai-c-mark-1024.png'), encodePng(launcher, { opaque: true }));
console.log('wrote       cufmai-c-mark-1024.png');

// 7. Android adaptive layers. Foreground art is kept inside the circle-safe
//    66% of the canvas; the background is the mark-free gradient.
let ax0 = W, ay0 = H, ax1 = -1, ay1 = -1;
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  if (matte[y * W + x] > 0.2) {
    if (x < ax0) ax0 = x; if (x > ax1) ax1 = x;
    if (y < ay0) ay0 = y; if (y > ay1) ay1 = y;
  }
}
const artW = ax1 - ax0 + 1, artH = ay1 - ay0 + 1;
const artCx = (ax0 + ax1) / 2, artCy = (ay0 + ay1) / 2;
console.log(`mark bbox   ${artW}x${artH} at ${ax0},${ay0}  (aspect ${(artW / artH).toFixed(2)})`);
// the mark has to survive the crop, or the launcher icon would clip the swoosh
const margin = Math.round(Math.min(ax0 - crop.x, ay0 - crop.y,
  crop.x + crop.w - 1 - ax1, crop.y + crop.h - 1 - ay1));
if (margin < 0) throw new Error(`mark overruns the launcher square by ${-margin}px — it would be clipped`);
console.log(`clearance   ${margin}px between the mark and the edge of the launcher square`);

// How big the mark should be in the foreground canvas. flutter_launcher_icons
// insets the foreground drawable by 16% on each side (adaptive_icon_foreground_inset,
// default 16), so the art is drawn into 68% of the 108dp layer, and Material's
// safe keyline is a 66dp circle. The mark's bounding box is artW x artH, so its
// circumscribed circle is sqrt(artW^2 + artH^2) / max(artW, artH) times its long
// edge; solving for a 66dp circle gives a long edge of 52.5dp on screen, which is
// 52.5 / (0.68 * 108) = 71.5% of the canvas.
const SAFE = 0.715 * 1024;
const scale = SAFE / Math.max(artW, artH);
const fgSide = Math.ceil(Math.max(artW, artH) * scale) + 24;
const fg = resample(mark, {
  x: artCx - fgSide / 2 / scale, y: artCy - fgSide / 2 / scale,
  w: fgSide / scale, h: fgSide / scale,
}, fgSide, fgSide);
const fgCanvas = { w: 1024, h: 1024, px: Buffer.alloc(1024 * 1024 * 4) };
const off = Math.round((1024 - fgSide) / 2);
for (let y = 0; y < fgSide; y++) for (let x = 0; x < fgSide; x++) {
  const so = (y * fgSide + x) * 4, dst = ((y + off) * 1024 + (x + off)) * 4;
  fgCanvas.px[dst] = fg.px[so]; fgCanvas.px[dst + 1] = fg.px[so + 1];
  fgCanvas.px[dst + 2] = fg.px[so + 2]; fgCanvas.px[dst + 3] = fg.px[so + 3];
}
fs.writeFileSync(path.join(OUT, 'cufmai-c-mark-adaptive-foreground-1024.png'), encodePng(fgCanvas));
const dp = (0.68 * 108 * SAFE) / 1024;
console.log(`wrote       cufmai-c-mark-adaptive-foreground-1024.png  (long edge ${((100 * SAFE) / 1024).toFixed(0)}% of the canvas = ${dp.toFixed(1)}dp on a 108dp layer, inside the 66dp keyline)`);

const bgSource = extendToTile(field);
const bgLayer = resample(bgSource, crop, 1024, 1024);
fs.writeFileSync(path.join(OUT, 'cufmai-c-mark-adaptive-background-1024.png'), encodePng(bgLayer, { opaque: true }));
console.log('wrote       cufmai-c-mark-adaptive-background-1024.png');

// 8. sanity checks, so a bad build fails loudly instead of shipping quietly
const flatSide = Math.round(side);
let corners = 0;
for (const [cx, cy] of [[0, 0], [flatSide - 1, 0], [0, flatSide - 1], [flatSide - 1, flatSide - 1]]) {
  if (flattened.px[(cy * flatSide + cx) * 4 + 3] === 255) corners++;
}
console.log(`\nlauncher    ${launcher.w}x${launcher.h} RGB, ${corners}/4 corners opaque, no alpha channel`);

let bgMax = 0;
for (let i = 0; i < W * H; i++) {
  const l = luma(bgSource.px[i * 4], bgSource.px[i * 4 + 1], bgSource.px[i * 4 + 2]);
  if (l > bgMax) bgMax = l;
}
console.log(`background  peak luma ${bgMax.toFixed(0)} (gold measures ~230, so anything near that is a ghost of the mark)`);
const hex = (x, y) => '#' + [0, 1, 2].map((c) => bgSource.px[(y * W + x) * 4 + c].toString(16).padStart(2, '0')).join('');
console.log(`            top-left ${hex(Math.round(crop.x) + 6, Math.round(crop.y) + 6)}  bottom-right ${hex(Math.round(crop.x + side) - 7, Math.round(crop.y + side) - 7)}`);

// 9. Editable vector. Hand-tracing an AI render never quite lines up, so the
//    mark's own silhouette is contoured straight out of the matte with marching
//    squares, then simplified. The result is a genuine path of the genuine
//    shape: flat where the render is beveled, exact where it matters. Holes fall
//    out of fill-rule="evenodd", and because the contour is taken over the same
//    square as the launcher icon, the file drops straight into the icon.
const VEC = 512;
const sample = new Float32Array((VEC + 1) * (VEC + 1));
for (let gy = 0; gy <= VEC; gy++) for (let gx = 0; gx <= VEC; gx++) {
  const sx = crop.x + gx * crop.w / VEC, sy = crop.y + gy * crop.h / VEC;
  const x0 = Math.min(W - 2, Math.max(0, Math.floor(sx))), y0 = Math.min(H - 2, Math.max(0, Math.floor(sy)));
  const tx = Math.min(1, Math.max(0, sx - x0)), ty = Math.min(1, Math.max(0, sy - y0));
  const at = (x, y) => matte[y * W + x];
  sample[gy * (VEC + 1) + gx] =
    at(x0, y0) * (1 - tx) * (1 - ty) + at(x0 + 1, y0) * tx * (1 - ty) +
    at(x0, y0 + 1) * (1 - tx) * ty + at(x0 + 1, y0 + 1) * tx * ty;
}
// A light blur before thresholding. The taper where the C's bar thins out sits
// right on the 0.5 level, so the raw threshold produces ragged one-pixel
// tentacles, and simplifying those makes the outline cross itself — which under
// evenodd tears holes in the fill.
const smoothed = new Float32Array(sample.length);
for (let y = 0; y <= VEC; y++) for (let x = 0; x <= VEC; x++) {
  let sum = 0, n = 0;
  for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
    const nx = x + dx, ny = y + dy;
    if (nx < 0 || ny < 0 || nx > VEC || ny > VEC) continue;
    sum += sample[ny * (VEC + 1) + nx]; n++;
  }
  smoothed[y * (VEC + 1) + x] = sum / n;
}
const ink = new Uint8Array((VEC + 1) * (VEC + 1));
for (let i = 0; i < ink.length; i++) ink[i] = smoothed[i] > 0.5 ? 1 : 0;

// node id: even = midpoint of a vertical grid edge, odd = horizontal
const edgeNode = (x, y, vertical) => ((y * (VEC + 1) + x) << 1) | (vertical ? 0 : 1);
const at = (x, y) => ink[y * (VEC + 1) + x];
const segs = [], adj = new Map();
const addSeg = (a, b) => {
  const i = segs.length;
  segs.push([a, b]);
  for (const n of [a, b]) { if (!adj.has(n)) adj.set(n, []); adj.get(n).push(i); }
};
for (let cy = 0; cy < VEC; cy++) for (let cx = 0; cx < VEC; cx++) {
  const tl = at(cx, cy), tr = at(cx + 1, cy), br = at(cx + 1, cy + 1), bl = at(cx, cy + 1);
  const top = edgeNode(cx, cy, false), right = edgeNode(cx + 1, cy, true);
  const bottom = edgeNode(cx, cy + 1, false), left = edgeNode(cx, cy, true);
  switch ((tl << 3) | (tr << 2) | (br << 1) | bl) {
    case 1: case 14: addSeg(left, bottom); break;
    case 2: case 13: addSeg(bottom, right); break;
    case 3: case 12: addSeg(left, right); break;
    case 4: case 11: addSeg(right, top); break;
    case 6: case 9: addSeg(bottom, top); break;
    case 7: case 8: addSeg(top, left); break;
    case 5: addSeg(top, left); addSeg(right, bottom); break;
    case 10: addSeg(top, right); addSeg(left, bottom); break;
    default: break;
  }
}

// The segments form closed loops; each node is met by an even number of them, so
// any unvisited neighbour is a valid continuation.
const visited = new Uint8Array(segs.length);
const loops = [];
for (let s = 0; s < segs.length; s++) {
  if (visited[s]) continue;
  const loop = [];
  let cur = s, node = segs[s][0];
  for (;;) {
    visited[cur] = 1;
    const [a, b] = segs[cur];
    const next = a === node ? b : a;
    loop.push(next);
    node = next;
    const step = (adj.get(node) ?? []).find((i) => !visited[i]);
    if (step === undefined) break;
    cur = step;
  }
  if (loop.length >= 3) loops.push(loop);
}
const nodePos = (id) => {
  const idx = id >> 1, x = idx % (VEC + 1), y = (idx / (VEC + 1)) | 0;
  return (id & 1) === 0 ? [x + 0.5, y] : [x, y + 0.5];
};

// Douglas-Peucker, with the split taken at the point furthest from the first so
// a closed loop simplifies as a whole rather than keeping its arbitrary start.
function simplify(points, epsilon) {
  if (points.length < 3) return points;
  let far = 0, best = -1;
  for (let i = 1; i < points.length; i++) {
    const d = (points[i][0] - points[0][0]) ** 2 + (points[i][1] - points[0][1]) ** 2;
    if (d > best) { best = d; far = i; }
  }
  const run = (pts) => {
    if (pts.length < 3) return pts;
    const keep = new Uint8Array(pts.length);
    keep[0] = keep[pts.length - 1] = 1;
    const stack = [[0, pts.length - 1]];
    while (stack.length) {
      const [i0, i1] = stack.pop();
      const [x0, y0] = pts[i0], [x1, y1] = pts[i1];
      const dx = x1 - x0, dy = y1 - y0, len = Math.hypot(dx, dy) || 1;
      let worst = -1, wi = -1;
      for (let i = i0 + 1; i < i1; i++) {
        const d = Math.abs((pts[i][0] - x0) * dy - (pts[i][1] - y0) * dx) / len;
        if (d > worst) { worst = d; wi = i; }
      }
      if (worst > epsilon) { keep[wi] = 1; stack.push([i0, wi], [wi, i1]); }
    }
    return pts.filter((_, i) => keep[i]);
  };
  return run(points.slice(0, far + 1)).concat(run(points.slice(far)).slice(1, -1));
}

const TOLERANCE = 0.5;
const pathData = loops.map((loop) => {
  const pts = simplify(loop.map(nodePos), TOLERANCE);
  const n = (v) => Math.round(v * 10) / 10;
  return `M${pts.map(([x, y]) => `${n(x)} ${n(y)}`).join('L')}Z`;
}).join('');

// The flat colour is the mark's own median, taken from its solid core.
const core = [];
for (let i = 0; i < W * H; i++) if (matte[i] > 0.92) core.push(i);
core.sort((a, b) => luma(mark.px[a * 4], mark.px[a * 4 + 1], mark.px[a * 4 + 2]) - luma(mark.px[b * 4], mark.px[b * 4 + 1], mark.px[b * 4 + 2]));
const mid = mark.px.slice((core[core.length >> 1]) * 4, (core[core.length >> 1]) * 4 + 3);
const gold = '#' + [...mid].map((c) => c.toString(16).padStart(2, '0')).join('').toUpperCase();

if (process.argv.includes('--dump-mask')) {
  // The binary grid the contours were cut from, so the rendered SVG can be
  // compared against it pixel for pixel.
  const dbg = Buffer.alloc(VEC * VEC * 4);
  for (let y = 0; y < VEC; y++) for (let x = 0; x < VEC; x++) {
    const o = (y * VEC + x) * 4, v = ink[y * (VEC + 1) + x] ? 255 : 0;
    dbg[o] = dbg[o + 1] = dbg[o + 2] = v; dbg[o + 3] = 255;
  }
  fs.writeFileSync('.artifacts/tmp-mask-512.png', encodePng({ w: VEC, h: VEC, px: dbg }, { opaque: true }));
  console.log(`wrote       .artifacts/tmp-mask-512.png  (${VEC}x${VEC} silhouette reference)`);
}

const svg = `<?xml version="1.0" encoding="UTF-8"?>
<!--
  CUFMAI / SoleVision mark - the C with a loafer inside it.

  Generated by build-icons.mjs from source/cufmai-c-mark-1254.png: the mark's
  silhouette is contoured out of the alpha matte, so this is the render's exact
  shape without its bevel, drop shadow and gradient. Flat by design - it stays
  legible at sizes where the rendered version mushes together.

  Holes rely on fill-rule="evenodd", so do not split the single path.
  The tile layer is present but hidden; unhide it for the launcher composition.
-->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${VEC} ${VEC}" width="${VEC}" height="${VEC}" role="img" aria-label="CUFMAI">
  <g id="tile" display="none">
    <rect width="${VEC}" height="${VEC}" rx="128" fill="#2C1207"/>
  </g>
  <path id="symbol" fill="${gold}" fill-rule="evenodd" d="${pathData}"/>
</svg>
`;
fs.writeFileSync(path.join(OUT, 'sole-mark-04-c-loafer.svg'), svg);
const points = loops.reduce((n, l) => n + simplify(l.map(nodePos), TOLERANCE).length, 0);
console.log(`\nwrote       sole-mark-04-c-loafer.svg  (${loops.length} contours, ${points} points, ${(svg.length / 1024).toFixed(1)}KB, fill ${gold})`);

// read the files back: the two opaque layers must have no alpha channel at all
for (const f of ['cufmai-c-mark-1024.png', 'cufmai-c-mark-adaptive-background-1024.png']) {
  const buf = fs.readFileSync(path.join(OUT, f));
  if (buf.readUInt32BE(16) !== 1024 || buf.readUInt32BE(20) !== 1024 || buf[24] !== 8 || buf[25] !== 2) {
    throw new Error(`${f} is not an opaque 1024x1024 RGB PNG`);
  }
}
const fgBuf = fs.readFileSync(path.join(OUT, 'cufmai-c-mark-adaptive-foreground-1024.png'));
if (fgBuf.readUInt32BE(16) !== 1024 || fgBuf[25] !== 6) throw new Error('foreground is not a 1024x1024 RGBA PNG');
console.log('\nall checks passed');
