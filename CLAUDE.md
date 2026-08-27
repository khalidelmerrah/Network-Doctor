# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

NetDoctor is a single-file, standalone PowerShell tool (Windows 10/11) that diagnoses and optimizes network settings for low latency: Path MTU discovery, NIC driver latency flags, Windows multimedia throttling, and TCP stack tuning. No dependencies, no build system, no test suite - 100% native PowerShell 5.1/7+.

Users run it one of two ways, and both must keep working:
- Remote one-liner: `irm https://raw.githubusercontent.com/khalidelmerrah/Network-Doctor/main/NetDoctor.ps1 | iex` (no `$PSScriptRoot`, so file output falls back to the Desktop)
- Locally via `NetDoctor.bat`, which self-elevates to Administrator and invokes the script with `-ExecutionPolicy Bypass`

## Running / Testing

No test suite. Verify changes with a parse check on BOTH engines (PS 5.1 behaves differently from 7):

```bash
powershell -NoProfile -Command "$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path NetDoctor.ps1),[ref]$t,[ref]$e)|Out-Null;if($e.Count){$e.Message;exit 1};'OK'"
```

Pure helpers (`Get-PingStats`, `Test-MtuPayload`, `Find-OptimalPayload`, `Write-Status`) can be smoke-tested unelevated by extracting function ASTs and running them against `127.0.0.1` - see git history for the pattern. The actual optimization paths need an elevated shell. Menu option `[2]` (Diagnostics only) is read-only and safe to run repeatedly; options `[1]`/`[3]` mutate system state (MTU, NIC advanced properties, registry) and option `[5]` restores from backup.

## Architecture (NetDoctor.ps1)

Single script, top-to-bottom:

1. `$script:Version` - single source of truth for the version (window title, header, report)
2. Output helpers - `Write-Status` (timestamped `[ OK ]/[WARN]/[FAIL]/[INFO]` lines), `Write-Section`
3. Admin check - friendly banner and exit if not elevated
4. Network helpers - `Get-PhysicalAdapters` (filters Hyper-V/virtual/loopback/TAP/VPN), `Get-PingStats`, `Test-MtuPayload`, `Find-OptimalPayload` (binary search), `Save-SettingsBackup`
5. `Run-Diagnostics` (supports `-Silent`) - returns a hashtable (`Issues`, `OptimalMTU`, `Adapters`, latency stats) consumed by everything else
6. `Apply-Optimizations` - snapshots settings first (only if no backup exists), then sets MTU via `netsh`, disables vendor latency flags, sets registry values, tunes TCP globals; every change is read back and verified
7. `Restore-Defaults` - replays the JSON backup exactly (including removing registry values that did not exist); falls back to stock defaults + `Reset-NetAdapterAdvancedProperty` when no backup
8. Interactive menu loop - option `[1]` runs diagnose -> optimize -> re-diagnose, prints a before/after table, writes `NetDoctor_Report.txt`

Backup lives at `%ProgramData%\NetDoctor\settings-backup.json`. It is written once (first optimization), consumed and deleted by a successful restore.

## Gotchas

- **The file must stay UTF-8 WITH BOM.** Without a BOM, `powershell.exe` (5.1) reads it as ANSI; any multi-byte character then corrupts string parsing and the `.bat` launch path breaks. Editing tools that strip the BOM must have it re-added before committing. Keep the script content ASCII-only as a second line of defense (no emoji).
- **Never parse ping/netsh text output** - it is localized. All ICMP goes through .NET `System.Net.NetworkInformation.Ping` (also the reason `Test-Connection` is not used: 5.1 exposes `ResponseTime`, 7 exposes `Latency`, and 7 emits objects even for failed pings).
- `NetworkThrottlingIndex` disabled value is `0xFFFFFFFF` (4294967295). Comparisons must handle it as unsigned - past bugs came from uint32 casts and signed `-1` comparisons (commits a879012, 7866809). Backup stores registry DWORDs as strings and restores via `[uint32]"$val"` for the same reason.
- NIC vendor properties differ per driver: matching uses both `RegistryKeyword` (exact and `*`-prefixed standardized keywords like `*FlowControl` - the asterisk is part of the literal name) and `DisplayName` wildcards. Keep both paths when adding a new flag, in diagnosis, apply, and the post-apply verify block.
- Optimal MTU = passing ICMP payload + 28 bytes (ICMP+IP header); falls back to 1492 (PPPoE) when the sweep is inconclusive.
- Restore must never touch virtual/VPN adapters (forcing MTU 1500 on WireGuard/Hyper-V interfaces breaks tunnels) - always go through `Get-PhysicalAdapters`.
- Repo URL is `khalidelmerrah/Network-Doctor` (no trailing hyphen) - it appears in the script's remote-run instructions and README; keep them in sync.
- Every shipped change bumps `$script:Version` and gets a `CHANGELOG.md` entry (see the global `release-discipline` skill).
