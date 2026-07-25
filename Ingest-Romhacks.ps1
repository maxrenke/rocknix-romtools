<#
.SYNOPSIS
  End-to-end romhack ingest for the Rocknix catalog. Scans an inbox (Downloads) for new ROMs/
  patches, classifies each as an UPDATE (matches an existing catalog entry) or NEW, normalizes
  file naming + placement, updates rom-catalog.html, prunes dangling Playnite entries, then runs
  the full pipeline: Import -> Link -> Categories -> Collections -> Gamelists -> Backup.

  UPDATES are fully automatic: version detected from the filename, catalog version bumped, file
  placed as "<prefix> - <Name> [<Cat>] (<ver>).<ext>" in the same tier folder, old version moved
  to <sys>\romhacks\OLD\.
  NEW hacks PROMPT for name/category/tier/base/description (the judgment part a script can't do).
  Use -DefaultsForNew to accept the guesses unattended.
  .bps patches: prompts for / auto-finds a base ROM and applies it (CRC-verified) before ingest.

.PARAMETER Inbox          Folder to scan (top level). Default ~\Downloads
.PARAMETER Root           Catalog/ROM root. Default D:\RocknixBackup
.PARAMETER Days           Only consider files modified within N days (0 = all). Default 3
.PARAMETER DryRun         Plan only; change nothing.
.PARAMETER DefaultsForNew Don't prompt for new hacks; use guessed name + Story/extras.
.PARAMETER SkipPipeline   Do ingest + catalog only; skip Import/Link/Categories/Collections/Gamelists/Backup.

.NOTES Playnite must be closeable (the script closes it for the DB steps). Run from D:\RocknixBackup.
#>
[CmdletBinding()]
param(
  [string]$Inbox = "$env:USERPROFILE\Downloads",
  [string]$Root  = "D:\RocknixBackup",
  [int]$Days     = 3,
  [switch]$DryRun,
  [switch]$DefaultsForNew,
  [switch]$SkipPipeline
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
function ExtractVer([string]$b){ $m=[regex]::Match($b,'\(([vV]?\d+(?:\.\d+)+[^)]*)\)'); if($m.Success){ $v=$m.Groups[1].Value.Trim(); if($v -notmatch '^[vV]'){$v="v$v"}; return ($v -replace '^V','v') }; '' }
function XmlSafe([string]$s){ ($s -replace '"',"'" ) -replace '[{}]','' }   # catalog desc is JS double-quoted; no " or {}

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

  # match to a CURRENT catalog entry of same system (substring either direction)
  $match = $entries | ?{ $_.sys -eq $sys -and $_.status -notin 'old','retail' -and ((Norm $_.name).Contains($nrm) -or $nrm.Contains((Norm $_.name))) }
  if($match.Count -gt 1){ $match = $match | Sort-Object { [math]::Abs((Norm $_.name).Length - $nrm.Length) } | Select -First 1 }
  elseif($match.Count -eq 1){ $match=$match[0] }

  if($match){   # ---- UPDATE ----
    if($ver -eq $match.ver){ Write-Host "skip (already current): $($match.name)"; continue }
    $cur = @(CurrentFiles $sys $match.name)
    if($cur.Count -eq 0){ Write-Warning "  no existing file found for $($match.name) - treating as new"; $match=$null }
    else {
      $pfx = ($cur[0].BaseName -replace '^(\d{3}) - .*','$1')
      $folder = $cur[0].Directory.FullName
      $verStr = if($ver){" ($ver)"}else{""}
      $newFile = Join-Path $folder ("$pfx - $($match.name) [$($match.cat)]$verStr$ext")
      $updates += [pscustomobject]@{ entry=$match; old=@($cur | %{ $_.FullName }); new=$newFile; src=$src; ver=$ver }
    }
  }
  if(-not $match){   # ---- NEW ----
    $name=$clean; $cat='Story'; $tier='extras'; $base=''; $star=$false; $desc=''
    if(-not $DefaultsForNew){
      Write-Host "`nNEW: $($f.Name)  [sys=$sys ver=$(if($ver){$ver}else{'-'})]" -ForegroundColor Cyan
      $i=Read-Host "  Catalog name [$name]"; if($i){$name=$i}
      $i=Read-Host "  Category Story/QoL/Cross/Rogue/Diff/Patch/Rand [$cat]"; if($i){$cat=$i}
      $i=Read-Host "  Tier extras/favorites/definitive/roguelike [$tier]"; if($i){$tier=$i}
      $base=Read-Host "  Base game (e.g. Pokemon Crystal)"
      $star=((Read-Host "  Favorite/Pick? y/N") -match '^[yY]')
      $desc=Read-Host "  Description"
    }
    if($tier -eq 'favorites'){ $star=$true }
    $nextNum++; $nextPfx++
    $tierFolder = if($tier -in 'definitive','favorites','roguelike'){$tier}else{'extras'}
    $dir = "$Root\$sys\romhacks\$tierFolder"
    $verStr = if($ver){" ($ver)"}else{""}
    $newFile = Join-Path $dir ("{0:000} - $name [$cat]$verStr$ext" -f $nextPfx)
    $news += [pscustomobject]@{ name=$name; sys=$sys; cat=$cat; tier=$tier; base=$base; star=$star; desc=$desc; ver=$ver; src=$src; new=$newFile; num=$nextNum }
  }
}

# ---------- report plan ----------
Write-Host "`n==== PLAN ====" -ForegroundColor Yellow
$updates | %{ "UPDATE  $($_.entry.name): $($_.entry.ver) -> $($_.ver)   [$([IO.Path]::GetFileName($_.new))]" }
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
  # bump version in catalog (file: re-derived by the linker)
  $esc=[regex]::Escape($u.entry.name)
  $html = $html -replace "(\{num:$($u.entry.num),name:`"$esc`",ver:`")[^`"]*(`")", ('${1}'+$u.ver+'${2}')
}
if($news){
  $block = ($news | %{
    $d = XmlSafe $_.desc; $st = if($_.star){',star:true'}else{''}
    "{num:$($_.num),name:`"$($_.name)`",ver:`"$($_.ver)`",sys:`"$($_.sys)`",cat:`"$($_.cat)`",status:`"available`",base:`"$($_.base)`",desc:`"$d`"$st,tier:`"$($_.tier)`"}"
  }) -join ",`n"
  foreach($n in $news){ if(-not (Test-Path (Split-Path $n.new))){ New-Item -ItemType Directory -Force (Split-Path $n.new)|Out-Null }; Copy-Item -LiteralPath $n.src $n.new -Force }
  $ins = $html.LastIndexOf('];', $html.IndexOf('const SYSTEMS'))
  $html = $html.Substring(0,$ins) + $block + ",`n" + $html.Substring($ins)
}
[IO.File]::WriteAllText($Catalog,$html,(New-Object Text.UTF8Encoding($false)))
"Catalog updated: $($updates.Count) bumped, $($news.Count) added. Files placed."

if($SkipPipeline){ "SkipPipeline set - done (run the workflow + Generate-Gamelists yourself)."; return }

# ---------- pipeline ----------
# close Playnite
$p=Get-Process -Name 'Playnite*' -EA SilentlyContinue
if($p){ $p|%{ $_.CloseMainWindow()|Out-Null }; Start-Sleep 4; $p=Get-Process -Name 'Playnite*' -EA SilentlyContinue; if($p){ $p|Stop-Process -Force; Start-Sleep 2 } }
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
