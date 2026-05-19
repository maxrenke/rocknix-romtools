<#
.SYNOPSIS
    Ingests ROMs from Downloads into D:\RocknixBackup, then renumbers all romhack files.
.DESCRIPTION
    PHASE 1 - Downloads intake:
    - Scans ~/Downloads for ROM files (.gba, .gb, .gbc, .nds, .z64, .n64, .nes, .smc, .sfc, .nes)
    - Determines system from extension
    - Detects romhack vs retail: region tags (USA/Japan/Europe/etc.) = retail, else = romhack
    - Moves file to system\romhacks\ or system\ accordingly

    PHASE 2 - Renumber romhacks:
    - Scans all romhacks subfolders (definitive/, story/, difficulty/, etc.)
    - Sorts by CreationTime ascending across ALL subfolders globally
    - Assigns prefix NNN_ where the oldest file gets the highest number
      (so descending alpha sort = oldest first)
    - Renames matching save files (.srm, .sav, .dsv, .rtc, .dss) to stay in sync
    - Strips any existing NNN_ prefix before assigning the new one
    - Supports -DryRun to preview changes without touching files
    - New downloads (Phase 1) land in romhacks/ root; move them to the correct
      subfolder (definitive/, story/, etc.) before running Phase 2.
.PARAMETER RootPath
    Root of your backup directory. Defaults to D:\RocknixBackup
.PARAMETER DownloadsPath
    Path to scan for new ROMs. Defaults to ~/Downloads
.PARAMETER DryRun
    If specified, prints what would happen without touching files.
.EXAMPLE
    .\Organize-Romhacks.ps1
    .\Organize-Romhacks.ps1 -DryRun
    .\Organize-Romhacks.ps1 -RootPath "E:\MyBackup"
#>
param(
    [string]$RootPath      = "D:\RocknixBackup",
    [string]$DownloadsPath = "$env:USERPROFILE\Downloads",
    [switch]$DryRun,
    [switch]$SkipIngest
)

# --- Extension -> system folder map ---
$extToSystem = @{
    ".gba" = "gba"
    ".gb"  = "gb"
    ".gbc" = "gbc"
    ".nds" = "nds"
    ".z64" = "n64"
    ".n64" = "n64"
    ".nes" = "nes"
    ".smc" = "snes"
    ".sfc" = "snes"
    ".sms" = "mastersystem"
    ".gg"  = "gamegear"
    ".pce" = "pcengine"
    ".cso" = "psp"
    ".iso" = "psp"   # most common in this collection; adjust if needed
}

# Region tag pattern = retail ROM
$retailPattern = '\((USA|Japan|Europe|World|Australia|En|J|U|E|Fr|De|Es|It)\b'

# Romhack keyword/version pattern (fallback if no region tag found)
$romhackPattern = 'v\d+[\.\d]+|[\(\[]\d{1,2}-\d{1,2}-\d{2}[\)\]]|' +
                  '(Redux|Rogue|Randomized|Kaizo|Legacy|Deluxe|Ultimate|Plus|Enhanced|' +
                  'Remake|Remaster|Reborn|Reloaded|Definitive|Expanded|Extended|' +
                  'Rebalanced|Recharged|Refilled|Reforged|Revival|Revolution|Reborn|' +
                  'Blazing|Inclement|Radical|Liquid|Crystal|Glazed|Unbound|Prism|' +
                  'Emerald|FireRed|Firered|LeafGreen|Leafgreen|HeartGold|SoulSilver)'

# --- PHASE 1: Ingest from Downloads ---
if ($SkipIngest) {
    Write-Host "=== PHASE 1: Downloads Intake ===" -ForegroundColor Cyan
    Write-Host "Skipped (-SkipIngest).`n"
} else {

$ingestRomExts = $extToSystem.Keys
$downloadsRoms = Get-ChildItem -Path $DownloadsPath -File |
    Where-Object { $ingestRomExts -contains $_.Extension.ToLower() }

if ($downloadsRoms.Count -gt 0) {
    Write-Host "=== PHASE 1: Downloads Intake ===" -ForegroundColor Cyan
    Write-Host "Found $($downloadsRoms.Count) ROM(s) in Downloads.`n"
    foreach ($rom in $downloadsRoms) {
        $ext    = $rom.Extension.ToLower()
        $system = $extToSystem[$ext]
        if (-not $system) {
            Write-Host "  SKIP (unknown system): $($rom.Name)" -ForegroundColor DarkGray
            continue
        }
        $systemPath = Join-Path $RootPath $system
        if (-not (Test-Path $systemPath)) {
            Write-Host "  SKIP (no system folder '$system'): $($rom.Name)" -ForegroundColor DarkGray
            continue
        }
        # Determine retail vs romhack
        if ($rom.Name -match $retailPattern) {
            $destDir  = $systemPath
            $destType = "retail"
        } else {
            $destDir  = Join-Path $systemPath "romhacks"
            $destType = "romhack"
        }
        $destPath = Join-Path $destDir $rom.Name
        Write-Host "  [$($system.ToUpper())] $destType : $($rom.Name)" -ForegroundColor $(if ($destType -eq "romhack") {"Green"} else {"White"})
        if (-not $DryRun) {
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
            Move-Item -LiteralPath $rom.FullName -Destination $destPath -Force
        }
    }
    Write-Host ""
} else {
    Write-Host "=== PHASE 1: Downloads Intake ===" -ForegroundColor Cyan
    Write-Host "No ROMs found in Downloads.`n"
}

} # end -not SkipIngest

# --- PHASE 2: Renumber romhacks ---
Write-Host "=== PHASE 2: Renumber Romhacks ===" -ForegroundColor Cyan
$romExtensions  = @("*.gba","*.gb","*.gbc","*.nds","*.z64","*.n64","*.nes")
$saveExtensions = @("*.srm","*.sav","*.dsv","*.rtc","*.dss")
if ($DryRun) { Write-Host "[DRY RUN] No files will be changed.`n" -ForegroundColor Yellow }
# --- Collect all roms in any romhacks subfolder ---
$allRoms = foreach ($ext in $romExtensions) {
    Get-ChildItem -Path $RootPath -Recurse -Filter $ext |
        Where-Object { $_.FullName -like "*\romhacks\*" }
}
$allRoms = $allRoms | Sort-Object CreationTime
$total = $allRoms.Count
if ($total -eq 0) {
    Write-Host "No romhack files found under $RootPath" -ForegroundColor Red
    exit
}
Write-Host "Found $total romhack files. Calculating prefixes..." -ForegroundColor Cyan
# --- Rename roms and build save file map ---
$saveMap   = @{}   # old basename -> new basename
$romRenamed = 0
$romSkipped = 0
for ($i = 0; $i -lt $total; $i++) {
    $file      = $allRoms[$i]
    $prefix    = "{0:D3}" -f ($total - $i)
    $cleanName = $file.Name -replace "^\d{3}(?:_| - )", ""
    $newName   = "$prefix - $cleanName"
    $oldBase = $file.BaseName
    $newBase = "$prefix - " + ($file.BaseName -replace "^\d{3}(?:_| - )", "")
    $saveMap[$oldBase] = $newBase
    if ($file.Name -eq $newName) {
        $romSkipped++
        continue
    }
    $subLabel = $file.Directory.Name  # e.g. "definitive", "story"
    if ($DryRun) {
        Write-Host "  ROM  [$subLabel]: $($file.Name)  ->  $newName"
    } else {
        try {
            Rename-Item -LiteralPath $file.FullName -NewName $newName -ErrorAction Stop
            $romRenamed++
        } catch {
            Write-Host "FAILED: $($file.Name) -> $newName`n  $_" -ForegroundColor Red
        }
    }
}
# --- Rename matching save files ---
$allSaves = foreach ($ext in $saveExtensions) {
    Get-ChildItem -Path $RootPath -Recurse -Filter $ext |
        Where-Object { $_.FullName -like "*\romhacks\*" }
}
$saveRenamed = 0
$saveSkipped = 0
foreach ($sf in $allSaves) {
    $oldBase = $sf.BaseName
    if (-not $saveMap.ContainsKey($oldBase)) { $saveSkipped++; continue }
    $newSaveName = $saveMap[$oldBase] + $sf.Extension
    if ($sf.Name -eq $newSaveName) { $saveSkipped++; continue }
    if ($DryRun) {
        Write-Host "  SAVE : $($sf.Name)  ->  $newSaveName"
    } else {
        try {
            Rename-Item -LiteralPath $sf.FullName -NewName $newSaveName -ErrorAction Stop
            $saveRenamed++
        } catch {
            Write-Host "FAILED: $($sf.Name) -> $newSaveName`n  $_" -ForegroundColor Red
        }
    }
}
# --- Summary ---
Write-Host ""
if ($DryRun) {
    Write-Host "[DRY RUN] Would rename: $($total - $romSkipped) roms, $($allSaves.Count - $saveSkipped) saves. $romSkipped roms and $saveSkipped saves already correct." -ForegroundColor Yellow
} else {
    Write-Host "Done!" -ForegroundColor Green
    Write-Host "  Roms renamed : $romRenamed  (skipped already-correct: $romSkipped)"
    Write-Host "  Saves renamed: $saveRenamed  (skipped already-correct: $saveSkipped)"
}
