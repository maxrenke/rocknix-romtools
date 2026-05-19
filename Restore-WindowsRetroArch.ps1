<#
.SYNOPSIS
    Restores Windows RetroArch configs and handheld shaders from _windows_retroarch\.
    Run this after a fresh RetroArch install on a new Windows machine.
.PARAMETER RetroArchPath
    RetroArch installation folder. Default: C:\RetroArch-Win64
.EXAMPLE
    .\Restore-WindowsRetroArch.ps1
    .\Restore-WindowsRetroArch.ps1 -RetroArchPath "D:\RetroArch"
#>
param(
    [string]$RetroArchPath = "C:\RetroArch-Win64"
)

$BackupRoot = Join-Path $PSScriptRoot "_windows_retroarch"

if (-not (Test-Path $BackupRoot)) {
    Write-Host "No backup found at $BackupRoot" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $RetroArchPath)) {
    Write-Host "RetroArch not found at $RetroArchPath" -ForegroundColor Red
    Write-Host "Install RetroArch first, then re-run this script."
    exit 1
}

# retroarch.cfg
$src = Join-Path $BackupRoot "retroarch.cfg"
$dst = Join-Path $RetroArchPath "retroarch.cfg"
if (Test-Path -LiteralPath $src) {
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "  restored: retroarch.cfg"
}

# Core override configs
foreach ($core in @("mGBA", "Gambatte", "DeSmuME")) {
    $src = Join-Path $BackupRoot "config\$core\$core.cfg"
    $dst = Join-Path $RetroArchPath "config\$core\$core.cfg"
    if (Test-Path -LiteralPath $src) {
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Host "  restored: config\$core\$core.cfg"
    }
}

# Handheld shader tree
$srcShaders = Join-Path $BackupRoot "shaders\shaders_slang\handheld"
$dstShaders = Join-Path $RetroArchPath "shaders\shaders_slang"
if (Test-Path $srcShaders) {
    New-Item -ItemType Directory -Force $dstShaders | Out-Null
    Copy-Item -Path $srcShaders -Destination $dstShaders -Recurse -Force
    $count = (Get-ChildItem (Join-Path $dstShaders "handheld") -Recurse -File).Count
    Write-Host "  restored: shaders\shaders_slang\handheld\ ($count files)"
}

Write-Host ""
Write-Host "Restore complete." -ForegroundColor Green
Write-Host "Tip: launch RetroArch once before restoring so its default config is in place."
