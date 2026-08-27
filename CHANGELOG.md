# Changelog

## [1.3.1] - 2026-08-27 (commit: pending)
### Changed
- Restored the gaming identity: ASCII logo, colored all-caps menu, gaming tagline, and diagnostics copy rewritten in gamer terms (lag sources, rubberbanding, ping spikes, game-ready status) - while keeping the v1.3.0 timestamped status log, change verification and backup messaging
- README rewritten back to its gaming voice with the author's before/after fiber-line measurements (labeled as such), keeping the factual feature and backup/restore documentation

## [1.3.0] - 2026-08-27 (commit: 92a0a6e)
### Added
- Settings backup: the first optimization run snapshots per-adapter MTU, all NIC advanced properties and the multimedia registry values to `%ProgramData%\NetDoctor\settings-backup.json`
- Restore (option 5) replays that exact snapshot; without a backup it resets NIC properties to driver defaults and applies stock Windows values
- Before/after results comparison after a full optimization, plus a richer saved report
- Timestamped `[ OK ]/[WARN]/[FAIL]/[INFO]` status output and invalid-menu-choice feedback
### Fixed
- PowerShell 7 compatibility: latency, jitter and packet loss were reported as 0 because `Test-Connection` exposes different properties on PS7; replaced with locale-independent .NET ICMP probes
- Non-English Windows: MTU discovery parsed localized `ping.exe` output and silently failed; now uses .NET `Ping` with the Don't-Fragment flag
- Script saved as UTF-8 with BOM: without it, Windows PowerShell 5.1 read the file as ANSI and failed to parse, breaking the `NetDoctor.bat` launch path
- Restore no longer forces MTU 1500 on virtual/VPN interfaces (could break tunnels) and now actually restores NIC properties as the menu claimed
- MTU and NIC driver changes are verified after applying instead of printing unconditional success
### Changed
- MTU discovery binary-searches the exact fragmentation boundary instead of testing five fixed sizes
- Jitter is now standard deviation instead of max minus min
- Cloudflare benchmark uses `HttpClient` with a 30 s timeout instead of the deprecated `WebClient` with none
- Terminal UI and README rewritten: professional copy, no emoji, factual issue descriptions

## [1.2.0] - 2026-08-26 (commit: 7bf90b5)
### Added
- Auto-admin elevation via `NetDoctor.bat`, vendor-neutral NIC latency flags (Intel, Realtek, Killer, Marvell), safety revert option
- Friendly instruction banner when not run as Administrator (fbe91d6)
### Fixed
- Unsigned `4294967295` evaluation and uint32 cast error for `NetworkThrottlingIndex` (7866809, a879012)
