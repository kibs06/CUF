# 360° Foot Scan QA Protocol (measurement-first pass)

> Own-build portal scan: guided orbit capture → `foot-scans` bucket →
> `foot_scan_jobs` row → `reconstruct-foot` → mesh + measurements.
> This doc is the acceptance ritual — run it on a real mid-range Android
> (reference: Huawei P30 Pro) before calling the pass done.

## 1. Capture gates (no backend needed)

1. Open `/foot-scan`, start camera, walk one slow orbit (~20 s).
2. Expect: frame counter climbs toward ~50, coverage toward 360°.
3. Stop early at half orbit → review shows coverage <300° and refuses
   upload with "go all the way around the foot."
4. Cover the lens mid-sweep → dark frames are skipped, count stalls
   instead of banking bad frames.

## 2. Job lifecycle (worker unconfigured)

Until `RECONSTRUCT_WORKER_URL` is set, the honest path is:

1. Complete a good sweep → upload 100% → status `queued`.
2. `reconstruct-foot` fires → job goes `processing` → `failed` with
   code `worker_not_configured` and the "not switched on yet" sentence.
3. Results page `/foot-scan/:jobId` polls to `failed` and offers Retry.
4. No orphaned rows, no stuck `processing`, no crash.

## 3. Measurement truth (worker configured)

Same foot, three captures — the bar for trusting the numbers:

| Source | Length | Width | EU |
|---|---|---|---|
| Tape on paper (ground truth) | ___ mm | ___ mm | ___ |
| App AR scan (`ar_guided_tap`) | ___ mm | ___ mm | ___ |
| Portal 360 (`portal_360`) | ___ mm | ___ mm | ___ |

Acceptance: portal length within **±3 mm** of tape. A miss is filed as
a named defect with the three rows attached — never averaged away.

## 4. Persistence

1. Save from the results page → new `foot_measurements` row with
   `measurement_source = 'portal_360'`, `algorithm_version = 'portal-v1'`.
2. Row is owner-visible only (RLS), mesh loads via signed URL only
   (bucket stays private — confirm no public URL works).
3. Deleting the job row is the mesh delete path until retention
   automation lands (frames target: purge ~30 days post-processing).
