# Foot detector training scaffold (portal robust tracking)

Goal: a custom **YOLO11n-pose** model — one box (`foot`) + two keypoints
(`heel`, `toe`) — exported to ONNX and run in the portal with
`onnxruntime-web`. It replaces PoseLandmarker's 3 sparse points with a
detector that has actually seen blurry, dim feet.

## Where photos live

- Raw uploads: `training/foot-detector/datasets/raw/` — **gitignored**.
  Dump phone photos here, grouped by session:
  `datasets/raw/2026-10-20-dim-bedroom/`, `.../2026-10-21-shop-floor/`, …
- Labels: YOLO-pose `.txt` next to a mirrored split (see `data.yaml`).
- Nothing under `datasets/` except `data.yaml` is committed. When the set
  outgrows a folder, move it to shared storage and keep this layout —
  scripts below assume it.

## How many

- **200** real photos: minimum viable first training run.
- **500–2,000**: where blur/dim robustness actually comes from.
- Split **by session**, never random frames (near-duplicates leak).
  Suggested: 80% train / 10% val / 10% held-out test, session-grouped.
- Cover the deployment conditions on purpose: dim rooms, motion blur,
  striped/textured floors, socks, sandals, close-ups AND lower-leg shots,
  both feet, occlusion (trouser hem, other foot).

## Label schema (one row per foot, normalized 0–1)

```
<class> <x_center> <y_center> <w> <h> <heel_x> <heel_y> <heel_v> <toe_x> <toe_y> <toe_v>
```

- `class 0` = `foot`. Side (left/right) is a later extension — do not add it now.
- Visibility `v`: `2` = visible, `1` = occluded but estimated, `0` = not labeled.
- Heel = back of calcaneus contact point; toe = tip of longest toe.
- Label with Roboflow (easiest share/annotate loop), CVAT, or labelme, then
  export/convert to this txt layout under `datasets/foot/{images,labels}/{train,val}/`.

## Train (GPU machine or Colab)

```bash
pip install -r training/foot-detector/requirements.txt
yolo pose train \
  data=training/foot-detector/data.yaml \
  model=yolo11n-pose.pt \
  epochs=100 imgsz=640 batch=16 \
  hsv_h=0.015 hsv_s=0.4 hsv_v=0.4 \
  degrees=15 translate=0.1 scale=0.3 \
  mosaic=0.5 mixup=0.1 copy_paste=0.1
```

Blur/low-light robustness comes from **real** bad photos first; the
augmentation flags above only stretch them. Add Albumentations
`MotionBlur` + JPEG compression rounds if the dim slice still fails.

## Evaluate the hard slices, not the average

```bash
yolo pose val data=training/foot-detector/data.yaml model=runs/pose/train/weights/best.pt
```

Then score heel/toe error separately on tagged subsets (dim, blur,
close-up, occluded). An aggregate mAP that hides the dim slice is a lie —
fix the slice with more photos from that condition.

## Export for the browser

```bash
yolo export model=runs/pose/train/weights/best.pt format=onnx opset=12 dynamic=False
```

- Keep opset 12 for `onnxruntime-web` operator coverage.
- Measure the `.onnx` size (nano target: ~6–12 MB) and full pipeline
  latency on a real mid-range Android (preprocess + inference + decode),
  WASM and WebGPU providers.
- Vendoring follows the existing tracker pattern
  (`customer-portal/scripts/vendor-trackers.mjs`): same-origin,
  immutable-cached, byte-size-pinned. The worker protocol
  (`init` → `ready`, `frame` → `pose`) stays unchanged — only the
  inference backend swaps.

## License notes (read before shipping)

- YOLO11: AGPL-3.0 / Enterprise — fine for internal R&D, review before
  commercial deployment.
- CMU foot annotations: CC BY 4.0 (images inherit COCO terms).
  COCO-WholeBody: research/non-commercial — pretrain only, confirm terms.
- Your own photos: you own them; get consent from anyone identifiable.
