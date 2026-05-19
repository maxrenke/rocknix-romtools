# rocknix-romtools

PowerShell and Python scripts for managing a Rocknix ROM hack library and RetroArch config backups.

## Quick start

```powershell
# Full pipeline: ingest new downloads, cleanup dupes, normalize names, re-number, sync in-progress
.\Update-Romhacks.ps1

# Preview without touching anything
.\Update-Romhacks.ps1 -DryRun
```

---

## ROM management scripts

### `Update-Romhacks.ps1` - main pipeline orchestrator

Runs all five maintenance steps in order:

| Step | Script | What it does |
|------|--------|--------------|
| 1 | Organize-Romhacks.ps1 | Ingest from Downloads + renumber |
| 2 | Cleanup-Romhacks.ps1 | Remove older duplicate versions |
| 3 | Normalize-Romhacks.ps1 | Clean filenames + apply [TAG] |
| 4 | Organize-Romhacks.ps1 | Re-number after normalize renames |
| 5 | Sync-InProgress.ps1 | Move ROMs with saves to in-progress/ |

Pauses after Step 1 if new ROMs landed in a romhacks/ root that needs subfolder sorting.

```powershell
.\Update-Romhacks.ps1
.\Update-Romhacks.ps1 -DryRun
.\Update-Romhacks.ps1 -SkipIngest   # skip Downloads intake, just clean/normalize
.\Update-Romhacks.ps1 -RootPath "E:\MyRoms"
```

---

### `Normalize-Romhacks.ps1` - filename normalizer

Renames romhack files to canonical format: `NNN - Title [TAG] (version).ext`

**Tags:** `Story`, `QoL`, `Diff`, `Rand`, `Rogue`, `Cross`, `Patch`

```powershell
.\Normalize-Romhacks.ps1 -DryRun   # preview
.\Normalize-Romhacks.ps1            # apply
```

**Features:**
- Manual override table for filenames that need specific titles/tags
- Auto-tagging via keyword rules for everything else
- Version extraction from parens `(v1.2.3)`, bare `v1.2`, numeric `1.0.5`, date `(12-5-25)`, edition words `(Beta)`, `(Demo)`
- Save file co-rename: `.srm`, `.sav`, `.dsv`, `.rtc`, `.dss` renamed alongside the ROM
- Idempotent: re-running on clean files is a no-op
- HTML check at end: reports active ROMs missing from `rom-catalog.html` and inserts placeholder entries

### `Preview-Normalize.ps1` - lightweight preview

Same logic as Normalize-Romhacks.ps1, always read-only. No `-DryRun` flag needed.

```powershell
.\Preview-Normalize.ps1
```

---

### `Organize-Romhacks.ps1` - ingest + renumber

**Phase 1 - Downloads intake:** scans `~/Downloads` for ROM files, detects retail vs romhack by region tags, moves each to the correct `system\` or `system\romhacks\` folder.

**Phase 2 - Renumber:** sorts all romhack files by creation time and assigns `NNN -` prefixes (newest = lowest number, oldest = highest, so descending alpha sort shows most recent first).

```powershell
.\Organize-Romhacks.ps1 -DryRun
.\Organize-Romhacks.ps1
.\Organize-Romhacks.ps1 -SkipIngest   # renumber only, skip Downloads scan
```

---

### `Cleanup-Romhacks.ps1` - deduplicate

Groups ROMs by base name (ignoring version strings), keeps the newest version per group by comparing version tuples, falls back to file modification time for unversioned duplicates. Also deletes `.sync-conflict*` and `.filepart` junk files.

```powershell
.\Cleanup-Romhacks.ps1
```

---

### `Sync-InProgress.ps1` - in-progress folder management

Moves ROMs that have save files into `in-progress/` subfolders. Moves them back when their save is deleted (game completed or abandoned). Uses fuzzy name matching to pair saves with ROMs that were renamed or renumbered.

```powershell
.\Sync-InProgress.ps1 -DryRun
.\Sync-InProgress.ps1
```

---

### `Get-Romhacks.ps1` - discover and download new hacks

Fetches the hackdex.app discover pages, lets you pick which hacks to download, extracts archives, and places ROMs in the correct system folder.

```powershell
.\Get-Romhacks.ps1                         # fetch live from hackdex.app
.\Get-Romhacks.ps1 -Count 20               # show more results per page
.\Get-Romhacks.ps1 -DryRun                 # preview without downloading
.\Get-Romhacks.ps1 -DumpHtml               # dump raw HTML (debug parsing issues)

# If hackdex.app blocks automated requests (Cloudflare), use local HTML:
#   1. Open https://www.hackdex.app/discover?sort=updated in browser
#   2. F12 -> Console -> copy(document.documentElement.outerHTML)
#   3. Paste to updated.html, repeat for ?sort=new -> new.html
.\Get-Romhacks.ps1 -LocalHtmlUpdated updated.html -LocalHtmlNew new.html
```

---

## RetroArch backup scripts

### `Backup-RocknixBackup.ps1` - full archive

Compresses the entire `D:\RocknixBackup` folder, distributes in parallel to a local drive (`E:\`) and a CasaOS NAS over SCP, then prunes old archives. Optionally pulls device configs first.

```powershell
.\Backup-RocknixBackup.ps1
.\Backup-RocknixBackup.ps1 -PullDevices   # pull configs from Rocknix devices first
.\Backup-RocknixBackup.ps1 -Keep 5        # keep 5 archives instead of 3
```

### `Sync-WindowsRetroArch.ps1` - snapshot Windows RetroArch

Copies `retroarch.cfg`, core configs/options, playlists, and handheld shaders from a Windows RetroArch install into `_windows_retroarch\` for backup.

```powershell
.\Sync-WindowsRetroArch.ps1
.\Sync-WindowsRetroArch.ps1 -RetroArchPath "D:\RetroArch"
```

### `Restore-WindowsRetroArch.ps1` - restore Windows RetroArch

Restores configs and shaders from `_windows_retroarch\` back to a Windows RetroArch install.

```powershell
.\Restore-WindowsRetroArch.ps1
.\Restore-WindowsRetroArch.ps1 -RetroArchPath "D:\RetroArch"
```

### `Sync-DeviceConfigs.py` - pull configs from Rocknix devices

Pulls RetroArch configs from Rocknix devices over SSH/SFTP into `_device_configs\`. Edit `HOSTS` at the top of the file to set your device IPs.

```
python Sync-DeviceConfigs.py
```

### `Restore-DeviceConfigs.py` - push configs to Rocknix devices

Restores configs from `_device_configs\` back to Rocknix devices over SSH/SFTP. Useful after a firmware upgrade.

```
python Restore-DeviceConfigs.py
python Restore-DeviceConfigs.py RG35XX-SP   # single device
```

**Setup:** edit `HOSTS` in both Python files to set your device LAN IPs. Requires `paramiko` (`pip install paramiko`).

---

## Directory structure

```
<RootPath>/
  <system>/              # gba, nds, gb, gbc, n64, nes, ...
    romhacks/
      NNN - Title [TAG] (version).ext
      in-progress/       # ROMs with active save files
        <subfolder>/
      OLD/               # archived/retired versions
      <subfolder>/       # story/, definitive/, etc.
    in-progress/         # retail ROMs with active saves
  _windows_retroarch/    # Windows RetroArch snapshot
  _device_configs/       # Rocknix device config snapshots
```

## Adding a new override

If a ROM's title or tag auto-normalizes wrong, add an entry to `$overrides` in `Normalize-Romhacks.ps1`:

```powershell
"Exact Or StartsWith Match" = "Clean Title|TAG"
```

Keys are matched longest-first. The key matches the start of the stripped base name (prefix and existing `[TAG]` removed).
