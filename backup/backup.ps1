# ============================================================
# SoleVision - Local Backup Script  (Windows / PowerShell 5.1+)
# ============================================================
# Backs up a hosted Supabase project to your laptop:
#   1. SQL schema dump   (supabase db dump  -> schema.sql)   - restore source
#   2. SQL data dump     (supabase db dump --data-only)      - restore source
#   3. SQL roles dump    (supabase db dump --role-only)      - best-effort
#   4. JSON export of key tables (PostgREST + service role)  - human-readable
#      spot-checks + no-psql restore path
#   5. Storage download of every bucket (folder structure preserved)
#   6. Auto-prune: keeps the N most recent runs (config: $KeepBackups)
#
# RUN MANUALLY:
#     powershell -ExecutionPolicy Bypass -File backup.ps1
#
# SCHEDULE (Windows Task Scheduler):
#     See docs/BACKUP_AND_RESTORE.md for the exact schtasks command.
#
# REQUIREMENTS:
#   * Supabase CLI installed (npm i -g supabase  or  scoop/winget).
#     It bundles pg_dump, so `supabase db dump` needs no separate install.
#     (Docker Desktop is required by the CLI's pg_dump runner - the
#      script will warn you if `supabase` is missing or the dump fails.)
#   * backup/config.ps1  (copy of config.example.ps1 with real secrets)
#
# SECURITY: config.ps1 holds the service role key + DB password and is
# gitignored. Never commit it, never paste it into a public channel.
# ============================================================

[CmdletBinding()]
param(
    [switch]$SkipStorage,   # skip the (slow) storage file download
    [switch]$SkipJson,      # skip JSON table exports
    [switch]$SkipPrune      # skip pruning of old backups
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# Bootstrap config (gitignored)
# ------------------------------------------------------------
$configPath = Join-Path $PSScriptRoot 'config.ps1'
if (-not (Test-Path $configPath)) {
    Write-Host ''
    Write-Host '  ERROR: backup/config.ps1 not found.' -ForegroundColor Red
    Write-Host '  Copy backup/config.example.ps1 to backup/config.ps1 and fill in your secrets.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}
. $configPath

# ------------------------------------------------------------
# State / counters
# ------------------------------------------------------------
$script:WarningCount = 0
$script:JsonFiles = 0
$script:StorageFiles = 0
$script:StorageBytes = 0

function Write-Step([string]$title) {
    Write-Host ''
    Write-Host "  >> $title" -ForegroundColor Cyan
}

function Write-Ok([string]$msg)  { Write-Host "     [OK] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) {
    $script:WarningCount++
    Write-Host "     [WARN] $msg" -ForegroundColor Yellow
}
function Write-Fail([string]$msg) {
    $script:WarningCount++
    Write-Host "     [FAIL] $msg" -ForegroundColor Red
}

# ------------------------------------------------------------
# Preflight checks
# ------------------------------------------------------------
$supabaseCli = (Get-Command supabase -ErrorAction SilentlyContinue)
if (-not $supabaseCli) {
    Write-Host ''
    Write-Host '  ERROR: Supabase CLI not found on PATH.' -ForegroundColor Red
    Write-Host '  Install it:   npm install -g supabase' -ForegroundColor Yellow
    Write-Host '  then re-run this script.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

if ([string]::IsNullOrWhiteSpace($ServiceRoleKey) -or $ServiceRoleKey -like 'REPLACE_*') {
    Write-Host ''
    Write-Host '  ERROR: ServiceRoleKey is not set in backup/config.ps1' -ForegroundColor Red
    Write-Host ''
    exit 1
}
if ([string]::IsNullOrWhiteSpace($DbPassword) -or $DbPassword -like 'REPLACE_*') {
    Write-Host ''
    Write-Host '  ERROR: DbPassword is not set in backup/config.ps1' -ForegroundColor Red
    Write-Host ''
    exit 1
}
if (-not $BackupRoot -or -not (Split-Path -Parent $BackupRoot -IsAbsolute)) {
    Write-Host ''
    Write-Host '  ERROR: BackupRoot must be an absolute path in backup/config.ps1' -ForegroundColor Red
    Write-Host ''
    exit 1
}

# ------------------------------------------------------------
# Derived values
# ------------------------------------------------------------
$stamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $BackupRoot $stamp
$jsonDir   = Join-Path $backupDir 'json'
$storageDir = Join-Path $backupDir 'storage'
$dbName    = 'postgres'
$escapedPw = [uri]::EscapeDataString($DbPassword)
$dbUrl     = "postgresql://postgres:$escapedPw@db.$ProjectRef.supabase.co:5432/$dbName"
$restHeaders = @{
    apikey         = $ServiceRoleKey
    Authorization  = "Bearer $ServiceRoleKey"
}

New-Item -ItemType Directory -Force -Path $backupDir, $jsonDir, $storageDir | Out-Null

# ------------------------------------------------------------
# 1) SQL schema dump  (restore source - schema only, per CLI default)
# ------------------------------------------------------------
Write-Step 'Dumping database schema (schema.sql)'
$schemaFile = Join-Path $backupDir 'schema.sql'
$schemaOut = & $supabaseCli.Source db dump --db-url $dbUrl -f $schemaFile 2>&1
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $schemaFile)) {
    Write-Fail "schema.sql dump failed: $($schemaOut | Out-String). Docker must be running for the CLI's pg_dump."
} else {
    $kb = [math]::Round((Get-Item $schemaFile).Length / 1KB, 1)
    Write-Ok "schema.sql ($kb KB)"
}

# ------------------------------------------------------------
# 2) SQL data dump  (restore source)
# ------------------------------------------------------------
Write-Step 'Dumping database data (data.sql)'
$dataFile = Join-Path $backupDir 'data.sql'
$dataOut = & $supabaseCli.Source db dump --db-url $dbUrl --data-only -f $dataFile 2>&1
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dataFile)) {
    Write-Fail "data.sql dump failed: $($dataOut | Out-String)"
} else {
    $kb = [math]::Round((Get-Item $dataFile).Length / 1KB, 1)
    Write-Ok "data.sql ($kb KB)"
}

# ------------------------------------------------------------
# 3) SQL roles dump  (best-effort; harmless if it fails)
# ------------------------------------------------------------
Write-Step 'Dumping database roles (roles.sql)'
$rolesFile = Join-Path $backupDir 'roles.sql'
$rolesOut = & $supabaseCli.Source db dump --db-url $dbUrl --role-only -f $rolesFile 2>&1
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $rolesFile)) {
    Write-Warn "roles.sql dump failed - continuing without it: $($rolesOut | Out-String)"
}

# ------------------------------------------------------------
# 4) JSON export of key tables  (human-readable spot-checks)
# ------------------------------------------------------------
if (-not $SkipJson) {
    Write-Step "Exporting JSON copies of $($TablesToExport.Count) tables"
    foreach ($table in $TablesToExport) {
        try {
            $rows = @()
            $offset = 0
            $pageSize = 1000
            while ($true) {
                $range = "$offset-$($offset + $pageSize - 1)"
                $pageHeaders = $restHeaders + @{
                    Range      = $range
                    'Range-Unit' = 'items'
                }
                # NOTE: no ORDER BY on purpose - not every table has an
                # `id` column (inventory, store_follows use composite PKs),
                # and row order is irrelevant for a backup dump.
                $page = Invoke-RestMethod `
                    -Method Get `
                    -Uri "$SupabaseUrl/rest/v1/$table`?select=*" `
                    -Headers $pageHeaders
                if ($null -eq $page) { break }
                $rows += @($page)
                if (@($page).Count -lt $pageSize) { break }
                $offset += $pageSize
            }
            $outFile = Join-Path $jsonDir "$table.json"
            @($rows) | ConvertTo-Json -Depth 10 | Set-Content -Path $outFile -Encoding UTF8
            $script:JsonFiles++
        } catch {
            Write-Warn "Table '$table' export failed: $($_.Exception.Message)"
        }
    }
    Write-Ok "Exported $script:JsonFiles tables to json/"
}

# ------------------------------------------------------------
# 5) Storage download - every bucket, folder structure preserved
# ------------------------------------------------------------
if (-not $SkipStorage) {
    Write-Step 'Downloading storage buckets'
    try {
        $buckets = @(Invoke-RestMethod -Method Get -Uri "$SupabaseUrl/storage/v1/bucket" -Headers $restHeaders)
        # Save bucket metadata so restore can recreate them exactly.
        @($buckets) | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $backupDir 'buckets.json') -Encoding UTF8

        if ($buckets.Count -eq 0) { Write-Ok 'No buckets found.' }
        foreach ($bucket in $buckets) {
            $bucketId = $bucket.id
            $bucketDir = Join-Path $storageDir $bucketId
            New-Item -ItemType Directory -Force -Path $bucketDir | Out-Null

            # Recursively list every file (offset pagination, 100 at a time).
            $allFiles = @()
            $offset = 0
            while ($true) {
                $body = @{ prefix = ''; limit = 100; offset = $offset; sortBy = @{ column = 'name'; order = 'asc' } } | ConvertTo-Json
                $entries = @(Invoke-RestMethod -Method Post -Uri "$SupabaseUrl/storage/v1/object/list/$bucketId" -Headers $restHeaders -ContentType 'application/json' -Body $body)
                if ($entries.Count -eq 0) { break }
                foreach ($entry in $entries) {
                    # Files carry an id; folders do not.
                    if ($null -ne $entry.id) { $allFiles += $entry }
                }
                $offset += 100
                if ($entries.Count -lt 100) { break }
            }

            foreach ($entry in $allFiles) {
                $relPath = $entry.name
                $dest = Join-Path $bucketDir ($relPath -replace '/', [IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
                # Encode each path segment so spaces/unicode survive the URL.
                $segments = $relPath.Split('/') | ForEach-Object { [uri]::EscapeDataString($_) }
                $encoded  = $segments -join '/'
                try {
                    Invoke-WebRequest -Method Get -Uri "$SupabaseUrl/storage/v1/object/$bucketId/$encoded" -Headers $restHeaders -OutFile $dest -UseBasicParsing
                    $script:StorageFiles++
                    if (Test-Path $dest) { $script:StorageBytes += (Get-Item $dest).Length }
                } catch {
                    Write-Warn "  failed: $bucketId/$relPath ($($_.Exception.Message))"
                }
            }
            Write-Ok "bucket '$bucketId': $($allFiles.Count) files"
        }
        $mb = [math]::Round($script:StorageBytes / 1MB, 1)
        Write-Ok "Storage done - $script:StorageFiles files, $mb MB"
    } catch {
        Write-Fail "Storage download failed: $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------
# 6) Manifest + summary
# ------------------------------------------------------------
$manifest = [ordered]@{
    project_ref     = $ProjectRef
    created_at_utc  = (Get-Date).ToUniversalTime().ToString('o')
    files           = @(
        @{ name = 'schema.sql'; path = 'schema.sql' },
        @{ name = 'data.sql';   path = 'data.sql' }
    ) + (@(Get-ChildItem $jsonDir -Filter '*.json' -ErrorAction SilentlyContinue) | ForEach-Object {
        @{ name = $_.Name; path = "json/$($_.Name)"; bytes = $_.Length }
    }) + (@(Get-ChildItem $storageDir -Recurse -File -ErrorAction SilentlyContinue) | ForEach-Object {
        $rel = $_.FullName.Substring($storageDir.Length + 1) -replace '\\', '/'
        @{ name = $rel; path = "storage/$rel"; bytes = $_.Length }
    })
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $backupDir 'manifest.json') -Encoding UTF8

Write-Step 'Backup summary'
Write-Host "    Backup folder : $backupDir" -ForegroundColor White
Write-Host "    Tables (JSON) : $script:JsonFiles" -ForegroundColor White
Write-Host "    Storage files : $script:StorageFiles" -ForegroundColor White

# ------------------------------------------------------------
# 7) Prune old backups
# ------------------------------------------------------------
if (-not $SkipPrune -and $KeepBackups -gt 0) {
    $existing = @(Get-ChildItem $BackupRoot -Directory | Sort-Object LastWriteTime -Descending)
    if ($existing.Count -gt $KeepBackups) {
        $toRemove = $existing | Select-Object -Skip $KeepBackups
        Write-Step "Pruning $($toRemove.Count) old backup(s) - keeping the newest $KeepBackups"
        foreach ($old in $toRemove) {
            try {
                Remove-Item -Path $old.FullName -Recurse -Force
                Write-Ok "removed $($old.Name)"
            } catch {
                Write-Warn "could not remove $($old.Name): $($_.Exception.Message)"
            }
        }
    }
}

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------
if ($script:WarningCount -gt 0) {
    Write-Host ''
    Write-Host "  [WARN] Backup finished with $script:WarningCount warning(s) - review the lines above." -ForegroundColor Yellow
    exit 2
}
Write-Host ''
Write-Host '  [DONE] Backup complete.' -ForegroundColor Green
exit 0
