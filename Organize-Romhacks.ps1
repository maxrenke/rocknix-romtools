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
    - Renames matching RetroArch cheat files (.cht, any core subfolder under
      CheatsPath) to stay in sync - so a cheat you've set up for a ROM keeps
      working after that ROM's prefix changes. Matches purely by basename, so
      it's automatic for any future cheat file - nothing to configure per-game.
    - Strips any existing NNN_ prefix before assigning the new one
    - Supports -DryRun to preview changes without touching files
    - New downloads (Phase 1) land in romhacks/ root; move them to the correct
      subfolder (definitive/, story/, etc.) before running Phase 2.
.PARAMETER RootPath
    Root of your backup directory. Defaults to D:\RocknixBackup
.PARAMETER DownloadsPath
    Path to scan for new ROMs. Defaults to ~/Downloads
.PARAMETER CheatsPath
    RetroArch cheats root (searched recursively across all core subfolders).
    Defaults to C:\RetroArch-Win64\cheats
.PARAMETER DryRun
    If specified, prints what would happen without touching files.
.PARAMETER Force
    Renumber even while Playnite is running. Normally refused: the renames break
    every Playnite ROM path, and the prune/reimport that repairs them needs
    Playnite closed. Ingest-Romhacks passes this, having closed Playnite first.
.EXAMPLE
    .\Organize-Romhacks.ps1
    .\Organize-Romhacks.ps1 -DryRun
    .\Organize-Romhacks.ps1 -RootPath "E:\MyBackup"
#>
param(
    [string]$RootPath      = "D:\RocknixBackup",
    [string]$DownloadsPath = "$env:USERPROFILE\Downloads",
    [string]$CheatsPath    = "C:\RetroArch-Win64\cheats",
    [switch]$DryRun,
    [switch]$SkipIngest,
    [switch]$Force
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
# Renaming ROMs invalidates every Playnite path that points at them. If Playnite
# is open the repair (prune -> reimport -> relink) cannot run afterwards, so the
# library is left pointing at files that no longer exist until someone notices.
# Refuse rather than leave it in that state. -Force overrides, e.g. when the
# caller is Ingest-Romhacks, which has already closed Playnite itself.
if (-not $DryRun -and -not $Force -and (Get-Process -Name 'Playnite*' -ErrorAction SilentlyContinue)) {
    throw "Playnite is running. Renumbering now would leave its library pointing at renamed files, and the prune/reimport that fixes that needs Playnite closed. Exit it (window + tray) and rerun, or pass -Force."
}
$romExtensions  = @("*.gba","*.gb","*.gbc","*.nds","*.z64","*.n64","*.nes","*.sfc","*.smc")
$saveExtensions = @("*.srm","*.sav","*.dsv","*.rtc","*.dss")
if ($DryRun) { Write-Host "[DRY RUN] No files will be changed.`n" -ForegroundColor Yellow }
# --- Collect all roms in any romhacks subfolder ---
# EXCLUDES \OLD\: "*\romhacks\*" matches paths INSIDE romhacks\OLD\ too, since
# OLD is itself a subfolder of romhacks. Without the exclusion this renumbers
# archived/superseded ROMs right along with live ones - churn nobody asked for
# (OLD is meant to be a stable historical record), and the direct cause of a
# real failure: a file freshly archived by Ingest-Romhacks.ps1 got caught by a
# Syncthing scan moments later while this script tried to also rename it.
$allRoms = foreach ($ext in $romExtensions) {
    Get-ChildItem -Path $RootPath -Recurse -Filter $ext |
        Where-Object { $_.FullName -like "*\romhacks\*" -and $_.FullName -notmatch '\\OLD\\' }
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
# Match by SUFFIX, not by a fixed extension list. Two reasons the old
# extension-list approach silently orphaned files:
#   1. savestates were never listed at all (.state, .state1, ...), so every
#      renumber left them pointing at a dead prefix
#   2. PowerShell's BaseName strips only the LAST extension, so
#      "NNN - Game.state.png" had BaseName "NNN - Game.state", which is not a
#      key in $saveMap and never matched
# Anything under romhacks\ that is not itself a ROM and whose name begins with
# a renumbered ROM's basename is a companion file: carry it across verbatim,
# keeping whatever suffix it had.
$romExtSet = $romExtensions | ForEach-Object { $_.TrimStart('*') }
$allSaves = Get-ChildItem -Path $RootPath -Recurse -File |
    Where-Object { $_.FullName -like "*\romhacks\*" -and $_.FullName -notmatch '\\OLD\\' -and $romExtSet -notcontains $_.Extension.ToLower() }
$saveRenamed = 0
$saveSkipped = 0
foreach ($sf in $allSaves) {
    # longest matching ROM basename wins, so "Game" cannot claim "Game 2"'s files
    $oldBase = $saveMap.Keys |
        Where-Object { $sf.Name.Length -gt $_.Length -and $sf.Name.StartsWith("$_.") } |
        Sort-Object Length -Descending | Select-Object -First 1
    if (-not $oldBase) { $saveSkipped++; continue }
    $newSaveName = $saveMap[$oldBase] + $sf.Name.Substring($oldBase.Length)
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
# --- Rename matching RetroArch cheat files (any core subfolder, matched by basename) ---
$allCheats = if (Test-Path $CheatsPath) {
    Get-ChildItem -Path $CheatsPath -Recurse -Filter "*.cht"
} else { @() }
$cheatRenamed = 0
$cheatSkipped = 0
foreach ($cf in $allCheats) {
    $oldBase = $cf.BaseName
    if (-not $saveMap.ContainsKey($oldBase)) { $cheatSkipped++; continue }
    $newCheatName = $saveMap[$oldBase] + $cf.Extension
    if ($cf.Name -eq $newCheatName) { $cheatSkipped++; continue }
    if ($DryRun) {
        Write-Host "  CHEAT [$($cf.Directory.Name)]: $($cf.Name)  ->  $newCheatName"
    } else {
        try {
            Rename-Item -LiteralPath $cf.FullName -NewName $newCheatName -ErrorAction Stop
            $cheatRenamed++
        } catch {
            Write-Host "FAILED: $($cf.Name) -> $newCheatName`n  $_" -ForegroundColor Red
        }
    }
}
# --- Summary ---
Write-Host ""
if ($DryRun) {
    Write-Host "[DRY RUN] Would rename: $($total - $romSkipped) roms, $($allSaves.Count - $saveSkipped) saves, $($allCheats.Count - $cheatSkipped) cheats. $romSkipped roms, $saveSkipped saves, and $cheatSkipped cheats already correct." -ForegroundColor Yellow
} else {
    Write-Host "Done!" -ForegroundColor Green
    Write-Host "  Roms renamed  : $romRenamed  (skipped already-correct: $romSkipped)"
    Write-Host "  Saves renamed : $saveRenamed  (skipped already-correct: $saveSkipped)"
    Write-Host "  Cheats renamed: $cheatRenamed  (skipped already-correct: $cheatSkipped)"
}
