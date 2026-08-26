# ✅ Task Board

> Simple kanban for tracking what's in flight. Use `- [ ]` checkboxes so Obsidian's core **Search → Tasks** picks everything up, or install the community **Kanban** plugin for a visual board. **#project/solevision**

## 📥 Inbox (untriaged)
- [ ] 

## 🚧 In Progress
- [ ] Obsidian vault audit & refresh (MOCs, Code Map, tasks) #docs

## 🔜 Backlog / Next up
- [ ] ⛔ **REMOVE dev mode before release** — UI-only signup skip (unlock: swipe ↑↑↓↓→→←← on "Create your account"). Files + checklist: [[docs/AI/DEV_MODE_ARCHITECTURE|Dev Mode Architecture]] #auth
- [ ] Sandbox verification for PayMongo online GCash (attempt #6) — see [[docs/AI/PAYMONGO_ONLINE_GCASH_TEST_PLAN|PayMongo test plan]] #checkout
- [ ] Real-time order updates via Supabase Realtime (available, not integrated) #checkout
- [ ] CSV/PDF export for reports (currently stub only) #seller
- [ ] Image gallery zoom on product detail #customer

## ✅ Done (recent)
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
