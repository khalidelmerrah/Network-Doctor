# 🩺 Network-Doctor

> **One-Click Windows Network Diagnostic, Path MTU Discovery & Gaming Latency Optimizer.**  
> Zero installation. Zero external dependencies. 100% native PowerShell.

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6?logo=windows)](https://github.com/khalidelmerrah/Network-Doctor-)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell)](https://github.com/khalidelmerrah/Network-Doctor-)

---

## ⚡ Instant Run (No Download Required)

Open **PowerShell as Administrator** and paste this one-liner:

```powershell
irm https://raw.githubusercontent.com/khalidelmerrah/Network-Doctor-/main/NetDoctor.ps1 | iex
```

*(Or download/clone this repo and double-click `NetDoctor.bat`)*

---

## 🎯 What Problems Does Network-Doctor Solve?

* 🔴 **Packet Loss & Rubberbanding:** Detects PPPoE / ISP MTU mismatches where oversized unfragmented frames get dropped (e.g. 1500 vs 1492 MTU).
* 🔴 **High Jitter & Micro-Stutters:** Disables latency-inducing network card features like **Green Ethernet**, **Gigabit Lite**, and **Large Send Offload (LSO)**.
* 🔴 **Pause-Frame Lag:** Disables **Flow Control** which temporarily freezes UDP game streams when network buffers fill.
* 🔴 **Windows Background Throttling:** Uncaps `NetworkThrottlingIndex` and sets `SystemResponsiveness` to `0` (Maximum Gaming Priority).
* 🔴 **Cable / Port Degradation:** Detects when a damaged cable or bad port has silently negotiated down to 100 Mbps or 10 Mbps.

---

## 🖥️ Interactive Dashboard

```text
==========================================================================
  _   _      _   ____             _                                       
 | \ | | ___| |_|  _ \  ___   ___| |_ ___  _ __                           
 |  \| |/ _ \ __| | | |/ _ \ / __| __/ _ \| '__|                          
 | |\  |  __/ |_| |_| | (_) | (__| || (_) | |                             
 |_| \_|\___|\__|____/ \___/ \___|\__\___/|_|                             
                                                                          
 Standalone Network Diagnostics, MTU Discovery & Gaming Latency Optimizer 
==========================================================================

  [1] 🚀 FULL AUTO-FIX (Diagnose -> Optimize -> Verify & Report)
  [2] 🔍 DIAGNOSE ONLY (Scan for MTU, bufferbloat & packet loss)
  [3] ⚡ APPLY OPTIMIZATIONS ONLY
  [0] ❌ EXIT

Select an option (0-3):
```

---

## 🚀 Features Breakdown

| Feature | Description |
| :--- | :--- |
| **Dynamic Path MTU Discovery** | Sweeps frame sizes (1472, 1464, 1452, 1420, 1372 bytes) with the Don't-Fragment bit to discover your connection's exact packet boundary. |
| **NDIS Driver Tuning** | Toggles Realtek/Intel hardware registry flags for Green Ethernet, EEE, and LSO. |
| **MMCSS Multimedia Priority** | Reconfigures Windows Multimedia Class Scheduler to prioritize game packets over Windows background tasks. |
| **TCP Stack Optimization** | Enables TCP Autotuning (`normal`), Receive Side Scaling (RSS), and Fast Open. |
| **Verification & Reporting** | Re-measures latency and jitter and generates a timestamped report on your Desktop. |

---

## 📜 License
MIT License. Free to use, share, and modify.
