#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# SoleVision — AR timing capture
# Measures screen-open → first-successful-point on a real device by capturing
# the [AR_TIMING] milestone lines emitted by foot_manual_measure_screen.dart.
#
# Usage:
#   1. Plug in your real phone (USB debugging on), ARCore installed.
#   2. Run:   bash capture_ar_timing.sh
#   3. When it says "GO", open the app → Foot Sizing → "Got it, start scanning".
#   4. Move the phone slightly until the floor tracks, then tap to place
#      heel/toe/width points (or accept a smart-assist suggestion).
#   5. It captures for 90s and saves the result to ar_timing_capture.txt
#      (press Ctrl+C early if you finish sooner).
# ─────────────────────────────────────────────────────────────────────────────
set -e
cd "$(dirname "$0")"

DEVICES=$(adb devices | awk 'NR>1 && $2=="device" {print $1}')
if [ -z "$DEVICES" ]; then
  echo "❌ No device connected. Plug in your phone and enable USB debugging."
  exit 1
fi
echo "✅ Connected: $DEVICES"

echo "Clearing logcat buffer..."
adb logcat -c

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  GO! Run the flow now:"
echo "    app → Profile → 'Get Your Foot Size' → 'Got it, start scanning'"
echo "    → place heel & toe points (or accept a suggestion)"
echo "  Capturing for 90 seconds (Ctrl+C to stop early)…"
echo "═══════════════════════════════════════════════════════════════"

adb logcat -v threadtime \
  | grep -E "AR_TIMING|ArFootSizing|ARCore|solevision" \
  | tee ar_timing_capture.txt &

CAPTURE_PID=$!
sleep 90
kill $CAPTURE_PID 2>/dev/null || true

echo ""
echo "✅ Done. Capture saved to ar_timing_capture.txt"
echo "   The key lines are the '[AR_TIMING]' milestones — paste them back here"
echo "   and I'll compute the screen-open → first-point numbers."
