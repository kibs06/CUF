# 🗺️ Roadmap, Logs & History

> Where the project is going and where it's been: roadmap, changelog, session logs, test reports, and releases. **#moc**

---

## 📌 Overview

This MOC indexes the project's **history and trajectory**: the roadmap, the changelog, chronological session logs, audit/test reports, and the machine-readable `releases/` metadata. It's also the place to keep notes about **doc consolidation** — `docs/` has several near-duplicate master documents worth reconciling.

---

## 🚀 Forward-looking

- [[docs/RoadMap/SOLEVISION_ROADMAP|🧭 SoleVision roadmap]] — the plan
- [[docs/fixes/PROJECT_IMPROVEMENT_PLAN|Project improvement plan]] — tracked fixes + gaps (includes a note that a changelog entry claims "rebranded to CUFMAI" while branding was reverted in `f39b34b` — later re-applied)
- [[docs/AI_PROJECT_SUMMARY|⚡ AI Project Summary — "Current State"]] — what's working / broken / next (compiled July 8; partially stale)
- [[docs/PROJECT_HANDOFF|📄 Project Handoff]] — decisions, known issues, "What's Next" (v1.1.0, July 2; partially stale)

### Known roadmap priorities (from handoff + summary)
**High**: real-time order updates (Supabase Realtime — available, not integrated), payment gateway (PayMongo/GCash — attempt #6 implemented, sandbox verification pending), image gallery zoom.
**Medium**: real AR fitting (currently simulated, wall calibration added), seller analytics, reviews/ratings (partially live), wishlist, store-follow feed.
**Low**: multi-language, offline caching, seller-customer chat (**live** — see [[obsidian/MOCs/06 - Notifications & Messaging|🔔 Messaging]]), admin role delegation, CSV/PDF export (CSV is a stub).

**Recently completed**: push notifications (FCM — live), search filters (live), account management & settings redesign, home hero redesign, banner system, sticky search, buy-again flow, per-color photo galleries, foot sizing v2 (wall calibration).

---

## 📜 Session logs (chronological)

- [[docs/SESSION_DOCUMENTATION_JULY_3_2026|Session docs July 3]] — checkout-bug investigation narrative
- [[docs/SESSION_LOG_JULY_2_3_2026|Session log July 2–3]] — checkout overhaul
- [[docs/SESSION_LOG_JULY_8_2026|Session log July 8]] — map location, dart-define config
- [[docs/SESSION_LOG_JULY_8_2026_FULL|Session log July 8 (full)]]
- [[docs/SESSION_LOG_JULY_9_2026|Session log July 9]] — test report day
- [[docs/SESSION_LOG_JULY_14_2026|Session log July 14]] — messaging + seller notification center wiring
- [[docs/SESSION_LOG_SEPTEMBER_28_2026|Session log September 28]]
- [[docs/SESSION_LOG_SEPTEMBER_30_2026|Session log September 30]]
- [[docs/SESSION_LOG_CUSTOMER_ADDRESSES_RLS_FIX|Session log — customer addresses RLS fix]]
- [[docs/debug/SESSION_LOG_JULY_2_2026|Debug session log July 2]]
- [[docs/debug/SESSION_LOG_JUNE_30_2026|Debug session log June 30]] — login-freeze investigation
- [[docs/debug/SoleVision_Project_Documentation2|Debug project documentation 2]]

## 📊 Test reports & audits

- [[docs/APP_TEST_REPORT_JULY_9_2026|App test report July 9]]
- [[docs/VERIFICATION_AUDIT_JULY_4_2026|Verification audit July 4]] — proof that prior fixes were never deployed
- [[docs/PHASE1_5_SECURITY_AUDIT|Security audit (Phase 1–5)]]
- [[docs/MIGRATION_AUDIT_JULY_8_2026.sql|Migration audit SQL]]
- Test suite: full Flutter suite ~2,770 passing (7 skipped, Oct 2026) plus JVM suites for the try-on math (`DetectionDotsTest`, `FootSnapshotTest`, `FootPoseTrackerTest`, `FootFlowTest`, `DepthMathTest`). Run with `flutter test`.

## 📦 Releases

- `releases/version.json` + `releases/changelog.json` — machine-readable release metadata (latest: v1.0.55, Oct 13). `CHANGELOG.md` at repo root has the per-release narratives; the list below is the map, not the territory.
- **v1.0.55** (Oct 13): AR try-on behind-the-scenes improvements (not yet customer-visible) — see [[docs/3D fitting/AR_TRY_ON_V4_CHANGELOG|AR try-on V4 changelog]].
- **v1.0.54** (Oct 13): lockout answers WHERE — city-level IP geolocation on overlay, e-mail, admin views.
- **v1.0.53** (Oct 12): in-app password reset (e-mail link opens CUFMAI, new password in-app).
- **v1.0.52** (Oct 12): foot sizing — camera scan or tap-to-measure.
- **v1.0.51–v1.0.49** (Oct 9): try-on groundwork — tap-to-place shoe, floor-search guide with lock progress, depth reads the floor under the foot (not behind it), blur/unsettled-floor gates.
- **v1.0.48–v1.0.46** (Oct 5–7): audience rails share one row (Men/Women/Kids → shelf pages); try-on works end to end, upright camera, shoe anchored to foot on floor.
- **v1.0.45–v1.0.34** (Sep 29–Oct 3): the 3D viewer series — product-page 3D, fullscreen viewer, WebView renderer, GLES 3.0 floor message, touch/load diagnostics.
- **v1.0.33–v1.0.31** (Sep 28): one project signing key (in-app update stops failing); sellers attach `.glb` handovers (11 validation checks) or request CUFMAI modeling.
- **v1.0.30–v1.0.25** (Sep 13–22): app icon, sale tags, search-as-a-place, white-and-ink theme, vouchers.
- **v1.0.24–v1.0.16** (Aug 26–Sep 7): GCash auto-cancel fix, 2FA, manual-GCash fraud hardening, lockout overlay + local lockout repair.
- **v1.0.15** (Aug 22): logout fix (pop all routes → AuthGate), seller profile logout button.
- **v1.0.14** (Aug 22): banner system, sticky search bar, seller settings icon disabled.
- **v1.0.13** (Aug 21): full-bleed home hero, store perf fix, account management, profile redesign.
- Earlier: seller tiered verification · CUFMAI terms gating · seller espresso/cream redesign · admin suspension management · paymongo webhook push on confirmed online GCash.
- Also shipped along the way: AR wall calibration (foot sizing v2), buy-again-to-cart, settings redesign, per-color photo galleries, masonry grid, product tags, recently viewed, dev-build update guard (`in_app_update_eligibility`).
- [[docs/RELEASE_SIGNING|Release signing]] — one project key, debug-keystore trap, why `android/key.properties` matters. Read before touching signing or the update flow.
- **Release comms:** `lib/widgets/update_overlay.dart` + `lib/screens/shared/whats_new_screen.dart` announce a release; `lib/utils/in_app_update_eligibility.dart` is the single decision behind them — dev builds are told *why* (debug keystore) instead of being offered a download Android will refuse.

## 📚 Master docs (near-duplicates — consolidation candidate)

| File | Notes |
|------|-------|
| [[docs/SoleVision_Complete_Documentation|SoleVision_Complete_Documentation]] | **Master reference — 22 sections, recommended** |
| [[docs/project_doc|project_doc]] | Earlier master (v1.2.0) |
| [[docs/SoleVision_Project_Documentation|SoleVision_Project_Documentation]] | v1.0 |
| [[docs/SoleVision_Project_Documentation2|SoleVision_Project_Documentation2]] | v1.1 (schema corrections) |
| [[docs/SoleVision_Project_Documentation_Concise|…_Concise]] | Condensed reference |
| [[docs/debug/SoleVision_Project_Documentation2|debug/ copy]] | Duplicate in debug/ |

> 💡 **Suggested cleanup**: consolidate to one canonical master doc; move one-off session logs into `docs/debug/`; align naming to CUFMAI (docs still largely say SoleVision after the rebrand).

## ⚠️ Staleness warnings

1. [[docs/AI_PROJECT_SUMMARY|AI Project Summary]] claims "**No git repository exists**" — **stale**: the repo is now under git (branch `main`, committed releases). Also predates suspension, tiered verification, messaging, ratings.
2. [[docs/PROJECT_HANDOFF|Project Handoff]] (July 2) predates most 2026-08 features — use per-area MOCs for current state.
3. `supabase/schema.sql` is outdated — see [[obsidian/MOCs/05 - Database & Supabase|🗄️ Database MOC]].

## 🔗 Related

- [[obsidian/Home|🏠 Home]]
- [[obsidian/Onboarding|🧑‍💻 Onboarding]]
