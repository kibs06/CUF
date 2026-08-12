# ============================================================
# SoleVision - Restore Script  (Windows / PowerShell 5.1+)
# ============================================================
# Restores a backup folder created by backup.ps1 into the SAME
# Supabase project (or a new one). Uses the service-role key + REST
# APIs, so it works without psql / Docker.
#
#   powershell -ExecutionPolicy Bypass -File restore.ps1 `
#       -BackupFolder "C:\Users\jeffh\Documents\SoleVisionBackups\20260813_091500"
#
# WHAT IT RESTORES (in this order):
#   1. Storage buckets  (recreates missing buckets with their public flag)
#   2. Storage files    (uploads every backed-up file, overwriting)
#   3. Table data       (JSON upserts - FK order from config, merge-duplicates)
#
# IMPORTANT CAVEAT - auth.users
#   `profiles.id` references `auth.users.id`, which is managed by
#   Supabase Auth and is NOT exported by the backup. Restoring profiles
#   works fine in the SAME project (the user rows still exist). On a
#   BRAND-NEW project you must first recreate the user accounts
#   (Dashboard -> Authentication -> Users -> Add user, or invite them) so
#   the FK resolves - otherwise the profiles upsert will be rejected.
#
# ALWAYS take a fresh backup of the current state before restoring -
# this script OVERWRITES existing rows (merge/upsert semantics).
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupFolder,

    # Comma-separated list of tables to SKIP (e.g. '-SkipTables profiles,notifications')
    [string]$SkipTables = '',

    [switch]$SkipStorage,
    [switch]$SkipBuckets,
    [switch]$DryRun    # validate connectivity + list what would happen, change nothing
)

$ErrorActionPreference = 'Stop'

# -- Config (for project URL + service role key) ------------------
$configPath = Join-Path $PSScriptRoot 'config.ps1'
if (-not (Test-Path $configPath)) {
    Write-Host ''
    Write-Host '  ERROR: backup/config.ps1 not found. Copy config.example.ps1 to config.ps1 first.' -ForegroundColor Red
    Write-Host ''
    exit 1
}
. $configPath

if ($ServiceRoleKey -like 'REPLACE_*' -or [string]::IsNullOrWhiteSpace($ServiceRoleKey)) {
    Write-Host ''
    Write-Host '  ERROR: ServiceRoleKey is not set in backup/config.ps1' -ForegroundColor Red
    Write-Host ''
    exit 1
}

# -- Validate backup folder ----------------------------------------
if (-not (Test-Path $BackupFolder)) {
    Write-Host ''
    Write-Host "  ERROR: Backup folder not found: $BackupFolder" -ForegroundColor Red
    Write-Host ''
    exit 1
}
$manifestPath = Join-Path $BackupFolder 'manifest.json'
if (-not (Test-Path $manifestPath)) {
    Write-Host ''
    Write-Host '  ERROR: manifest.json not found in the backup folder - is this a backup.ps1 output folder?' -ForegroundColor Red
    Write-Host ''
    exit 1
}
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

$skipSet = @{}
foreach ($t in ($SkipTables -split ',')) {
    $name = $t.Trim()
    if ($name) { $skipSet[$name] = $true }
}

$restHeaders = @{
    apikey        = $ServiceRoleKey
    Authorization = "Bearer $ServiceRoleKey"
}

function Write-Step([string]$title) {
    Write-Host ''
    Write-Host "  >> $title" -ForegroundColor Cyan
}
function Write-Ok([string]$msg)   { Write-Host "     [OK] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "     [WARN] $msg" -ForegroundColor Yellow }

# -- Connectivity check -------------------------------------------
Write-Step 'Checking connectivity'
try {
    $probe = Invoke-RestMethod -Method Get -Uri "$SupabaseUrl/rest/v1/profiles?select=id&limit=1" -Headers $restHeaders
    Write-Ok "Connected to $ProjectRef (service role OK)"
} catch {
    Write-Host ''
    Write-Host '  ERROR: Could not reach the Supabase project with the service role key.' -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

if ($DryRun) {
    Write-Host ''
    Write-Host '  DRY RUN - no changes made. The following would be restored:' -ForegroundColor Yellow
    $jsonDir = Join-Path $BackupFolder 'json'
    $jsonFiles = @(Get-ChildItem $jsonDir -Filter '*.json' -ErrorAction SilentlyContinue)
    $storageFiles = @($manifest.files | Where-Object { $_.path -like 'storage/*' })
    Write-Host "    Tables : $($jsonFiles.Count) JSON files"
    Write-Host "    Storage: $($storageFiles.Count) files"
    exit 0
}

# -- 1) Buckets ----------------------------------------------------
if (-not $SkipBuckets -and (Test-Path (Join-Path $BackupFolder 'buckets.json'))) {
    Write-Step 'Restoring storage buckets'
    $buckets = Get-Content (Join-Path $BackupFolder 'buckets.json') -Raw | ConvertFrom-Json
    $existing = @(Invoke-RestMethod -Method Get -Uri "$SupabaseUrl/storage/v1/bucket" -Headers $restHeaders)
    $existingIds = @($existing | ForEach-Object { $_.id })
    foreach ($b in $buckets) {
        if ($existingIds -contains $b.id) {
            # Update public flag + limits to match the backup.
            $patch = @{ public = [bool]$b.public } | ConvertTo-Json
            Invoke-RestMethod -Method Patch -Uri "$SupabaseUrl/storage/v1/bucket/$($b.id)" -Headers $restHeaders -ContentType 'application/json' -Body $patch | Out-Null
            Write-Ok "bucket '$($b.id)' already exists - public flag synced"
        } else {
            $create = @{
                id = $b.id; name = $b.name; public = [bool]$b.public
            } | ConvertTo-Json
            Invoke-RestMethod -Method Post -Uri "$SupabaseUrl/storage/v1/bucket" -Headers $restHeaders -ContentType 'application/json' -Body $create | Out-Null
            Write-Ok "bucket '$($b.id)' created (public = $($b.public))"
        }
    }
}

# -- 2) Storage files ----------------------------------------------
if (-not $SkipStorage) {
    Write-Step 'Restoring storage files'
    $storageFiles = @($manifest.files | Where-Object { $_.path -like 'storage/*' })
    $storageRoot = Join-Path $BackupFolder 'storage'
    $count = 0
    foreach ($f in $storageFiles) {
        $rel = $f.path.Substring('storage/'.Length) -replace '/', [IO.Path]::DirectorySeparatorChar
        $src = Join-Path $storageRoot $rel
        if (-not (Test-Path $src)) {
            Write-Warn "missing source file, skipped: $rel"
            continue
        }
        # Split 'storage/<bucket>/<path>' -> bucket + object path. Encode
        # each segment exactly like backup.ps1 does (spaces, unicode, '#',
        # '&' all survive; already-encoded names are NOT double-encoded).
        $parts = $f.path.Substring('storage/'.Length).Split('/')
        $bucketId = $parts[0]
        $objectPath = (($parts[1..($parts.Length - 1)]) | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
        $url = "$SupabaseUrl/storage/v1/object/$bucketId/$objectPath"
        try {
            Invoke-WebRequest -Method Post -Uri $url -Headers ($restHeaders + @{ 'x-upsert' = 'true' }) -InFile $src -ContentType 'application/octet-stream' -UseBasicParsing | Out-Null
            $count++
        } catch {
            Write-Warn "upload failed for $($f.path): $($_.Exception.Message)"
        }
    }
    Write-Ok "Uploaded $count storage file(s)"
}

# -- 3) Table data (JSON upserts) ----------------------------------
Write-Step 'Restoring table data (JSON upserts)'
# on_conflict column(s) per table - the natural key for merge-upserts.
# Tables not listed fall back to 'id' (their PK column name).
$conflictKeys = @{
    'inventory'                = 'product_id,size'
    'store_follows'            = 'user_id,store_id'
    'product_reviews'          = 'product_id,customer_id'
    'order_status_history'     = 'id'
    'payment_intents'          = 'id'
    'payment_webhook_events'   = 'id'
}

$jsonDir = Join-Path $BackupFolder 'json'
# Restore in the FK-safe order declared in config ($TablesToExport: parents
# before children) - alphabetical order would try order_items before orders
# and inventory before products, failing on a fresh/empty database.
$tablesToRestore = if ($TablesToExport) { @($TablesToExport) } else { @() }
$presentTables = @(Get-ChildItem $jsonDir -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
if ($presentTables.Count -eq 0) {
    Write-Warn 'No JSON exports found in this backup folder - nothing to restore from JSON.'
} else {
    # Declared order first, then any extra tables found in the folder.
    $tablesToRestore += $presentTables | Where-Object { $_ -notin $tablesToRestore }
    $totalRows = 0
    foreach ($table in $tablesToRestore) {
        $file = Join-Path $jsonDir "$table.json"
        if (-not (Test-Path $file)) { continue }
        if ($skipSet[$table]) {
            Write-Warn "skipping table '$table' (requested)"
            continue
        }
        $rows = @(Get-Content $file -Raw | ConvertFrom-Json)
        if ($rows.Count -eq 0) {
            Write-Ok "table '$table': 0 rows"
            continue
        }
        $conflict = if ($conflictKeys.ContainsKey($table)) { $conflictKeys[$table] } else { 'id' }
        $uri = "$SupabaseUrl/rest/v1/$table`?on_conflict=$conflict"
        $chunkSize = 500
        $inserted = 0
        $failed = 0
        for ($i = 0; $i -lt $rows.Count; $i += $chunkSize) {
            $chunk = @($rows[$i..([math]::Min($i + $chunkSize - 1, $rows.Count - 1))])
            try {
                $body = $chunk | ConvertTo-Json -Depth 10 -Compress
                Invoke-RestMethod -Method Post -Uri $uri -Headers ($restHeaders + @{ Prefer = 'resolution=merge-duplicates,return=minimal' }) -ContentType 'application/json' -Body $body | Out-Null
                $inserted += $chunk.Count
            } catch {
                $failed++
                Write-Warn "chunk failed for '$table' (rows $i-$($i + $chunk.Count - 1)): $($_.Exception.Message)"
            }
        }
        $totalRows += $inserted
        $note = if ($failed -gt 0) { " ($failed chunk(s) failed)" } else { '' }
        Write-Ok "table '$table': $inserted/$($rows.Count) rows$note"
    }
    Write-Host "    Total rows upserted: $totalRows" -ForegroundColor White
}

# -- Done ----------------------------------------------------------
Write-Host ''
Write-Host '  [DONE] Restore finished.' -ForegroundColor Green
Write-Host '  Remember: profiles restore requires auth.users to exist (see header notes).' -ForegroundColor Yellow
exit 0
