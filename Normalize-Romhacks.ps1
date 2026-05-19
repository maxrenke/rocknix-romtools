<#
.SYNOPSIS
    Normalizes romhack filenames: cleans titles, adds [TAG] classification,
    changes NNN_ prefix to "NNN - " separator.
.PARAMETER RootPath
    Root of backup. Defaults to D:\RocknixBackup
.PARAMETER DryRun
    Preview only, no files touched.
.EXAMPLE
    .\Normalize-Romhacks.ps1 -DryRun
    .\Normalize-Romhacks.ps1
#>
param(
    [string]$RootPath = "D:\RocknixBackup",
    [switch]$DryRun
)
$exts = @(".gba",".gb",".gbc",".nds",".z64",".n64",".nes")
# Manual overrides: key matches start of stripped base name -> "Clean Title|TAG"
# Longer keys listed first so more-specific matches win.
$overrides = [ordered]@{
    # GBA
    "Pokemon Crystal Advance Redux"                = "Pokemon Crystal Advance Redux|QoL"
    "Pokémon Crystal Advance Redux"                = "Pokemon Crystal Advance Redux|QoL"
    "Pokemon Crossroads Hoenn"                      = "Pokemon Crossroads Hoenn|Cross"
    "Pokemon Crossroads Kanto"                      = "Pokemon Crossroads Kanto|Cross"
    "Pokemon Crossroads Beta 1.0 hoenn"            = "Pokemon Crossroads Hoenn|Cross"
    "Pokemon Crossroads Beta 1.0 kanto"            = "Pokemon Crossroads Kanto|Cross"
    "Pokemon Inclement Emerald v1.0.13"            = "Pokemon Inclement Emerald|Diff"
    "Inclement_Emerald_Beta"                       = "Pokemon Inclement Emerald|Diff"
    "Pokemon Omega Ruby Origins"                   = "Pokemon Omega Ruby Origins|Story"
    "Pokemon Mystery Dungeon Rogue Rescue Team"     = "PMD Rogue Rescue Team|Rogue"
    "Pokemon Mystery Dungeon Rescue Team EX"        = "PMD Rescue Team EX|Rogue"
    "Pokemon Mystery Dungeon Explorers of Skies"    = "PMD Explorers of Skies|Story"
    "Pokemon Mystery Dungeon - Rogue Rescue Team"  = "PMD Rogue Rescue Team|Rogue"
    "Pokemon Mystery Dungeon - Explorers Of Skies" = "PMD Explorers of Skies|Story"
    "Pokemon - Ash Gray"                           = "Pokemon Ash Gray|Story"
    "Pokemon - Liquid Crystal"                     = "Pokemon Liquid Crystal|Story"
    "Pokemon - Ultimate Fusion"                    = "Pokemon Ultimate Fusion|Story"
    "Pokemon - Emerald Version"                    = "!! RETAIL ROM - move to gba/ root|!!"
    "Pokemon Elite Redux beta"                     = "Pokemon Elite Redux|Diff"
    "Pokemon Elite Redux"                          = "Pokemon Elite Redux|Diff"
    "Pokemon Sword and Shield Ultimate Plus"       = "Pokemon Sword Shield Ultimate Plus|Story"
    "Pokemon Sword and Shield Ultimate"            = "Pokemon Sword Shield Ultimate|Story"
    "Pokemon The Legend of Zelda Minish Quest"     = "Pokemon Zelda Minish Quest|Cross"
    "Pokemon Gs Chronicles"                        = "Pokemon GS Chronicles|Story"
    "Pokemon HeartGold Lux"                        = "Pokemon HeartGold Lux|QoL"
    "Pokemon Heartgold Generations"                = "Pokemon HeartGold Generations|QoL"
    "Pokemon Aesthetic Red"                        = "Pokemon Aesthetic Red|QoL"
    "Pokemon RadiCLA"                              = "Pokemon RadiCLA|Rand"
    "Pokemon Sun Moon GBA"                         = "Pokemon Sun Moon GBA|Story"
    "Pokemon Stadium 2 Patched"                    = "Pokemon Stadium 2|Patch"
    "Pokemon Stadium (USA)_bps_patched"            = "Pokemon Stadium|Patch"
    "Pokemon Kart 64"                              = "Pokemon Kart 64|Cross"
    "PokeLand 0 - Episode 1"                       = "PokeLand Episode 1|Cross"
    "Pokemblem"                                    = "Pokemblem|Cross"
    "FE8PLUS"                                      = "Fire Emblem Sacred Stones Plus|QoL"
    "Fire Emblem The Blazing Blade Plus"            = "Fire Emblem Blazing Blade Plus|QoL"
    "Fire Emblem - The Blazing Blade Plus"         = "Fire Emblem Blazing Blade Plus|QoL"
    "Fire Emblem - Sacred Stones Plus"             = "Fire Emblem Sacred Stones Plus|QoL"
    "Fire Emblem - Sealed Sword"                   = "Fire Emblem Sealed Sword|QoL"
    "Darkest Emblem 2"                             = "Darkest Emblem 2|Cross"
    "Andaron Saga"                                 = "Andaron Saga|Cross"
    "Advance Wars Returns"                         = "Advance Wars Returns|QoL"
    "Red Rescue Team Shiny Patch"                  = "Red Rescue Team Shiny Patch|Patch"
    "Fire Emblem Vision Quest"                     = "Fire Emblem Vision Quest|Story"
    "Pokemon Blazed Glazed"                        = "Pokemon Blazed Glazed|Story"
    "Pokemon Glazed"                               = "Pokemon Glazed|Story"
    "Pokemon Renegade Platinum"                    = "Pokemon Renegade Platinum|QoL"
    "Pk Emr Kaizo"                                 = "Pokemon Emerald Kaizo|Diff"
    "SquashuasPokeEmeraldv"                        = "Pokemon Emerald Squashua QoL|QoL"
    "Pokemon Emerald Squashua"                     = "Pokemon Emerald Squashua QoL|QoL"
    "Pokemon Emerald RogueEX"                      = "Pokemon Emerald Rogue EX|Rogue"
    "emeraldrogue_vanilla"                         = "Pokemon Emerald Rogue Vanilla|Rogue"
    "emeraldrogue_ex"                              = "Pokemon Emerald Rogue EX|Rogue"
    "emerald_randomized"                           = "Pokemon Emerald Randomized|Rand"
    "emerald_random1"                              = "Pokemon Emerald Random|Rand"
    "emerald_imperium"                             = "Pokemon Emerald Imperium|Story"
    "liquid-crystal-Redux"                         = "Pokemon Liquid Crystal Redux|Story"
    "official_ironmon AutoRandomized"              = "Pokemon Emerald IronMon AutoRandomized|Rand"
    "RSE Standard AutoRandomized"                  = "Pokemon RSE AutoRandomized|Rand"
    "1986 - Pokemon Emerald"                       = "Pokemon Emerald TrashMan Randomized|Rand"
    "Rescueteamex"                                 = "PMD Rescue Team EX|Rogue"
    "Rogue Rescue Team"                            = "PMD Rogue Rescue Team|Rogue"
    "PokeScape"                                    = "Pokemon Scape|Cross"
    "Pokemon Scape"                                = "Pokemon Scape|Cross"
    "Pokemon ROWE"                                 = "Pokemon ROWE|QoL"
    "Pokemon_ROWE"                                 = "Pokemon ROWE|QoL"
    "ThePit_Gen9"                                  = "Pokemon The Pit Gen 9|Rogue"
    "Thepit Gen3"                                  = "Pokemon The Pit Gen 3|Rogue"
    "Super Mariomon"                               = "Super Mariomon|Cross"
    # N64
    "SM64_USAMUNE"                                 = "Super Mario 64 USAMUNE|Story"
    "Super Mario 64 USAMUNE"                       = "Super Mario 64 USAMUNE|Story"
    "Sonic 64_bps_patched"                         = "Sonic 64|Cross"
    "StarFox64SurvivalV14"                         = "Star Fox 64 Survival|Story"
    "Star Fox 64 Survival"                         = "Star Fox 64 Survival|Story"
    "The Sealed Palace"                            = "The Sealed Palace|Story"
    "Substance Wars"                               = "Substance Wars|Story"
    # NDS
    "Pokemon Conquest_ Ultimate"                   = "Pokemon Conquest Ultimate|Story"
    "Pokemon Conquest_ Twin Dragons"               = "Pokemon Conquest Twin Dragons|Story"
    "Pokemon Conquest Reconquered"                 = "Pokemon Conquest Reconquered|Story"
    "Fire Emblem - Shadow Dragon"                  = "Fire Emblem Shadow Dragon FCP|Patch"
    "Fire Emblem Shadow Dragon"                    = "Fire Emblem Shadow Dragon FCP|Patch"
    "Zoids Saga DS - Legend of Arcadia"            = "Zoids Saga DS Legend of Arcadia|Patch"
    "Zoids Saga DS Legend of Arcadia"              = "Zoids Saga DS Legend of Arcadia|Patch"
    "Super Mario Galaxy DS"                        = "Super Mario Galaxy DS|Cross"
    # NES
    "Smooth Mario Bros"                            = "Smooth Mario Bros|Patch"
    # GB/GBC
    "Pokemon Extreme Yellow"                       = "Pokemon Extreme Yellow|Story"
    "Pokemon Yellow Legacy"                        = "Pokemon Yellow Legacy|QoL"
    "Pokemon_Righteous_Red"                        = "Pokemon Righteous Red|Story"
    "Pokemon_PureRed"                              = "Pokemon Pure Red|QoL"
    "Pokemon - Red Version Colorized"              = "Pokemon Red Colorized|Patch"
    "Pokemon Ambrosia (Crystal)"                   = "Pokemon Ambrosia Crystal|Story"
    "Pokemon TCG Generations"                      = "Pokemon TCG Generations|Story"
    "Pokemon TCG Neo Ver"                          = "Pokemon TCG Neo|Story"
    "Pokemon Complete Crystal"                     = "Pokemon Complete Crystal|QoL"
    "Pokemon Crystal Adventures"                   = "Pokemon Crystal Adventures|Rogue"
    "Pokemon Crystal Clear"                        = "Pokemon Crystal Clear|Story"
    "Pokemon Modern Crystal"                       = "Pokemon Modern Crystal|QoL"
    # NDS (missed in first pass)
    "mythicsilver"                                 = "Pokemon Mythic Silver|Story"
    "mythic silver demo"                           = "Pokemon Mythic Silver (Demo)|Story"
    # GBA - name fixes (dash in filename, Beta in title, etc.)
    "Pokemon Emerald - Seaglass"                   = "Pokemon Emerald Seaglass|QoL"
    "Pokemon Odyssey Beta"                         = "Pokemon Odyssey|Story"
    "Rose Gold NDS Demo"                           = "Rose Gold NDS|Story"
    # NDS - QoL hacks (no auto-tag match, would fall through to Story)
    "Pokemon Black Boost"                          = "Pokemon Black Boost|QoL"
    "Pokemon MasterSilver"                         = "Pokemon MasterSilver|QoL"
    "Pokemon WoofGold"                             = "Pokemon WoofGold|QoL"
    "Refined Gold Overhaul"                        = "Refined Gold Overhaul|QoL"
    "Refined Platinum Overhaul"                    = "Refined Platinum Overhaul|QoL"
    "Pokemon True Soul"                            = "Pokemon True Soul|QoL"
    "Pokemon Pure Heart"                           = "Pokemon Pure Heart|QoL"
    # NDS - Diff hacks (no auto-tag match, would fall through to Story)
    "Pokemon Infinite Black 2"                     = "Pokemon Infinite Black 2|Diff"
    "Pokemon Volt White 2 Redux"                   = "Volt White 2 Redux|Diff"
    "Pokemon Blaze Black 2 Redux"                  = "Blaze Black 2 Redux|Diff"
}
$tagRules = [ordered]@{
    "AutoRandomized|IronMon|Randomized|\bROWE\b|RadiCLA|\bRandom\b"                             = "Rand"
    "\bRogue\b|Nuzlomizer|The Pit|Rescue Team EX"                                               = "Rogue"
    "Kaizo|Radical Red|Inclement|Blazing Emerald|Darkfire|Soulslike|Nuzlock"                    = "Diff"
    "Jimmy QOL|Reignited|Deluxe|\bLegacy\b|Polished|Contemporary|Seaglass|Squared|\bMini\b|Complete Crystal|Modern Crystal|PureRed|Pure Red|PureGreen|Pure Green|PureBlue|Pure Blue|Aesthetic|Colorized|Crystal Clear|Glazed|\bLux\b|HeartGold Generations|Advance Wars Returns|Blazing Blade|Sealed Sword|Sacred Stones Plus" = "QoL"
    "Mariomon|Pokemblem|PokeLand|Minish Quest|Advance Wars|Fire Emblem|Kart 64|Sonic 64|Star Fox|Darkest Emblem|Andaron|Super Mario|Crossroads|Zoids|FCP" = "Cross"
    "\bFCP\b|Smooth Mario|\bStadium\b|bps.patch"                                                = "Patch"
}
function Get-AutoTag($title) {
    foreach ($pat in $tagRules.Keys) {
        if ($title -match $pat) { return $tagRules[$pat] }
    }
    return "Story"
}
function Extract-Version($n) {
    $ic = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    # Date pattern (D-M-YY) or (DD-M-YY[-rev])
    $m = [regex]::Match($n, '^(.*?)\s*\((\d{1,2}-\d{1,2}-\d{2}(?:-\d+)?)\)\s*$')
    if ($m.Success) { return @($m.Groups[1].Value.TrimEnd(), "($($m.Groups[2].Value))") }
    # Version in parens: (v1.2.3), (v2.0.1-EX), (1.7.2b), (2.65 beta 2)
    $m = [regex]::Match($n, '^(.*?)\s*\(([vV]?[\d][\d.\-]*(?:[a-zA-Z]{1,4})?(?:\s*(?:beta|alpha|demo)\s*\d*)?)\)\s*$', $ic)
    if ($m.Success) {
        $v = $m.Groups[2].Value.Trim()
        if ($v -notmatch "^v") { $v = "v$v" }
        return @($m.Groups[1].Value.TrimEnd(), "($v)")
    }
    # Single-word edition suffix like (Simple) — not a version string but kept in version slot
    $m = [regex]::Match($n, '^(.*?)\s*\((Simple|Standard|Lite|Full|Base|Beta|Demo)\)\s*$', $ic)
    if ($m.Success) { return @($m.Groups[1].Value.TrimEnd(), "($($m.Groups[2].Value))") }
    # Trailing bare version: v1.2.3, v2.0.1a, v1.92u
    $m = [regex]::Match($n, '^(.*?)\s+([vV][\d][\d.\-]*[a-zA-Z]{0,4})\s*$', $ic)
    if ($m.Success) {
        $v = $m.Groups[2].Value.Trim() -replace "^V","v"
        return @($m.Groups[1].Value.TrimEnd(), "($v)")
    }
    # Trailing numeric: 3.3 or 1.0.5
    $m = [regex]::Match($n, '^(.*?)\s+(\d+\.\d[\d.]*)\s*$')
    if ($m.Success) { return @($m.Groups[1].Value.TrimEnd(), "(v$($m.Groups[2].Value.Trim()))") }
    return @($n, "")
}
function Process-Name($filename) {
    $ext      = [System.IO.Path]::GetExtension($filename)
    $base     = [System.IO.Path]::GetFileNameWithoutExtension($filename)
    # Handle both NNN_ and NNN - prefix formats (idempotent re-run support)
    $stripped = $base -replace "^\d{3}[\s_-]+", ""
    # Strip any existing [TAG] classifications from previous runs
    $stripped = $stripped -replace "\s*\[(QoL|Story|Diff|Rand|Rogue|Cross|Patch)\]", ""
    # Strip unclosed version parens: "(vX.Y " followed by another "(" (e.g. duplicate from bad run)
    $stripped = $stripped -replace "\s*\([vV]?[\d][\d\.\-]*[a-zA-Z]*\s+(?=\()", ""
    # Strip orphaned close-paren suffixes left if the open paren was already removed (e.g. "beta 2)")
    $stripped = $stripped -replace "\s+(?:beta|alpha|demo)\s*\d*\)\s*$", ""
    $stripped = $stripped.Trim() -replace "\s{2,}"," "
    # Normalize V1_4_7 style version strings
    $stripped = $stripped -replace "\bV(\d+)_(\d+)_(\d+)\b", "v`$1.`$2.`$3"
    # Match override (longest key first via ordered dict)
    $overrideKey = $null
    foreach ($k in $overrides.Keys) {
        if ($stripped -like "$k*" -or $stripped -eq $k) { $overrideKey = $k; break }
    }
    # Fallback: try matching after stripping version from end
    if (-not $overrideKey) {
        $noVer = $stripped -replace "\s*\(.*$","" -replace "\s+[vV]\d.*$","" -replace "\s+\d[\d.]+.*$",""
        $noVer = $noVer.TrimEnd(" -_")
        foreach ($k in $overrides.Keys) {
            if ($noVer -eq $k) { $overrideKey = $k; break }
        }
    }
    if ($overrideKey) {
        $parts     = $overrides[$overrideKey] -split "\|"
        $cleanTitle = $parts[0]
        $tag        = $parts[1]
        # Extract version from normalized stripped name
        $forVer    = $stripped -replace "_"," "
        $forVer    = $forVer -replace "\s*\(USA\)","" -replace "\s*\(Japan\)","" -replace "\s*\(World\)","" -replace "\s*\(patched\)",""
        $forVer    = $forVer -replace "\s*\(\d+\)\s*$",""   # strip trailing dupe indicators like (2)
        $verParts  = Extract-Version $forVer
        $ver        = if ($verParts[1]) { " $($verParts[1])" } else { "" }
        return [PSCustomObject]@{ Title = $cleanTitle; Tag = $tag; Ver = $ver }
    }
    # Auto-normalize
    $n = $stripped
    $n = $n -replace "é","e" -replace "è","e" -replace "ê","e" -replace "É","E"
    $n = $n -replace "\s*\(if\([^)]*\)[.]*\)", ""          # strip (if().) junk
    $n = $n -replace "\s*\(custom[^)]*\)", ""               # strip (custom X.X Update) notes
    $n = $n -replace "\s*\(GBA\)","" -replace "\s*\(NDS\)","" -replace "\s*\(N64\)",""
    $n = $n -replace "\s*\(U\)\s*"," " -replace "\s*\(J\)\s*$",""
    $n = $n -replace "_"," "
    $n = $n.Trim() -replace "\s+"," "
    $verParts = Extract-Version $n
    $title    = $verParts[0].Trim()
    $ver      = if ($verParts[1]) { " $($verParts[1])" } else { "" }
    $tag      = Get-AutoTag $title
    return [PSCustomObject]@{ Title = $title; Tag = $tag; Ver = $ver }
}
# Collect all romhack files
$allRoms = Get-ChildItem -Path $RootPath -Recurse |
    Where-Object { $_.FullName -like "*\romhacks\*" -and $exts -contains $_.Extension.ToLower() } |
    Sort-Object { ($_.FullName -split "\\romhacks\\")[0] | Split-Path -Leaf },
                { ($_.FullName -split "\\romhacks\\")[1] -split "\\" | Select-Object -First 1 },
                Name
$currentSys = ""; $currentSub = ""; $flags = @(); $renamed = 0; $skipped = 0; $failed = 0
if ($DryRun) { Write-Host "[DRY RUN] No files will be changed.`n" -ForegroundColor Yellow }
foreach ($rom in $allRoms) {
    $parts  = $rom.FullName -split "\\romhacks\\"
    $sys    = $parts[0] | Split-Path -Leaf
    $sub    = ($parts[1] -split "\\")[0]
    $header = "$($sys.ToUpper()) > $sub"
    if ($sys -ne $currentSys -or $sub -ne $currentSub) {
        Write-Host "`n[$header]" -ForegroundColor Cyan
        $currentSys = $sys; $currentSub = $sub
    }
    $prefix = if ($rom.BaseName -match "^(\d{3})") { $Matches[1] } else { "???" }
    $result = Process-Name $rom.Name
    if ($result.Tag -eq "!!") {
        Write-Host "  $($rom.Name)" -ForegroundColor DarkGray
        Write-Host "  !! $($result.Title)" -ForegroundColor Red
        Write-Host ""
        $flags += $rom.FullName
        continue
    }
    $newName = "$prefix - $($result.Title) [$($result.Tag)]$($result.Ver)$($rom.Extension)"
    if ($newName -eq $rom.Name) {
        Write-Host "  $($rom.Name) (unchanged)" -ForegroundColor DarkGray
        $skipped++
        continue
    }
    $saveExts  = @(".srm",".sav",".dsv",".rtc",".dss")
    $oldBase   = $rom.BaseName
    $newBase   = [System.IO.Path]::GetFileNameWithoutExtension($newName)
    $savePairs = @($saveExts | ForEach-Object {
        $p = Join-Path $rom.DirectoryName "$oldBase$_"
        if (Test-Path -LiteralPath $p) { [PSCustomObject]@{ OldPath = $p; NewName = "$newBase$_" } }
    } | Where-Object { $_ })
    Write-Host "  $($rom.Name)" -ForegroundColor DarkGray
    Write-Host "  -> $newName" -ForegroundColor Yellow
    foreach ($sp in $savePairs) { Write-Host "     save: $(Split-Path $sp.OldPath -Leaf) -> $($sp.NewName)" -ForegroundColor DarkGreen }
    Write-Host ""
    if (-not $DryRun) {
        try {
            Rename-Item -LiteralPath $rom.FullName -NewName $newName -ErrorAction Stop
            $renamed++
            foreach ($sp in $savePairs) {
                try { Rename-Item -LiteralPath $sp.OldPath -NewName $sp.NewName -ErrorAction Stop }
                catch { Write-Host "  SAVE FAILED: $_" -ForegroundColor Red }
            }
        } catch {
            Write-Host "  FAILED: $_" -ForegroundColor Red
            $failed++
        }
    }
}
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "  Would rename : $($allRoms.Count - $skipped)"
    Write-Host "  Already clean: $skipped"
} else {
    Write-Host "  Renamed : $renamed"
    Write-Host "  Skipped : $skipped"
    Write-Host "  Failed  : $failed"
}
if ($flags.Count -gt 0) {
    Write-Host "`n  ACTION REQUIRED (retail ROMs in romhacks/):" -ForegroundColor Red
    $flags | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
}

# --- HTML placeholder check ---
$htmlPath = Join-Path $RootPath "rom-catalog.html"
if (Test-Path $htmlPath) {
    $html = Get-Content $htmlPath -Raw
    $romsBlock = [regex]::Match($html, 'const ROMS\s*=\s*\[([\s\S]*?)\];')
    $existingNames = if ($romsBlock.Success) {
        [regex]::Matches($romsBlock.Groups[1].Value, 'name:"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
    } else { @() }

    $htmlMissing = @()
    foreach ($rom in $allRoms) {
        $parts = $rom.FullName -split "\\romhacks\\"
        if ($rom.FullName -match "\\OLD\\") { continue }
        $result = Process-Name $rom.Name
        if ($result.Tag -eq "!!") { continue }
        $sys = ($parts[0] | Split-Path -Leaf)
        if ($existingNames -notcontains $result.Title) {
            $htmlMissing += [PSCustomObject]@{ Title = $result.Title; Tag = $result.Tag; Ver = $result.Ver.Trim(); Sys = $sys; File = $rom.Name }
        }
    }

    Write-Host "`n=== HTML CHECK ===" -ForegroundColor Cyan
    if ($htmlMissing.Count -eq 0) {
        Write-Host "  All active files accounted for in HTML." -ForegroundColor DarkGray
    } else {
        Write-Host "  $($htmlMissing.Count) file(s) missing from HTML:" -ForegroundColor Magenta
        $htmlMissing | ForEach-Object { Write-Host "    $($_.File)" -ForegroundColor Magenta }
        if (-not $DryRun) {
            $placeholders = ($htmlMissing | ForEach-Object {
                "{num:0,name:`"$($_.Title)`",ver:`"$($_.Ver)`",sys:`"$($_.Sys)`",cat:`"$($_.Tag)`",status:`"available`",base:`"`",desc:`"TODO`"},"
            }) -join "`n"
            $constIdx = $html.IndexOf('const SYSTEMS')
            $insertIdx = $html.LastIndexOf('];', $constIdx)
            if ($insertIdx -ge 0) {
                $html = $html.Insert($insertIdx, "// --- AUTO-ADDED PLACEHOLDERS ---`n$placeholders`n")
                [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.Encoding]::UTF8)
                Write-Host "  Inserted $($htmlMissing.Count) placeholder(s) into HTML." -ForegroundColor Magenta
            }
        } else {
            Write-Host "  [DRY RUN] Would insert $($htmlMissing.Count) placeholder(s) into HTML." -ForegroundColor Magenta
        }
    }
}
