# rocknix-romtools

PowerShell scripts for managing a Rocknix ROM hack library.

## Scripts

### `Normalize-Romhacks.ps1`

Renames romhack files to a canonical format: `NNN - Title [TAG] (version).ext`

**Tags:** `Story`, `QoL`, `Diff`, `Rand`, `Rogue`, `Cross`, `Patch`

**Usage:**
```powershell
# Preview changes (no files touched)
.\Normalize-Romhacks.ps1 -DryRun

# Apply renames
.\Normalize-Romhacks.ps1

# Different root path
.\Normalize-Romhacks.ps1 -RootPath "E:\MyRoms"
```

**Features:**
- Manual override table for known filenames that need specific titles or tags
- Auto-tagging via keyword rules for everything else
- Version extraction from parens `(v1.2.3)`, bare suffix `v1.2`, numeric `1.0.5`, date `(12-5-25)`, and edition words `(Beta)`, `(Demo)`, etc.
- Save file co-rename: renames `.srm`, `.sav`, `.dsv`, `.rtc`, `.dss` alongside the ROM
- Idempotent: re-running on already-clean files is a no-op
- HTML check at end: reports any active (non-OLD) ROM not present in `rom-catalog.html`, and inserts placeholder entries

**Expected directory structure:**
```
<RootPath>/
  <system>/          # e.g. gba, nds, gb, gbc, n64, nes
    romhacks/
      NNN - Title [TAG] (version).ext
      in-progress/   # WIP files, still processed
      OLD/           # archived, still processed for name normalization
```

### `Preview-Normalize.ps1`

Lighter preview-only version of the normalizer. No `-DryRun` flag needed - always read-only. Useful for a quick check without the full HTML audit.

```powershell
.\Preview-Normalize.ps1
.\Preview-Normalize.ps1 -RootPath "E:\MyRoms"
```

## Adding a new ROM

1. Drop the file in `<system>/romhacks/` with any name.
2. Run `.\Normalize-Romhacks.ps1 -DryRun` and check the proposed rename.
3. If the title or tag is wrong, add an entry to `$overrides` in `Normalize-Romhacks.ps1`.
4. Run without `-DryRun` to apply.
5. Update `rom-catalog.html` with the new entry (the script inserts a placeholder if it's missing).

## Override table

Overrides are matched longest-key-first (ordered dict). Key matches the start of the stripped base name (prefix and existing `[TAG]` removed). Value is `"Clean Title|TAG"`.

```powershell
"Pokemon Emerald - Seaglass" = "Pokemon Emerald Seaglass|QoL"
"Rose Gold NDS Demo"         = "Rose Gold NDS|Story"
```

If a file needs a specific tag that auto-tagging would get wrong, add it to the override table with the correct tag.
