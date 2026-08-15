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
**High**: real-time order updates (Supabase Realtime — available, not integrated), push notifications (FCM — in progress), payment gateway (PayMongo/GCash — attempt #6 implemented, sandbox verification pending), image gallery zoom, search filters.
**Medium**: real AR fitting (currently simulated), seller analytics, reviews/ratings (partially live), wishlist, store-follow feed.
**Low**: multi-language, offline caching, seller-customer chat (**live** — see [[obsidian/MOCs/06 - Notifications & Messaging|🔔 Messaging]]), admin role delegation, CSV/PDF export (CSV is a stub).

---

## 📜 Session logs (chronological)

- [[docs/SESSION_DOCUMENTATION_JULY_3_2026|Session docs July 3]] — checkout-bug investigation narrative
- [[docs/SESSION_LOG_JULY_2_3_2026|Session log July 2–3]] — checkout overhaul
- [[docs/SESSION_LOG_JULY_8_2026|Session log July 8]] — map location, dart-define config
- [[docs/SESSION_LOG_JULY_8_2026_FULL|Session log July 8 (full)]]
- [[docs/SESSION_LOG_JULY_9_2026|Session log July 9]] — test report day
- [[docs/SESSION_LOG_JULY_14_2026|Session log July 14]] — messaging + seller notification center wiring
- [[docs/SESSION_LOG_CUSTOMER_ADDRESSES_RLS_FIX|Session log — customer addresses RLS fix]]
- [[docs/debug/SESSION_LOG_JULY_2_2026|Debug session log July 2]]
- [[docs/debug/SESSION_LOG_JUNE_30_2026|Debug session log June 30]] — login-freeze investigation
- [[docs/debug/SoleVision_Project_Documentation2|Debug project documentation 2]]

## 📊 Test reports & audits

- [[docs/APP_TEST_REPORT_JULY_9_2026|App test report July 9]]
- [[docs/VERIFICATION_AUDIT_JULY_4_2026|Verification audit July 4]] — proof that prior fixes were never deployed
- [[docs/PHASE1_5_SECURITY_AUDIT|Security audit (Phase 1–5)]]
- [[docs/MIGRATION_AUDIT_JULY_8_2026.sql|Migration audit SQL]]
- Test suite: `test/` has real widget tests (terms/privacy screen, terms policy tile, smoke test) — 327 unit/widget tests passing per [[docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE|Checkout & GCash architecture]] §10.8. Run with `flutter test`.

## 📦 Releases

- `releases/version.json` + `releases/changelog.json` — machine-readable release metadata (latest: v1.0.8 — admin suspension + enforcement).
- Recent commits (git): seller tiered verification · CUFMAI terms gating · seller espresso/cream redesign · admin suspension management · paymongo webhook push on confirmed online GCash.

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
