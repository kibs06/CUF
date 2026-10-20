# Foot try-on research (Phase 3)

Dated 2026-10-20. Sources kept with links; limits stated, not smoothed over.

## 1. Foot vs shank (knee-to-ankle) length

**Working number: foot ~= 0.626 x shank.** From Hora et al., 49 healthy
non-obese Czech adults aged 19-38 (25 men, 24 women); shank measured
knee-joint center to ankle-joint center, foot on an osteometric board.
Quotients of group means: men 271/433 mm = 0.626, women 248/396 mm = 0.626.

- Source: https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0172112
- Sample ranges (not population norms): men foot 229-293 mm / shank
  373-488 mm; women foot 227-285 mm / shank 345-441 mm.
- **Single-source limit:** only one study found reports both lengths
  together, so the 0.55-0.65 band is NOT two-source confirmed. The ratio is
  a quotient of means, not a distribution — no per-person variance known.

## 2. Foot vs height (second source, height only)

Foot ~= 14-15% of stature. Hora et al.: 14.9% men, 14.8% women.
Nepalese medical students 18-24 (Pandey et al. 2024): 14.4% both sexes.

- Source: https://pmc.ncbi.nlm.nih.gov/articles/PMC11455646/
- Supports the height ratio only — says nothing about foot-vs-shank.
- No verified general-population ankle-to-heel longitudinal ratio found
  (published "heel" measures are usually breadth, not the heel-ankle segment).

## 3. BlazePose / Pose Landmarker foot points

- Indices: heel 29 (left) / 30 (right), foot-index 31 (left) / 32 (right).
  "Foot index" is one forward point, not toes.
- Source: https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker
- **No official per-foot accuracy number exists** (legacy eval covers 17
  COCO keypoints only). Foot points are documented as approximate.
- Visibility (0-1) = likelihood the point is visible, NOT a coordinate
  accuracy metric. Task thresholds default 0.5; the drawing utility also
  uses 0.5 — which is why the leg prior gates knees at 0.5 while the
  close-up foot gate stays at 0.3.
- Known failure: heel/toe misplaced on the far leg (treadmill-running
  frames) — https://github.com/google-ai-edge/mediapipe/issues/3496.
  Coordinates can also exceed frame bounds despite high visibility
  (https://github.com/google-ai-edge/mediapipe/issues/4462), so bounds
  checks stay independent of visibility.

## 4. What this means for the tracker

The 0.626 prior is a population mean applied per-person: expect residual
error, wider on children and older adults (unstudied here). The shank is
worth trusting over a collapsed axis anyway — it spans hundreds of pixels
where the collapse spans tens — which is exactly what `MAX_DISAGREE_RATIO`
encodes. Re-derive it once knee-visible fixtures exist.
