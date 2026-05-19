<#
.SYNOPSIS
    Full romhack maintenance pipeline: ingest, cleanup, normalize, renumber.
.DESCRIPTION
    Runs the five maintenance scripts in the correct order:

    STEP 1 - Organize-Romhacks.ps1
        Ingests new ROMs from Downloads into the correct system folder,
        then renumbers all romhack files by creation date.

    STEP 2 - Cleanup-Romhacks.ps1
        Removes older duplicate versions, keeping the newest per hack.
        Also removes sync-conflict and junk files.

    STEP 3 - Normalize-Romhacks.ps1
        Cleans filenames, applies [TAG] classifications, standardises
        version strings, and renames save files to match.

    STEP 4 - Organize-Romhacks.ps1 (renumber only)
        Re-runs renumbering so any renames from Step 3 get clean prefixes.

    STEP 5 - Sync-InProgress.ps1
        Moves ROMs with save files into in-progress/ subfolders.
        Moves ROMs back when their save is deleted (game completed).

    After Step 1, if any new ROMs landed in a romhacks/ root folder you
    should move them into the correct subfolder (definitive/, story/, etc.)
    before continuing - the script will pause and prompt you to do so.
.PARAMETER RootPath
    Root of your backup directory. Defaults to D:\RocknixBackup
.PARAMETER DownloadsPath
    Path to scan for new ROMs. Defaults to ~/Downloads
.PARAMETER DryRun
    Preview all steps without touching any files.
.PARAMETER SkipIngest
    Skip Step 1 Downloads intake (still runs renumber). Use when you have
    no new downloads and just want to clean/normalize existing files.
.EXAMPLE
    .\Update-Romhacks.ps1
    .\Update-Romhacks.ps1 -DryRun
    .\Update-Romhacks.ps1 -SkipIngest
#>
param(
    [string]$RootPath      = "D:\RocknixBackup",
    [string]$DownloadsPath = "$env:USERPROFILE\Downloads",
    [switch]$DryRun,
    [switch]$SkipIngest
)

$here = $PSScriptRoot

function Write-Banner([string]$Label) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host "  $Label" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkGray
}

if ($DryRun) {
    Write-Host "[DRY RUN] No files will be changed in any step.`n" -ForegroundColor Yellow
}

# --- STEP 1: Ingest + renumber ---
Write-Banner "STEP 1 - Ingest from Downloads + Renumber"
& "$here\Organize-Romhacks.ps1" -RootPath $RootPath -DownloadsPath $DownloadsPath -DryRun:$DryRun -SkipIngest:$SkipIngest

# --- Pause after ingest so user can categorize new files into subfolders ---
if (-not $DryRun -and -not $SkipIngest) {
    $newInRoot = @("gba","gbc","gb","nds","n64","nes","snes") | ForEach-Object {
        Get-ChildItem "$RootPath\$_\romhacks" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @(".gba",".gb",".gbc",".nds",".z64",".n64",".nes",".sfc",".smc") }
    }
    if ($newInRoot) {
        Write-Host ""
        Write-Host "  New ROMs are sitting in a romhacks/ root (not yet in a subfolder):" -ForegroundColor Yellow
        $newInRoot | ForEach-Object { Write-Host "    $($_.FullName)" -ForegroundColor Yellow }
        Write-Host ""
        Write-Host "  Move them into the correct subfolder (definitive/, story/, etc.)," -ForegroundColor Yellow
        Write-Host "  then press Enter to continue with cleanup and normalize." -ForegroundColor Yellow
        Read-Host "  Press Enter when ready"
    }
}

# --- STEP 2: Cleanup duplicates ---
Write-Banner "STEP 2 - Cleanup Duplicates"
& "$here\Cleanup-Romhacks.ps1"

# --- STEP 3: Normalize filenames ---
Write-Banner "STEP 3 - Normalize Filenames"
& "$here\Normalize-Romhacks.ps1" -RootPath $RootPath -DryRun:$DryRun

# --- STEP 4: Re-renumber after normalize renames ---
Write-Banner "STEP 4 - Re-Renumber After Normalize"
& "$here\Organize-Romhacks.ps1" -RootPath $RootPath -DownloadsPath $DownloadsPath -DryRun:$DryRun -SkipIngest

# --- STEP 5: Sync in-progress folders ---
Write-Banner "STEP 5 - Sync In-Progress"
& "$here\Sync-InProgress.ps1" -RootPath $RootPath -DryRun:$DryRun

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  All steps complete." -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor DarkGray
