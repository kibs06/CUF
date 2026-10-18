# ✅ Task Board

> Simple kanban for tracking what's in flight. Use `- [ ]` checkboxes so Obsidian's core **Search → Tasks** picks everything up, or install the community **Kanban** plugin for a visual board. **#project/solevision**

## 📥 Inbox (untriaged)
- [ ] 

## 🚧 In Progress
- [ ] AR try-on projection probe — 30-sec on-device retest, then Step 1 fix (mapping-direction vs session-geometry) #customer
- [ ] Product audience P5 — combined regression + width/brightness/text-scale sweep on a real device #customer #seller

## 🔜 Backlog / Next up
- [ ] ⛔ **REMOVE dev mode before release** — UI-only signup skip (unlock: swipe ↑↑↓↓→→←← on "Create your account"). Files + checklist: [[docs/AI/DEV_MODE_ARCHITECTURE|Dev Mode Architecture]] #auth
- [ ] Sandbox verification for PayMongo online GCash (attempt #6) — see [[docs/AI/PAYMONGO_ONLINE_GCASH_TEST_PLAN|PayMongo test plan]] #checkout
- [ ] Real-time order updates via Supabase Realtime (available, not integrated) #checkout
- [ ] CSV/PDF export for reports (currently stub only) #seller
- [ ] Image gallery zoom on product detail #customer
- [ ] Product audience (Men's / Women's / Kids' / Unisex) — **every phase is built, switched on, and the catalog still has no audiences**. P0 (column/vocabulary), P1 (seller input), P2 (home rails), P3 (US/UK labels from the product's own chart), P4 (the unset count surfaced to sellers as a rotating alert + `Not Set` filter, and per-product visibility for admins) and the Home audience chips + shelf pages have all landed; `AppConstants.productAudienceEnabled` is `true`, and **P5 is done bar the on-device pass** — the combined regression (rails + labels + seller nudge + admin view, one seeded catalog), the width/brightness/text-scale sweep, the docs and a proven rollback are all in, gate clean at 1355. Measured 2026-09-19: **15 of 15 products unset** (Valladolid 9, demo_storeName 5, Janella 1). What is left is **data, not code**: a seller has to answer "Who is it for?" on each product — until then no rail, chip or shelf has anything to show — plus the same QA table on a real device with real fonts. Plan: [[docs/AI/PRODUCT_AUDIENCE_PLAN|Product audience plan]] #customer #seller

## ✅ Done (recent)
- [x] AR try-on V4.13–V4.21 batch (dots, presence ring, detection-driven shoe, hold rule, mirroring, held-carry, still capture, probes) + V4 changelog — see [[docs/3D fitting/AR_TRY_ON_V4_CHANGELOG|V4 changelog]] #customer
- [x] v1.0.55 — AR try-on behind-the-scenes improvements #customer
- [x] v1.0.54 — lockout says WHERE (city-level IP geolocation, all surfaces) #auth #admin
- [x] v1.0.53 — in-app password reset #auth
- [x] v1.0.52 — foot sizing: camera scan or tap-to-measure #customer
- [x] v1.0.51–v1.0.49 — try-on groundwork (tap-to-place, floor-search lock bar, floor-depth accuracy) #customer
- [x] v1.0.46 — virtual try-on end to end, upright camera, floor-anchored shoe #customer
- [x] v1.0.45–v1.0.34 — 3D viewer series (product-page 3D, WebView renderer, GLES floor, diagnostics) #customer
- [x] v1.0.33 — single project signing key, in-app update stops failing #customer
- [x] v1.0.32–v1.0.31 — seller `.glb` attach with 11 checks + CUFMAI modeling request #seller
- [x] Dev-build update guard (`in_app_update_eligibility` — dev builds told why, not offered the impossible) #customer
- [x] Failed-login location fallback + lockout-write repair (UPDATE-by-id/INSERT) #auth #admin
- [x] Product audience P0–P4 built and on (`productAudienceEnabled=true`); left = seller data + on-device QA #customer #seller
- [x] v1.0.30–v1.0.25 — app icon, sale tags, search page, white-and-ink theme, vouchers #customer
- [x] v1.0.24–v1.0.16 — GCash auto-cancel fix, 2FA, fraud hardening, lockout overlay #auth #checkout
- [x] v1.0.15 — Fixed logout bug (pop all routes to AuthGate) #auth
- [x] v1.0.14 — Banner system, sticky search bar, seller settings icon #customer
- [x] v1.0.13 — Home hero redesign, store perf fix, account management, profile redesign #customer
- [x] AR wall calibration + foot sizing v2 data model #customer
- [x] Buy-again-to-cart flow from purchase history #customer
- [x] Settings screen redesign with sections #customer
- [x] Per-color photo galleries + size/variant architecture refactor #seller
- [x] Obsidian vault created (MOCs, Code Map, Templates, Tasks) #docs

---

## Notes on usage
- Tag tasks for the area: `#auth`, `#checkout`, `#seller`, `#admin`, `#db`, `#notifications`.
- Link a task to its doc when it exists, e.g. `- [ ] Ship X — see [[docs/AI/...|...]]`.
- Friday: fold completed work into [[obsidian/Templates/Weekly Review|Weekly Review]].
- Bigger ambitions live in [[docs/RoadMap/SOLEVISION_ROADMAP|🧭 Roadmap]].
