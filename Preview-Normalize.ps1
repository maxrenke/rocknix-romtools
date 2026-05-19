param([string]$RootPath = "D:\RocknixBackup")
$exts = @(".gba",".gb",".gbc",".nds",".z64",".n64",".nes")
$overrides = @{
    "FE8PLUS"                                      = "Fire Emblem Sacred Stones Plus|QoL"
    "Pk Emr Kaizo"                                 = "Pokemon Emerald Kaizo|Diff"
    "SquashuasPokeEmeraldv"                        = "Pokemon Emerald Squashua QoL|QoL"
    "emeraldrogue_vanilla"                         = "Pokemon Emerald Rogue Vanilla|Rogue"
    "emeraldrogue_ex"                              = "Pokemon Emerald Rogue EX|Rogue"
    "emerald_randomized"                           = "Pokemon Emerald Randomized|Rand"
    "emerald_random1"                              = "Pokemon Emerald Random|Rand"
    "emerald_imperium"                             = "Pokemon Emerald Imperium|Story"
    "liquid-crystal-Redux"                         = "Pokemon Liquid Crystal Redux|Story"
    "official_ironmon AutoRandomized"              = "Pokemon Emerald IronMon AutoRandomized|Rand"
    "RSE Standard AutoRandomized"                  = "Pokemon RSE AutoRandomized|Rand"
    "1986 - Pokemon Emerald"                       = "Pokemon Emerald TrashMan Randomized|Rand"
    "Pokemon Mystery Dungeon Rogue Rescue Team"     = "PMD Rogue Rescue Team|Rogue"
    "Pokemon Mystery Dungeon Rescue Team EX"        = "PMD Rescue Team EX|Rogue"
    "Pokemon Mystery Dungeon Explorers of Skies"    = "PMD Explorers of Skies|Story"
    "Rescueteamex"                                 = "PMD Rescue Team EX|Rogue"
    "PokeScape"                                    = "Pokemon Scape|Story"
    "Pokemon_ROWE"                                 = "Pokemon ROWE|QoL"
    "ThePit_Gen9"                                  = "Pokemon The Pit Gen 9|Rogue"
    "Thepit Gen3"                                  = "Pokemon The Pit Gen 3|Rogue"
    "Super Mariomon"                               = "Super Mariomon|Cross"
    "SM64_USAMUNE"                                 = "Super Mario 64 USAMUNE|Story"
    "Sonic 64_bps_patched"                         = "Sonic 64|Cross"
    "StarFox64SurvivalV14"                         = "Star Fox 64 Survival|Story"
    "mythicsilver"                                 = "Pokemon Mythic Silver|Story"
    "mythic silver demo"                           = "Pokemon Mythic Silver (Demo)|Story"
    "Pokemon Conquest_ Ultimate"                   = "Pokemon Conquest Ultimate|Story"
    "Pokemon Conquest_ Twin Dragons"               = "Pokemon Conquest Twin Dragons|Story"
    "Pokemon Conquest Reconquered"                 = "Pokemon Conquest Reconquered|Story"
    "Pokemon Mystery Dungeon - Explorers Of Skies" = "Pokemon Mystery Dungeon Explorers of Skies|Story"
    "Rogue Rescue Team"                            = "PMD Rogue Rescue Team|Rogue"
    "Pokemon Mystery Dungeon - Rogue Rescue Team"  = "PMD Rogue Rescue Team|Rogue"
    "Fire Emblem - Shadow Dragon"                  = "Fire Emblem Shadow Dragon FCP|Patch"
    "Fire Emblem - The Blazing Blade Plus"         = "Fire Emblem The Blazing Blade Plus|QoL"
    "Fire Emblem - Sealed Sword"                   = "Fire Emblem Sealed Sword|QoL"
    "Zoids Saga DS - Legend of Arcadia"            = "Zoids Saga DS Legend of Arcadia|Patch"
    "Super Mario Galaxy DS"                        = "Super Mario Galaxy DS|Cross"
    "Smooth Mario Bros"                            = "Smooth Mario Bros|Patch"
    "Pokemon Stadium 2 Patched"                    = "Pokemon Stadium 2|Patch"
    "Pokemon Stadium (USA)_bps_patched"            = "Pokemon Stadium|Patch"
    "Pokemon Kart 64"                              = "Pokemon Kart 64|Cross"
    "The Sealed Palace"                            = "The Sealed Palace|Story"
    "Substance Wars"                               = "Substance Wars|Story"
    "Advance Wars Returns"                         = "Advance Wars Returns|QoL"
    "Pokemon - Ash Gray"                           = "Pokemon Ash Gray|Story"
    "Pokemon - Liquid Crystal"                     = "Pokemon Liquid Crystal|Story"
    "Pokemon - Ultimate Fusion"                    = "Pokemon Ultimate Fusion|Story"
    "Pokemon - Emerald Version"                    = "!! RETAIL ROM - move to gba/ root|!!"
    "PokeLand 0 - Episode 1"                       = "PokeLand Episode 1|Cross"
    "Pokemon RadiCLA"                              = "Pokemon RadiCLA|Rand"
    "Pokemon The Legend of Zelda Minish Quest"     = "Pokemon Zelda Minish Quest|Cross"
    "Pokemblem"                                    = "Pokemblem|Cross"
    "Darkest Emblem 2"                             = "Darkest Emblem 2|Cross"
    "Andaron Saga"                                 = "Andaron Saga|Cross"
    "Pokemon Omega Ruby Origins"                   = "Pokemon Omega Ruby Origins|Story"
    "Pokemon Aesthetic Red"                        = "Pokemon Aesthetic Red|QoL"
    "Pokemon_Righteous_Red"                        = "Pokemon Righteous Red|Story"
    "Pokemon_PureRed"                              = "Pokemon Pure Red|QoL"
    "Pokemon - Red Version Colorized"              = "Pokemon Red Colorized|Patch"
    "Pokemon Heartgold Generations"                = "Pokemon HeartGold Generations|QoL"
    "Pokemon HeartGold Lux"                        = "Pokemon HeartGold Lux|QoL"
    "Pokemon Ambrosia (Crystal)"                   = "Pokemon Ambrosia Crystal|Story"
    "Pokemon TCG Generations"                      = "Pokemon TCG Generations|Story"
    "Pokemon TCG Neo Ver"                          = "Pokemon TCG Neo|Story"
    "Pokemon Complete Crystal"                     = "Pokemon Complete Crystal|QoL"
    "Pokemon Crystal Adventures"                   = "Pokemon Crystal Adventures|Story"
    "Pokemon Crystal Clear"                        = "Pokemon Crystal Clear|Story"
    "Pokemon Modern Crystal"                       = "Pokemon Modern Crystal|QoL"
    "Pokemon Extreme Yellow"                       = "Pokemon Extreme Yellow|Story"
    "Pokemon Yellow Legacy"                        = "Pokemon Yellow Legacy|QoL"
    "Pokemon Sword and Shield Ultimate Plus"       = "Pokemon Sword Shield Ultimate Plus|Story"
    "Pokemon Sword and Shield Ultimate"            = "Pokemon Sword Shield Ultimate|Story"
    "Pokemon Sun Moon GBA"                         = "Pokemon Sun Moon GBA|Story"
    # GBA - name fixes
    "Pokemon Crossroads Hoenn"                     = "Pokemon Crossroads Hoenn|Cross"
    "Pokemon Crossroads Kanto"                     = "Pokemon Crossroads Kanto|Cross"
    "Pokemon Crossroads Beta 1.0 hoenn"            = "Pokemon Crossroads Hoenn|Cross"
    "Pokemon Crossroads Beta 1.0 kanto"            = "Pokemon Crossroads Kanto|Cross"
    "Fire Emblem The Blazing Blade Plus"           = "Fire Emblem Blazing Blade Plus|QoL"
    "Fire Emblem - The Blazing Blade Plus"         = "Fire Emblem Blazing Blade Plus|QoL"
    "Fire Emblem - Sacred Stones Plus"             = "Fire Emblem Sacred Stones Plus|QoL"
    "Pokemon Emerald - Seaglass"                   = "Pokemon Emerald Seaglass|QoL"
    "Pokemon Odyssey Beta"                         = "Pokemon Odyssey|Story"
    "Rose Gold NDS Demo"                           = "Rose Gold NDS|Story"
    "Pokemon Mystery Dungeon - Explorers Of Skies" = "PMD Explorers of Skies|Story"
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
    "AutoRandomized|IronMon|Randomized|\bROWE\b|RadiCLA|\bRandom\b"       = "Rand"
    "\bRogue\b|Nuzlomizer|Soulslike|The Pit|Rescue Team EX"               = "Rogue"
    "Kaizo|Radical Red|Inclement|Blazing Emerald|Darkfire"                = "Diff"
    "Jimmy QOL|Reignited|Deluxe|\bLegacy\b|Polished|Contemporary|Seaglass|Squared|\bMini\b|Complete Crystal|Modern Crystal|Pure Red|Pure Blue|Pure Green|Aesthetic|Colorized|Crystal Clear|Glazed|\bLux\b|HeartGold Generations|Advance Wars Returns|Blazing Blade|Sealed Sword|Sacred Stones Plus" = "QoL"
    "Mariomon|Pokemblem|PokeLand|Minish Quest|Advance Wars|Fire Emblem|Kart 64|Sonic 64|Star Fox|Darkest Emblem|Andaron|Super Mario|Crossroads|Zoids" = "Cross"
    "\bFCP\b|Smooth Mario|\bStadium\b|bps patch"                          = "Patch"
}
function Get-AutoTag($title) {
    foreach ($pat in $tagRules.Keys) {
        if ($title -match $pat) { return $tagRules[$pat] }
    }
    return "Story"
}
function Extract-Version($n) {
    # Date pattern (D-M-YY)
    if ($n -match "\s*\((\d{1,2}-\d{1,2}-\d{2}(?:-\d+)?)\)\s*$") {
        $matched = $Matches[0]; $cap = $Matches[1]
        $cleaned = $n.Substring(0, $n.Length - $matched.Length).TrimEnd()
        return @($cleaned, "($cap)")
    }
    # Version in parens like (v1.2.3), (1.2.3b), (2.65 beta 2)
    if ($n -match "\s*\((v?[\d][\d.\-]*(?:\s*(?:beta\s*\d*|alpha|demo))?[a-zA-Z]?)\)\s*$") {
        $matched = $Matches[0]; $v = $Matches[1].Trim()
        if ($v -notmatch "^v") { $v = "v$v" }
        $cleaned = $n.Substring(0, $n.Length - $matched.Length).TrimEnd()
        return @($cleaned, "($v)")
    }
    # Single-word edition suffix like (Simple)
    if ($n -match "(?i)^(.*?)\s*\((Simple|Standard|Lite|Full|Base|Beta|Demo)\)\s*$") {
        return @($Matches[1].TrimEnd(), "($($Matches[2]))")
    }
    # Trailing bare version like v1.2.3 or v2.0.1a
    if ($n -match "\s+(v[\d][\d.\-]*[a-z]?)\s*$") {
        $matched = $Matches[0]; $v = $Matches[1].Trim()
        $cleaned = $n.Substring(0, $n.Length - $matched.Length).TrimEnd()
        return @($cleaned, "($v)")
    }
    # Trailing numeric like 3.3 or 1.0.5
    if ($n -match "\s+(\d+\.[\d.]+)\s*$") {
        $matched = $Matches[0]; $v = $Matches[1].Trim()
        $cleaned = $n.Substring(0, $n.Length - $matched.Length).TrimEnd()
        return @($cleaned, "(v$v)")
    }
    return @($n, "")
}
function Process-Name($filename) {
    $base     = [System.IO.Path]::GetFileNameWithoutExtension($filename)
    $ext      = [System.IO.Path]::GetExtension($filename)
    $stripped = $base -replace "^\d{3}[\s_-]+", ""
    # Try override - exact or startsWith
    $overrideKey = $null
    foreach ($k in ($overrides.Keys | Sort-Object { $_.Length } -Descending)) {
        if ($stripped -like "$k*" -or $stripped -eq $k) { $overrideKey = $k; break }
    }
    # Try override on stripped-of-version name
    if (-not $overrideKey) {
        $noVer = $stripped -replace "\s*\(.*$","" -replace "\s+v\d.*$","" -replace "\s+\d[\d.]+.*$",""
        $noVer = $noVer.TrimEnd(" -")
        foreach ($k in ($overrides.Keys | Sort-Object { $_.Length } -Descending)) {
            if ($noVer.Trim() -eq $k) { $overrideKey = $k; break }
        }
    }
    if ($overrideKey) {
        $parts     = $overrides[$overrideKey] -split "\|"
        $cleanTitle = $parts[0]
        $tag        = $parts[1]
        $verParts  = Extract-Version $stripped
        $ver        = if ($verParts[1]) { " $($verParts[1])" } else { "" }
        return [PSCustomObject]@{ Title = $cleanTitle; Tag = $tag; Ver = $ver }
    }
    # Auto-normalize
    $n = $stripped
    $n = $n -replace "e","e"  # no-op placeholder
    $n = $n -replace "é","e" -replace "è","e" -replace "ê","e" -replace "É","E"
    $n = $n -replace "\s*\(if\([^)]*\)[.]*\)", ""
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
# Collect
$allRoms = Get-ChildItem -Path $RootPath -Recurse |
    Where-Object { $_.FullName -like "*\romhacks\*" -and $exts -contains $_.Extension.ToLower() } |
    Sort-Object { ($_.FullName -split "\\romhacks\\")[0] | Split-Path -Leaf },
                { ($_.FullName -split "\\romhacks\\")[1] -split "\\" | Select-Object -First 1 },
                Name
$currentSys = ""; $currentSub = ""; $flags = @(); $changes = 0; $nochange = 0
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
        $flags += $rom.Name
    } else {
        $newName = "$prefix - $($result.Title) [$($result.Tag)]$($result.Ver)$($rom.Extension)"
        if ($newName -ne $rom.Name) {
            Write-Host "  $($rom.Name)" -ForegroundColor DarkGray
            Write-Host "  -> $newName" -ForegroundColor Yellow
            Write-Host ""
            $changes++
        } else {
            Write-Host "  $($rom.Name) (unchanged)" -ForegroundColor DarkGray
            $nochange++
        }
    }
}
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "  Files to rename : $changes"
Write-Host "  Already clean   : $nochange"
if ($flags.Count -gt 0) {
    Write-Host "`n  ACTION REQUIRED:" -ForegroundColor Red
    $flags | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
}
