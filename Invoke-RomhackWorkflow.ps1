<#
.SYNOPSIS
    End-to-end Rocknix romhack -> Playnite workflow. Runs the sub-scripts in order, with status
    output and y/n prompts before each step:
        1. Import romhacks into Playnite        (Import-RomhacksToPlaynite.ps1)
        2. Link catalog Play buttons to GUIDs   (Update-CatalogPlayniteLinks.ps1)
        3. Assign Definitive/Roguelike/Picks     (Set-PlayniteRomhackCategories.ps1)
        4. Build Rocknix collection lists        (Build-RocknixCollections.ps1)
        5. Repoint Playnite desktop shortcuts    (Repair-PlayniteShortcuts.ps1)
        6. Backup catalog to OneDrive            (Backup-Catalog.ps1)
    All steps need Playnite closed; the script waits for you to exit it.

    Step 5 exists because step 1 deletes and re-imports Playnite entries, minting new
    GUIDs. Any .url desktop shortcut then points at a dead entry and silently does
    nothing when clicked. It must run after step 2, which refreshes the catalog pnids
    the repair reads from.

.PARAMETER All          Run every step without prompting.
.PARAMETER IncludeOld   Passed to the importer: also import superseded OLD\ ROMs.
.PARAMETER DryRunImport Passed to the importer: preview only, no DB writes.
#>
[CmdletBinding()]
param(
    [switch]$All,
    [switch]$IncludeOld,
    [switch]$DryRunImport
)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
function Ask([string]$q) { if ($All) { return $true }; return ((Read-Host "$q [Y/n]") -notmatch '^\s*[nN]') }
function Banner([string]$t) { Write-Host "`n==== $t ====" -ForegroundColor Cyan }

# ---- ensure Playnite is closed ----
while (Get-Process -Name 'Playnite*' -ErrorAction SilentlyContinue) {
  Read-Host "Playnite is running. Fully exit it (window + tray), then press Enter"
}

Banner "Rocknix romhack -> Playnite workflow"

if (Ask "Step 1/6: Import romhacks into Playnite?") {
  Banner "1/6 Import"
  $a = @{}; if ($IncludeOld) { $a.IncludeOld = $true }; if ($DryRunImport) { $a.DryRun = $true }
  & "$dir\Import-RomhacksToPlaynite.ps1" @a
}

if (Ask "Step 2/6: Link catalog Play buttons to Playnite (pnid)?") {
  Banner "2/6 Link catalog"
  & "$dir\Update-CatalogPlayniteLinks.ps1"
}

if (Ask "Step 3/6: Assign Definitive/Roguelike/Picks categories?") {
  Banner "3/6 Categories"
  & "$dir\Set-PlayniteRomhackCategories.ps1"
}

if (Ask "Step 4/6: Build Rocknix collection lists (Picks/Play Order/Roguelike/Favorites)?") {
  Banner "4/6 Rocknix collections"
  & "$dir\Build-RocknixCollections.ps1"
}

if (Ask "Step 5/6: Repoint Playnite desktop shortcuts to current GUIDs?") {
  Banner "5/6 Repair shortcuts"
  & "$dir\Repair-PlayniteShortcuts.ps1"
}

if (Ask "Step 6/6: Back up the catalog to OneDrive?") {
  Banner "6/6 Backup"
  & "$dir\Backup-Catalog.ps1"
}

Banner "Workflow complete"
Write-Host "Reopen Playnite to see the imported games, categories, and use the catalog's Play buttons." -ForegroundColor Green
