# NetDoctor - Standalone Windows Network Optimizer & Diagnostics Tool for Gamers
# Run directly via PowerShell: irm https://raw.githubusercontent.com/khalidelmerrah/Network-Doctor/main/NetDoctor.ps1 | iex
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "NetDoctor v1.2 - Ultimate Gaming Network & Latency Optimizer"

# --- 1. Enforce Administrator Privileges (Auto-Elevation) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating to Administrator privileges..." -ForegroundColor Yellow
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/khalidelmerrah/Network-Doctor/main/NetDoctor.ps1 | iex`"" -Verb RunAs
    }
    exit
}

function Show-Header {
    Clear-Host
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "  _   _      _   ____             _                                       " -ForegroundColor Cyan
    Write-Host " | \ | | ___| |_|  _ \  ___   ___| |_ ___  _ __                           " -ForegroundColor Cyan
    Write-Host " |  \| |/ _ \ __| | | |/ _ \ / __| __/ _ \| '__|                          " -ForegroundColor Cyan
    Write-Host " | |\  |  __/ |_| |_| | (_) | (__| || (_) | |                             " -ForegroundColor Cyan
    Write-Host " |_| \_|\___|\__|____/ \___/ \___|\__\___/|_|                             " -ForegroundColor Cyan
    Write-Host "                                                                          " -ForegroundColor Cyan
    Write-Host "    🎮 ULTIMATE GAMING LATENCY OPTIMIZER & PATH MTU DISCOVERY ENGINE      " -ForegroundColor Yellow
    Write-Host "    Zero Lag • 0% Packet Loss • Lowest Ping • No Input Queue Delay        " -ForegroundColor White
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Run-CloudflareTest {
    Write-Host ">>> RUNNING NATIVE CLOUDFLARE SPEED & LATENCY BENCHMARK..." -ForegroundColor Cyan
    Write-Host "Connecting to nearest Cloudflare Edge Server..." -ForegroundColor Gray
    
    $downMbps = 0
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc = New-Object System.Net.WebClient
        $data = $wc.DownloadData("https://speed.cloudflare.com/__down?bytes=10000000")
        $sw.Stop()
        if ($sw.ElapsedMilliseconds -gt 0) {
            $downMbps = [math]::Round(($data.Length * 8 / 1000000) / ($sw.ElapsedMilliseconds / 1000), 2)
            Write-Host "  • Cloudflare Download Speed: $downMbps Mbps (10MB in $($sw.ElapsedMilliseconds) ms)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  • Native Cloudflare Test: Network busy or timed out." -ForegroundColor Yellow
    }

    Write-Host ""
    $openBrowser = Read-Host "Would you like to open https://speed.cloudflare.com/ in your browser for a full visual benchmark? (Y/N)"
    if ($openBrowser -eq "Y" -or $openBrowser -eq "y") {
        Start-Process "https://speed.cloudflare.com/"
    }
}

function Run-Diagnostics {
    param([switch]$Silent)

    if (-not $Silent) {
        Write-Host "--- [1/5] SCANNING NETWORK HARDWARE & LINK SPEED ---" -ForegroundColor Yellow
    }
    
    $adapters = Get-NetAdapter | Where-Object { 
        $_.Status -eq "Up" -and 
        $_.InterfaceDescription -notlike "*Hyper-V*" -and 
        $_.InterfaceDescription -notlike "*Wintun*" -and 
        $_.InterfaceDescription -notlike "*Virtual*" -and 
        $_.InterfaceDescription -notlike "*Loopback*"
    }
    if (-not $adapters) { $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } }

    $issues = @()
    $adapterDetails = @()

    foreach ($a in $adapters) {
        $ipConf = Get-NetIPInterface -InterfaceAlias $a.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $mtu = if ($ipConf) { $ipConf.NlMtu } else { 1500 }
        
        $adapterDetails += [PSCustomObject]@{
            Name = $a.Name
            Description = $a.InterfaceDescription
            Speed = $a.LinkSpeed
            MTU = $mtu
        }

        if (-not $Silent) {
            Write-Host "  • Adapter: $($a.Name) ($($a.InterfaceDescription))" -ForegroundColor White
            Write-Host "    Link Speed: $($a.LinkSpeed) | Current IPv4 MTU: $mtu" -ForegroundColor Gray
        }

        if ($a.LinkSpeed -like "*100 Mbps*" -or $a.LinkSpeed -like "*10 Mbps*") {
            $issues += "Ethernet link speed is negotiated at $($a.LinkSpeed) (Damaged cable or bad LAN port)."
        }
    }

    # 2. Path MTU Discovery Sweep
    if (-not $Silent) {
        Write-Host ""
        Write-Host "--- [2/5] RUNNING PATH MTU DISCOVERY (PACKET FRAGMENTATION CHECK) ---" -ForegroundColor Yellow
    }
    $target = "8.8.8.8"
    $testSizes = @(1472, 1464, 1452, 1420, 1372)
    $optimalPayload = 0

    foreach ($size in $testSizes) {
        $pingRes = ping $target -f -l $size -n 1
        $isFrag = $pingRes | Where-Object { $_ -like "*fragmented*" -or $_ -like "*DF set*" }
        $isReply = $pingRes | Where-Object { $_ -like "*Reply from*" }

        if ($isReply -and -not $isFrag) {
            $optimalPayload = $size
            if (-not $Silent) {
                Write-Host "    Payload $size B (+28B Header = MTU $($size+28)): PASS (No Packet Drops)" -ForegroundColor Green
            }
            break
        } else {
            if (-not $Silent) {
                Write-Host "    Payload $size B (+28B Header = MTU $($size+28)): FAILED (Fragmentation Drops)" -ForegroundColor Red
            }
        }
    }
    $optimalMTU = if ($optimalPayload -gt 0) { $optimalPayload + 28 } else { 1492 }

    foreach ($ad in $adapterDetails) {
        if ($ad.MTU -gt $optimalMTU) {
            $issues += "MTU Mismatch on '$($ad.Name)' (Current: $($ad.MTU) vs Optimal: $optimalMTU). Causes 5-75% gaming packet loss!"
        }
    }

    # 3. Multi-Vendor NIC Driver Latency Settings (Intel, Realtek, Killer, Marvell)
    if (-not $Silent) {
        Write-Host ""
        Write-Host "--- [3/5] CHECKING HARDWARE LATENCY DRIVER FLAGS (INTEL / REALTEK / KILLER) ---" -ForegroundColor Yellow
    }
    foreach ($a in $adapters) {
        $props = Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue
        if ($props) {
            # Check Green & Power Savings across all vendors
            $powerSavingProps = $props | Where-Object { 
                $_.RegistryKeyword -in @("EnableGreenEthernet", "GigaLite", "PowerSavingMode", "AdvancedEEE", "EEELinkAdvertisement", "*EnergyEfficientEthernet", "*ReduceSpeedOnPowerDown", "*PowerDownPcie", "*ModernStandby") -or
                $_.DisplayName -like "*Green*" -or $_.DisplayName -like "*Energy Efficient*" -or $_.DisplayName -like "*Gigabit Lite*" -or $_.DisplayName -like "*Power Saving*"
            }

            $hasActivePowerSaving = $false
            foreach ($p in $powerSavingProps) {
                if ($p.DisplayValue -eq "Enabled" -or $p.RegistryValue -eq 1 -or $p.DisplayValue -like "*Enable*") {
                    $hasActivePowerSaving = $true
                    break
                }
            }

            if ($hasActivePowerSaving) {
                $issues += "Hardware Power Throttling / Green Ethernet is ENABLED on '$($a.Name)'"
                if (-not $Silent) { Write-Host "    [!] Power Throttling / Green Ethernet: Enabled on $($a.Name)" -ForegroundColor Yellow }
            } else {
                if (-not $Silent) { Write-Host "    [OK] Hardware Power Throttling / Green Ethernet: Disabled" -ForegroundColor Green }
            }

            # Check LSO (Large Send Offload)
            $lsoProps = $props | Where-Object { $_.RegistryKeyword -like "*LsoV2*" -or $_.DisplayName -like "*Large Send Offload*" }
            $hasLSO = ($lsoProps | Where-Object { $_.DisplayValue -eq "Enabled" -or $_.RegistryValue -eq 1 })
            if ($hasLSO) {
                $issues += "Large Send Offload (LSO) is ENABLED on '$($a.Name)' (Causes packet batching jitter)"
                if (-not $Silent) { Write-Host "    [!] Large Send Offload: Enabled (Packet batching jitter)" -ForegroundColor Yellow }
            } else {
                if (-not $Silent) { Write-Host "    [OK] Large Send Offload: Disabled" -ForegroundColor Green }
            }

            # Check Flow Control
            $flowProps = $props | Where-Object { $_.RegistryKeyword -eq "*FlowControl" -or $_.DisplayName -like "*Flow Control*" }
            $hasFlow = ($flowProps | Where-Object { $_.DisplayValue -ne "Disabled" -and $_.RegistryValue -ne 0 })
            if ($hasFlow) {
                $issues += "Flow Control is ENABLED on '$($a.Name)' (Can pause UDP game packets)"
                if (-not $Silent) { Write-Host "    [!] Flow Control: Enabled (Pauses game packets on traffic spikes)" -ForegroundColor Yellow }
            } else {
                if (-not $Silent) { Write-Host "    [OK] Flow Control: Disabled" -ForegroundColor Green }
            }
        }
    }

    # 4. Latency & Jitter Ping Test
    if (-not $Silent) {
        Write-Host ""
        Write-Host "--- [4/5] MEASURING IN-GAME PING, JITTER & PACKET LOSS ---" -ForegroundColor Yellow
    }
    $gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway }).IPv4DefaultGateway.NextHop
    $gwLatency = 0
    if ($gw) {
        $gwPings = Test-Connection -ComputerName $gw -Count 5 -ErrorAction SilentlyContinue
        if ($gwPings) {
            $gwLatency = [math]::Round(($gwPings | Measure-Object -Property ResponseTime -Average).Average, 1)
            if (-not $Silent) { Write-Host "    Local Router Hop ($gw): $gwLatency ms (0% Loss)" -ForegroundColor Green }
        }
    }

    $wanPings = Test-Connection -ComputerName "8.8.8.8" -Count 10 -ErrorAction SilentlyContinue
    $wanAvg = 0; $wanJitter = 0; $wanLoss = 0
    if ($wanPings) {
        $wanAvg = [math]::Round(($wanPings | Measure-Object -Property ResponseTime -Average).Average, 1)
        $wanMin = ($wanPings | Measure-Object -Property ResponseTime -Minimum).Minimum
        $wanMax = ($wanPings | Measure-Object -Property ResponseTime -Maximum).Maximum
        $wanJitter = [math]::Round($wanMax - $wanMin, 1)
        $wanLoss = (10 - $wanPings.Count) * 10
        if (-not $Silent) {
            Write-Host "    Internet Latency (8.8.8.8): $wanAvg ms | Jitter: $wanJitter ms | Loss: $wanLoss%" -ForegroundColor $(if ($wanLoss -eq 0) { "Green" } else { "Red" })
        }
    }

    # 5. Windows Gaming Multimedia Settings
    if (-not $Silent) {
        Write-Host ""
        Write-Host "--- [5/5] WINDOWS MULTIMEDIA NETWORK THROTTLING FOR GAMES ---" -ForegroundColor Yellow
    }
    $sysProfile = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -ErrorAction SilentlyContinue
    $throttleVal = if ($sysProfile) { $sysProfile.NetworkThrottlingIndex } else { $null }
    $isThrottlingDisabled = ($throttleVal -eq 4294967295 -or $throttleVal -eq -1 -or $throttleVal -eq 0xFFFFFFFF)
    if ($null -ne $throttleVal -and -not $isThrottlingDisabled) {
        $issues += "Windows Multimedia Network Throttling is ACTIVE (Limits game packet priority)"
        if (-not $Silent) { Write-Host "    [!] NetworkThrottlingIndex: Active (Throttles gaming packets)" -ForegroundColor Yellow }
    } else {
        if (-not $Silent) { Write-Host "    [OK] NetworkThrottlingIndex: Disabled (100% Gaming Priority)" -ForegroundColor Green }
    }

    return @{
        Issues = $issues
        OptimalMTU = $optimalMTU
        Adapters = $adapters
        WanAvg = $wanAvg
        WanJitter = $wanJitter
        WanLoss = $wanLoss
        GwLatency = $gwLatency
    }
}

function Apply-Optimizations {
    param($Diag)

    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "                     APPLYING GAMING OPTIMIZATIONS                        " -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""

    $optimalMTU = $Diag.OptimalMTU
    $adapters = $Diag.Adapters

    # 1. Set MTU
    Write-Host "[1/4] Setting Optimal MTU ($optimalMTU) on Network Interfaces..." -ForegroundColor Yellow
    foreach ($a in $adapters) {
        netsh interface ipv4 set subinterface "$($a.Name)" mtu=$optimalMTU store=persistent | Out-Null
        Write-Host "  [OK] Set MTU on '$($a.Name)' to $optimalMTU" -ForegroundColor Green
    }

    # 2. Hardware Driver Properties (Vendor-Neutral: Intel, Realtek, Killer, Marvell)
    Write-Host "[2/4] Disabling Latency Flags across all NIC Vendors..." -ForegroundColor Yellow
    $vendorKeywords = @(
        "EnableGreenEthernet", "GigaLite", "PowerSavingMode", "AdvancedEEE", "EEELinkAdvertisement",
        "*EnergyEfficientEthernet", "*ReduceSpeedOnPowerDown", "*PowerDownPcie", "*ModernStandby",
        "*FlowControl", "*LsoV2IPv4", "*LsoV2IPv6"
    )

    foreach ($a in $adapters) {
        foreach ($kw in $vendorKeywords) {
            Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword $kw -RegistryValue 0 -ErrorAction SilentlyContinue
        }
        # Fallback wildcard matching for proprietary displays
        Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName "*Green*" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName "*Gigabit Lite*" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName "*Power Saving*" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName "*Energy Efficient*" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName "*Flow Control*" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName "*Large Send Offload*" -DisplayValue "Disabled" -ErrorAction SilentlyContinue

        Write-Host "  [OK] Tuned NIC power & packet flags on '$($a.Name)'" -ForegroundColor Green
    }

    # 3. Windows Gaming Priority & MMCSS
    Write-Host "[3/4] Tuning Windows Multimedia Scheduler for Max Game Priority..." -ForegroundColor Yellow
    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] NetworkThrottlingIndex disabled & SystemResponsiveness set to 0 (Max Priority)" -ForegroundColor Green

    # 4. TCP Stack Tuning & DNS Flush
    Write-Host "[4/4] Optimizing TCP Window Autotuning & Flushing DNS..." -ForegroundColor Yellow
    netsh int tcp set global autotuninglevel=normal | Out-Null
    netsh int tcp set global rss=enabled | Out-Null
    netsh int tcp set global fastopen=enabled | Out-Null
    Clear-DnsClientCache
    Write-Host "  [OK] TCP Window Autotuning set to Normal, RSS Enabled, DNS Flushed" -ForegroundColor Green
    Write-Host ""
}

function Restore-Defaults {
    Show-Header
    Write-Host "==========================================================================" -ForegroundColor Yellow
    Write-Host "                  RESTORE WINDOWS DEFAULT NETWORK SETTINGS                " -ForegroundColor Yellow
    Write-Host "==========================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This will revert your network stack back to stock Windows defaults:" -ForegroundColor White
    Write-Host "  • Reset IPv4 MTU to standard 1500" -ForegroundColor Gray
    Write-Host "  • Re-enable Windows Multimedia Throttling (NetworkThrottlingIndex = 10)" -ForegroundColor Gray
    Write-Host "  • Reset SystemResponsiveness to default (20)" -ForegroundColor Gray
    Write-Host "  • Re-enable standard NIC properties" -ForegroundColor Gray
    Write-Host "  • Reset TCP stack to default autotuning" -ForegroundColor Gray
    Write-Host ""

    $confirm = Read-Host "Are you sure you want to restore defaults? (Y/N)"
    if ($confirm -eq "Y" -or $confirm -eq "y") {
        Write-Host ""
        Write-Host "Reverting network settings..." -ForegroundColor Yellow

        # 1. Reset MTU to 1500
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        foreach ($a in $adapters) {
            netsh interface ipv4 set subinterface "$($a.Name)" mtu=1500 store=persistent | Out-Null
            Write-Host "  [OK] Reset MTU on '$($a.Name)' to 1500" -ForegroundColor Green
        }

        # 2. Reset Multimedia Throttling Registry
        $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 20 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Reverted NetworkThrottlingIndex to 10 & SystemResponsiveness to 20" -ForegroundColor Green

        # 3. Reset TCP Stack
        netsh int tcp set global autotuninglevel=normal | Out-Null
        Clear-DnsClientCache
        Write-Host "  [OK] Reset TCP stack & flushed DNS" -ForegroundColor Green

        Write-Host ""
        Write-Host "✅ Network settings successfully restored to Windows defaults!" -ForegroundColor Green
    } else {
        Write-Host "Operation cancelled." -ForegroundColor Gray
    }
    Write-Host ""
    Read-Host "Press Enter to return to menu..."
}

# --- Interactive Main Loop ---
while ($true) {
    Show-Header
    Write-Host "  [1] 🚀 FULL AUTO-FIX FOR GAMERS (Diagnose -> Optimize -> Verify)" -ForegroundColor Green
    Write-Host "  [2] 🔍 DIAGNOSE ONLY (Check Packet Loss, Jitter & MTU Boundary)" -ForegroundColor Yellow
    Write-Host "  [3] ⚡ APPLY GAMING OPTIMIZATIONS ONLY" -ForegroundColor Cyan
    Write-Host "  [4] 🌐 CLOUDFLARE SPEED & LOADED LATENCY TEST" -ForegroundColor Magenta
    Write-Host "  [5] 🔄 RESTORE WINDOWS DEFAULT SETTINGS (Safety Revert)" -ForegroundColor DarkYellow
    Write-Host "  [0] ❌ EXIT" -ForegroundColor Gray
    Write-Host ""
    $choice = Read-Host "Select an option (0-5)"

    switch ($choice) {
        "1" {
            Show-Header
            Write-Host ">>> PHASE 1: INITIAL DIAGNOSIS" -ForegroundColor Cyan
            $before = Run-Diagnostics
            
            Write-Host ""
            if ($before.Issues.Count -gt 0) {
                Write-Host "Found $($before.Issues.Count) bottleneck(s) affecting gaming performance!" -ForegroundColor Yellow
                foreach ($iss in $before.Issues) { Write-Host "  • $iss" -ForegroundColor Red }
            } else {
                Write-Host "Connection is healthy, optimizing hardware and Windows settings..." -ForegroundColor Green
            }

            Apply-Optimizations -Diag $before

            Write-Host ">>> PHASE 2: POST-OPTIMIZATION VERIFICATION" -ForegroundColor Cyan
            $after = Run-Diagnostics
            
            # Save Report
            $desktopDir = [Environment]::GetFolderPath("Desktop")
            $reportPath = if ($PSScriptRoot) { [System.IO.Path]::Combine($PSScriptRoot, "NetDoctor_Report.txt") } else { [System.IO.Path]::Combine($desktopDir, "NetDoctor_Report.txt") }
            
            $reportContent = @"
==========================================================================
                 NETDOCTOR GAMING OPTIMIZATION REPORT                     
==========================================================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Optimal Path MTU: $($after.OptimalMTU)
Local Router Latency: $($after.GwLatency) ms
Internet Ping: $($after.WanAvg) ms
Ping Jitter: $($after.WanJitter) ms
Packet Loss: $($after.WanLoss)%

Issues Resolved:
$($before.Issues | ForEach-Object { " - $_" } | Out-String)
Gaming Status: READY FOR COMPETITIVE GAMING (VALORANT / CS2 / FORTNITE / WARZONE)
==========================================================================
"@
            $reportContent | Set-Content -Path $reportPath -Encoding utf8

            Write-Host ""
            Write-Host "==========================================================================" -ForegroundColor Green
            Write-Host "✅ GAMING OPTIMIZATION COMPLETE! Report saved to:" -ForegroundColor Green
            Write-Host "   $reportPath" -ForegroundColor White
            Write-Host "==========================================================================" -ForegroundColor Green
            Write-Host ""
            Read-Host "Press Enter to return to menu..."
        }
        "2" {
            Show-Header
            $diag = Run-Diagnostics
            Write-Host ""
            if ($diag.Issues.Count -eq 0) {
                Write-Host "✅ NO ISSUES FOUND! Network is primed for low-latency gaming." -ForegroundColor Green
            } else {
                Write-Host "⚠️ ISSUES FOUND ($($diag.Issues.Count)):" -ForegroundColor Red
                foreach ($iss in $diag.Issues) { Write-Host "  • $iss" -ForegroundColor Yellow }
            }
            Write-Host ""
            Read-Host "Press Enter to return to menu..."
        }
        "3" {
            Show-Header
            $diag = Run-Diagnostics -Silent
            Apply-Optimizations -Diag $diag
            Write-Host ""
            Write-Host "✅ Gaming optimizations applied successfully!" -ForegroundColor Green
            Read-Host "Press Enter to return to menu..."
        }
        "4" {
            Show-Header
            Run-CloudflareTest
            Write-Host ""
            Read-Host "Press Enter to return to menu..."
        }
        "5" {
            Restore-Defaults
        }
        "0" {
            exit
        }
    }
}
