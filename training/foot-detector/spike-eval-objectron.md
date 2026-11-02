# Spike eval: Objectron shoe model as try-on tracker (2026-10-30)

## What ran
Legacy `mp.solutions.objectron` (`model_name="Shoe"`, == `object_detection_3d_sneakers.tflite`
path, auto-downloaded by mediapipe 0.10.14) on Python 3.12, desktop CPU, static-image mode.

## Populations
- A: 51 bare-foot photos, `datasets/raw/` (2026-10-18-blurry, 2026-10-18-dim-room) = deployment condition.
- B: 276 COCO person photos, `datasets/foot/images/train` = favorable control (people often shod).

## Numbers
| set | detected | rate | ms median | ms max |
|-----|----------|------|-----------|--------|
| A bare feet | 0 / 51 | 0% | 22.9 | 50.1 |
| B COCO people | 235 / 276 | 85% | 42.5 | 66.0 |

All 235 B-detections carry 9-pt 2D projections + rotation + translation + scale;
median box ~109k px2, aspect ~1.1 — sane shoe boxes, not garbage positives.

## Verdict: NO-GO for bare-foot try-on tracking
The model works (85% on shod people clears the 80% bar on the wrong population)
but scores 0% on the deployment condition: customers point the camera at bare
feet, and a shoe detector sees nothing there. Desktop ms is a proxy only; the
Kirin number was never reached because quality failed first.

## Consequence
- Do NOT build `ObjectronShoeDetector` as the primary tracker.
- Recommended: YOLO11n-pose foot-keypoint scaffold (this dir), SynFoot pretrain.
- Objectron retained only as a possible shoe-presence cross-check, undecided.

## Repro
Models: /tmp scratch (see chat). Results JSON: run `eval.py` (scratch) with the
venv at its side. Overlays: per-run `overlays/` next to each `results.json`.
