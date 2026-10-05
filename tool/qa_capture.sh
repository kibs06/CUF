#!/usr/bin/env bash
# QA capture — one command that turns a QA-APK run into files you can read.
#
# Why it exists. The two faults being chased (a 3D box that stops presenting while
# its frame loop keeps running, and a crash on the *second* open of the same box)
# have been diagnosed from screenshots of a one-line on-page heartbeat, because the
# phone they happen on — a Huawei P30 Pro — has developer options locked behind a
# password its previous owner set. No `adb logcat` will ever be read from *that*
# phone; its log leaves through the app's own share-sheet export instead (README →
# "QA builds — a measurement, not a release").
#
# So this captures a device where adb *does* work:
#   * an emulator — the QA APK's `x86_64` build. Its translated GLES resolves
#     FEATURE_LEVEL_1, so the render never happens there (F14/F24); what it can
#     check is the Dart path, the refusal reaching the page, and the heartbeat
#     plumbing end to end.
#   * another phone, or any device with USB debugging on.
#   * a runner with a device attached — `qa-logcat.yml` calls this script.
#
# What lands in the output folder:
#   logcat-full.txt        the whole buffer over the window (threadtime)
#   logcat-app.txt         the same, filtered to the tags this feature logs under
#   qa_preview_status.txt  the renderer's own heartbeat file, pulled with `run-as`
#                          (possible because a QA APK is debuggable)
#   heartbeats.txt         that file read every few seconds, so a *stall* shows up
#                          as consecutive identical lines instead of one last line
#   digest.txt             the few numbers worth reading first
#   facts.txt, MANIFEST.txt
#
# Usage:
#   bash tool/qa_capture.sh                       # 60 s, the only device attached
#   bash tool/qa_capture.sh --seconds 90 --serial emulator-5554
#   bash tool/qa_capture.sh --out build/qa/run2 --no-launch
#   bash tool/qa_capture.sh --tryon               # V4.9's session: steps, locks, meminfo
#   bash tool/qa_capture.sh --check                # "is a device here?", for CI
#
# `--tryon` is V4.9's mode. It prints the try-on session's own steps instead of
# the preview box's repro, samples `dumpsys meminfo` beside the heartbeat, and
# adds a digest section that answers the V4 exit criteria from one run:
# `tryon_sessions`, `tryon_locks_within_10s` (first `footLock locked=true` after
# each `session resumed (startSession)`, on logcat's own clock) and the last
# heartbeat's `foot`/`len`/`scale`/`thermal`. The protocol it feeds lives in
# `docs/RoadMap/VIRTUAL_FITTING_V4_9_DEVICE_REVIEW.md`.
#
# Exit codes: 0 captured · 2 no device (or several, and none named) · 3 no adb
#             4 the app is not installed. `--check` exits 0/2/3 and captures nothing:
#             `qa-logcat.yml` asks this instead of keeping its own copy of the rule.
set -euo pipefail

PACKAGE="com.solevision.app"
ACTIVITY="$PACKAGE/.MainActivity"
STATUS_FILE="files/qa_preview_status.txt"
WINDOW_SECONDS=60
SNAPSHOT_EVERY=5
SERIAL=""
OUT=""
LAUNCH=1
CHECK=0
TRYON=0

# Tags this feature logs under. `NavDiag` carries the try-on lines relayed into the
# app's own diag file, `Filament`/`gltfio`/`FEngine`/`libfilament` are Filament's own
# voice (which no Dart-side logging can reproduce), and the rest is the crash.
TAG_FILTER='ArTryOnView|ArTryOnPlugin|ArTryOnSpike|NavDiag|Filament|gltfio|FEngine|libfilament|AndroidRuntime|DEBUG|SIGSEGV|Fatal signal|solevision|flutter'

usage() {
  cat <<'EOF'
QA capture — pull a device run's log and the renderer's heartbeat into one folder.

  bash tool/qa_capture.sh [--seconds N] [--serial SERIAL] [--out DIR] [--no-launch]

  --seconds N   how long the log window stays open (default 60)
  --serial S    which adb device (default: the only one attached)
  --out DIR     where to write (default: build/qa/capture-<UTC timestamp>)
  --no-launch   do not force-stop/start the app; capture what is already running
  --tryon       V4.9's try-on session: its steps, lock-rate metrics and meminfo
  --check       report whether a device is attached (exit 0), and capture nothing
  -h, --help    this text
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds) WINDOW_SECONDS="${2:?--seconds needs a number}"; shift 2 ;;
    --serial)  SERIAL="${2:?--serial needs a value}"; shift 2 ;;
    --out)     OUT="${2:?--out needs a path}"; shift 2 ;;
    --no-launch) LAUNCH=0; shift ;;
    --tryon)   TRYON=1; shift ;;
    --check)   CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$WINDOW_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "--seconds needs a whole number of seconds, got '$WINDOW_SECONDS'" >&2
  exit 2
fi

# ── adb, from PATH or from an SDK install ───────────────────────────────────────────────
# Git Bash on Windows usually has adb on PATH; a fresh machine often does not, so check
# the standard install locations before giving up.
ADB="${ADB:-}"
if [[ -z "$ADB" ]] && command -v adb >/dev/null 2>&1; then
  ADB=adb
fi
if [[ -z "$ADB" ]]; then
  for candidate in \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${LOCALAPPDATA:-}/Android/Sdk/platform-tools/adb.exe" \
    "$HOME/AppData/Local/Android/Sdk/platform-tools/adb.exe"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then ADB="$candidate"; break; fi
  done
fi
if [[ -z "$ADB" ]]; then
  echo "❌ adb not found. Install Android platform-tools, or set ADB=/path/to/adb." >&2
  exit 3
fi
ADB_RUN=("$ADB")

devices() { "${ADB_RUN[@]}" devices | awk 'NR > 1 && $2 == "device" { print $1 }'; }

# `--check` stops here on purpose: it answers one question for CI and never touches the
# app, the log buffer or the filesystem.
if [[ "$CHECK" == 1 ]]; then
  CHECKED=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && CHECKED+=("$line")
  done < <(devices)
  if [[ ${#CHECKED[@]} -eq 0 ]]; then
    echo "no adb device attached" >&2
    exit 2
  fi
  printf 'adb device(s) attached: %s\n' "${CHECKED[*]}"
  exit 0
fi

# ── Which device ────────────────────────────────────────────────────────────────────────
if [[ -z "$SERIAL" ]]; then
  ATTACHED=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && ATTACHED+=("$line")
  done < <(devices)
  if [[ ${#ATTACHED[@]} -eq 0 ]]; then
    echo "❌ No adb device attached (adb devices lists none)." >&2
    echo "   The P30 Pro cannot be one of them — its developer options are locked," >&2
    echo "   so its log leaves through the in-app export instead (README → QA builds)." >&2
    exit 2
  fi
  if [[ ${#ATTACHED[@]} -gt 1 ]]; then
    echo "❌ ${#ATTACHED[@]} devices attached — name one with --serial:" >&2
    printf '   %s\n' "${ATTACHED[@]}" >&2
    exit 2
  fi
  SERIAL="${ATTACHED[0]}"
fi
ADB_RUN=("$ADB" -s "$SERIAL")

if ! "${ADB_RUN[@]}" get-state >/dev/null 2>&1; then
  echo "❌ '$SERIAL' is not a usable device (adb get-state failed)." >&2
  exit 2
fi
case "$SERIAL" in
  emulator-*)
    echo "ℹ️  $SERIAL is an emulator: its translated GLES resolves FEATURE_LEVEL_1, so expect the"
    echo "    refusal/broken-render path (F14/F24). The Dart path, the refusal wording, and the"
    echo "    heartbeat plumbing are what a run here can check — not a picture."
    ;;
esac

# ── The app has to be the QA one ────────────────────────────────────────────────────────
# A release build answers to none of this: the QA switches are compile-time and the two
# that matter are locked to a debuggable APK, and `run-as` needs debuggable too.
if ! "${ADB_RUN[@]}" shell pm list packages "$PACKAGE" 2>/dev/null | tr -d '\r' | grep -q "^package:$PACKAGE$"; then
  echo "❌ $PACKAGE is not installed on $SERIAL." >&2
  echo "   Install the QA APK from the qa-apk.yml artifact first (a release APK cannot" >&2
  echo "   answer any of the QA switches and has no run-as heartbeat file)." >&2
  exit 4
fi

OUT="${OUT:-build/qa/capture-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"
echo "→ capturing $PACKAGE on $SERIAL for ${WINDOW_SECONDS}s into $OUT"

# ── Facts, so the log is self-describing ────────────────────────────────────────────────
fact() { "${ADB_RUN[@]}" shell getprop "$1" 2>/dev/null | tr -d '\r' || true; }
{
  echo "captured_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "serial=$SERIAL"
  echo "manufacturer=$(fact ro.product.manufacturer)"
  echo "model=$(fact ro.product.model)"
  echo "device=$(fact ro.product.device)"
  echo "android=$(fact ro.build.version.release) (sdk $(fact ro.build.version.sdk))"
  echo "abi=$(fact ro.product.cpu.abi)"
  echo "hardware=$(fact ro.hardware)"
  echo "opengles_version=$(fact ro.opengles.version)"
  echo "fingerprint=$(fact ro.build.fingerprint)"
  echo "--- installed package ---"
  "${ADB_RUN[@]}" shell dumpsys package "$PACKAGE" 2>/dev/null \
    | tr -d '\r' \
    | grep -E 'versionName=|versionCode=|lastUpdateTime=|flags=' || true
} > "$OUT/facts.txt"

# ── The window ──────────────────────────────────────────────────────────────────────────
if [[ "$LAUNCH" == 1 ]]; then
  "${ADB_RUN[@]}" shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
fi
"${ADB_RUN[@]}" logcat -c || true
if [[ "$LAUNCH" == 1 ]]; then
  echo
  if [[ "$TRYON" == 1 ]]; then
    echo "  The app is starting. Do this while the capture runs — one lock session, in steps:"
    echo "    1. a product with a size chart → 'Try On in AR'"
    echo "    2. point the camera at the floor, put the foot in frame, hold still until the shoe locks"
    echo "    3. move the foot a little — the shoe should stay attached, not slide or resize"
    echo "    4. wait for the manual offer or 30 s, then press back (one session ends)"
    echo "    Repeat for each product in the run; the digest reads the log, not the screen."
  else
    echo "  The app is starting. Do this while the capture runs — it is the fault report, in steps:"
    echo "    1. JBC Crown Leather Sandals → tap the 3D icon in the corner of the photo"
    echo "    2. drag the shoe — the freeze lands about a second in"
    echo "    3. back out of the viewer, then open it again — this is where the app dies"
  fi
  echo
  "${ADB_RUN[@]}" shell am start -n "$ACTIVITY" >/dev/null 2>&1 || \
    echo "  ⚠️  could not start $ACTIVITY — start the app by hand."
fi

: > "$OUT/heartbeats.txt"
if [[ "$TRYON" == 1 ]]; then : > "$OUT/meminfo.txt"; fi
elapsed=0
previous=""
identical=0
while [[ "$elapsed" -lt "$WINDOW_SECONDS" ]]; do
  sleep "$SNAPSHOT_EVERY"
  elapsed=$((elapsed + SNAPSHOT_EVERY))
  if [[ "$TRYON" == 1 ]]; then
    # V4.9: the ≤ 250 MB session budget is a *sustained* number, so it is
    # sampled on the same clock as the heartbeat. Parses both the modern
    # ('TOTAL PSS:') and the older ('TOTAL') App Summary lines.
    pss=$("${ADB_RUN[@]}" shell dumpsys meminfo "$PACKAGE" 2>/dev/null \
      | tr -d '\r' \
      | awk '/TOTAL PSS:/ {print $3; exit} /^ *TOTAL / {print $2; exit}' || true)
    echo "--- t=+${elapsed}s total_pss_kb=${pss:-?}" >> "$OUT/meminfo.txt"
  fi
  # `exec-out` rather than `shell`: it does not translate newlines on the way back.
  beat=$("${ADB_RUN[@]}" exec-out run-as "$PACKAGE" cat "$STATUS_FILE" 2>/dev/null \
    | tr -d '\r' | grep -a 'loop=' | tail -1 || true)
  {
    echo "--- t=+${elapsed}s"
    if [[ -n "$beat" ]]; then echo "$beat"; else echo "<no heartbeat yet>"; fi
  } >> "$OUT/heartbeats.txt"
  if [[ -n "$beat" ]]; then
    printf '  t=+%3ss  %s\n' "$elapsed" "$beat"
    # Consecutive identical lines are the freeze, expressed as a fact: the loop keeps
    # reporting while nothing it reports is changing.
    if [[ "$beat" == "$previous" ]]; then identical=$((identical + 1)); fi
    previous="$beat"
  else
    printf '  t=+%3ss  (no heartbeat — is SHOE_PREVIEW_DIAGNOSTICS on, and a box open?)\n' "$elapsed"
  fi
done

# ── The log, and the heartbeat that survived ────────────────────────────────────────────
if ! "${ADB_RUN[@]}" logcat -d -v threadtime > "$OUT/logcat-full.txt" 2>/dev/null; then
  echo "(logcat dump failed — was the device still attached?)" > "$OUT/logcat-full.txt"
fi
if ! grep -aE "$TAG_FILTER" "$OUT/logcat-full.txt" > "$OUT/logcat-app.txt" 2>/dev/null; then
  echo "(nothing matched the tag filter — the app may not have logged anything)" > "$OUT/logcat-app.txt"
fi
# `grep` for the line rather than trusting `cat`: `exec-out` merges the device's stderr
# into stdout, so a missing file would otherwise be captured as the file's *content*
# ("cat: files/qa_preview_status.txt: No such file or directory") and read as a fact.
if ! "${ADB_RUN[@]}" exec-out run-as "$PACKAGE" cat "$STATUS_FILE" 2>/dev/null \
  | tr -d '\r' | grep -a 'loop=' > "$OUT/qa_preview_status.txt"; then
  echo "<no heartbeat on the device: no box has been opened with diagnostics on yet>" \
    > "$OUT/qa_preview_status.txt"
fi

# ── The digest: the few numbers worth reading before the megabytes ──────────────────────
max_of() { # max_of <pattern> <files…> — highest value of a `key=N` across the capture
  local pattern="$1"; shift
  grep -aoE "$pattern=[0-9]+" "$@" 2>/dev/null | cut -d= -f2 | sort -n | tail -1 || true
}
count_of() { grep -acE "$1" "${@:2}" 2>/dev/null | awk '{ n += $1 } END { print n + 0 }'; }
last_of() { # last_of <pattern> <file> — the last `key=value` of that shape, value only
  grep -aoE "$1" "$2" 2>/dev/null | tail -1 | cut -d= -f2 || true
}

LAST_BEAT="$(grep -a 'loop=' "$OUT/heartbeats.txt" 2>/dev/null | tail -1 || true)"
{
  echo "device=$SERIAL"
  echo "window_seconds=$WINDOW_SECONDS"
  echo "heartbeat_snapshots=$(grep -ac -- '--- t=+' "$OUT/heartbeats.txt" || true)"
  echo "heartbeat_snapshots_identical_to_previous=$identical"
  echo "last_heartbeat=$LAST_BEAT"
  # A stopped loop and a frozen picture are different faults, and this is the line that tells
  # them apart: `loop=STOPPED` means the frame callback died, while a live `loop=on` next to a
  # `present_max` that never moved is the freeze the chain rebuild was written for.
  echo "loop_stopped=$(count_of 'loop=STOPPED' "$OUT/heartbeats.txt" "$OUT/logcat-app.txt")"
  echo "iter_max=$(max_of 'iter' "$OUT/heartbeats.txt" "$OUT/qa_preview_status.txt")"
  echo "present_max=$(max_of 'present' "$OUT/heartbeats.txt" "$OUT/qa_preview_status.txt")"
  echo "beginFail_max=$(max_of 'beginFail' "$OUT/heartbeats.txt" "$OUT/qa_preview_status.txt")"
  echo "rebuild_max=$(max_of 'rebuild' "$OUT/heartbeats.txt" "$OUT/qa_preview_status.txt")"
  echo "touch_downs_max=$(max_of 'touch' "$OUT/heartbeats.txt" "$OUT/qa_preview_status.txt")"
  echo "chain_last=$(last_of 'chain=[A-Za-z]+' "$OUT/heartbeats.txt")"
  echo "asset_last=$(last_of 'asset=[A-Za-z]+' "$OUT/heartbeats.txt")"
  echo "yaw_last=$(last_of 'yaw=[0-9]+' "$OUT/heartbeats.txt")"
  echo "logcat_lines=$(wc -l < "$OUT/logcat-full.txt" | tr -d ' ')"
  echo "app_lines=$(wc -l < "$OUT/logcat-app.txt" | tr -d ' ')"
  echo "relay_lines=$(count_of '\[preview\]' "$OUT/logcat-app.txt")"
  echo "refusals=$(count_of 'renderer_feature_level_unsupported' "$OUT/logcat-app.txt")"
  echo "material_load_failures=$(count_of 'No material with the specified requirements' "$OUT/logcat-app.txt")"
  echo "frame_loop_stopped=$(count_of 'renderFrame threw|preview_frame_failed' "$OUT/logcat-app.txt")"
  echo "crash_signatures=$(count_of 'SIGSEGV|Fatal signal|tombstone' "$OUT/logcat-full.txt")"
  if [[ "$TRYON" == 1 ]]; then
    # ── V4.9: the session's own numbers ─────────────────────────────────────────────────────
    # A "session" is one `startAr`, marked through the in-app relay
    # (`session resumed (startSession)`); a lock is the first
    # `footLock locked=true` after it, on logcat's own threadtime clock. Both
    # markers are also what the nav_diag export carries on a phone with no adb,
    # so the same rule can be re-applied to an exported log by hand.
    awk '
      function secs(t,   p) { split(t, p, ":"); return p[1]*3600 + p[2]*60 + p[3] }
      /session resumed \(startSession\)/ { starts++; startAt = secs($2); waiting = 1; next }
      /ArTryOnView: footLock locked=true/ {
        if (waiting) {
          waiting = 0
          d = secs($2) - startAt
          if (d >= 0) { printf "session %d: first lock %.1fs\n", starts, d; locks++ }
        }
      }
      END { printf "sessions=%d locks=%d\n", starts + 0, locks + 0 }
    ' "$OUT/logcat-app.txt" > "$OUT/tryon_lock_times.txt"
    echo "tryon_sessions=$(grep -c 'session resumed (startSession)' "$OUT/logcat-app.txt" || true)"
    echo "tryon_lock_edges=$(count_of 'ArTryOnView: footLock locked=' "$OUT/logcat-app.txt")"
    echo "tryon_locks_within_10s=$(awk -F': first lock ' 'NF == 2 { split($2, a, "s"); if (a[1] + 0 <= 10) n++ } END { print n + 0 }' "$OUT/tryon_lock_times.txt")"
    echo "tryon_first_locks=$(grep -c 'first lock' "$OUT/tryon_lock_times.txt" || true)"
    echo "foot_last=$(last_of 'foot=[a-z]+' "$OUT/heartbeats.txt")"
    echo "len_last=$(last_of 'len=[0-9]+mm' "$OUT/heartbeats.txt")"
    echo "scale_last=$(last_of 'scale=[0-9.]+' "$OUT/heartbeats.txt")"
    echo "thermal_last=$(last_of 'thermal=[a-zA-Z0-9()]+' "$OUT/heartbeats.txt")"
    echo "mask_last=$(grep -ao 'mask=[a-z]*' "$OUT/heartbeats.txt" | tail -1 | cut -d= -f2 || true)"
    echo "meminfo_samples=$(grep -c -- '--- t=+' "$OUT/meminfo.txt" || true)"
    echo "meminfo_max_pss_kb=$(grep -aoE 'total_pss_kb=[0-9]+' "$OUT/meminfo.txt" | cut -d= -f2 | sort -n | tail -1 || true)"
    echo "meminfo_last_pss_kb=$(grep -aoE 'total_pss_kb=[0-9]+' "$OUT/meminfo.txt" | cut -d= -f2 | tail -1 || true)"
  fi
} > "$OUT/digest.txt"

cat > "$OUT/MANIFEST.txt" <<EOF
QA capture — $SERIAL — $(date -u +%Y-%m-%dT%H:%M:%SZ)

What this run was for: two faults on a real phone, neither of which the phone can
report itself (its developer options are locked, so it has no adb).

  1. the box freezes about a second after it appears — the frame loop keeps running
     (heartbeats keep arriving) while nothing presents (present= stays put)
  2. the app dies when the same box is opened a *second* time — leave the viewer,
     open it again

Files
  facts.txt              the device, and the installed package's version
  logcat-full.txt        the whole buffer over the window
  logcat-app.txt         filtered to this feature's tags
  qa_preview_status.txt  the renderer's heartbeat file (run-as; a QA APK is debuggable)
  heartbeats.txt         that file sampled every ${SNAPSHOT_EVERY}s — a stall is visible as repeats
  digest.txt             the numbers worth reading first

Read digest.txt first. In heartbeats.txt, "present=" climbing means frames are being
presented; repeats of an identical line with a live "loop=on" are the freeze.
EOF

if [[ "$TRYON" == 1 ]]; then
  cat >> "$OUT/MANIFEST.txt" <<EOF

Try-on session (--tryon)
  tryon_lock_times.txt   one line per session: how long until its first lock
  meminfo.txt            TOTAL PSS every ${SNAPSHOT_EVERY}s (the ≤ 250 MB budget)

The V4.9 thresholds these feed are in docs/RoadMap/VIRTUAL_FITTING_V4_9_DEVICE_REVIEW.md
(≥ 85% of sessions lock within 10 s; ≤ 250 MB across the twenty-cycle run).
EOF
fi

echo
echo "=== digest ==="
cat "$OUT/digest.txt"
echo
echo "✅ wrote $(ls -1 "$OUT" | wc -l | tr -d ' ') files to $OUT"
echo "   read $OUT/digest.txt first, then heartbeats.txt"
