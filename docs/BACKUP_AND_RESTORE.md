# SoleVision — Local Backup & Restore

Because the Supabase **free tier has no automatic backups**, this project ships a
local backup system that copies your database and storage files to your own
Windows laptop on a schedule. Everything runs client-side — no paid add-ons.

## What you get

| Component | What it does | Restore value |
|---|---|---|
| `schema.sql` | Full schema dump (`supabase db dump`) | Schema recovery on a new project |
| `data.sql` | Full data dump (`supabase db dump --data-only`) | **Primary** full-data restore source |
| `roles.sql` | Postgres roles dump (best-effort) | Usually unnecessary on new projects |
| `json/*.json` | Readable copies of key tables | Human spot-checks + no-psql restore path |
| `storage/<bucket>/...` | Every file from every storage bucket, folder structure preserved | Storage recovery |
| `buckets.json` | Bucket metadata (public flag etc.) | Bucket recreation |
| `manifest.json` | File list + metadata for this run | Restore script uses it |

Each run creates a timestamped folder, e.g.
`C:\Users\jeffh\Documents\SoleVisionBackups\20260813_091500\`.

---

## One-time setup

1. **Install the Supabase CLI** (bundles `pg_dump`, so no separate Postgres
   install is needed):

   ```powershell
   npm install -g supabase
   ```

   > The CLI's `db dump` runs pg_dump inside Docker, so also install/start
   > **Docker Desktop** once before the first run. (If Docker is unavailable
   > the script still completes the JSON + storage halves and warns about the
   > SQL dumps.)

2. **Create the config with your secrets:**

   ```powershell
   cd backup
   Copy-Item config.example.ps1 config.ps1
   notepad config.ps1
   ```

   Fill in:
   - `$ServiceRoleKey` — Dashboard → Settings → **API Keys** → `service_role`
   - `$DbPassword` — the database password you set when creating the project
   - `$BackupRoot` — where backups should live on your laptop
   - `$KeepBackups` — how many runs to keep (older ones are auto-deleted)

   `backup/config.ps1` is **gitignored** — it will never be committed. If you
   ever suspect it leaked, rotate the keys in the Dashboard.

## Run manually

```powershell
cd backup
powershell -ExecutionPolicy Bypass -File backup.ps1
```

Optional flags: `-SkipStorage`, `-SkipJson`, `-SkipPrune`.

## Schedule it (Windows Task Scheduler)

The simplest reliable schedule is a daily task. From an **admin** PowerShell:

```powershell
schtasks /Create /TN "SoleVision Backup" /SC DAILY /ST 02:30 `
  /TR "powershell -ExecutionPolicy Bypass -File \"C:\path\to\backup\backup.ps1\"" `
  /F
```

Adjust:
- `/ST 02:30` — run time (2:30 AM, when nobody is using the app)
- `/SC WEEKLY /D SUN` — weekly instead of daily
- To run only when logged on: add `/IT` (interactive) — recommended so you
  notice failures; otherwise the task runs in the background.

Verify it ran: check the newest folder in `$BackupRoot` and open
`<folder>\data.sql` — it should contain `INSERT INTO`/`COPY` lines.

> **Watch for:** if the laptop is asleep at 2:30 AM the task may skip. Enable
> "Wake the computer to run this task" in the task's settings if you want.

---

## Restoring in an emergency

### Fastest path (same project, no extra tools)

Works when the project still exists but data was lost/corrupted, or you want
to roll a table back. The script upserts from the JSON exports using the
service-role key (RLS bypassed):

```powershell
cd backup
powershell -ExecutionPolicy Bypass -File restore.ps1 `
  -BackupFolder "C:\Users\jeffh\Documents\SoleVisionBackups\20260813_091500"
```

It restores buckets → storage files → table data in FK-safe order, merging
(`on_conflict`) so it can safely run over existing data.

**`auth.users` caveat:** `profiles.id` references Supabase Auth's `auth.users`,
which is *not* exported. In the **same project** the user rows still exist, so
`profiles` restores fine. On a **brand-new project** you must first recreate
the accounts (Dashboard → Authentication → Users → Add user with the same
emails) or the `profiles` upsert will be rejected by the FK.

### Full SQL restore (schema + data, psql)

The SQL dumps are the complete restore source. With `psql` available
(standalone Postgres tools, or the one bundled with the Supabase CLI's Docker
image):

```powershell
# New project, fresh database: apply schema, then data
psql "postgresql://postgres:YOUR_DB_PASSWORD@db.<ref>.supabase.co:5432/postgres" -f schema.sql
psql "postgresql://postgres:YOUR_DB_PASSWORD@db.<ref>.supabase.co:5432/postgres" -f data.sql
```

Same caveats apply:
- `auth`/`storage` schemas are intentionally excluded from the dump — recreate
  buckets via `restore.ps1` (step above) and users via the Dashboard.
- On a fresh project, `data.sql` will complain about `profiles` FK rows until
  the users exist; inserting with FK checks off
  (`SET session_replication_role = replica;` before, `SET ... = origin;`
  after) can force it, but then **recreate the users anyway** so logins work.

### Restoring just storage files

`restore.ps1` restores buckets + files first, so run it with `-SkipTables` if
you only need storage back.

---

## Security notes (why it's built this way)

- **Secrets never leave your machine.** The service-role key can read *all*
  rows and files — exactly what a backup needs, and why it must live only in
  the gitignored `config.ps1`. The app itself never uses this key; it uses the
  `anon` key with RLS.
- **RLS is bypassed for backup/restore on purpose.** A backup that obeys RLS
  would silently miss rows you couldn't "see". The service-role key is the
  documented escape hatch — treat it like a password.
- **JSON exports are a convenience, not the primary restore.** The SQL dump is
  the source of truth for recovery; JSON is for quick inspection and the
  no-psql path.

## Known limitations / trade-offs

1. **`auth.users` is never exported.** This is a Supabase platform constraint
   (the CLI intentionally excludes managed schemas). User *profiles* back up,
   but login credentials cannot be restored — users can reset their passwords.
2. **`supabase db dump` needs Docker** (for its bundled pg_dump). The script
   degrades gracefully (JSON + storage still complete), but for the full SQL
   dumps, Docker Desktop must be running.
3. **Free-tier egress.** Downloading a large storage bucket runs up bandwidth;
   storage files are usually small here (product photos), but prune with
   `$KeepBackups` to keep disk and bandwidth in check.
4. **Not a point-in-time snapshot.** A backup taken at 2:30 AM reflects the DB
   at that instant; orders placed after are not in it. That's expected for a
   daily local backup.
