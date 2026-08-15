# Obsidian Vault — SoleVision

This folder turns the entire SoleVision repo into an Obsidian knowledge base. Obsidian is pointed at the **repo root** as its vault, so every existing markdown file in `docs/` and `admin-portal/docs/` is searchable, linkable, and visible in the graph view — no copying or conversion needed.

---

## 1. First-time setup (2 minutes)

1. Open Obsidian → **Open folder as vault** → select the **repo root** (the folder containing `lib/`, `admin-portal/`, `docs/`, `supabase/`).
2. In **Settings → Templates**, set:
   - **Template folder location**: `obsidian/Templates`
3. (Optional, recommended) In **Settings → Files and Links → Excluded files**, add `build/`, `.dart_tool/`, `.pub-cache/`, `node_modules/`, `backup/` so Obsidian doesn't index build artifacts.
4. (Optional) Install the **Daily notes** core plugin and point it at the Daily Note template.

`.obsidian/` (your local settings) is gitignored — settings stay personal, notes are shared.

## 2. Folder layout

| Path | Purpose |
|------|---------|
| `obsidian/Home.md` | Dashboard hub — start here every session |
| `obsidian/MOCs/` | Maps of Content — one per area, each links the relevant docs |
| `obsidian/Templates/` | Daily note + weekly review templates |
| `obsidian/Onboarding.md` | Guided ramp-up path for new devs / AI agents |
| `obsidian/Tasks.md` | Task inbox + simple kanban board |
| `docs/`, `admin-portal/docs/` | Existing project docs (read-only source of truth) |

## 3. Linking conventions

- Always use **full-path wikilinks** so links are unambiguous even when two files share a basename (e.g. `docs/SIGNUP_ARCHITECTURE.md` and `docs/AI/SIGNUP_ARCHITECTURE.md`):
  - `[[docs/AI/SIGNUP_ARCHITECTURE|Signup architecture]]`
- When adding a new doc under `docs/`, link it from the relevant MOC so it becomes discoverable.
- Use tags lightly: `#moc` on MOCs, `#project/solevision` on tasks.

## 4. The daily loop

1. Open `Home.md` → pick the relevant MOC for what you're working on.
2. Create a daily note from the template (`obsidian/Templates/Daily Note.md`).
3. Track tasks in `obsidian/Tasks.md` (or in the daily note with `- [ ]`).
4. Friday: run the weekly review template.
