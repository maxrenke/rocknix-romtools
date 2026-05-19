<#
.SYNOPSIS
    Fetches the latest ROM hacks from hackdex.app, lets you pick which to download,
    places them in the correct D:\RocknixBackup\[system]\romhacks\ folder,
    and runs Organize-Romhacks.ps1 to renumber everything.
.PARAMETER Count
    Number of entries to show per sort page (default: 10).
.PARAMETER RootPath
    Root of your backup directory (default: D:\RocknixBackup).
.PARAMETER DryRun
    Preview only - no downloads, moves, or renaming.
.PARAMETER DumpHtml
    Print raw fetched HTML from both discover URLs and exit. Use this to
    inspect what was actually returned if parsing yields no results.
.PARAMETER LocalHtmlUpdated
    Path to a local HTML file for the "sort=updated" page. Use this when the
    site blocks automated requests. Workflow:
      1. Open https://www.hackdex.app/discover?sort=updated in your browser
      2. Press F12 -> Console -> type:  copy(document.documentElement.outerHTML)
      3. Paste into a file, e.g. updated.html
      4. Pass that file via -LocalHtmlUpdated updated.html
.PARAMETER LocalHtmlNew
    Path to a local HTML file for the "sort=new" page (same workflow as above).
.EXAMPLE
    .\Get-Romhacks.ps1
    .\Get-Romhacks.ps1 -Count 15
    .\Get-Romhacks.ps1 -DryRun
    .\Get-Romhacks.ps1 -DumpHtml
    .\Get-Romhacks.ps1 -LocalHtmlUpdated updated.html -LocalHtmlNew new.html
    .\Get-Romhacks.ps1 -LocalHtmlUpdated updated.html   # just one page is fine
#>
param(
    [int]    $Count             = 10,
    [string] $RootPath          = "D:\RocknixBackup",
    [switch] $DryRun,
    [switch] $DumpHtml,
    [string] $LocalHtmlUpdated  = "",
    [string] $LocalHtmlNew      = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$DiscoverUrls = @(
    "https://www.hackdex.app/discover?sort=updated",
    "https://www.hackdex.app/discover?sort=new"
)

$ExtToSystem = @{
    ".gba" = "gba"
    ".gb"  = "gb"
    ".gbc" = "gbc"
    ".nds" = "nds"
    ".z64" = "n64"
    ".n64" = "n64"
    ".nes" = "nes"
    ".sfc" = "snes"
    ".smc" = "snes"
    ".md"  = "genesis"
    ".gen" = "genesis"
    ".smd" = "genesis"
}

$RomExts     = @(".gba",".gb",".gbc",".nds",".z64",".n64",".nes",".sfc",".smc",".md",".gen",".smd")
$ArchiveExts = @(".zip",".rar",".7z")
$UserAgent   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

$script:SpaDetected  = $false
$script:ParseFailed  = $false

# ---------------------------------------------------------------------------
# Helper: HTML-decode common entities
# ---------------------------------------------------------------------------
function ConvertFrom-HtmlEntities([string]$text) {
    $text = $text -replace "&amp;",  "&"
    $text = $text -replace "&lt;",   "<"
    $text = $text -replace "&gt;",   ">"
    $text = $text -replace "&quot;", '"'
    $text = $text -replace "&#39;",  "'"
    $text = $text -replace "&nbsp;", " "
    $text = [System.Text.RegularExpressions.Regex]::Replace($text, "&#(\d+);", {
        param($m) [char][int]$m.Groups[1].Value
    })
    return $text.Trim()
}

# ---------------------------------------------------------------------------
# Helper: strip HTML tags
# ---------------------------------------------------------------------------
function Remove-HtmlTags([string]$html) {
    return ($html -replace "<[^>]+>", "").Trim()
}

# ---------------------------------------------------------------------------
# Fetch a page - tries curl.exe first (better TLS fingerprint, bypasses 429),
# falls back to Invoke-WebRequest.
# ---------------------------------------------------------------------------
function Invoke-HackdexPage([string]$Url) {
    $html = $null

    # --- Try curl.exe (ships with Windows 10+, has a real browser TLS stack) ---
    $curlExe = "$env:SystemRoot\System32\curl.exe"
    if (Test-Path $curlExe) {
        try {
            $html = & $curlExe -s -L --max-time 30 `
                -H "User-Agent: $UserAgent" `
                -H "Accept: text/html,application/xhtml+xml,*/*;q=0.9" `
                -H "Accept-Language: en-US,en;q=0.9" `
                -H "Accept-Encoding: gzip, deflate, br" `
                -H "Referer: https://www.hackdex.app/" `
                --compressed `
                $Url 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $html) { $html = $null }
        } catch { $html = $null }
    }

    # --- Fallback to Invoke-WebRequest ---
    if (-not $html) {
        $headers = @{
            "User-Agent"      = $UserAgent
            "Accept"          = "text/html,application/xhtml+xml,*/*;q=0.9"
            "Accept-Language" = "en-US,en;q=0.9"
            "Referer"         = "https://www.hackdex.app/"
        }
        try {
            $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers $headers -TimeoutSec 30
            $html = $resp.Content
        } catch {
            $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "?" }
            Write-Host "  WARN: Could not fetch $Url (HTTP $status)" -ForegroundColor Yellow
            return $null
        }
    }

    # SPA detection: Next.js/React shell with no hack links
    $hasHackLinks = $html -match 'href="?/hack/'
    $isShell      = ($html.Length -lt 4000) -or ($html -match 'id="__next"' -and -not $hasHackLinks)
    if ($isShell) { $script:SpaDetected = $true }

    return $html
}

# ---------------------------------------------------------------------------
# Parse listing blocks out of raw HTML
# Returns array of PSCustomObjects: Title, Platform, DetailUrl, DownloadUrl
# ---------------------------------------------------------------------------
function Get-HackListings([string]$Html, [int]$Max) {
    if (-not $Html) { return @() }

    $results = [System.Collections.Generic.List[object]]::new()

    # --- Try to find repeating item blocks ---
    $patterns = @(
        '(?s)<article[^>]*>(.*?)</article>',
        '(?s)<li[^>]*class="[^"]*hack[^"]*"[^>]*>(.*?)</li>',
        '(?s)<div[^>]*class="[^"]*card[^"]*"[^>]*>(.*?)</div>',
        '(?s)<div[^>]*class="[^"]*item[^"]*"[^>]*>(.*?)</div>'
    )

    $blocks = @()
    foreach ($pat in $patterns) {
        $m = [regex]::Matches($Html, $pat)
        if ($m.Count -ge 3) { $blocks = $m; break }
    }

    # Fallback: collect all /hack/ anchor tags as minimal entries
    if ($blocks.Count -eq 0) {
        $hackLinks = [regex]::Matches($Html, '(?s)<a[^>]+href="(/hack/[^"]+)"[^>]*>(.*?)</a>')
        if ($hackLinks.Count -ge 1) {
            foreach ($lm in $hackLinks) {
                $relUrl   = $lm.Groups[1].Value
                $inner    = $lm.Groups[2].Value
                $title    = ConvertFrom-HtmlEntities (Remove-HtmlTags $inner)
                if (-not $title) { $title = $relUrl -replace "^/hack/","" -replace "-"," " }
                $results.Add([PSCustomObject]@{
                    Title       = $title
                    Platform    = "?"
                    DetailUrl   = "https://www.hackdex.app$relUrl"
                    DownloadUrl = ""
                })
            }
        }
    } else {
        foreach ($blk in $blocks) {
            $block = $blk.Groups[1].Value

            # Title
            $titleMatch = [regex]::Match($block, '<h\d[^>]*>(.*?)</h\d>')
            if (-not $titleMatch.Success) {
                $titleMatch = [regex]::Match($block, 'title="([^"]+)"')
            }
            $title = if ($titleMatch.Success) {
                ConvertFrom-HtmlEntities (Remove-HtmlTags $titleMatch.Groups[1].Value)
            } else { "" }
            if (-not $title) { continue }

            # Platform
            $platMatch = [regex]::Match($block, '(?i)class="[^"]*(?:platform|system|console)[^"]*"[^>]*>(.*?)</')
            $platform  = if ($platMatch.Success) {
                ConvertFrom-HtmlEntities (Remove-HtmlTags $platMatch.Groups[1].Value)
            } else {
                # Try to find known platform tokens in the block text
                $plainText = Remove-HtmlTags $block
                $found = ""
                @("GBA","GBC","GB","NDS","N64","NES","SNES","Genesis","PSX","PSP","Dreamcast") | ForEach-Object {
                    if (-not $found -and $plainText -imatch "\b$_\b") { $found = $_ }
                }
                $found
            }

            # Detail URL
            $urlMatch  = [regex]::Match($block, 'href="(/hack/[^"]+)"')
            $detailUrl = if ($urlMatch.Success) { "https://www.hackdex.app" + $urlMatch.Groups[1].Value } else { "" }

            # Direct download URL (may exist in block)
            $dlMatch   = [regex]::Match($block, 'href="(https?://[^"]+(?:\.gba|\.gb|\.gbc|\.nds|\.z64|\.n64|\.nes|\.zip|\.rar|\.7z))"')
            $dlUrl     = if ($dlMatch.Success) { $dlMatch.Groups[1].Value } else { "" }

            if (-not $detailUrl -and -not $dlUrl) { continue }

            $results.Add([PSCustomObject]@{
                Title       = $title
                Platform    = $platform
                DetailUrl   = $detailUrl
                DownloadUrl = $dlUrl
            })
        }
    }

    if ($results.Count -eq 0) { $script:ParseFailed = $true }
    return $results | Select-Object -First $Max
}

# ---------------------------------------------------------------------------
# Fetch a detail page and extract the first direct download link
# ---------------------------------------------------------------------------
function Resolve-DownloadUrl([string]$DetailUrl) {
    $html = $null
    $curlExe = "$env:SystemRoot\System32\curl.exe"
    if (Test-Path $curlExe) {
        $html = & $curlExe -s -L --max-time 30 `
            -H "User-Agent: $UserAgent" `
            -H "Accept: text/html,*/*;q=0.9" `
            -H "Accept-Language: en-US,en;q=0.9" `
            -H "Referer: https://www.hackdex.app/" `
            --compressed `
            $DetailUrl 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $html) { $html = $null }
    }
    if (-not $html) {
        try {
            $resp = Invoke-WebRequest -Uri $DetailUrl -UseBasicParsing -Headers @{ "User-Agent" = $UserAgent } -TimeoutSec 30
            $html = $resp.Content
        } catch { return "" }
    }
    # Look for direct ROM/archive href
    $m = [regex]::Match($html, 'href="(https?://[^"]+(?:\.gba|\.gb|\.gbc|\.nds|\.z64|\.n64|\.nes|\.zip|\.rar|\.7z))"')
    if ($m.Success) { return $m.Groups[1].Value }
    # ROMhacking.net style: /utils/downloads/?id=NNNNN
    $m2 = [regex]::Match($html, 'href="(https?://[^"]*romhacking\.net/utils/downloads/\?id=[^"]+)"')
    if ($m2.Success) { return $m2.Groups[1].Value }
    # Any /download/ path
    $m3 = [regex]::Match($html, 'href="(https?://[^"]+/download[^"]*)"')
    if ($m3.Success) { return $m3.Groups[1].Value }
    return ""
}

# ---------------------------------------------------------------------------
# Parse user selection string into list of 1-based indices
# ---------------------------------------------------------------------------
function Resolve-Selection([string]$Selection, [int]$Max) {
    if (-not $Selection) { return @() }
    $selected = [System.Collections.Generic.HashSet[int]]::new()
    $tokens   = $Selection.Trim().ToLower() -split ","
    foreach ($tok in $tokens) {
        $tok = $tok.Trim()
        if ($tok -eq "all") {
            1..$Max | ForEach-Object { [void]$selected.Add($_) }
            break
        } elseif ($tok -match "^(\d+)-(\d+)$") {
            [int]$lo = $Matches[1]; [int]$hi = $Matches[2]
            $lo..$hi | Where-Object { $_ -ge 1 -and $_ -le $Max } | ForEach-Object { [void]$selected.Add($_) }
        } elseif ($tok -match "^\d+$") {
            $n = [int]$tok
            if ($n -ge 1 -and $n -le $Max) { [void]$selected.Add($n) }
        } else {
            Write-Host "  Ignored unrecognised token: '$tok'" -ForegroundColor DarkYellow
        }
    }
    return @($selected | Sort-Object)
}

# ---------------------------------------------------------------------------
# Download a file to temp dir; return local path or $null on failure
# ---------------------------------------------------------------------------
function Invoke-RomDownload([string]$Url, [string]$TempDir, [string]$FallbackName) {
    $headers = @{ "User-Agent" = $UserAgent }

    # HEAD for size + filename hint
    $filename = ""
    try {
        $head = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -Headers $headers -TimeoutSec 20
        $cd   = $head.Headers["Content-Disposition"]
        if ($cd -and $cd -match 'filename="?([^";]+)"?') { $filename = $Matches[1].Trim() }
        $bytes = $head.Headers["Content-Length"]
        $kb    = if ($bytes) { [math]::Round([int]$bytes / 1KB, 1) } else { "?" }
        Write-Host "  Downloading $kb KB ..." -ForegroundColor DarkCyan
    } catch {
        Write-Host "  (HEAD failed, downloading blind)" -ForegroundColor DarkYellow
    }

    # Derive filename from URL if not found in headers
    if (-not $filename) {
        $uriPath = ([System.Uri]$Url).AbsolutePath
        $filename = [System.IO.Path]::GetFileName([System.Uri]::UnescapeDataString($uriPath))
    }
    if (-not $filename -or $filename -notmatch "\.\w+$") {
        $safe     = $FallbackName -replace '[\\/:*?"<>|]', '_'
        $filename = $safe + ".download"
    }

    $outPath = Join-Path $TempDir $filename
    try {
        Invoke-WebRequest -Uri $Url -OutFile $outPath -UseBasicParsing -Headers $headers -TimeoutSec 300
    } catch {
        Write-Host "  FAILED to download: $_" -ForegroundColor Red
        return $null
    }

    if (-not (Test-Path $outPath) -or (Get-Item $outPath).Length -eq 0) {
        Write-Host "  FAILED: downloaded file is empty." -ForegroundColor Red
        return $null
    }

    Write-Host "  Saved: $filename" -ForegroundColor Green
    return $outPath
}

# ---------------------------------------------------------------------------
# Expand archive and return list of contained ROM files
# ---------------------------------------------------------------------------
function Expand-Archive-Safe([string]$ArchivePath, [string]$TempDir) {
    $ext     = [System.IO.Path]::GetExtension($ArchivePath).ToLower()
    $outDir  = Join-Path $TempDir ([System.IO.Path]::GetFileNameWithoutExtension($ArchivePath))
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    if ($ext -eq ".zip") {
        try {
            Expand-Archive -Path $ArchivePath -DestinationPath $outDir -Force
        } catch {
            Write-Host "  FAILED to extract ZIP: $_" -ForegroundColor Red
            return @()
        }
    } elseif ($ext -in @(".rar",".7z")) {
        $sevenZip = "$env:ProgramFiles\7-Zip\7z.exe"
        if (-not (Test-Path $sevenZip)) {
            $sevenZip = "$env:ProgramFiles(x86)\7-Zip\7z.exe"
        }
        if (-not (Test-Path $sevenZip)) {
            Write-Host "  WARN: 7-Zip not found - cannot extract $([System.IO.Path]::GetFileName($ArchivePath)). File left in temp." -ForegroundColor Yellow
            return @()
        }
        & $sevenZip x $ArchivePath "-o$outDir" -y | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAILED to extract with 7-Zip (exit $LASTEXITCODE)" -ForegroundColor Red
            return @()
        }
    }

    return Get-ChildItem -Path $outDir -Recurse -File | Where-Object { $RomExts -contains $_.Extension.ToLower() }
}

# ---------------------------------------------------------------------------
# Place a single ROM file into the correct system romhacks folder
# Returns $true if placed (or dry-run), $false if skipped
# ---------------------------------------------------------------------------
function Move-RomToSystemFolder([string]$FilePath) {
    $ext    = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $system = $ExtToSystem[$ext]
    if (-not $system) {
        Write-Host "  SKIP: unknown extension '$ext' for $([System.IO.Path]::GetFileName($FilePath)) - left in temp" -ForegroundColor Yellow
        return $false
    }

    $destDir = Join-Path (Join-Path $RootPath $system) "romhacks"
    $name    = [System.IO.Path]::GetFileName($FilePath)
    $dest    = Join-Path $destDir $name

    # Handle name collision
    if (Test-Path $dest) {
        $base    = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $dest    = Join-Path $destDir ($base + "_new" + $ext)
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Would move -> $destDir\$([System.IO.Path]::GetFileName($dest))" -ForegroundColor Yellow
        return $true
    }

    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Move-Item -LiteralPath $FilePath -Destination $dest -Force
    Write-Host "  -> $system\romhacks\$([System.IO.Path]::GetFileName($dest))" -ForegroundColor Green
    return $true
}

# ===========================================================================
# MAIN
# ===========================================================================

if ($DryRun) { Write-Host "[DRY RUN] No files will be downloaded, moved, or renamed.`n" -ForegroundColor Yellow }

# --- Fetch or load local HTML ---
function Get-PageHtml([string]$Url, [string]$LocalFile, [string]$Label) {
    if ($LocalFile) {
        if (-not (Test-Path $LocalFile)) {
            Write-Host "  ERROR: -Local file not found: $LocalFile" -ForegroundColor Red
            return $null
        }
        Write-Host "  Using local file for $Label`: $LocalFile" -ForegroundColor DarkCyan
        return Get-Content -Path $LocalFile -Raw -Encoding UTF8
    }
    return Invoke-HackdexPage $Url
}

Write-Host "Fetching hackdex.app discover pages..." -ForegroundColor Cyan
$htmlUpdated = Get-PageHtml $DiscoverUrls[0] $LocalHtmlUpdated "sort=updated"
$htmlNew     = Get-PageHtml $DiscoverUrls[1] $LocalHtmlNew     "sort=new"

# --- Dump mode ---
if ($DumpHtml) {
    Write-Host "`n=== HTML: $($DiscoverUrls[0]) ===" -ForegroundColor Cyan
    Write-Output $htmlUpdated
    Write-Host "`n=== HTML: $($DiscoverUrls[1]) ===" -ForegroundColor Cyan
    Write-Output $htmlNew
    exit 0
}

# --- Parse ---
Write-Host "Parsing listings..." -ForegroundColor Cyan
$listUpdated = Get-HackListings $htmlUpdated $Count
$listNew     = Get-HackListings $htmlNew     $Count

# --- Merge and deduplicate ---
$seen     = @{}
$combined = [System.Collections.Generic.List[object]]::new()
foreach ($entry in (@($listUpdated) + @($listNew))) {
    if (-not $entry) { continue }
    $key = if ($entry.DetailUrl) { $entry.DetailUrl } else { $entry.Title }
    if (-not $seen.ContainsKey($key)) {
        $seen[$key] = $true
        $combined.Add($entry)
    }
}

# --- Handle no results ---
if ($combined.Count -eq 0) {
    Write-Host ""
    if ($script:SpaDetected) {
        Write-Host "ERROR: hackdex.app appears to be a JavaScript SPA." -ForegroundColor Red
        Write-Host "  Invoke-WebRequest fetches the pre-JS shell, so listings are not in the HTML." -ForegroundColor Red
    } else {
        Write-Host "ERROR: No listings found - the HTML parser may need updating." -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  The site is likely blocking automated requests (Cloudflare / rate limiting)."
    Write-Host "  Use the browser fallback:"
    Write-Host "    1. Open https://www.hackdex.app/discover?sort=updated in Chrome/Edge"
    Write-Host "    2. Press F12 -> Console, then run:"
    Write-Host "         copy(document.documentElement.outerHTML)"
    Write-Host "    3. Paste into a file, e.g. updated.html"
    Write-Host "    4. Repeat for ?sort=new -> new.html"
    Write-Host "    5. Run:"
    Write-Host "         .\Get-Romhacks.ps1 -LocalHtmlUpdated updated.html -LocalHtmlNew new.html"
    Write-Host ""
    Write-Host "  Or use -DumpHtml to see what the script actually received."
    exit 1
}

# --- Display ---
Write-Host ""
Write-Host ("  {0,-4} {1,-45} {2,-12} {3}" -f "#", "Title", "Platform", "URL") -ForegroundColor White
Write-Host ("  " + ("-" * 90)) -ForegroundColor DarkGray
$i = 1
foreach ($entry in $combined) {
    $shortTitle = if ($entry.Title.Length -gt 43) { $entry.Title.Substring(0,40) + "..." } else { $entry.Title }
    $plat       = if ($entry.Platform) { $entry.Platform } else { "?" }
    $url        = if ($entry.DetailUrl) { $entry.DetailUrl } else { $entry.DownloadUrl }
    Write-Host ("  [{0,-2}] " -f $i) -ForegroundColor Cyan -NoNewline
    Write-Host ("{0,-45} " -f $shortTitle) -NoNewline
    Write-Host ("{0,-12} " -f $plat) -ForegroundColor Yellow -NoNewline
    Write-Host $url -ForegroundColor DarkGray
    $i++
}
Write-Host ""

$raw = Read-Host "Enter selections (e.g. 1,3,5 or 1-5 or all)"
$indices = @(Resolve-Selection $raw $combined.Count)

if ($indices.Count -eq 0) {
    Write-Host "No valid selections. Exiting." -ForegroundColor Yellow
    exit 0
}

# --- Download and place ---
$tempDir   = Join-Path $env:TEMP ("romhacks_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$placed  = 0
$skipped = 0
$bySystem = @{}

foreach ($idx in $indices) {
    $entry = $combined[$idx - 1]
    Write-Host ""
    Write-Host "[$idx] $($entry.Title)" -ForegroundColor White

    # Resolve download URL if we only have a detail page
    $dlUrl = $entry.DownloadUrl
    if (-not $dlUrl -and $entry.DetailUrl) {
        Write-Host "  Fetching detail page for download link..." -ForegroundColor DarkCyan
        $dlUrl = Resolve-DownloadUrl $entry.DetailUrl
    }

    if (-not $dlUrl) {
        Write-Host "  SKIP: no download URL found. Visit $($entry.DetailUrl) manually." -ForegroundColor Yellow
        $skipped++
        continue
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Would download: $dlUrl" -ForegroundColor Yellow
        $placed++
        continue
    }

    $localPath = Invoke-RomDownload $dlUrl $tempDir $entry.Title
    if (-not $localPath) { $skipped++; continue }

    $ext = [System.IO.Path]::GetExtension($localPath).ToLower()

    if ($ArchiveExts -contains $ext) {
        Write-Host "  Extracting archive..." -ForegroundColor DarkCyan
        $romFiles = Expand-Archive-Safe $localPath $tempDir
        Remove-Item $localPath -Force -ErrorAction SilentlyContinue
        if ($romFiles.Count -eq 0) { $skipped++; continue }
        foreach ($rf in $romFiles) {
            $ok = Move-RomToSystemFolder $rf.FullName
            if ($ok) {
                $sys = $ExtToSystem[$rf.Extension.ToLower()]
                if ($sys) { $bySystem[$sys] = $(if ($bySystem[$sys]) { $bySystem[$sys] } else { 0 }) + 1 }
                $placed++
            } else { $skipped++ }
        }
    } else {
        $ok = Move-RomToSystemFolder $localPath
        if ($ok) {
            $sys = $ExtToSystem[$ext]
            if ($sys) { $bySystem[$sys] = $(if ($bySystem[$sys]) { $bySystem[$sys] } else { 0 }) + 1 }
            $placed++
        } else { $skipped++ }
    }
}

# --- Clean up empty temp dir ---
if (@(Get-ChildItem $tempDir -Recurse -File).Count -eq 0) {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Summary ---
Write-Host ""
Write-Host "========== SUMMARY ==========" -ForegroundColor Cyan
Write-Host "  Placed : $placed  |  Skipped: $skipped"
foreach ($sys in ($bySystem.Keys | Sort-Object)) {
    Write-Host "    $sys : $($bySystem[$sys]) file(s)" -ForegroundColor Green
}

# --- Run Organize-Romhacks.ps1 ---
if ($placed -gt 0 -or $DryRun) {
    Write-Host ""
    $organizeScript = Join-Path $RootPath "Organize-Romhacks.ps1"
    if (Test-Path $organizeScript) {
        Write-Host "Running Organize-Romhacks.ps1..." -ForegroundColor Cyan
        if ($DryRun) {
            & $organizeScript -RootPath $RootPath -DryRun
        } else {
            & $organizeScript -RootPath $RootPath
        }
    } else {
        Write-Warning "Organize-Romhacks.ps1 not found at $organizeScript - skipping renumber step."
    }
}
