# Train on Colab (GPU) — run cells top to bottom.
# Assumes this repo is uploaded (or `git clone` it) with
# training/foot-detector/datasets/foot/ already bootstrapped
# (node training/foot-detector/bootstrap_coco_to_yolo.mjs → 276 train / 146 val).

# 1) Install
# pip install -r training/foot-detector/requirements.txt

# 2) Train (A100/T4, ~30-60 min for 100 epochs at 640)
# yolo pose train \
#   data=training/foot-detector/data.yaml \
#   model=yolo11n-pose.pt \
#   epochs=100 imgsz=640 batch=16 \
#   hsv_h=0.015 hsv_s=0.4 hsv_v=0.4 \
#   degrees=15 translate=0.1 scale=0.3 \
#   mosaic=0.5 mixup=0.1 copy_paste=0.1 \
#   project=training/foot-detector/runs name=foot-v1

# 3) Validate the hard slices (not just mAP)
# yolo pose val data=training/foot-detector/data.yaml model=training/foot-detector/runs/foot-v1/weights/best.pt

# 4) Export for the browser (opset 12 = onnxruntime-web coverage)
# yolo export model=training/foot-detector/runs/foot-v1/weights/best.pt format=onnx opset=12 dynamic=False
# → best.onnx (~6-12 MB for nano). Copy to customer-portal/public/vendor/foot-detector/foot-v1.onnx
#    and record its byte size in customer-portal/scripts/vendor-trackers.mjs (FOOT_ONNX_BYTES).

# 5) Measure on a real mid-range Android: preprocess + inference + decode
#    for WASM and WebGPU providers. Target <150ms end-to-end at 480px input.
#    If slower, drop imgsz to 384 and re-export.

# After step 4 the portal auto-uses the ONNX model (worker tries
# /vendor/foot-detector/foot-v1.onnx first, falls back to Pose Landmarker
# when absent) — no viewer changes needed.
