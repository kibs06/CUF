# 🧑‍💻 Onboarding / Handoff

> A guided ramp-up path for anyone (human dev or AI agent) starting on SoleVision. Follow it top to bottom — each step links the docs you need. **#moc**

---

## Step 0 — The 2-minute picture
- [[docs/AI_PROJECT_SUMMARY|⚡ AI Project Summary]] — self-contained brief: stack, structure, data flow, current state, bug history. **Read this first, always.**
- [[docs/ABOUT_SOLEVISION|About SoleVision]] — what the product is

## Step 1 — Where the code lives
- `lib/` — Flutter app (Provider state mgmt, singleton services)
- `admin-portal/` — React admin portal (Vite + Tailwind + TanStack Query)
- `supabase/migrations/` — SQL migrations (numeric filenames)
- `docs/` — all documentation; `obsidian/MOCs/` — index into it
- 🗺️ [[obsidian/Code Map|Code Map]] — every `lib/` folder mapped to its MOC (code → docs)

## Step 2 — How to work on a feature
- [[docs/AI/feature_file_lookup_guide|🔍 Feature file lookup guide]] — maps features → exact files + existing logic
- Pick the area's MOC from [[obsidian/Home|🏠 Home]] for deep dives.

## Step 3 — Architecture essentials
- [[docs/PROJECT_HANDOFF|📄 Project Handoff]] — decisions & rationale, known issues, what's next
- [[docs/SoleVision_Complete_Documentation|📘 Master documentation]] — 22 sections (schema, RLS, services, setup)
- [[admin-portal/docs/architecture|🏛️ Admin portal architecture]]
- [[docs/AI/ADMIN_SUSPENSION_ARCHITECTURE|⛔ Admin suspension architecture]]

## Step 4 — Critical warnings (read before touching code)
1. **DO NOT use `supabase/schema.sql`** — it's outdated. Docs + live DB are truth.
2. **Verify every migration is applied to the live DB** — the #1 cause of past failed fixes.
3. **Revenue always combines online + POS** — never one alone.
4. **`inventory` is the authoritative stock source**, not `product_variants`.
5. **Products PK is TEXT**, not UUID — mind type comparisons.
6. **Full rebuild after service-layer changes** (`flutter clean && flutter pub get && flutter run`) — hot reload isn't enough.
7. Don't modify `validateCartForCheckout()` / app-level stock logic — it was proven correct; the bug was in the DB trigger.

## Step 5 — Environment
- Supabase project: `psczvbfoybqhjeqssimw.supabase.co` (creds hardcoded in `lib/constants/app_constants.dart`)
- MapTiler key → `dart_defines.json` (gitignored), run via `run_debug.sh` / `run_debug.bat`
- Admin portal: `cd admin-portal && npm install && npm run dev` (needs `.env` with `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`)

## Step 6 — Your first task
1. Create a daily note from [[obsidian/Templates/Daily Note|📝 Daily Note template]].
2. Add tasks to [[obsidian/Tasks|✅ Task board]].
3. Explore the graph view (Ctrl/Cmd-G) to see how docs connect.
4. When you learn something new, link it from the relevant MOC.

## Handoff checklist (end of a work session)
- [ ] Daily note updated: what I did, what's next, blockers
- [ ] New/changed architecture captured in the right MOC
- [ ] Tasks on [[obsidian/Tasks|✅ Task board]] reflect reality
- [ ] Home → **Active context** updated
