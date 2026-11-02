"""Zip datasets/synfoot for Drive -> Colab upload (JPGs already compressed, so STORED)."""
from __future__ import annotations
import sys
from pathlib import Path
from zipfile import ZipFile, ZIP_STORED

HERE = Path(__file__).resolve().parent
SRC = HERE / "datasets" / "synfoot"
OUT = HERE / "synfoot-50k.zip"

def main() -> int:
    if not SRC.is_dir():
        print(f"[zip] missing {SRC}", flush=True)
        return 1
    files = [p for p in SRC.rglob("*") if p.is_file()]
    print(f"[zip] packing {len(files)} files -> {OUT}", flush=True)
    OUT.unlink(missing_ok=True)
    with ZipFile(OUT, "w", ZIP_STORED) as z:
        for n, p in enumerate(sorted(files), 1):
            z.write(p, p.relative_to(HERE))
            if n % 5000 == 0:
                print(f"[zip] {n}/{len(files)} ...", flush=True)
    size_gb = OUT.stat().st_size / 1e9
    print(f"[zip] done: {OUT.name} {size_gb:.2f} GB, {len(files)} files", flush=True)
    print("[zip] next: upload to Drive, unzip on Colab, run colab_synfoot_train.ipynb", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
