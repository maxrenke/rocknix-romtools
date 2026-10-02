<#
.SYNOPSIS
    Imports Rocknix romhacks (D:\RocknixBackup\<sys>\romhacks\) into Playnite as emulated
    games, with metadata pulled from rom-catalog.html (description, version, tags), all placed
    in the "Emulator" category. Launch uses direct File actions to the configured emulators:
        GB/GBC/GBA/NES -> BizHawk (EmuHawk.exe)   NDS -> melonDS   N64 -> Rosalie's Mupen GUI (RMG.exe)
    Idempotent: ROMs already present in Playnite (matched by path) are skipped. Excludes OLD\.

.PARAMETER Source      Catalog/ROM root. Default D:\RocknixBackup
.PARAMETER Catalog     rom-catalog.html. Default <Source>\rom-catalog.html
.PARAMETER Library     Playnite library dir. Default %APPDATA%\Playnite\library
.PARAMETER LiteDbDll   LiteDB.dll. Default %LOCALAPPDATA%\Playnite\LiteDB.dll
.PARAMETER IncludeOld  Also import superseded ROMs under OLD\. Default off.
.PARAMETER DryRun      Report what would happen; write nothing.

.NOTES Playnite MUST be fully closed (incl. tray) before running.
#>
[CmdletBinding()]
param(
    [string]$Source    = "D:\RocknixBackup",
    [string]$Catalog   = "",
    [string]$Library   = "$env:APPDATA\Playnite\library",
    [string]$LiteDbDll = "$env:LOCALAPPDATA\Playnite\LiteDB.dll",
    [switch]$IncludeOld,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
if (-not $Catalog) { $Catalog = Join-Path $Source 'rom-catalog.html' }
if (Get-Process -Name 'Playnite*' -ErrorAction SilentlyContinue) { throw "Close Playnite fully (incl. tray) before running." }
Add-Type -Path $LiteDbDll

$EMU_CATEGORY_ID = 'fc24f29d-e419-4f69-8dc7-5186723f5ea3'   # existing "Emulator" category
# All systems launch via RetroArch with the appropriate libretro core (changed from
# standalone BizHawk/melonDS/RMG). To switch a system back, restore its exe/args/wd.
$RA    = 'C:\RetroArch-Win64'
$RAEXE = "$RA\retroarch.exe"
$CORES = "$RA\cores"
# per-system: platform GUID, launcher exe, args (with {ROM} placeholder), working dir, extensions
$SysCfg = @{
  gb  = @{ plat='e0104814-7380-4403-a35a-0decfba60ac9'; exe=$RAEXE; args="-L `"$CORES\gambatte_libretro.dll`" `"{ROM}`""; wd=$RA; ext=@('gb','sgb') }
  gbc = @{ plat='7cb43636-5271-49a6-8fa1-1a944fb84eba'; exe=$RAEXE; args="-L `"$CORES\gambatte_libretro.dll`" `"{ROM}`""; wd=$RA; ext=@('gbc') }
  gba = @{ plat='861948e4-8c3c-481f-8dbc-917d49a169bf'; exe=$RAEXE; args="-L `"$CORES\mgba_libretro.dll`" `"{ROM}`""; wd=$RA; ext=@('gba') }
  nes = @{ plat='d7dfcad0-377a-425d-b47a-7212e0f19d92'; exe=$RAEXE; args="-L `"$CORES\nestopia_libretro.dll`" `"{ROM}`""; wd=$RA; ext=@('nes') }
  nds = @{ plat='ac6ec908-1021-4028-b7f6-ff8dcf574c1c'; exe=$RAEXE; args="-L `"$CORES\desmume_libretro.dll`" `"{ROM}`""; wd=$RA; ext=@('nds') }
  n64 = @{ plat='e4528289-df58-4408-9bbf-746aa69b9534'; exe=$RAEXE; args="-L `"$CORES\mupen64plus_next_libretro.dll`" `"{ROM}`""; wd=$RA; ext=@('z64','n64','v64') }
  snes= @{ plat='895347e2-fcf0-40a2-9788-f21616b98b52'; exe=$RAEXE; args="-L `"$CORES\snes9x_libretro.dll`" `"{ROM}`""; wd=$RA; ext=@('sfc','smc') }
}

# ---- parse catalog ----
$html = Get-Content -LiteralPath $Catalog -Raw
$idx = @{}
$rx = [regex]'\{num:(\d+),name:"([^"]*)",ver:"([^"]*)",sys:"([^"]*)",cat:"([^"]*)",status:"([^"]*)",base:"([^"]*)",desc:"([^"]*)"(.*?)tier:"([^"]*)"'
function Norm([string]$s){ (((($s -replace '[^a-zA-Z0-9]',' ') -replace '\s+',' ').Trim()).ToLower()) }
function NormPath([string]$p){ ($p -replace '\\+','\').ToLower().TrimEnd('\') }
foreach ($m in $rx.Matches($html)) {
  $e = [pscustomobject]@{
    name=$m.Groups[2].Value; ver=$m.Groups[3].Value; sys=$m.Groups[4].Value; cat=$m.Groups[5].Value
    status=$m.Groups[6].Value; base=$m.Groups[7].Value; desc=$m.Groups[8].Value
    star=($m.Groups[9].Value -match 'star:true'); tier=$m.Groups[10].Value
  }
  if ($e.tier -ne 'retail' -and $e.status -ne 'retail') {
    $k = "$($e.sys)|$(Norm $e.name)"
    $cur = $idx[$k]
    $curOld = $cur -and ($cur.status -eq 'old' -or $cur.tier -eq 'old')
    $newOld = ($e.status -eq 'old' -or $e.tier -eq 'old')
    if (-not $cur -or ($curOld -and -not $newOld)) { $idx[$k] = $e }   # prefer current over superseded
  }
}
"Catalog romhack entries parsed: $($idx.Count)"

# ---- scan ROM files, match to catalog ----
$jobs = @()
foreach ($sys in $SysCfg.Keys) {
  $root = Join-Path $Source "$sys\romhacks"
  if (-not (Test-Path -LiteralPath $root)) { continue }
  foreach ($f in Get-ChildItem -LiteralPath $root -Recurse -File) {
    if ($f.Extension.TrimStart('.').ToLower() -notin $SysCfg[$sys].ext) { continue }
    if (-not $IncludeOld -and $f.FullName -match '\\OLD\\') { continue }
    $title = ($f.BaseName -replace '^\d{3} - ','') -replace '\s*\[[^\]]*\].*$',''
    $tag = if ($f.BaseName -match '\[([^\]]+)\]') { $matches[1] } else { '' }
    $folderTier = $f.Directory.Name
    $e = $idx["$sys|$(Norm $title)"]
    $jobs += [pscustomobject]@{
      sys=$sys; file=$f; title=$title; matched=[bool]$e
      name = if($e){$e.name}else{$title}
      desc = if($e){$e.desc}else{''}
      ver  = if($e){$e.ver}else{''}
      cat  = if($e){$e.cat}else{$tag}
      tier = if($e){$e.tier}else{$folderTier}
      base = if($e){$e.base}else{''}
      star = if($e){$e.star}else{$false}
    }
  }
}
"ROM files found: $($jobs.Count)  (matched to catalog: $(@($jobs|? matched).Count), unmatched: $(@($jobs|? {-not $_.matched}).Count))"

# ---- existing rom paths in Playnite (dedup) + delete TEST games ----
$gdb = New-Object LiteDB.LiteDatabase("Filename=$Library\games.db")
$gcol = $gdb.GetCollection("Game")
$existing = New-Object 'System.Collections.Generic.HashSet[string]'
$testIds = @()
foreach ($g in $gcol.FindAll()) {
  if ($g['Name'].AsString -match '^TEST ') { $testIds += $g['_id'] }
  if ($g.ContainsKey('Roms') -and -not $g['Roms'].IsNull) {
    $inst = if($g.ContainsKey('InstallDirectory')){$g['InstallDirectory'].AsString}else{''}
    foreach ($r in $g['Roms'].AsArray) {
      $p = ($r['Path'].AsString) -replace '\{InstallDir\}', $inst
      [void]$existing.Add((NormPath $p))
    }
  }
}

$toImport = $jobs | Where-Object { -not $existing.Contains((NormPath (Join-Path $_.file.DirectoryName $_.file.Name))) }
"Already in Playnite (skip): $($jobs.Count - $toImport.Count)   To import: $($toImport.Count)   TEST entries to remove: $($testIds.Count)"

if ($DryRun) {
  "`n-- DRY RUN; nothing written. Sample of first 12 to import: --"
  $toImport | Select-Object -First 12 | ForEach-Object { "  [{0}] {1}  (cat={2} tier={3} matched={4})" -f $_.sys.ToUpper(), $_.name, $_.cat, $_.tier, $_.matched }
  $gdb.Dispose(); return
}

# ---- backup games.db ----
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
Copy-Item "$Library\games.db" "$Library\games.db.bak_import_$stamp" -Force
"Backup: games.db.bak_import_$stamp"

# remove TEST games
foreach ($tid in $testIds) { [void]$gcol.Delete($tid) }

# ---- ensure tags exist (tags.db) ----
$tagNames = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($j in $toImport) {
  [void]$tagNames.Add('Romhack'); [void]$tagNames.Add($j.sys.ToUpper())
  if ($j.cat)  { [void]$tagNames.Add($j.cat) }
  if ($j.tier) { [void]$tagNames.Add((Get-Culture).TextInfo.ToTitleCase($j.tier)) }
  if ($j.base) { [void]$tagNames.Add($j.base) }
  if ($j.star) { [void]$tagNames.Add('Pick') }
}
$tdb = New-Object LiteDB.LiteDatabase("Filename=$Library\tags.db")
$tcol = $tdb.GetCollection("Tag")
$tagMap = @{}
foreach ($t in $tcol.FindAll()) { $tagMap[$t['Name'].AsString] = $t['_id'].AsGuid }
foreach ($name in $tagNames) {
  if (-not $tagMap.ContainsKey($name)) {
    $doc = New-Object LiteDB.BsonDocument
    $gid = [guid]::NewGuid(); $doc['_id'] = [LiteDB.BsonValue]::new($gid); $doc['Name'] = $name
    [void]$tcol.Insert($doc); $tagMap[$name] = $gid
  }
}
$tdb.Dispose()

# ---- build + insert games (inline; scope-safe, insert immediately) ----
$n = 0
foreach ($j in $toImport) {
  $s = $SysCfg[$j.sys]
  $rom = Join-Path $j.file.DirectoryName $j.file.Name
  $d = New-Object LiteDB.BsonDocument
  $d['_id'] = [LiteDB.BsonValue]::new([guid]::NewGuid())
  $d['Name'] = [string]$j.name
  if ($j.desc) { $d['Description'] = [string]$j.desc }
  if ($j.ver)  { $d['Version'] = [string]$j.ver }
  $d['Hidden'] = $false; $d['Favorite'] = $false
  $d['InstallDirectory'] = [string]$j.file.DirectoryName
  $d['GameId'] = [guid]::NewGuid().ToString()
  $d['PluginId'] = [LiteDB.BsonValue]::new([guid]::Empty)
  $d['IncludeLibraryPluginAction'] = $true
  $act = New-Object LiteDB.BsonDocument
  $act['Type']='File'; $act['Path']=[string]$s.exe; $act['Arguments']=[string]($s.args.Replace('{ROM}', $rom))
  $act['OverrideDefaultArgs']=$false; $act['Name']='Play'; $act['IsPlayAction']=$true; $act['WorkingDir']=[string]$s.wd
  $act['TrackingMode']='Default'; $act['InitialTrackingDelay']=[int]0; $act['TrackingFrequency']=[int]2000
  $aArr = New-Object LiteDB.BsonArray; [void]$aArr.Add($act); $d['GameActions']=$aArr
  $pArr = New-Object LiteDB.BsonArray; [void]$pArr.Add([LiteDB.BsonValue]::new([guid][string]$s.plat)); $d['PlatformIds']=$pArr
  $r = New-Object LiteDB.BsonDocument; $r['Name']=[string]$j.name; $r['Path']="{InstallDir}\$($j.file.Name)"
  $rArr = New-Object LiteDB.BsonArray; [void]$rArr.Add($r); $d['Roms']=$rArr
  $cArr = New-Object LiteDB.BsonArray; [void]$cArr.Add([LiteDB.BsonValue]::new([guid]$EMU_CATEGORY_ID)); $d['CategoryIds']=$cArr
  $names = @('Romhack', $j.sys.ToUpper())
  if ($j.cat) { $names += [string]$j.cat }
  if ($j.tier){ $names += (Get-Culture).TextInfo.ToTitleCase([string]$j.tier) }
  if ($j.base){ $names += [string]$j.base }
  if ($j.star){ $names += 'Pick' }
  $tArr = New-Object LiteDB.BsonArray
  foreach ($nm in ($names | Select-Object -Unique)) { if ($tagMap.ContainsKey($nm)) { [void]$tArr.Add([LiteDB.BsonValue]::new([guid]$tagMap[$nm])) } }
  $d['TagIds']=$tArr
  $nowv = [LiteDB.BsonValue]::new([datetime]::UtcNow)
  $d['Added']=$nowv; $d['Modified']=$nowv; $d['IsInstalled']=$true
  $d['SourceId']=[LiteDB.BsonValue]::new([guid]::Empty)
  [void]$gcol.Insert($d['_id'], $d)
  $n++
}
$total = $gcol.Count()
$gdb.Dispose()

"Imported: $n   |   Playnite game count now: $total"
"Done. Reopen Playnite to see the games (Category = Emulator)."
