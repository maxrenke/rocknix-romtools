<#
.SYNOPSIS
  End-to-end romhack ingest for the Rocknix catalog. Scans an inbox (Downloads) for new ROMs/
  patches, classifies each as an UPDATE (matches an existing catalog entry) or NEW, normalizes
  file naming + placement, updates rom-catalog.html, prunes dangling Playnite entries, then runs
  the full pipeline: Renumber -> Prune -> Import -> Link -> Categories -> Collections ->
  Shortcuts -> Backup -> Gamelists.

  UPDATES are fully automatic: version detected from the filename, catalog version bumped, file
  placed as "<prefix> - <Name> [<Cat>] (<ver>).<ext>" in the same tier folder, old version moved
  to <sys>\romhacks\OLD\.
  NEW hacks PROMPT for name/category/tier/base/description/demake (the judgment part a
  script can't do). "Demake" = a GBA-base hack named after a non-GBA-generation game
  (HeartGold, Platinum, Sword/Shield, Crystal, ...); the y/N prompt is pre-filled from a
  keyword guess (Test-LikelyDemake) but always asked, since the guess has known false
  positives (native GBA IP like Golden Sun, GBA-native remakes like LeafGreen).
  Use -DefaultsForNew to accept the guesses (including the demake guess) unattended.
  .bps patches: prompts for / auto-finds a base ROM and applies it (CRC-verified) before ingest.

.PARAMETER Inbox          Folder to scan (top level). Default ~\Downloads
.PARAMETER Root           Catalog/ROM root. Default D:\RocknixBackup
.PARAMETER Days           Only consider files modified within N days (0 = all). Default 3
.PARAMETER DryRun         Plan only; change nothing.
.PARAMETER DefaultsForNew Don't prompt for new hacks; use guessed name + Story/extras.
.PARAMETER SkipPipeline   Do ingest + catalog only; skip Import/Link/Categories/Collections/Gamelists/Backup.
.PARAMETER SkipRenumber   Skip the renumber step inside the pipeline. Prefixes then keep
                          whatever values they had; the newest arrival will NOT sort to 001.
.PARAMETER KeepSource     Leave the ingested originals in the inbox. By default a source
                          file is deleted once its placed copy exists and byte-matches,
                          because placement is a copy and the leftover otherwise looks
                          un-ingested on the next run.

.NOTES Playnite must be closeable (the script closes it for the DB steps). Run from D:\RocknixBackup.
#>
[CmdletBinding()]
param(
  [string]$Inbox = "$env:USERPROFILE\Downloads",
  [string]$Root  = "D:\RocknixBackup",
  [int]$Days     = 3,
  [switch]$DryRun,
  [switch]$DefaultsForNew,
  [switch]$SkipPipeline,
  [switch]$KeepSource,
  [switch]$SkipRenumber
)
$ErrorActionPreference = 'Stop'
$Catalog = Join-Path $Root 'rom-catalog.html'
$ExtSys  = @{ '.gba'='gba'; '.gbc'='gbc'; '.gb'='gbc'; '.nds'='nds'; '.z64'='n64'; '.n64'='n64'; '.v64'='n64'; '.nes'='nes'; '.sfc'='snes'; '.smc'='snes' }
$RomExt  = @($ExtSys.Keys)
$PatchExt= @('.bps')
$EmuExt  = @{ gba='gba'; gbc='gbc'; nds='nds'; n64='z64'; nes='nes'; snes='sfc' }   # output ext per sys

function StripAccents([string]$s){ $n=$s.Normalize([Text.NormalizationForm]::FormD); (-join ($n.ToCharArray()|?{[Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark'})) }
function Norm([string]$s){ ((StripAccents $s) -replace '[^a-zA-Z0-9]','').ToLower() }
function CleanName([string]$b){ $x=StripAccents $b; $x=$x -replace '\[[^\]]*\]',''; $x=$x -replace '\([^)]*\)',''; $x=$x -replace '_',' '; ($x -replace '\s+',' ').Trim() }
# Version out of "(...)" in the filename.
# Dashed dates are checked FIRST and returned verbatim: some hacks version by
# release date, e.g. Crystal Advance Redux ships "(1-8-26)". The dotted-version
# pattern below cannot match those (it needs a '.' separator), so they used to
# come back empty - which wrote ver:"" into the catalog and dropped the version
# out of the placed filename entirely. They also must NOT be given a "v"
# prefix; the catalog stores these bare, as "26-7-26".
function ExtractVer([string]$b){
  $d=[regex]::Match($b,'\((\d{1,2}-\d{1,2}-\d{2,4})\)')
  if($d.Success){ return $d.Groups[1].Value }
  $m=[regex]::Match($b,'\(([vV]?\d+(?:\.\d+)+[^)]*)\)')
  if($m.Success){ $v=$m.Groups[1].Value.Trim(); if($v -notmatch '^[vV]'){$v="v$v"}; return ($v -replace '^V','v') }
  ''
}
function XmlSafe([string]$s){ ($s -replace '"',"'" ) -replace '[{}]','' }   # catalog desc is JS double-quoted; no " or {}

# "Demake" heuristic: a GBA-base hack whose NAME references a non-GBA-generation
# Pokemon title (Platinum, HeartGold, Black/White, Sword/Shield, Scarlet/Violet,
# Crystal, Gold/Silver, Let's Go, Legends Arceus, Omega Ruby/Alpha Sapphire...).
# Only ever a DEFAULT for the "Demake? y/N" prompt below, never an auto-decision -
# a naive keyword match has real false positives (native GBA IP like Golden Sun,
# or GBA-native remakes like LeafGreen) which is exactly why this stays a
# suggestion the operator confirms rather than something written unattended,
# except under -DefaultsForNew where the caller has already accepted that
# every guessed field may need a manual correction pass.
$DEMAKE_TERMS = 'platinum|diamond|pearl|heart ?gold|soul ?silver|heart ?and ?soul|\bblack\b|\bwhite\b|\bsword\b|\bshield\b|scarlet|violet|\bsun\b|\bmoon\b|\bcrystal\b|\bgold\b|\bsilver\b|legends|arceus|omega ?ruby|alpha ?sapphire|let''?s ?go'
$DEMAKE_EXCLUDE = 'golden ?sun|leafgreen|leaf ?green|firered ?emerald|fire ?red ?emerald'
function Test-LikelyDemake([string]$sys,[string]$cleanName){
  if($sys -ne 'gba'){ return $false }
  if($cleanName -match $DEMAKE_EXCLUDE){ return $false }
  return [bool]($cleanName -match $DEMAKE_TERMS)
}

# Lowercase alphanumeric word tokens, for matching that respects word bounds.
function Toks([string]$s){ @((((StripAccents $s) -replace '[^a-zA-Z0-9]',' ') -split '\s+') | ?{ $_ } | %{ $_.ToLower() }) }
# True when the shorter token list is a CONTIGUOUS PREFIX of the longer one.
# Prefix, not subset: a variant almost always extends the base name at the END
# ("Pokemon The Pit" -> "Pokemon The Pit Gen 9"), whereas a mere subset lets
# unrelated names collide -- [pokemon,emerald,ex] is a subset of
# [pokemon,emerald,rogue,ex] but a prefix of neither. Whole-token comparison
# also rejects "ex" ~ "extended", which raw substring matching accepted.
function TokenPrefix($a,$b){
  if(-not $a -or -not $b -or $a.Count -eq 0 -or $b.Count -eq 0){ return $false }
  $short,$long = if($a.Count -le $b.Count){ ,$a + ,$b } else { ,$b + ,$a }
  for($i=0; $i -lt $short.Count; $i++){ if($short[$i] -ne $long[$i]){ return $false } }
  return $true
}

# ---------- filename -> catalog name aliases ----------
# The fuzzy matcher below is substring-only in both directions, so it fails
# whenever the author's release filename is not a substring of the catalog
# name (or vice versa). Two real cases:
#   "FireEmerald"          vs "Pokemon FireRed Emerald"  -> the intervening
#                             "red" breaks the substring both ways
#   "PMD_ Explorers Remixed!" vs "Pokemon Mystery Dungeon Explorers of Sky
#                             Remixed" -> abbreviation
# Both silently ingested as NEW and had to be hand-filed.
#
# It also matches too eagerly: a NEW hack whose name CONTAINS an existing
# entry gets taken for an update to it. "Pokemon Odyssey II - Heroes of
# Lemuria" resolved to "Pokemon Odyssey" and would have overwritten it, back
# when Odyssey II was not yet in the catalog. Pinning the short name of every
# such pair makes an exact filename resolve to itself no matter what the
# fuzzy pass or its length tie-break would have preferred.
#
# KEY   = Norm(CleanName(<download filename stem>)) - lowercase alphanumerics
#         only, version parens already stripped.
# VALUE = the exact catalog `name`. Checked before the fuzzy pass; an entry
#         here that matches no live catalog row is reported, not silently
#         ignored.
$ALIAS = @{
  # --- confirmed misses (verified against the live matcher) ---
  'fireemerald'                                  = 'Pokemon FireRed Emerald'
  'pmdexplorersremixed'                          = 'Pokemon Mystery Dungeon Explorers of Sky Remixed'
  # --- name-collision traps: DIFFERENT hacks the fuzzy pass conflates ---
  # "Pokemon Emerald Ex" normalizes to pokemonemeraldex, which is a prefix of
  # pokemonemerald|ex|tendedcut -- so it resolved to Extended Cut and would
  # have overwritten that favorites build with an unrelated hack. EEC has no
  # X.Y.Z releases at all (Classic -> Classic+ -> Hotfix 1.x), so any 1.0.0
  # "Emerald Ex" is a different project. Left unmapped on purpose: pinning it
  # to its own catalog name once it HAS one is the fix; until then this entry
  # documents why it must never be auto-matched.
  # 'pokemonemeraldex'                           = '<its own catalog entry>'
  # --- defensive pins: the short half of every substring-collision pair ---
  'pokemonemeraldextendedcut'                    = 'Pokemon Emerald Extended Cut'
  'pokemonmysterydungeonroguerescueteam'         = 'Pokemon Mystery Dungeon Rogue Rescue Team'
  'pokemonthepit'                                = 'Pokemon The Pit'
  'pokemonodyssey'                               = 'Pokemon Odyssey'
  'pokemonliquidcrystal'                         = 'Pokemon Liquid Crystal'
  'pokemonambrosia'                              = 'Pokemon Ambrosia'
  # "Sword and Shield Ultimate Plus" - filename drops "Pokemon" and inserts
  # "and", so neither the exact nor the token-prefix pass could reach
  # "Pokemon Sword Shield Ultimate Plus". Confirmed 2026-08-03: a download
  # under this exact name hashed byte-identical to the file already filed,
  # so this alias only needed to fix the version tag, not move any content -
  # but a future real update from this author would hit the same miss.
  'swordandshieldultimateplus'                   = 'Pokemon Sword Shield Ultimate Plus'
}

# ---------- parse catalog ----------
$html = [IO.File]::ReadAllText($Catalog)
$entries = @()
foreach($m in [regex]::Matches($html,'\{num:\d+,[^{}]*\}')){
  $o=$m.Value
  $entries += [pscustomobject]@{
    num=[int]([regex]'num:(\d+)').Match($o).Groups[1].Value
    name=([regex]'name:"([^"]*)"').Match($o).Groups[1].Value
    ver=([regex]'ver:"([^"]*)"').Match($o).Groups[1].Value
    sys=([regex]'sys:"([^"]*)"').Match($o).Groups[1].Value
    cat=([regex]'cat:"([^"]*)"').Match($o).Groups[1].Value
    status=([regex]'status:"([^"]*)"').Match($o).Groups[1].Value
    tier=([regex]'tier:"([^"]*)"').Match($o).Groups[1].Value
    base=([regex]'base:"([^"]*)"').Match($o).Groups[1].Value
  }
}
$maxNum = ($entries|Measure num -Max).Maximum
$rhDirs = Get-ChildItem $Root -Directory -EA SilentlyContinue | %{ Join-Path $_.FullName 'romhacks' } | ?{ Test-Path -LiteralPath $_ }
$pfxs = if($rhDirs){ Get-ChildItem -LiteralPath $rhDirs -Recurse -File -EA SilentlyContinue | %{ if($_.BaseName -match '^(\d{3}) - '){[int]$Matches[1]} } }
$maxPfx = if($pfxs){ ($pfxs | Measure-Object -Maximum).Maximum } else { 0 }
"Catalog: $($entries.Count) entries, max num $maxNum, max prefix $maxPfx"

# find ALL current rom files on disk for an entry (excludes OLD; rom-ext only, so saves like .dsv are left alone)
function CurrentFiles($sys,$name){
  $rext = '.' + $EmuExt[$sys]
  Get-ChildItem "$Root\$sys\romhacks" -Recurse -File -EA SilentlyContinue |
    ?{ $_.FullName -notmatch '\\OLD\\' -and $_.Extension -eq $rext -and (Norm ($_.BaseName -replace '^\d{3} - ','' -replace '\s*\[[^\]]*\].*$','')) -eq (Norm $name) }
}

# ---------- apply a .bps patch (CRC-verified) ----------
$bpsPy = Join-Path $env:TEMP 'ingest_bps.py'
@'
import sys,zlib,struct
patch=open(sys.argv[1],"rb").read(); src=open(sys.argv[2],"rb").read()
if patch[:4]!=b"BPS1": raise SystemExit("not BPS1")
pos=4
def v():
    global pos; d=0; sh=1
    while True:
        x=patch[pos]; pos+=1; d+=(x&0x7f)*sh
        if x&0x80: break
        sh<<=7; d+=sh
    return d
ss=v(); ts=v(); ms=v(); pos+=ms
out=bytearray(ts); oo=0; sr=0; tr=0; end=len(patch)-12
while pos<end:
    d=v(); cmd=d&3; ln=(d>>2)+1
    if cmd==0:
        for _ in range(ln): out[oo]=src[oo]; oo+=1
    elif cmd==1:
        for _ in range(ln): out[oo]=patch[pos]; pos+=1; oo+=1
    elif cmd==2:
        dd=v(); sr+=(-(dd>>1) if dd&1 else (dd>>1))
        for _ in range(ln): out[oo]=src[sr]; sr+=1; oo+=1
    else:
        dd=v(); tr+=(-(dd>>1) if dd&1 else (dd>>1))
        for _ in range(ln): out[oo]=out[tr]; tr+=1; oo+=1
if (zlib.crc32(src)&0xffffffff)!=struct.unpack("<I",patch[end:end+4])[0]: raise SystemExit("SOURCE CRC MISMATCH - wrong base ROM")
if (zlib.crc32(bytes(out))&0xffffffff)!=struct.unpack("<I",patch[end+4:end+8])[0]: raise SystemExit("TARGET CRC MISMATCH - build failed")
open(sys.argv[3],"wb").write(bytes(out)); print("OK")
'@ | Set-Content $bpsPy -Encoding UTF8

function ApplyBps($patch,$sys){
  $base = Read-Host "  .bps base ROM for '$([IO.Path]::GetFileName($patch))' (full path; blank to skip)"
  if(-not $base -or -not (Test-Path -LiteralPath $base)){ Write-Warning "  no valid base - skipping patch"; return $null }
  $out = Join-Path $env:TEMP ("ingest_" + [guid]::NewGuid().ToString('N') + "." + $EmuExt[$sys])
  $r = & python $bpsPy $patch $base $out 2>&1
  if($LASTEXITCODE -ne 0){ Write-Warning "  patch failed: $r"; return $null }
  Write-Host "  patched OK"; return $out
}

# ---------- gather candidates ----------
$cands = Get-ChildItem $Inbox -File -EA SilentlyContinue | ?{
  ($RomExt -contains $_.Extension.ToLower() -or $PatchExt -contains $_.Extension.ToLower()) -and
  ($Days -le 0 -or $_.LastWriteTime -gt (Get-Date).AddDays(-$Days))
}
if(-not $cands){ "No candidate ROMs/patches in $Inbox (last $Days days)."; return }
"Candidates: $($cands.Count)"

$updates=@(); $news=@(); $newCatalog=@()
$nextNum=$maxNum; $nextPfx=$maxPfx

foreach($f in $cands){
  $ext=$f.Extension.ToLower(); $src=$f.FullName
  if($PatchExt -contains $ext){
    $sys = $ExtSys[(([regex]'\.(gb|gbc|gba)$').Match($f.BaseName).Value)]  # best-effort; else ask
    if(-not $sys){ $sys = Read-Host "  system for patch '$($f.Name)' (gba/gbc/nds/...)" }
    $built = ApplyBps $src $sys; if(-not $built){ continue }
    $src=$built; $ext='.'+$EmuExt[$sys]
  } else { $sys=$ExtSys[$ext] }
  if(-not $sys){ Write-Warning "skip (unknown system): $($f.Name)"; continue }
  $clean = CleanName $f.BaseName
  $ver   = ExtractVer $f.BaseName
  $nrm   = Norm $clean

  # match to a CURRENT catalog entry of same system.
  # Order: explicit alias -> exact normalized name -> substring either direction.
  # $how records which rule fired so the plan can show it: a fuzzy hit is the
  # one that can silently retarget the wrong entry, so it must be visible
  # before anything is moved.
  $live  = $entries | ?{ $_.sys -eq $sys -and $_.status -notin 'old','retail' }
  $match = $null; $how = ''

  if($ALIAS.ContainsKey($nrm)){
    $want  = $ALIAS[$nrm]
    $match = $live | ?{ $_.name -eq $want } | Select -First 1
    if($match){ $how = 'alias' }
    else { Write-Warning "alias '$nrm' -> '$want' matches no live $sys entry - check `$ALIAS in this script" }
  }
  if(-not $match){
    $match = $live | ?{ (Norm $_.name) -eq $nrm } | Select -First 1
    if($match){ $how = 'exact' }
  }
  if(-not $match){
    # Token-subset, NOT raw substring. A plain substring test matches across
    # word boundaries: "Pokemon Emerald Ex" -> pokemonemerald|ex|tendedcut is a
    # prefix of "Pokemon Emerald Extended Cut", so an unrelated hack resolved
    # to that entry and would have overwritten it. Requiring every token of
    # the shorter name to appear as a WHOLE token in the longer one rejects
    # that ("ex" is not "extended") while still catching the real supersets
    # ("Pokemon The Pit" inside "Pokemon The Pit Gen 9").
    $ftok = @(Toks $clean)
    $cand = @($live | ?{ TokenPrefix $ftok @(Toks $_.name) })
    if($cand.Count -gt 1){ $match = $cand | Sort-Object { [math]::Abs((Norm $_.name).Length - $nrm.Length) } | Select -First 1 }
    elseif($cand.Count -eq 1){ $match = $cand[0] }
    if($match){ $how = if($cand.Count -gt 1){ "fuzzy, $($cand.Count) candidates" } else { 'fuzzy' } }
  }
  if($match){ $match | Add-Member -NotePropertyName _how -NotePropertyValue $how -Force }

  if($match){   # ---- UPDATE ----
    if($ver -eq $match.ver){
      Write-Host "skip (already current): $($match.name)"
      # A leftover from an earlier run (placement is a copy) would otherwise sit
      # in the inbox forever, since this branch never reaches the cleanup pass.
      # Hash-verify against the placed file before removing anything.
      if(-not $KeepSource){
        $curf = @(CurrentFiles $sys $match.name)
        if($curf.Count -eq 1 -and (Test-Path -LiteralPath $f.FullName)){
          $a = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA1).Hash
          $b = (Get-FileHash -LiteralPath $curf[0].FullName -Algorithm SHA1).Hash
          if($a -eq $b){ Remove-Item -LiteralPath $f.FullName -Force; Write-Host "  removed identical leftover from inbox" -ForegroundColor DarkGray }
          else { Write-Warning "  inbox copy differs from the placed $($match.ver) file - left in place, check by hand" }
        }
      }
      continue
    }
    $cur = @(CurrentFiles $sys $match.name)
    if($cur.Count -eq 0){ Write-Warning "  no existing file found for $($match.name) - treating as new"; $match=$null }
    else {
      $pfx = ($cur[0].BaseName -replace '^(\d{3}) - .*','$1')
      $folder = $cur[0].Directory.FullName
      $verStr = if($ver){" ($ver)"}else{""}
      $newFile = Join-Path $folder ("$pfx - $($match.name) [$($match.cat)]$verStr$ext")
      $updates += [pscustomobject]@{ entry=$match; old=@($cur | %{ $_.FullName }); new=$newFile; src=$src; ver=$ver; inbox=$f.FullName }
    }
  }
  if(-not $match){   # ---- NEW ----
    $name=$clean; $cat='Story'; $tier='extras'; $base=''; $star=$false; $desc=''
    $demake=Test-LikelyDemake $sys $clean
    if(-not $DefaultsForNew){
      Write-Host "`nNEW: $($f.Name)  [sys=$sys ver=$(if($ver){$ver}else{'-'})]" -ForegroundColor Cyan
      $i=Read-Host "  Catalog name [$name]"; if($i){$name=$i}
      $i=Read-Host "  Category Story/QoL/Cross/Rogue/Diff/Patch/Rand [$cat]"; if($i){$cat=$i}
      $i=Read-Host "  Tier extras/favorites/definitive/roguelike [$tier]"; if($i){$tier=$i}
      $base=Read-Host "  Base game (e.g. Pokemon Crystal)"
      $star=((Read-Host "  Favorite/Pick? y/N") -match '^[yY]')
      # "Demake" = a GBA-base hack named after a non-GBA-generation game (HeartGold,
      # Platinum, Sword/Shield, Crystal, ...). Pre-filled from a keyword guess -
      # confirm or override, same as every other guessed field here.
      $dPrompt=Read-Host "  Demake (non-GBA name on a GBA base)? y/N [$(if($demake){'y'}else{'n'})]"
      $demake = if($dPrompt){ $dPrompt -match '^[yY]' } else { $demake }
      $desc=Read-Host "  Description"
    }
    if($tier -eq 'favorites'){ $star=$true }
    $nextNum++; $nextPfx++
    $tierFolder = if($tier -in 'definitive','favorites','roguelike'){$tier}else{'extras'}
    $dir = "$Root\$sys\romhacks\$tierFolder"
    $verStr = if($ver){" ($ver)"}else{""}
    $newFile = Join-Path $dir ("{0:000} - $name [$cat]$verStr$ext" -f $nextPfx)
    $news += [pscustomobject]@{ name=$name; sys=$sys; cat=$cat; tier=$tier; base=$base; star=$star; demake=$demake; desc=$desc; ver=$ver; src=$src; new=$newFile; num=$nextNum; inbox=$f.FullName }
  }
}

# ---------- report plan ----------
Write-Host "`n==== PLAN ====" -ForegroundColor Yellow
$updates | %{ "UPDATE  $($_.entry.name): $($_.entry.ver) -> $($_.ver)   [$([IO.Path]::GetFileName($_.new))]   (matched: $($_.entry._how))" }
if($updates | ?{ $_.entry._how -like 'fuzzy*' }){
  Write-Host "  note: a 'fuzzy' match came from a substring guess, not an exact or aliased name." -ForegroundColor DarkYellow
  Write-Host "        Confirm it targets the right entry; if not, add the filename to `$ALIAS." -ForegroundColor DarkYellow
}
$news    | %{ "NEW     #$($_.num) $($_.name) [$($_.sys)/$($_.cat)/$($_.tier)$(if($_.star){'/Pick'})]   base=$($_.base)" }
if(-not $updates -and -not $news){ "Nothing to do."; return }
if($DryRun){ "`n-- DryRun: no changes written --"; return }

# ---------- apply file moves + catalog edits ----------
foreach($u in $updates){
  # archive EVERY existing version to OLD (handles >1 stale copy left by back-to-back updates)
  foreach($old in @($u.old)){
    if($old -eq $u.new){ continue }   # never archive the file we're about to write
    $oldRoot = ((Split-Path $old) -replace '\\romhacks\\.*','\romhacks\OLD')
    if(-not (Test-Path $oldRoot)){ New-Item -ItemType Directory -Force $oldRoot|Out-Null }
    Move-Item -LiteralPath $old (Join-Path $oldRoot (Split-Path $old -Leaf)) -Force
  }
  Copy-Item -LiteralPath $u.src $u.new -Force
  # Carry saves onto the new filename. CurrentFiles deliberately returns only
  # ROMs, so a .srm/.dsv/.state sitting beside the old build is left untouched
  # above -- and when the version string is part of the filename the emulator
  # then looks for a save that no longer matches and the run reads as lost.
  # The renumber pass cannot recover it either: its map is keyed on ROM
  # basenames, and the old one is gone by then.
  $newBase = [IO.Path]::GetFileNameWithoutExtension($u.new)
  foreach($old in @($u.old)){
    $oldBase = [IO.Path]::GetFileNameWithoutExtension($old)
    if($oldBase -eq $newBase){ continue }
    $dir = Split-Path $old -Parent
    foreach($sf in @(Get-ChildItem -LiteralPath $dir -File -Filter "$oldBase.*" -EA SilentlyContinue)){
      if($RomExt -contains $sf.Extension.ToLower()){ continue }   # ROMs already archived
      $suffix = $sf.Name.Substring($oldBase.Length)               # keeps .state.png intact
      $dest   = Join-Path $dir ($newBase + $suffix)
      if(Test-Path -LiteralPath $dest){ Write-Warning "  save already at destination, left alone: $($sf.Name)"; continue }
      Move-Item -LiteralPath $sf.FullName $dest -Force
      Write-Host "  save carried forward: $($sf.Name) -> $(Split-Path $dest -Leaf)" -ForegroundColor DarkGray
    }
  }
  # bump version in catalog (file: re-derived by the linker)
  $esc=[regex]::Escape($u.entry.name)
  $html = $html -replace "(\{num:$($u.entry.num),name:`"$esc`",ver:`")[^`"]*(`")", ('${1}'+$u.ver+'${2}')
}
if($news){
  $block = ($news | %{
    $d = XmlSafe $_.desc; $st = if($_.star){',star:true'}else{''}
    $tg = if($_.demake){',tags:["Demake"]'}else{''}
    "{num:$($_.num),name:`"$($_.name)`",ver:`"$($_.ver)`",sys:`"$($_.sys)`",cat:`"$($_.cat)`",status:`"available`",base:`"$($_.base)`"$tg,desc:`"$d`"$st,tier:`"$($_.tier)`"}"
  }) -join ",`n"
  foreach($n in $news){ if(-not (Test-Path (Split-Path $n.new))){ New-Item -ItemType Directory -Force (Split-Path $n.new)|Out-Null }; Copy-Item -LiteralPath $n.src $n.new -Force }
  $ins = $html.LastIndexOf('];', $html.IndexOf('const SYSTEMS'))
  $html = $html.Substring(0,$ins) + $block + ",`n" + $html.Substring($ins)
}
[IO.File]::WriteAllText($Catalog,$html,(New-Object Text.UTF8Encoding($false)))
"Catalog updated: $($updates.Count) bumped, $($news.Count) added. Files placed."

# ---------- clear the ingested originals out of the inbox ----------
# Placement above is Copy-Item, not Move-Item, so without this the source
# stays in Downloads and looks un-ingested. Only ever remove a file whose
# destination exists and byte-matches, and only the file we actually read:
# for a .bps, .src is the built ROM in TEMP while .inbox is the patch itself.
if(-not $KeepSource){
  $cleared = 0
  foreach($rec in @($updates) + @($news)){
    $ib = $rec.inbox
    if(-not $ib -or -not (Test-Path -LiteralPath $ib)) { continue }
    if(-not (Test-Path -LiteralPath $rec.new)) { Write-Warning "  kept (destination missing): $(Split-Path $ib -Leaf)"; continue }
    if((Get-Item -LiteralPath $rec.new).Length -ne (Get-Item -LiteralPath $ib).Length) {
      Write-Warning "  kept (size mismatch vs placed file): $(Split-Path $ib -Leaf)"; continue
    }
    Remove-Item -LiteralPath $ib -Force
    $cleared++
  }
  if($cleared){ "Inbox cleared: $cleared file(s) removed from $Inbox." }
} else { "KeepSource set - originals left in $Inbox." }

if($SkipPipeline){ "SkipPipeline set - done (run the workflow + Generate-Gamelists yourself)."; return }

# ---------- pipeline ----------
# close Playnite
$p=Get-Process -Name 'Playnite*' -EA SilentlyContinue
if($p){ $p|%{ $_.CloseMainWindow()|Out-Null }; Start-Sleep 4; $p=Get-Process -Name 'Playnite*' -EA SilentlyContinue; if($p){ $p|Stop-Process -Force; Start-Sleep 2 } }

# renumber so the newest arrival sorts to 001 (oldest gets the highest prefix).
# This MUST run here: after Playnite is closed, and before the prune - the
# renames it performs are exactly what makes the old Playnite paths dangle, and
# the prune is what clears them so the workflow can reimport cleanly. Leaving it
# out (as this pipeline did) meant the ordering only ever happened when it was
# run by hand afterwards, which then needed a second manual prune + workflow.
if(-not $SkipRenumber){
  & "$Root\Organize-Romhacks.ps1" -RootPath $Root -SkipIngest -Force
  if($LASTEXITCODE -and $LASTEXITCODE -ne 0){ throw "Organize-Romhacks failed ($LASTEXITCODE) - stopping before the prune so nothing is half-renamed." }
} else { "SkipRenumber set - prefixes left as-is." }

# prune dangling RocknixBackup games (missing rom files)
Add-Type -Path "$env:LOCALAPPDATA\Playnite\LiteDB.dll"
$lib="$env:APPDATA\Playnite\library"
Copy-Item "$lib\games.db" "$lib\games.db.bak_ingest_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force
$db=New-Object LiteDB.LiteDatabase("Filename=$lib\games.db"); $col=$db.GetCollection("Game"); $pr=0
foreach($g in $col.FindAll()){
  if(-not ($g.ContainsKey('Roms') -and -not $g['Roms'].IsNull -and $g['Roms'].AsArray.Count)){ continue }
  $inst= if($g.ContainsKey('InstallDirectory') -and -not $g['InstallDirectory'].IsNull){$g['InstallDirectory'].AsString}else{''}
  $path=$g['Roms'].AsArray[0]['Path'].AsString.Replace('{InstallDir}',$inst)
  if($path -match 'RocknixBackup' -and -not (Test-Path -LiteralPath $path)){ [void]$col.Delete($g['_id']); $pr++ }
}
$db.Dispose(); "Pruned $pr dangling Playnite entries."
# run the chain
& "$Root\Invoke-RomhackWorkflow.ps1" -All
& "$Root\Generate-Gamelists.ps1"
"`n==== INGEST COMPLETE ===="
