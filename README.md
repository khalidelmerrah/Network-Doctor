# NetDoctor (For Competitive Gamers)

> **One-click Windows network diagnostics, Path MTU discovery and gaming latency optimizer.**
> Built for competitive multiplayer: **Valorant, CS2, Fortnite, Warzone, Apex Legends, Rocket League, League of Legends, EA FC**.
> Zero installation. Zero external tools. 100% native PowerShell. Fully reversible.

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6?logo=windows)](https://github.com/khalidelmerrah/Network-Doctor)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell)](https://github.com/khalidelmerrah/Network-Doctor)
[![Version](https://img.shields.io/badge/Version-1.3.1-blue)](CHANGELOG.md)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Instant 1-line run (no download required)

Open **PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/khalidelmerrah/Network-Doctor/main/NetDoctor.ps1 | iex
```

Or clone this repository and double-click `NetDoctor.bat` - it requests Administrator elevation automatically.

## Before vs. after (author's fiber line)

Measured on a real PPPoE fiber connection before and after running NetDoctor. Your numbers will vary with your line and hardware:

| Metric | Before | After | In-game impact |
| :--- | :--- | :--- | :--- |
| Small payload latency (100 kB upload) | `336.5 ms` | `30.3 ms` | Instant hit registration, no click delay |
| Medium payload latency (1 MB upload) | `220.0 ms` | `30.4 ms` | Smooth voice chat, accurate player positions |
| Upload throughput | `3.5 - 6.0 Mbps` (choked) | `95.5 Mbps` (full line) | No bottleneck streaming clips or Discord |
| Packet loss | `5.1% - 75.0%` | `0.0%` | No rubberbanding, teleporting or dropped shots |
| Ping jitter | `152.0 ms` | `1.0 - 8.0 ms` | Flat, steady ping |

## What it fixes

1. **In-game packet loss (Path MTU discovery).** On PPPoE/fiber lines the standard MTU 1500 exceeds the path maximum, so full-size game packets fragment or get silently dropped - the classic cause of rubberbanding. NetDoctor binary-searches the exact largest unfragmented packet size (locale-independent .NET ICMP with Don't-Fragment) and locks it in.

2. **NIC driver micro-stutters (vendor-neutral: Intel, Realtek, Killer, Marvell, Aquantia).** Disables Green Ethernet / Energy-Efficient Ethernet and power-down features that let the NIC doze off between packets (felt as random ping spikes), Large Send Offload that batches packets instead of firing them immediately (jitter), and Flow Control that pauses game traffic when a background buffer fills.

3. **Windows game packet priority.** Disables multimedia network throttling (`NetworkThrottlingIndex`) that deprioritizes game packets whenever Discord or music is playing, and sets `SystemResponsiveness` to 0.

4. **TCP stack.** Autotuning to normal, RSS and TCP Fast Open enabled, DNS cache flushed.

## Safety net: backup and restore

Before touching anything, the first optimization run snapshots your original settings (per-adapter MTU, every NIC advanced property, registry values) to `%ProgramData%\NetDoctor\settings-backup.json`.

**Option 5 restores that exact snapshot** - not generic defaults. No backup? It falls back to stock Windows defaults and driver-default NIC properties. VPN and virtual adapters are never touched. Every change is verified after applying - if a driver refuses a setting, you see a warning, not a fake success.

## Dashboard

```text
==========================================================================
  _   _      _   ____             _
 | \ | | ___| |_|  _ \  ___   ___| |_ ___  _ __
 |  \| |/ _ \ __| | | |/ _ \ / __| __/ _ \| '__|
 | |\  |  __/ |_| |_| | (_) | (__| || (_) | |
 |_| \_|\___|\__|____/ \___/ \___|\__\___/|_|    v1.3.1

  GAMING LATENCY OPTIMIZER + PATH MTU DISCOVERY ENGINE
  Lower ping. Zero packet loss. Flat jitter. Backed up and reversible.
==========================================================================

  1  FULL AUTO-FIX          diagnose -> optimize -> verify -> report
  2  DIAGNOSE ONLY          check ping, jitter, packet loss, MTU (read-only)
  3  APPLY OPTIMIZATIONS    straight to the fixes, no pre-diagnosis output
  4  SPEED TEST             Cloudflare edge download benchmark
  5  RESTORE SETTINGS       safety revert to backup or Windows defaults
  0  EXIT
```

Full auto-fix ends with a before/after comparison table and saves a report (`NetDoctor_Report.txt`) next to the script, or to the Desktop when run via `irm | iex`.

## Cloudflare speed test

Option 4 runs a native download benchmark against Cloudflare's nearest edge server, then offers to open [speed.cloudflare.com](https://speed.cloudflare.com/) for the full visual audit - latency under load, jitter and bufferbloat graphs.

## Requirements

- Windows 10 or 11, PowerShell 5.1 (built in) or 7+
- Administrator rights (the script checks and explains if missing)

## License

MIT. Free for all gamers and developers to use, share and improve.
