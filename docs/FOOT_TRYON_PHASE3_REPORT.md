# Phase 3 report — leg-proportion scale prior (2026-10-20)

## 1. Measurement table

Fixture: `customer-portal/src/lib/__fixtures__/jbc-crown-phone-2026-10-20.json`
(15 frames, 720x1280 portrait). True foot ~= 550px when fully visible.
Extended = raw x 1.44 (heel-back 0.16 + toe 0.28); `len` is the smoothed
tracker value. Ratio = extended-or-smoothed / 550.

| # | t | Framing | raw | extended/smoothed | ratio | Gate |
|---|---|---|---|---|---|---|
| 1 | 9362 | empty | — | — | — | no-foot |
| 2 | 11842 | empty | — | — | — | no-foot |
| 3 | 22308 | off-frame ghost (x<0), scores 0.33/0.35 | 187 | — | — | rejected |
| 4 | 23960 | off-frame ghost, HIGH scores 0.55-0.77 | 272 | — | — | rejected |
| 5 | 12363 | below frame bottom (y>1) | 88 | 126 | 0.23 | accepted |
| 6 | 13295 | close-up, both feet, scores ~0.31-0.41 | 60 | 110 | 0.20 | accepted |
| 7 | 17269 | close-up, best confidence 0.56-0.75 | 119 | 150 | 0.27 | accepted |
| 8 | 18233 | close-up, toe slightly off-frame | 116 | 158 | 0.29 | accepted |
| 9 | 24148 | below frame bottom | 123 | 167 | 0.30 | accepted |
| 10 | 26375 | close-up | 91 | 157 | 0.29 | accepted |
| 11 | 59688 | COLLAPSED axis | 30 | 119 | 0.22 | accepted (smoothed!) |
| 12 | 64289 | WORST collapse | 11 | 119 | 0.22 | accepted (smoothed!) |
| 13 | 19867 | lone 55px in ~40s of nothing | 56 | 80 < 86.4 gate | — | rejected (gate OK) |
| 14 | 58517 | near-vertical shin candidate, scores ~0.33 | 70 | 150 | 0.27 | accepted |
| 15 | 61951 | below frame, largest accepted | 169 | 206 | 0.37 | accepted |

Grouped: off-frame ghosts rejected; below-frame 0.23-0.37; close-up
0.20-0.29; collapsed 11-30px raw (smoothing hides the collapse at 119px);
lone 55px correctly rejected.

**Correction to the brief:** the axis reads **20-37% of true, not ~55%**.
No fixture supports 55%. Do not calibrate against 55%.

## 2. What shipped

- `estimateFootLengthFromLeg` / `blendFootLength` / `extractKnees` /
  `poseFromLandmarks` in `customer-portal/src/lib/footTryOn.js`
  (FOOT_SHANK_RATIO 0.626, knee gate 0.5, disagree edge 1.8 — provisional).
- Knees in every pose message (worker + main-thread); viewer blends the
  worn-side prior with the axis length, 0.4 lerp downstream unchanged.
- Debug overlay `src=axis|blend|leg-override` + `DISAGREE`; same fields in
  the frames export so knee-visible sessions become validatable fixtures.
- Extension constants untouched (0.28 / 0.16).

## 3. Known limits

- **Perspective foreshortening:** a foot pointing at the camera reads
  short on BOTH estimators (shank too). Neither models it. Documented,
  not modeled — a top-down close-up will still under-read.
- **No knee, no prior:** close-ups like this fixture's fall back to the
  axis unchanged, by design (no invented correction).
- **Close-up tolerance is looser by necessity:** with no knee in any of
  these 15 frames, the only verifiable close-up claim is "falls back to
  axis" — the +/-25% close-up target from the brief cannot be checked
  until knee-visible fixtures exist. The +/-15% target applies to
  synthetic leg-consistent inputs (covered in unit tests), not to these
  frames.
- **1.8 is provisional:** splits the observed 0.20-0.37 under-read band
  from honest noise. Re-derive from live knee-visible data.
- **No fixture here validates the prior end-to-end:** zero of 15 frames
  contain knee landmarks. First knee-visible `?footdebug=1` export that
  shows `src=blend` on device is the real acceptance event.

## 4. Calibration (owner input pending)

Per-model `default_scale` trim % at 100%, foot fully visible ~1m away —
to be recorded in the seed file once the owner answers. No global trim.
