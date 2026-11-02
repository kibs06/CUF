"""Convert SynFoot V1 to YOLO-pose (foot box + heel/toe) for pretraining.

Input  (gitignored): training/foot-detector/datasets/public/synfoot-v1/
         rgb/*.png (480x640 RGBA), labels/*.json, mask/*.png
Output : training/foot-detector/datasets/synfoot/{images,labels}/{train,val}/
         images are RGB .jpg (alpha dropped), labels are YOLO-pose .txt:
         <class> <xc> <yc> <w> <h> <heel_x> <heel_y> 2 <toe_x> <toe_y> 2

Split is grouped by foot scan id (labels[].foot, e.g. "0009-A") so the
same synthetic foot never lands in both train and val — every 10th foot
(sorted) goes to val (~10%).

Box comes from mask bounds (tight, honest); falls back to keypoint
extrema + 10% pad when the mask is empty.

Usage:
  python training/foot-detector/synfoot_to_yolo.py [--max N] [--val-every 10]
  --max N: convert only the first N samples (smoke test, e.g. 200).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / "datasets" / "public" / "synfoot-v1"
OUT = HERE / "datasets" / "synfoot"

W, H = 480, 640  # SynFoot V1 render size


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="SynFoot V1 -> YOLO-pose")
    p.add_argument("--max", type=int, default=0, help="convert first N only (0 = all)")
    p.add_argument("--val-every", type=int, default=10, help="every Nth foot scan -> val")
    return p.parse_args()


def mask_bbox(mask_path: Path) -> tuple[int, int, int, int] | None:
    """Tight (x0, y0, x1, y1) of mask pixels > 127, or None if empty."""
    from PIL import Image
    import numpy as np

    m = np.array(Image.open(mask_path).convert("L"))
    ys, xs = (m > 127).nonzero()
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def main() -> int:
    from PIL import Image

    args = parse_args()
    rgb_dir, lbl_dir, mask_dir = SRC / "rgb", SRC / "labels", SRC / "mask"
    missing = [d for d in (rgb_dir, lbl_dir, mask_dir) if not d.is_dir()]
    if missing:
        print(f"[synfoot] missing input dirs: {missing}", file=sys.stderr)
        print(f"[synfoot] expected under {SRC}/ (rgb/, labels/, mask/)", file=sys.stderr)
        return 1

    ids = sorted(p.stem for p in lbl_dir.glob("*.json"))
    if args.max:
        ids = ids[: args.max]
    if not ids:
        print("[synfoot] no labels found", file=sys.stderr)
        return 1

    # Group by foot scan so one foot never leaks across the split.
    feet: dict[str, list[str]] = {}
    foot_of: dict[str, str] = {}
    for i in ids:
        try:
            foot = json.loads((lbl_dir / f"{i}.json").read_text()).get("foot", "unk")
        except Exception:
            foot = "unk"
        feet.setdefault(str(foot), []).append(i)
        foot_of[i] = str(foot)
    ordered_feet = sorted(feet)
    val_feet = set(ordered_feet[:: args.val_every]) if args.val_every > 0 else set()

    stats = {"train": 0, "val": 0, "skipped": 0}
    for n, i in enumerate(ids, 1):
        split = "val" if foot_of[i] in val_feet else "train"
        try:
            lbl = json.loads((lbl_dir / f"{i}.json").read_text())
            kp = lbl["keypoints"]
            hx, hy = kp["heel"]
            tx, ty = kp["big toe"]
        except Exception:
            stats["skipped"] += 1
            continue
        # Clamp rogue pixels into frame instead of dropping the sample.
        hx, hy = min(max(hx, 0), W - 1), min(max(hy, 0), H - 1)
        tx, ty = min(max(tx, 0), W - 1), min(max(ty, 0), H - 1)

        bb = mask_bbox(mask_dir / f"{i}.png")
        if bb is None:  # fallback: keypoint extrema + 10% pad
            x0, x1 = sorted((hx, tx))
            y0, y1 = sorted((hy, ty))
            px, py = (x1 - x0) * 0.1 + 2, (y1 - y0) * 0.1 + 2
            bb = (int(x0 - px), int(y0 - py), int(x1 + px), int(y1 + py))
        x0, y0, x1, y1 = bb
        # Union with keypoints: heel (calcaneus contact) can sit a few px
        # outside the mask silhouette — the box must contain both points.
        x0 = min(x0, int(hx) - 2, int(tx) - 2)
        y0 = min(y0, int(hy) - 2, int(ty) - 2)
        x1 = max(x1, int(hx) + 2, int(tx) + 2)
        y1 = max(y1, int(hy) + 2, int(ty) + 2)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, W - 1), min(y1, H - 1)
        bw, bh = x1 - x0, y1 - y0
        if bw < 4 or bh < 4:
            stats["skipped"] += 1
            continue

        img_out = OUT / "images" / split
        lbl_out = OUT / "labels" / split
        img_out.mkdir(parents=True, exist_ok=True)
        lbl_out.mkdir(parents=True, exist_ok=True)

        src_img = rgb_dir / f"{i}.png"
        if not src_img.exists():
            stats["skipped"] += 1
            continue
        Image.open(src_img).convert("RGB").save(img_out / f"{i}.jpg", quality=92)

        xc = (x0 + x1) / 2 / W
        yc = (y0 + y1) / 2 / H
        row = (
            f"0 {xc:.6f} {yc:.6f} {bw / W:.6f} {bh / H:.6f} "
            f"{hx / W:.6f} {hy / H:.6f} 2 {tx / W:.6f} {ty / H:.6f} 2\n"
        )
        (lbl_out / f"{i}.txt").write_text(row)
        stats[split] += 1
        if n % 2000 == 0:
            print(f"[synfoot] {n}/{len(ids)} ...", flush=True)

    print(f"[synfoot] done: train={stats['train']} val={stats['val']} "
          f"skipped={stats['skipped']} (feet={len(ordered_feet)}, val_feet={len(val_feet)})")
    print(f"[synfoot] next: yolo pose train data=training/foot-detector/data-synfoot.yaml "
          f"model=yolo11n-pose.pt epochs=100 imgsz=640 ... (see TRAIN_COLAB.md)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
