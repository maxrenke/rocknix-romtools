<#
.SYNOPSIS
    Compresses D:\RocknixBackup into a timestamped archive.
.DESCRIPTION
    Builds archive on C:\ (SSD) for speed, then distributes in parallel to
    E:\RocknixBackup_Archives and casaos:/DATA/RocknixBackup_Archives.
    Deletes the C:\ build copy once both transfers finish.
    Keeps the N most recent archives on each destination and prunes older ones.
.PARAMETER DestDir
    Local archive destination. Defaults to E:\RocknixBackup_Archives.
.PARAMETER CasaOSHost
    CasaOS hostname or IP. Defaults to casaos.
.PARAMETER CasaOSPath
    Remote path on CasaOS. Defaults to /DATA/RocknixBackup_Archives.
.PARAMETER Keep
    Number of archives to retain per destination. Default: 3.
.PARAMETER SourcePath
    Root folder to back up. Default: D:\RocknixBackup.
.EXAMPLE
    .\Backup-RocknixBackup.ps1
    .\Backup-RocknixBackup.ps1 -Keep 5
#>
param(
    [string]$SourcePath  = "D:\RocknixBackup",
    [string]$DestDir     = "E:\RocknixBackup_Archives",
    [string]$CasaOSHost  = "casaos",
    [string]$CasaOSPath  = "/DATA/RocknixBackup_Archives",
    [int]   $Keep        = 3,
    [switch]$PullDevices          # pull latest configs from Rocknix devices before backup (devices must be on)
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Banner {
    param([string]$Text)
    $width = 64
    $line  = "=" * $width
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    $pad = [math]::Max(0, [math]::Floor(($width - $Text.Length) / 2))
    Write-Host (" " * $pad + $Text) -ForegroundColor White
    Write-Host $line -ForegroundColor Cyan
}

function Write-Step {
    param([int]$N, [int]$Total, [string]$Text)
    Write-Host ""
    Write-Host "  [$N/$Total] $Text" -ForegroundColor Cyan
    Write-Host "  " + ("-" * 58) -ForegroundColor DarkGray
}

function Write-StepResult {
    param([string]$Text, [string]$Color = "Green")
    Write-Host "         $Text" -ForegroundColor $Color
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "$([math]::Round($Bytes / 1GB, 2)) GB" }
    if ($Bytes -ge 1MB) { return "$([math]::Round($Bytes / 1MB, 1)) MB" }
    return "$([math]::Round($Bytes / 1KB, 0)) KB"
}

function Format-Elapsed {
    param([timespan]$T)
    if ($T.TotalMinutes -ge 1) { return "$([math]::Round($T.TotalMinutes, 1)) min" }
    return "$([math]::Round($T.TotalSeconds, 1)) s"
}

function Draw-Bar {
    param([int]$Pct, [int]$Width = 36)
    $filled = [math]::Round($Pct / 100 * $Width)
    $empty  = $Width - $filled
    $block  = [string][char]0x2588
    return "[" + ($block * $filled) + ("-" * $empty) + "] $Pct%"
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

$sessionStart = Get-Date
Write-Banner "ROCKNIX BACKUP  $(Get-Date -Format 'yyyy-MM-dd  HH:mm:ss')"

# ---------------------------------------------------------------------------
# Find 7-Zip
# ---------------------------------------------------------------------------

$7zPaths = @("7z","C:\Program Files\7-Zip\7z.exe","C:\Program Files (x86)\7-Zip\7z.exe")
$7z = $null
foreach ($p in $7zPaths) {
    if (Get-Command $p -ErrorAction SilentlyContinue) { $7z = $p; break }
}
$ext = if ($7z) { "7z" } else { "zip" }

# ---------------------------------------------------------------------------
# Step 1 - Sync Rocknix device configs
# ---------------------------------------------------------------------------

Write-Step 1 5 "Syncing Rocknix device configs"
$t = Get-Date
if (-not $PullDevices) {
    Write-StepResult "Skipped (devices off by default - use -PullDevices to pull)" "DarkGray"
} else {
    $syncDevice = Join-Path $SourcePath "Sync-DeviceConfigs.py"
    if (Test-Path $syncDevice) {
        $out = python $syncDevice 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-StepResult "Sync errors (continuing):" "Yellow"
            $out | ForEach-Object { Write-StepResult "  $_" "Yellow" }
        } else {
            $pulled  = ($out | Select-String "pulled:").Count
            $skipped = ($out | Select-String "skip").Count
            Write-StepResult "Pulled $pulled file(s) across 2 devices$(if($skipped){", $skipped skipped"})" "Green"
        }
        Write-StepResult "Done in $(Format-Elapsed ((Get-Date) - $t))" "DarkGray"
    } else {
        Write-StepResult "Sync-DeviceConfigs.py not found, skipped." "DarkGray"
    }
}

# ---------------------------------------------------------------------------
# Step 2 - Sync Windows RetroArch
# ---------------------------------------------------------------------------

Write-Step 2 5 "Syncing Windows RetroArch configs and shaders"
$t = Get-Date
$syncWindows = Join-Path $SourcePath "Sync-WindowsRetroArch.ps1"
if (Test-Path $syncWindows) {
    & $syncWindows
    $winBackup   = Join-Path $SourcePath "_windows_retroarch"
    $cfgCount    = (Get-ChildItem "$winBackup\config" -Recurse -Filter "*.cfg" -ErrorAction SilentlyContinue).Count + `
                   (Get-ChildItem $winBackup -Filter "retroarch.cfg" -ErrorAction SilentlyContinue).Count
    $shaderCount = (Get-ChildItem "$winBackup\shaders" -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-StepResult "$cfgCount config file(s) + $shaderCount shader file(s)" "Green"
} else {
    Write-StepResult "Sync-WindowsRetroArch.ps1 not found, skipped." "DarkGray"
}
Write-StepResult "Done in $(Format-Elapsed ((Get-Date) - $t))" "DarkGray"

# ---------------------------------------------------------------------------
# Step 3 - Measure source and build archive on C:\ (SSD)
# ---------------------------------------------------------------------------

Write-Step 3 5 "Building archive on C:\ (SSD)"

$sourceBytes = (Get-ChildItem $SourcePath -Recurse -File -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
Write-StepResult "Source size : $(Format-Bytes $sourceBytes)"

$buildDir  = "C:\Temp\RocknixBackup_Build"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$archiveName = "RocknixBackup_$timestamp"
New-Item -ItemType Directory -Force $buildDir | Out-Null
$buildPath = Join-Path $buildDir "$archiveName.$ext"

$t = Get-Date
$lastPct = -1

if ($7z) {
    Write-Host "         " -NoNewline
    & $7z a -t7z -mx=5 -ms=on -mmt=on -bsp1 "$buildPath" "$SourcePath\*" 2>&1 |
        ForEach-Object {
            if ($_ -match "^\s*(\d+)%") {
                $pct = [int]$Matches[1]
                if ($pct -ne $lastPct) {
                    $lastPct = $pct
                    $bar     = Draw-Bar $pct
                    $elapsed = Format-Elapsed ((Get-Date) - $t)
                    Write-Progress -Activity "Compressing" -Status "$bar  $elapsed elapsed" -PercentComplete $pct
                }
            }
        }
    Write-Progress -Activity "Compressing" -Completed
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  7-Zip failed (exit $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }
} else {
    Write-StepResult "7-Zip not found - falling back to ZIP (install 7-Zip for better compression)" "Yellow"
    Write-Progress -Activity "Compressing" -Status "Working..." -PercentComplete 0
    Compress-Archive -Path "$SourcePath\*" -DestinationPath $buildPath -CompressionLevel Optimal -Force
    Write-Progress -Activity "Compressing" -Completed
}

$buildElapsed = (Get-Date) - $t
$archiveBytes = (Get-Item $buildPath).Length
$ratio        = if ($sourceBytes -gt 0) { [math]::Round((1 - $archiveBytes / $sourceBytes) * 100, 1) } else { 0 }

Write-StepResult "Archive     : $(Format-Bytes $archiveBytes)  ($ratio% smaller)" "Green"
Write-StepResult "Built in    : $(Format-Elapsed $buildElapsed)" "DarkGray"

# ---------------------------------------------------------------------------
# Step 4 - Distribute in parallel: E:\ and CasaOS
# ---------------------------------------------------------------------------

Write-Step 4 5 "Distributing in parallel"
Write-StepResult "E:\$((Split-Path $DestDir -Leaf))  +  ${CasaOSHost}:${CasaOSPath}"

New-Item -ItemType Directory -Force $DestDir | Out-Null

$t = Get-Date

$jobE = Start-Job -Name "CopyE" -ScriptBlock {
    param($src, $dst, $name)
    Copy-Item -LiteralPath $src -Destination (Join-Path $dst $name) -Force
} -ArgumentList $buildPath, $DestDir, "$archiveName.$ext"

$jobCasa = Start-Job -Name "CopyCasa" -ScriptBlock {
    param($src, $host_, $remotePath, $name)
    ssh $host_ "mkdir -p '$remotePath'" 2>&1 | Out-Null
    scp -o "Compression no" -c chacha20-poly1305@openssh.com $src "${host_}:${remotePath}/${name}" 2>&1
} -ArgumentList $buildPath, $CasaOSHost, $CasaOSPath, "$archiveName.$ext"

$spinFrames = @("|", "/", "-", "\")
$spinIdx    = 0
$doneE      = $false
$doneCasa   = $false
$timeE      = $null
$timeCasa   = $null

while (-not ($doneE -and $doneCasa)) {
    Start-Sleep -Milliseconds 400
    $spinIdx = ($spinIdx + 1) % 4
    $spin    = $spinFrames[$spinIdx]
    $elapsed = Format-Elapsed ((Get-Date) - $t)

    $stE    = (Get-Job -Name "CopyE").State
    $stCasa = (Get-Job -Name "CopyCasa").State

    if ($stE -eq "Completed" -and -not $doneE) {
        $doneE = $true
        $timeE = Format-Elapsed ((Get-Date) - $t)
    }
    if ($stCasa -eq "Completed" -and -not $doneCasa) {
        $doneCasa = $true
        $timeCasa = Format-Elapsed ((Get-Date) - $t)
    }

    $lineE    = if ($doneE)    { "  [E:\]     $(Draw-Bar 100)  $timeE" }
                else           { "  [E:\]     $spin  $elapsed elapsed" }
    $lineCasa = if ($doneCasa) { "  [casaos]  $(Draw-Bar 100)  $timeCasa" }
                else           { "  [casaos]  $spin  $elapsed elapsed" }

    Write-Progress -Id 1 -Activity "E:\ copy"    -Status $lineE    -PercentComplete $(if ($doneE)    {100} else {50})
    Write-Progress -Id 2 -Activity "CasaOS copy" -Status $lineCasa -PercentComplete $(if ($doneCasa) {100} else {50})
}

Write-Progress -Id 1 -Activity "E:\ copy"    -Completed
Write-Progress -Id 2 -Activity "CasaOS copy" -Completed

# Check for errors
$errE    = Receive-Job -Name "CopyE"    2>&1
$errCasa = Receive-Job -Name "CopyCasa" 2>&1
Remove-Job -Name "CopyE","CopyCasa"

$transferElapsed = (Get-Date) - $t

if ($errE)    { Write-StepResult "E:\ warning: $errE" "Yellow" }
if ($errCasa) { Write-StepResult "CasaOS warning: $errCasa" "Yellow" }

Write-StepResult "E:\      -> $timeE" "Green"
Write-StepResult "CasaOS   -> $timeCasa" "Green"
Write-StepResult "Both transfers done in $(Format-Elapsed $transferElapsed)" "DarkGray"

# ---------------------------------------------------------------------------
# Delete build copy from C:\
# ---------------------------------------------------------------------------

Remove-Item -LiteralPath $buildPath -Force
Write-StepResult "Build copy deleted from C:\." "DarkGray"

# ---------------------------------------------------------------------------
# Step 5 - Prune old archives
# ---------------------------------------------------------------------------

Write-Step 5 5 "Pruning old archives (keeping $Keep per destination)"

# E:\
$oldE = Get-ChildItem $DestDir -Filter "RocknixBackup_*.$ext" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Keep

if ($oldE) {
    foreach ($f in $oldE) {
        Remove-Item $f.FullName -Force
    }
    Write-StepResult "E:\      pruned $($oldE.Count) archive(s)" "DarkYellow"
} else {
    Write-StepResult "E:\      nothing to prune" "DarkGray"
}

# CasaOS
$pruneScript = "ls ${CasaOSPath}/RocknixBackup_*.${ext} 2>/dev/null | sort -r | tail -n +$($Keep + 1) | xargs -r rm --"
ssh $CasaOSHost $pruneScript 2>&1 | Out-Null
$remoteCount = [int](ssh $CasaOSHost "ls ${CasaOSPath}/RocknixBackup_*.${ext} 2>/dev/null | wc -l" 2>$null)
Write-StepResult "CasaOS   $remoteCount archive(s) retained" "DarkGray"

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------

$totalElapsed = (Get-Date) - $sessionStart
Write-Banner "COMPLETE"
Write-Host ""
Write-Host ("  {0,-14} {1}" -f "Archive",  "$archiveName.$ext") -ForegroundColor White
Write-Host ("  {0,-14} {1}" -f "Source",   "$(Format-Bytes $sourceBytes)") -ForegroundColor White
Write-Host ("  {0,-14} {1}" -f "Compressed","$(Format-Bytes $archiveBytes)  ($ratio% smaller)") -ForegroundColor Green
Write-Host ("  {0,-14} {1}" -f "Build time", $(Format-Elapsed $buildElapsed)) -ForegroundColor White
Write-Host ("  {0,-14} {1}" -f "Total time", $(Format-Elapsed $totalElapsed)) -ForegroundColor White
Write-Host ("  {0,-14} {1}" -f "Local",    $DestDir) -ForegroundColor DarkGray
Write-Host ("  {0,-14} {1}" -f "Remote",   "${CasaOSHost}:${CasaOSPath}") -ForegroundColor DarkGray
Write-Host ""
Write-Host ("  " + "=" * 60) -ForegroundColor Cyan
Write-Host ""
