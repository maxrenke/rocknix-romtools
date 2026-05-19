<#
.SYNOPSIS
    Removes older duplicate versions of romhacks, keeping the newest version.
    Matches by base name (ignoring version numbers), compares version strings,
    and falls back to file modification time for undated dupes.
#>
$rootPath = "D:\RocknixBackup"
$romExtensions = @(".gba",".gb",".gbc",".nds",".z64",".n64",".nes")
$saveExtensions = @(".srm",".sav",".dsv",".rtc",".dss")
# -----------------------------------------------------------------------
# Helper: strip prefix, extension, version info to get a "base key"
# -----------------------------------------------------------------------
function Get-BaseKey($filename) {
    # Remove NNN_ prefix
    $name = $filename -replace "^\d{3}_", ""
    # Remove extension
    $name = [System.IO.Path]::GetFileNameWithoutExtension($name)
    # Normalize: remove version patterns like v1.2.3, V1.2, (1.0), 1.3.2a, v2.0.1-EX,
    # beta/demo labels, dates like 20251221, 31-01-23, etc.
    $name = $name -replace "\s*[\(\[]?v?\d+[\.\d\-]*[a-z]?[\)\]]?", ""
    $name = $name -replace "\s*(beta|demo|alpha|rc)\s*\d*", ""
    $name = $name -replace "\s*\d{6,8}", ""        # strip standalone dates
    $name = $name -replace "\s*\(if\(\)\.+\)", ""  # strip weird (if().) suffixes
    $name = $name -replace "\s*\[.*?\]", ""
    $name = $name -replace "[\s_\-]+$", ""         # trailing spaces/dashes
    $name = $name.Trim() -replace "\s+", " "
    return $name.ToLower()
}
# -----------------------------------------------------------------------
# Helper: extract a comparable version tuple from filename
# Returns array of ints for comparison, or $null if none found
# -----------------------------------------------------------------------
function Get-VersionTuple($filename) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($filename)
    # Date pattern: (D-M-YY) or (DD-M-YY) or (DD-M-YY-rev) e.g. (1-4-26), (10-2-26-2)
    if ($name -match "\((\d{1,2})-(\d{1,2})-(\d{2})(?:-(\d+))?\)") {
        $day = [int]$Matches[1]; $mon = [int]$Matches[2]; $yr = [int]$Matches[3]
        $rev = if ($Matches[4]) { [int]$Matches[4] } else { 0 }
        if ($day -ge 1 -and $day -le 31 -and $mon -ge 1 -and $mon -le 12 -and $yr -ge 20 -and $yr -le 40) {
            $fullYr = 2000 + $yr
            return [int[]]@($fullYr, $mon, $day, $rev)
        }
    }
    # Standard version patterns: v1.2.3, 1.2.3, (1.0.10), 2.4.2, etc.
    if ($name -match "v?(\d+)[\.\-](\d+)[\.\-](\d+)[\.\-]?(\d*)") {
        return [int[]]@([int]$Matches[1],[int]$Matches[2],[int]$Matches[3],[int]($Matches[4] -replace "^$","0"))
    }
    if ($name -match "v?(\d+)[\.\-](\d+)") {
        return [int[]]@([int]$Matches[1],[int]$Matches[2],0,0)
    }
    if ($name -match "v(\d+)\b") {
        return [int[]]@([int]$Matches[1],0,0,0)
    }
    return $null
}
# -----------------------------------------------------------------------
# Helper: compare two version tuples; return 1 if a > b, -1 if a < b, 0 if equal
# -----------------------------------------------------------------------
function Compare-Versions($a, $b) {
    if ($null -eq $a -and $null -eq $b) { return 0 }
    if ($null -eq $a) { return -1 }
    if ($null -eq $b) { return 1 }
    for ($i = 0; $i -lt 4; $i++) {
        if ($a[$i] -gt $b[$i]) { return 1 }
        if ($a[$i] -lt $b[$i]) { return -1 }
    }
    return 0
}
# -----------------------------------------------------------------------
# Collect all romhack rom files
# -----------------------------------------------------------------------
$allRoms = Get-ChildItem -Path $rootPath -Recurse |
    Where-Object {
        $_.FullName -like "*\romhacks\*" -and
        $romExtensions -contains $_.Extension.ToLower() -and
        $_.Name -notlike "*.sync-conflict*"
    }
Write-Host "Found $($allRoms.Count) romhack files across all systems.`n"
# -----------------------------------------------------------------------
# Group by (system folder + base key)
# -----------------------------------------------------------------------
$groups = @{}
foreach ($rom in $allRoms) {
    $parts        = $rom.FullName -split "\\romhacks\\"
    $systemFolder = $parts[0] | Split-Path -Leaf
    $subFolder    = ($parts[1] -split "\\")[0]   # e.g. "definitive", "story"
    $baseKey = "$systemFolder|$subFolder|$(Get-BaseKey $rom.Name)"
    if (-not $groups.ContainsKey($baseKey)) { $groups[$baseKey] = @() }
    $groups[$baseKey] += $rom
}
$toDelete = [System.Collections.Generic.List[object]]::new()
$keepLog  = [System.Collections.Generic.List[object]]::new()
foreach ($key in ($groups.Keys | Sort-Object)) {
    $group = $groups[$key]
    if ($group.Count -lt 2) { continue }   # no dupe, skip
    # Pick the winner: highest version number, else most recent LastWriteTime
    $winner = $group[0]
    $winnerVer = Get-VersionTuple $winner.Name
    foreach ($rom in $group[1..($group.Count-1)]) {
        $romVer = Get-VersionTuple $rom.Name
        $cmp = Compare-Versions $romVer $winnerVer
        if ($cmp -gt 0) {
            $winner    = $rom
            $winnerVer = $romVer
        } elseif ($cmp -eq 0) {
            # Same version string or no version ΓÇö pick newer file
            if ($rom.LastWriteTime -gt $winner.LastWriteTime) {
                $winner    = $rom
                $winnerVer = $romVer
            }
        }
    }
    $losers = $group | Where-Object { $_.FullName -ne $winner.FullName }
    foreach ($l in $losers) { $toDelete.Add($l) }
    $keepLog.Add([PSCustomObject]@{
        System    = ($key -split "\|")[0]
        SubFolder = ($key -split "\|")[1]
        BaseKey   = ($key -split "\|")[2]
        Kept      = $winner.Name
        Removed   = ($losers | ForEach-Object { $_.Name }) -join " | "
    })
}
# -----------------------------------------------------------------------
# Also catch sync-conflict files and .filepart files
# -----------------------------------------------------------------------
$junkFiles = Get-ChildItem -Path $rootPath -Recurse |
    Where-Object { $_.Name -like "*.sync-conflict*" -or $_.Name -like "*.filepart" }
foreach ($j in $junkFiles) { $toDelete.Add($j) }
# -----------------------------------------------------------------------
# Print breakdown
# -----------------------------------------------------------------------
Write-Host "========== DUPLICATE ROMHACKS TO REMOVE ==========" -ForegroundColor Cyan
foreach ($entry in ($keepLog | Sort-Object System, SubFolder, BaseKey)) {
    Write-Host ""
    Write-Host "  [$($entry.System.ToUpper()) > $($entry.SubFolder)]  $($entry.BaseKey)" -ForegroundColor Yellow
    Write-Host "    KEEP   : $($entry.Kept)" -ForegroundColor Green
    foreach ($r in $entry.Removed -split " \| ") {
        Write-Host "    REMOVE : $r" -ForegroundColor Red
    }
}
if ($junkFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "========== SYNC-CONFLICT / JUNK FILES ==========" -ForegroundColor Cyan
    foreach ($j in $junkFiles) {
        Write-Host "  REMOVE : $($j.Name)" -ForegroundColor Red
    }
}
Write-Host ""
Write-Host "========== SUMMARY ==========" -ForegroundColor Cyan
Write-Host "  Duplicate rom groups found : $($keepLog.Count)"
Write-Host "  Total files to delete      : $($toDelete.Count)"
Write-Host ""
# -----------------------------------------------------------------------
# Delete
# -----------------------------------------------------------------------
$deleted = 0
$failed  = 0
foreach ($f in $toDelete) {
    # Also remove matching save file if it exists (same base name)
    $dir = $f.DirectoryName
    $base = $f.BaseName
    foreach ($saveExt in $saveExtensions) {
        $savePath = Join-Path $dir "$base$saveExt"
        if (Test-Path -LiteralPath $savePath) {
            try {
                Remove-Item -LiteralPath $savePath -Force
                Write-Host "  Deleted save: $(Split-Path $savePath -Leaf)" -ForegroundColor DarkGray
            } catch {
                Write-Host "  FAILED save: $savePath`n  $_" -ForegroundColor Red
            }
        }
    }
    try {
        Remove-Item -LiteralPath $f.FullName -Force
        Write-Host "  Deleted: $($f.Name)" -ForegroundColor DarkGray
        $deleted++
    } catch {
        Write-Host "  FAILED: $($f.Name)`n  $_" -ForegroundColor Red
        $failed++
    }
}
Write-Host ""
Write-Host "Deleted $deleted files. Failed: $failed." -ForegroundColor $(if ($failed -eq 0) {"Green"} else {"Red"})
