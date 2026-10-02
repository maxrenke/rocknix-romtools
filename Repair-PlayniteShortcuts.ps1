<#
.SYNOPSIS
    Repoints Playnite desktop shortcuts (.url) at the current Playnite GUIDs.

.DESCRIPTION
    Playnite launch shortcuts embed a game GUID:
        URL=playnite://playnite/start/<guid>
    The romhack pipeline deletes and re-imports Playnite entries whenever ROMs are
    renumbered, which mints fresh GUIDs. Any existing shortcut then points at a
    deleted entry and silently does nothing when clicked - the file still looks fine.

    This script matches each .url by its FILENAME to a live rom-catalog.html entry of
    the same name, and rewrites the GUID to that entry's current pnid. Only the GUID
    is touched; IconFile/IconIndex and any other keys are preserved byte-for-byte.

    Run it AFTER Update-CatalogPlayniteLinks.ps1, so the catalog pnids are current.

    Shortcuts whose name matches no live catalog entry are reported and left alone,
    so hand-made shortcuts to non-romhack games are never clobbered.

.PARAMETER Catalog    rom-catalog.html. Default <script dir>\rom-catalog.html
.PARAMETER Paths      Directories to scan. Default: Desktop, OneDrive\Desktop, Public Desktop
.PARAMETER DryRun     Report what would change; write nothing.

.EXAMPLE
    .\Repair-PlayniteShortcuts.ps1 -DryRun
    .\Repair-PlayniteShortcuts.ps1
#>
[CmdletBinding()]
param(
    [string]$Catalog = "",
    [string[]]$Paths = @(),
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
if (-not $Catalog) { $Catalog = Join-Path $PSScriptRoot 'rom-catalog.html' }
if (-not $Paths -or $Paths.Count -eq 0) {
    $Paths = @(
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'OneDrive\Desktop'),
        (Join-Path $env:PUBLIC 'Desktop')
    )
}

# ---- build name -> current pnid from live catalog entries ----
$html = [IO.File]::ReadAllText($Catalog)
$map = @{}
foreach ($m in [regex]::Matches($html, '\{num:\d+,[^{}]*\}')) {
    $o = $m.Value
    $status = ([regex]'status:"([^"]*)"').Match($o).Groups[1].Value
    if ($status -eq 'old') { continue }
    $pnid = ([regex]'pnid:"([^"]*)"').Match($o).Groups[1].Value
    if (-not $pnid) { continue }
    $name = ([regex]'name:"([^"]*)"').Match($o).Groups[1].Value
    if ($name) { $map[$name] = $pnid }
}
if ($map.Count -eq 0) { Write-Warning "No live catalog entries with a pnid - run Update-CatalogPlayniteLinks.ps1 first."; return }

$fixed = 0; $ok = 0; $skipped = 0
foreach ($dir in ($Paths | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter *.url -File -ErrorAction SilentlyContinue) {
        $raw = [IO.File]::ReadAllText($f.FullName)
        $m = [regex]::Match($raw, 'playnite://playnite/start/([0-9a-fA-F-]{36})')
        if (-not $m.Success) { continue }   # not a Playnite shortcut

        $name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
        if (-not $map.ContainsKey($name)) {
            Write-Host ("  SKIP  {0}  (no live catalog entry named '{1}')" -f $f.Name, $name) -ForegroundColor DarkYellow
            $skipped++; continue
        }
        $want = $map[$name]
        if ($m.Groups[1].Value -eq $want) { $ok++; continue }

        if ($DryRun) {
            Write-Host ("  WOULD FIX {0}`n            {1} -> {2}" -f $f.Name, $m.Groups[1].Value, $want) -ForegroundColor Yellow
        } else {
            # replace only the GUID; leave IconFile/IconIndex and formatting untouched
            $new = $raw.Remove($m.Groups[1].Index, 36).Insert($m.Groups[1].Index, $want)
            [IO.File]::WriteAllText($f.FullName, $new)
            Write-Host ("  FIXED {0}`n          {1} -> {2}" -f $f.Name, $m.Groups[1].Value, $want) -ForegroundColor Green
        }
        $fixed++
    }
}

if ($DryRun) {
    Write-Host "[DRY RUN] Would repoint $fixed shortcut(s). $ok already current, $skipped unmatched." -ForegroundColor Yellow
} else {
    Write-Host "Shortcuts repointed: $fixed   (already current: $ok, unmatched: $skipped)"
}
