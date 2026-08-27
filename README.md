# NetDoctor

**Windows network diagnostics and latency optimizer.** A single, dependency-free PowerShell script that finds and fixes the configuration issues that cause packet loss, jitter and latency spikes - fragmented MTU, NIC power-saving features, packet batching offloads and Windows multimedia throttling.

Built with low-latency use cases in mind (competitive gaming, real-time audio/video, remote desktop), but the checks and fixes apply to any Windows machine.

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6?logo=windows)](https://github.com/khalidelmerrah/Network-Doctor)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell)](https://github.com/khalidelmerrah/Network-Doctor)
[![Version](https://img.shields.io/badge/Version-1.3.0-blue)](CHANGELOG.md)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Quick start

Run directly from PowerShell (opened as Administrator), no download needed:

```powershell
irm https://raw.githubusercontent.com/khalidelmerrah/Network-Doctor/main/NetDoctor.ps1 | iex
```

Or clone the repository and double-click `NetDoctor.bat` - it requests Administrator elevation automatically.

## What it checks

| Check | What it looks for |
| :--- | :--- |
| **Link speed** | Gigabit adapters negotiated down to 100/10 Mbps (damaged cable, bad port) |
| **Path MTU** | Binary-searches the largest unfragmented packet size to your ISP. On PPPoE lines the standard MTU 1500 exceeds the path maximum, so full-size packets fragment or get dropped |
| **NIC driver flags** | Green Ethernet, Energy-Efficient Ethernet, power-down features, Large Send Offload and Flow Control - across Intel, Realtek, Killer, Marvell and Aquantia drivers |
| **Latency and loss** | Gateway and internet round-trip time, jitter (standard deviation) and packet loss, measured with locale-independent .NET ICMP probes |
| **Windows throttling** | `NetworkThrottlingIndex` multimedia throttling that caps packet processing while audio/video plays |

## What it changes (option 1 or 3)

All changes are recorded in a backup **before** anything is modified:

- Sets each physical adapter's IPv4 MTU to the measured path maximum
- Disables NIC power-saving and packet-batching driver features (verified after applying - the tool reports anything the driver refused)
- Disables `NetworkThrottlingIndex` and sets `SystemResponsiveness` to 0
- Sets TCP autotuning to normal, enables RSS and TCP Fast Open, flushes the DNS cache

## Backup and restore

The first optimization run snapshots your original settings (per-adapter MTU, all NIC advanced properties, registry values) to `%ProgramData%\NetDoctor\settings-backup.json`.

**Option 5 restores that exact snapshot** - not generic defaults. If no backup exists, it falls back to stock Windows defaults and resets NIC properties to driver defaults. Virtual and VPN interfaces are never touched.

## Menu

```text
==========================================================================
 NetDoctor v1.3.0
 Windows Network Diagnostics & Latency Optimizer
==========================================================================

  1  Full optimization     diagnose, apply, verify, save report
  2  Diagnostics only      read-only health check, no changes
  3  Apply optimizations   apply without the pre-diagnosis output
  4  Speed test            Cloudflare download benchmark
  5  Restore settings      revert to backup or Windows defaults
  0  Exit
```

Option 1 finishes with a before/after comparison and writes a full report (`NetDoctor_Report.txt`) next to the script, or to the Desktop when run via `irm | iex`.

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built in) or PowerShell 7+
- Administrator rights (the script checks and explains if missing)

## License

MIT. See [LICENSE](LICENSE).
