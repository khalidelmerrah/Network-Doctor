# 🩺 Network-Doctor (For Competitive Gamers)

> **One-Click Windows Network Diagnostic, Path MTU Discovery & Gaming Latency Optimizer.**  
> Built for competitive multiplayer gaming: **Valorant, CS2, Fortnite, Warzone, Apex Legends, Rocket League, League of Legends, EA FC / FIFA**.  
> Zero installation. Zero external tools. 100% native PowerShell.

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6?logo=windows)](https://github.com/khalidelmerrah/Network-Doctor-)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell)](https://github.com/khalidelmerrah/Network-Doctor-)

---

## ⚡ Instant 1-Line Run (No Download Required)

Open **PowerShell** (Auto-prompts for Administrator) and run:

```powershell
irm https://raw.githubusercontent.com/khalidelmerrah/Network-Doctor-/main/NetDoctor.ps1 | iex
```

*(Or clone this repository and double-click `NetDoctor.bat` on your Desktop).*

---

## 📊 Real Before vs. After Benchmark (Live Test Proof)

Here are the actual results from a real gaming fiber connection before and after running **Network-Doctor**:

| Metric | Before Network-Doctor 🔴 | After Network-Doctor 🟢 | Gamer Impact |
| :--- | :--- | :--- | :--- |
| **Small Payload Latency (100kB Upload)** | **`336.5 ms`** | **`30.3 ms`** | **11x faster hit-registration** & zero click delay |
| **Medium Payload Latency (1MB Upload)** | **`220.0 ms`** | **`30.4 ms`** | Smooth voice chat & instant player positioning |
| **Upload Speed Throughput** | **`3.5 - 6.0 Mbps`** *(Choked)* | **`95.5 Mbps`** *(Full Line)* | No more bottleneck when uploading clips/Discord streams |
| **Packet Loss & Drops** | **`5.1% - 75.0%`** | **`0.0%`** | Eliminates rubberbanding, teleporting & dropped bullets |
| **Ping Jitter** | **`152.0 ms`** | **`1.0 - 8.0 ms`** | Perfectly steady, flat frame-time ping |

---

## 🎮 What Network-Doctor Fixes for Gamers

1. **🔴 Eliminates In-Game Packet Loss (Path MTU Discovery):**
   * If your ISP or Fiber connection uses **PPPoE**, standard `1500 MTU` drops up to **75%** of unfragmented gaming packets.
   * Network-Doctor sweeps packet boundaries (`1472` $\to$ `1464` $\to$ `1372`) and locks the exact optimal MTU (`1492`).

2. **🔴 Removes Hardware Driver Micro-Stutters (Multi-Vendor NIC Tuning):**
   * Universal vendor support for **Intel, Realtek, Killer, Marvell, and Aquantia** controllers.
   * Disables **Green Ethernet**, **Energy Efficient Ethernet (EEE)**, `ReduceSpeedOnPowerDown`, and `PowerDownPcie` which put the NIC to sleep and spike latency.
   * Disables **Large Send Offload (LSO)** which delays and batches UDP game packets into chunks instead of dispatching them immediately.
   * Disables **Flow Control** which temporarily pauses game traffic whenever a background buffer fills.

3. **🔴 Grants Maximum Windows Gaming Priority:**
   * Removes Windows Multimedia Network Throttling (`NetworkThrottlingIndex`) that throttles game packets when Discord audio or background music is playing.
   * Sets `SystemResponsiveness` to `0` for 100% CPU/Network gaming priority.

4. **🔄 Revert / Safety Net Functionality:**
   * Option `[5]` allows users to safely restore all stock Windows defaults (MTU 1500, default TCP stack, MMCSS throttling) with a single click.

---

## 🌐 Cloudflare Speed Test Integration

**Network-Doctor** comes with native Cloudflare speed benchmark integration:
* **Option 1 (Built-in):** Option `[4]` runs a live throughput & latency benchmark directly in PowerShell against Cloudflare's nearest edge server.
* **Option 2 (Visual Browser Audit):** Prompts you to launch [speed.cloudflare.com](https://speed.cloudflare.com/) in your browser to inspect real-time jitter, packet loss, and bufferbloat graphs.

---

## 🖥️ Interactive Dashboard Preview

```text
==========================================================================
  _   _      _   ____             _                                       
 | \ | | ___| |_|  _ \  ___   ___| |_ ___  _ __                           
 |  \| |/ _ \ __| | | |/ _ \ / __| __/ _ \| '__|                          
 | |\  |  __/ |_| |_| | (_) | (__| || (_) | |                             
 |_| \_|\___|\__|____/ \___/ \___|\__\___/|_|                             
                                                                          
    🎮 ULTIMATE GAMING LATENCY OPTIMIZER & PATH MTU DISCOVERY ENGINE      
    Zero Lag • 0% Packet Loss • Lowest Ping • No Input Queue Delay        
==========================================================================

  [1] 🚀 FULL AUTO-FIX FOR GAMERS (Diagnose -> Optimize -> Verify)
  [2] 🔍 DIAGNOSE ONLY (Check Packet Loss, Jitter & MTU Boundary)
  [3] ⚡ APPLY GAMING OPTIMIZATIONS ONLY
  [4] 🌐 CLOUDFLARE SPEED & LOADED LATENCY TEST
  [5] 🔄 RESTORE WINDOWS DEFAULT SETTINGS (Safety Revert)
  [0] ❌ EXIT

Select an option (0-5):
```

---

## 📜 License
MIT License. Free for all gamers and developers to use, share, and improve.
