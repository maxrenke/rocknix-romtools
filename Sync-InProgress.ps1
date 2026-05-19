<#
.SYNOPSIS
    Syncs ROMs with save files into in-progress/ subfolders, and moves completed games back out.
.DESCRIPTION
    IN  - Finds any ROM that has an associated save file and moves it (and all its saves)
          into an in-progress/ folder, preserving subfolder structure:
            Retail:  system/in-progress/
            Romhack: system/romhacks/in-progress/subfolder/

    OUT - Finds ROMs already in in-progress/ that no longer have saves and moves them back
          to their original subfolder (in-progress/ is stripped from the path).

    Uses fuzzy name matching to pair saves with ROMs whose names changed due to
    renumbering or Normalize-Romhacks.ps1 (strips prefix, [TAG], version strings).
    Orphaned saves with old names are renamed to match the current ROM basename on move.
.PARAMETER RootPath
    Root of your backup directory. Defaults to D:\RocknixBackup
.PARAMETER DryRun
    Preview only - no files moved.
.EXAMPLE
    .\Sync-InProgress.ps1
    .\Sync-InProgress.ps1 -DryRun
#>
param(
    [string]$RootPath = "D:\RocknixBackup",
    [switch]$DryRun
)

$romExts  = @(".gba",".gb",".gbc",".nds",".z64",".n64",".nes",".sfc",".smc")
$saveExts = @(".srm",".sav",".dsv",".rtc",".dss")

function Get-RomKey([string]$name) {
    $n = [IO.Path]::GetFileNameWithoutExtension($name)
    $n = $n -replace "^\d{3}[\s_-]+", ""                           # strip NNN_ or NNN - prefix
    $n = $n -replace "\s*\[[^\]]*\]", ""                           # strip [TAG]
    $n = $n -replace "\s*\([vV]?[\d][\d.\-]*[a-zA-Z]*\)\s*$", ""  # strip (v1.2.3)
    $n = $n -replace "\s*\(\d{5,8}\)\s*$", ""                      # strip date versions
    $n = $n -replace "\s+[vV]\d+(\.\d+)*\s*$", ""                  # strip trailing vX or vX.Y
    $n = $n -replace "[_\-]", " "
    $n = $n.Trim() -replace "\s+", " "
    return $n.ToLower()
}

# Helper: given a ROM path, return its canonical in-progress destination dir
function Get-InProgressDir([string]$romFullPath) {
    $rel = $romFullPath -replace [regex]::Escape("$RootPath\"), ""
    # Strip \in-progress if already there, so we always compute from origin
    $rel = $rel -replace "\\in-progress", ""
    $sys = ($rel -split "\\")[0]
    if ($rel -like "*\romhacks\*") {
        $sub = ($rel -split "\\romhacks\\")[1] -split "\\" | Select-Object -First 1
        # If $sub is the ROM file itself (no subfolder), don't nest under it
        if ($romExts -contains [IO.Path]::GetExtension($sub).ToLower()) {
            return Join-Path $RootPath "$sys\romhacks\in-progress"
        }
        return Join-Path $RootPath "$sys\romhacks\in-progress\$sub"
    } else {
        return Join-Path $RootPath "$sys\in-progress"
    }
}

if ($DryRun) { Write-Host "[DRY RUN] No files will be moved.`n" -ForegroundColor Yellow }

# --- Build full ROM index (ALL locations, including in-progress) ---
# "$sys|$key" -> FileInfo (first match wins, prefer non-in-progress)
$romIndex = @{}
Get-ChildItem $RootPath -Directory | Where-Object { $_.Name -notlike "_*" } | ForEach-Object {
    $sys = $_.Name
    # Non-in-progress first so they win over in-progress on key collision
    Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $romExts -contains $_.Extension.ToLower() } |
        Sort-Object { if ($_.FullName -like "*\in-progress\*") { 1 } else { 0 } } |
        ForEach-Object {
            $k = "$sys|$(Get-RomKey $_.Name)"
            if (-not $romIndex.ContainsKey($k)) { $romIndex[$k] = $_ }
        }
}

# --- Find all save files (skip only savestates/ - include in-progress saves) ---
$allSaves = Get-ChildItem $RootPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $saveExts -contains $_.Extension.ToLower() -and
    $_.FullName -notlike "*\savestates\*"
}

# --- Match saves to ROMs ---
# romPath -> List<saveFileInfo>
$romToSaves = @{}

foreach ($save in $allSaves) {
    $rel = $save.FullName -replace [regex]::Escape("$RootPath\"), ""
    $sys = ($rel -split "\\")[0]
    $k   = "$sys|$(Get-RomKey $save.Name)"
    $rom = $null

    # 1. Exact basename match in same directory (handles correctly-named saves)
    foreach ($ext in $romExts) {
        $candidate = Join-Path $save.DirectoryName ($save.BaseName + $ext)
        if (Test-Path -LiteralPath $candidate) {
            $rom = Get-Item -LiteralPath $candidate
            break
        }
    }

    # 2. Fuzzy match via global ROM index (handles renamed/renumbered saves)
    if (-not $rom -and $romIndex.ContainsKey($k)) {
        $rom = $romIndex[$k]
    }

    if (-not $rom) {
        Write-Host "  WARN: no ROM matched for '$($save.Name)' - skipping" -ForegroundColor DarkYellow
        continue
    }

    if (-not $romToSaves.ContainsKey($rom.FullName)) {
        $romToSaves[$rom.FullName] = [System.Collections.Generic.List[object]]::new()
    }
    $romToSaves[$rom.FullName].Add($save)
}

# --- Move ROM + saves into in-progress (or consolidate if ROM already there) ---
Write-Host "=== Moving to in-progress ===" -ForegroundColor Cyan
$movedIn = 0

foreach ($romPath in ($romToSaves.Keys | Sort-Object)) {
    $rom     = Get-Item -LiteralPath $romPath
    $saves   = $romToSaves[$romPath]
    $destDir = Get-InProgressDir $rom.FullName
    $romDest = Join-Path $destDir $rom.Name

    $romNeedsMove  = ($rom.FullName -ne $romDest)
    $savesNeedMove = @($saves | Where-Object {
        $syncedName = $rom.BaseName + $_.Extension
        $_.FullName -ne (Join-Path $destDir $syncedName)
    })

    if (-not $romNeedsMove -and $savesNeedMove.Count -eq 0) { continue }

    $rel = $rom.FullName -replace [regex]::Escape("$RootPath\"), ""
    Write-Host "  -> $rel" -ForegroundColor White

    if ($romNeedsMove) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Move-Item -LiteralPath $rom.FullName -Destination $romDest -Force
        }
        $movedIn++
    }

    foreach ($save in ($saves | Sort-Object Name | Select-Object -Unique)) {
        $syncedName = $rom.BaseName + $save.Extension
        $saveDest   = Join-Path $destDir $syncedName
        if ($save.FullName -eq $saveDest) { continue }
        $label = if ($syncedName -ne $save.Name) { "$($save.Name) -> $syncedName" } else { $save.Name }
        Write-Host "     save: $label" -ForegroundColor DarkCyan
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Move-Item -LiteralPath $save.FullName -Destination $saveDest -Force
        }
    }
}

if ($movedIn -eq 0 -and ($romToSaves.Keys | ForEach-Object { $romToSaves[$_] } | Measure-Object).Count -eq 0) {
    Write-Host "  Nothing to move in." -ForegroundColor DarkGray
}

# --- Move back: in-progress ROMs with no saves anywhere in the collection ---
Write-Host "`n=== Moving back (no save = completed or save deleted) ===" -ForegroundColor Cyan
$movedOut = 0

Get-ChildItem $RootPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $romExts -contains $_.Extension.ToLower() -and
    $_.FullName -like "*\in-progress\*"
} | ForEach-Object {
    $rom = $_
    # Check for saves in the same in-progress dir
    $hasSave = $false
    foreach ($ext in $saveExts) {
        if (Test-Path -LiteralPath (Join-Path $rom.DirectoryName ($rom.BaseName + $ext))) {
            $hasSave = $true; break
        }
    }
    if ($hasSave) { return }

    $origDir  = $rom.DirectoryName -replace "\\in-progress", ""
    $origPath = Join-Path $origDir $rom.Name
    $rel      = $rom.FullName -replace [regex]::Escape("$RootPath\"), ""

    Write-Host "  <- $rel" -ForegroundColor Green
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $origDir -Force | Out-Null
        Move-Item -LiteralPath $rom.FullName -Destination $origPath -Force
    }
    $movedOut++
}

if ($movedOut -eq 0) { Write-Host "  Nothing to move back." -ForegroundColor DarkGray }

# --- Clean up empty in-progress dirs ---
if (-not $DryRun) {
    Get-ChildItem $RootPath -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*\in-progress*" } |
        Sort-Object FullName -Descending |
        ForEach-Object {
            if ((Get-ChildItem $_.FullName -Recurse -File).Count -eq 0) {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
}

Write-Host ""
if ($DryRun) {
    Write-Host "[DRY RUN] Would move in: $movedIn  |  Would move back: $movedOut" -ForegroundColor Yellow
} else {
    Write-Host "Done. Moved in: $movedIn  |  Moved back: $movedOut" -ForegroundColor Green
}
