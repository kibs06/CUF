# ============================================================
# SoleVision - Backup configuration (TEMPLATE)
# ============================================================
# HOW TO USE:
#   1. Copy this file to  config.ps1  (same folder).
#   2. Fill in your real values below.
#   3. NEVER commit config.ps1 - it is gitignored because it holds
#      secrets (service role key + database password). If you ever
#      accidentally commit it, rotate both keys immediately.
# ============================================================

# --- Supabase project ------------------------------------------
# The project ref is the <ref> in https://<ref>.supabase.co
$ProjectRef = 'psczvbfoybqhjeqssimw'
$SupabaseUrl = "https://$ProjectRef.supabase.co"

# Service role key - Dashboard -> Settings -> API Keys -> service_role.
# Full read access to every table + storage bucket. It NEVER leaves this
# machine; it is only used to READ data out of Supabase for backup and to
# WRITE data back during restore.
$ServiceRoleKey = 'REPLACE_WITH_YOUR_SERVICE_ROLE_KEY'

# Database password - the one set when the project was created
# (Dashboard -> Settings -> Database -> Connection string shows the URL;
#  the password is the part after postgres: in it).
$DbPassword = 'REPLACE_WITH_YOUR_DB_PASSWORD'

# --- Backup destination ----------------------------------------
# A new subfolder with a timestamp is created here on every run:
#   <BackupRoot>/20260813_091500/schema.sql
#   <BackupRoot>/20260813_091500/data.sql
#   <BackupRoot>/20260813_091500/json/<table>.json
#   <BackupRoot>/20260813_091500/storage/<bucket>/<path...>
$BackupRoot = 'C:\Users\jeffh\Documents\SoleVisionBackups'

# Prune: keep only the N most recent backup runs, delete the rest.
$KeepBackups = 10

# --- JSON spot-check exports -----------------------------------
# Readable copies of the most important tables (NOT the primary restore
# path - the SQL dump is). Order matters for restore: parents before
# children so foreign keys resolve. Add/remove freely.
$TablesToExport = @(
  'profiles',
  'stores',
  'products',
  'product_variants',
  'inventory',
  'product_images',
  'orders',
  'order_items',
  'sales_transactions',
  'sales_transaction_items',
  'reviews',
  'product_reviews',
  'cart_items',
  'customization_requests',
  'conversations',
  'messages',
  'seller_business_docs',
  'notifications',
  'reports',
  'store_follows'
)

# --- Optional: pg_dump/psql override ---------------------------
# If you install the standalone PostgreSQL tools (or EDB binaries) and
# they are NOT on your PATH, point to the folder containing pg_dump.exe
# and psql.exe here (e.g. 'C:\Program Files\PostgreSQL\17\bin').
# Leave empty to use the Supabase CLI (default).
$PgToolsDir = ''
