<#
.SYNOPSIS
    Snapshots Windows RetroArch configs, playlists, core options, and handheld shaders
    into a local backup folder.
.PARAMETER RetroArchPath
    RetroArch installation folder. Default: C:\RetroArch-Win64
.PARAMETER BackupRoot
    Destination folder for the snapshot. Default: _windows_retroarch\ next to this script.
#>
param(
    [string]$RetroArchPath = "C:\RetroArch-Win64",
    [string]$BackupRoot    = (Join-Path $PSScriptRoot "_windows_retroarch")
)

if (-not (Test-Path $RetroArchPath)) {
    Write-Host "RetroArch not found at $RetroArchPath" -ForegroundColor Red
    exit 1
}

$counts = @{ copied = 0; skipped = 0 }

function Sync-File {
    param([string]$Src, [string]$Dst, [string]$Label)
    if (Test-Path -LiteralPath $Src) {
        New-Item -ItemType Directory -Force (Split-Path $Dst) | Out-Null
        Copy-Item -LiteralPath $Src -Destination $Dst -Force
        Write-Host "  copied: $Label"
        $script:counts.copied++
    } else {
        Write-Host "  skip (not found): $Label" -ForegroundColor DarkGray
        $script:counts.skipped++
    }
}

# retroarch.cfg
Sync-File (Join-Path $RetroArchPath "retroarch.cfg") `
          (Join-Path $BackupRoot "retroarch.cfg") "retroarch.cfg"

# All core .cfg and .opt files under config\
$srcConfig = Join-Path $RetroArchPath "config"
$dstConfig = Join-Path $BackupRoot "config"
if (Test-Path $srcConfig) {
    Get-ChildItem $srcConfig -Recurse -Include "*.cfg","*.opt" | ForEach-Object {
        $rel = $_.FullName.Substring($srcConfig.Length + 1)
        Sync-File $_.FullName (Join-Path $dstConfig $rel) "config\$rel"
    }
}

# All playlists
$srcPlaylists = Join-Path $RetroArchPath "playlists"
$dstPlaylists = Join-Path $BackupRoot "playlists"
if (Test-Path $srcPlaylists) {
    New-Item -ItemType Directory -Force $dstPlaylists | Out-Null
    Get-ChildItem $srcPlaylists -Filter "*.lpl" | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dstPlaylists $_.Name) -Force
        Write-Host "  copied: playlists\$($_.Name)"
        $counts.copied++
    }
}

# Handheld shader tree
$srcShaders = Join-Path $RetroArchPath "shaders\shaders_slang\handheld"
$dstParent  = Join-Path $BackupRoot "shaders\shaders_slang"
if (Test-Path $srcShaders) {
    New-Item -ItemType Directory -Force $dstParent | Out-Null
    Copy-Item -Path $srcShaders -Destination $dstParent -Recurse -Force
    $shaderCount = (Get-ChildItem (Join-Path $dstParent "handheld") -Recurse -File).Count
    Write-Host "  copied: shaders\shaders_slang\handheld\ ($shaderCount files)"
    $counts.copied++
} else {
    Write-Host "  skip (not found): shaders_slang\handheld" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Windows RetroArch backup complete -> $BackupRoot" -ForegroundColor Green
Write-Host "  $($counts.copied) item(s) copied, $($counts.skipped) skipped"
