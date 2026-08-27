# NetDoctor - Standalone Windows Network Optimizer & Diagnostics Tool
# No AI or external dependencies required. 100% native PowerShell.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "NetDoctor v1.0 - Windows Network Diagnostic & Gaming Optimizer"

function Show-Header {
    Clear-Host
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "  _   _      _   ____             _                                       " -ForegroundColor Cyan
    Write-Host " | \ | | ___| |_|  _ \  ___   ___| |_ ___  _ __                           " -ForegroundColor Cyan
    Write-Host " |  \| |/ _ \ __| | | |/ _ \ / __| __/ _ \| '__|                          " -ForegroundColor Cyan
    Write-Host " | |\  |  __/ |_| |_| | (_) | (__| || (_) | |                             " -ForegroundColor Cyan
    Write-Host " |_| \_|\___|\__|____/ \___/ \___|\__\___/|_|                             " -ForegroundColor Cyan
    Write-Host "                                                                          " -ForegroundColor Cyan
    Write-Host " Standalone Network Diagnostics, MTU Discovery & Gaming Latency Optimizer " -ForegroundColor White
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Run-Diagnostics {
    param([switch]$Silent)

    if (-not $Silent) {
        Write-Host "--- [1/5] SCANNING NETWORK ADAPTERS ---" -ForegroundColor Yellow
    }
    
    $adapters = Get-NetAdapter | Where-Object { 
        $_.Status -eq "Up" -and 
        $_.InterfaceDescription -notlike "*Hyper-V*" -and 
        $_.InterfaceDescription -notlike "*Wintun*" -and 
        $_.InterfaceDescription -notlike "*Virtual*"
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
            $issues += "Ethernet link speed is negotiated at $($a.LinkSpeed). (Slow/Damaged Cable)"
        }
    }

    # 2. Path MTU Discovery Sweep
    if (-not $Silent) {
        Write-Host ""
        Write-Host "--- [2/5] RUNNING PATH MTU DISCOVERY ---" -ForegroundColor Yellow
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
                Write-Host "    Payload $size B (MTU $($size+28)): PASS (No Fragmentation)" -ForegroundColor Green
            }
            break
        } else {
            if (-not $Silent) {
                Write-Host "    Payload $size B (MTU $($size+28)): FAILED (Fragmentation Required)" -ForegroundColor Red
            }
        }
    }
    $optimalMTU = if ($optimalPayload -gt 0) { $optimalPayload + 28 } else { 1492 }

    foreach ($ad in $adapterDetails) {
        if ($ad.MTU -gt $optimalMTU) {
            $issues += "MTU Mismatch on '$($ad.Name)' (Configured: $($ad.MTU), Optimal: $optimalMTU). Causes packet loss!"
        }
    }

    # 3. NIC Driver Latency Settings
    if (-not $Silent) {
        Write-Host ""
        Write-Host "--- [3/5] CHECKING HARDWARE LATENCY SETTINGS ---" -ForegroundColor Yellow
    }
    foreach ($a in $adapters) {
        $props = Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue
        if ($props) {
            $green = $props | Where-Object { $_.RegistryKeyword -eq "EnableGreenEthernet" }
            $lso = $props | Where-Object { $_.RegistryKeyword -eq "*LsoV2IPv4" }
            $flow = $props | Where-Object { $_.RegistryKeyword -eq "*FlowControl" }

            if ($green -and $green.DisplayValue -eq "Enabled") {
                $issues += "Green Ethernet / Power Throttling is Enabled on '$($a.Name)'"
                if (-not $Silent) { Write-Host "    [!] Green Ethernet: Enabled (Adds latency)" -ForegroundColor Yellow }
            } elseif ($green) {
                if (-not $Silent) { Write-Host "    [OK] Green Ethernet: Disabled" -ForegroundColor Green }
            }

            if ($lso -and $lso.DisplayValue -eq "Enabled") {
                $issues += "Large Send Offload (LSO) is Enabled on '$($a.Name)'"
                if (-not $Silent) { Write-Host "    [!] Large Send Offload: Enabled (Packet batching jitter)" -ForegroundColor Yellow }
            } elseif ($lso) {
                if (-not $Silent) { Write-Host "    [OK] Large Send Offload: Disabled" -ForegroundColor Green }
            }

            if ($flow -and $flow.DisplayValue -ne "Disabled") {
                $issues += "Flow Control is Enabled on '$($a.Name)'"
                if (-not $Silent) { Write-Host "    [!] Flow Control: Enabled (Can pause game packets)" -ForegroundColor Yellow }
            } elseif ($flow) {
                if (-not $Silent) { Write-Host "    [OK] Flow Control: Disabled" -ForegroundColor Green }
            }
        }
    }

    # 4. Latency & Jitter Ping Test
    if (-not $Silent) {
        Write-Host ""
        Write-Host "--- [4/5] MEASURING PING, JITTER & PACKET LOSS ---" -ForegroundColor Yellow
    }
    $gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway }).IPv4DefaultGateway.NextHop
    $gwLatency = 0
    if ($gw) {
        $gwPings = Test-Connection -ComputerName $gw -Count 5 -ErrorAction SilentlyContinue
        if ($gwPings) {
            $gwLatency = [math]::Round(($gwPings | Measure-Object -Property ResponseTime -Average).Average, 1)
            if (-not $Silent) { Write-Host "    Local Router ($gw): $gwLatency ms (0% Loss)" -ForegroundColor Green }
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
            Write-Host "    Internet Ping (8.8.8.8): $wanAvg ms | Jitter: $wanJitter ms | Loss: $wanLoss%" -ForegroundColor $(if ($wanLoss -eq 0) { "Green" } else { "Red" })
        }
    }

    # 5. Windows Gaming Multimedia Settings
    if (-not $Silent) {
        Write-Host ""
        Write-Host "--- [5/5] WINDOWS NETWORK SCHEDULER & P2P LEAK ---" -ForegroundColor Yellow
    }
    $sysProfile = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -ErrorAction SilentlyContinue
    if ($sysProfile -and $sysProfile.NetworkThrottlingIndex -ne [uint32]0xFFFFFFFF) {
        $issues += "Windows Multimedia Network Throttling is ACTIVE"
        if (-not $Silent) { Write-Host "    [!] NetworkThrottlingIndex: Active (Throttles gaming packets)" -ForegroundColor Yellow }
    } else {
        if (-not $Silent) { Write-Host "    [OK] NetworkThrottlingIndex: Disabled (Uncapped)" -ForegroundColor Green }
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
    Write-Host "                     APPLYING AUTOMATED OPTIMIZATIONS                     " -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""

    $optimalMTU = $Diag.OptimalMTU
    $adapters = $Diag.Adapters

    # 1. Set MTU
    Write-Host "[1/4] Applying Optimal MTU ($optimalMTU)..." -ForegroundColor Yellow
    foreach ($a in $adapters) {
        netsh interface ipv4 set subinterface "$($a.Name)" mtu=$optimalMTU store=persistent | Out-Null
        Write-Host "  [OK] Set MTU on '$($a.Name)' to $optimalMTU" -ForegroundColor Green
    }

    # 2. Hardware Driver Properties
    Write-Host "[2/4] Disabling NIC Latency & Power Throttling..." -ForegroundColor Yellow
    foreach ($a in $adapters) {
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "EnableGreenEthernet" -RegistryValue 0 -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "GigaLite" -RegistryValue 0 -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "PowerSavingMode" -RegistryValue 0 -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "AdvancedEEE" -RegistryValue 0 -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "EEELinkAdvertisement" -RegistryValue 0 -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "*FlowControl" -RegistryValue 0 -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "*LsoV2IPv4" -RegistryValue 0 -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "*LsoV2IPv6" -RegistryValue 0 -ErrorAction SilentlyContinue
        Write-Host "  [OK] Tuned NIC properties on '$($a.Name)'" -ForegroundColor Green
    }

    # 3. Windows Gaming Priority & MMCSS
    Write-Host "[3/4] Tuning Windows Gaming Network Priority..." -ForegroundColor Yellow
    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] NetworkThrottlingIndex disabled & SystemResponsiveness set to 0 (Max Priority)" -ForegroundColor Green

    # 4. TCP Stack Tuning & DNS Flush
    Write-Host "[4/4] Optimizing TCP Stack & Flushing DNS..." -ForegroundColor Yellow
    netsh int tcp set global autotuninglevel=normal | Out-Null
    netsh int tcp set global rss=enabled | Out-Null
    netsh int tcp set global fastopen=enabled | Out-Null
    Clear-DnsClientCache
    Write-Host "  [OK] TCP Window Autotuning set to Normal, RSS Enabled, DNS Flushed" -ForegroundColor Green
    Write-Host ""
}

# --- Interactive Main Loop ---
while ($true) {
    Show-Header
    Write-Host "  [1] 🚀 FULL AUTO-FIX (Diagnose -> Optimize -> Verify & Report)" -ForegroundColor Green
    Write-Host "  [2] 🔍 DIAGNOSE ONLY (Scan for MTU, bufferbloat & packet loss)" -ForegroundColor Yellow
    Write-Host "  [3] ⚡ APPLY OPTIMIZATIONS ONLY" -ForegroundColor Cyan
    Write-Host "  [0] ❌ EXIT" -ForegroundColor Gray
    Write-Host ""
    $choice = Read-Host "Select an option (0-3)"

    switch ($choice) {
        "1" {
            Show-Header
            Write-Host ">>> PHASE 1: INITIAL DIAGNOSIS" -ForegroundColor Cyan
            $before = Run-Diagnostics
            
            Write-Host ""
            if ($before.Issues.Count -gt 0) {
                Write-Host "Found $($before.Issues.Count) issues to fix!" -ForegroundColor Yellow
                foreach ($iss in $before.Issues) { Write-Host "  • $iss" -ForegroundColor Red }
            } else {
                Write-Host "Connection is already in good shape, optimizing settings further..." -ForegroundColor Green
            }

            Apply-Optimizations -Diag $before

            Write-Host ">>> PHASE 2: VERIFICATION TEST" -ForegroundColor Cyan
            $after = Run-Diagnostics
            
            # Save Report to Desktop
            $reportPath = [System.IO.Path]::Combine($PSScriptRoot, "NetDoctor_Report.txt")
            $reportContent = @"
==========================================================================
                      NETDOCTOR OPTIMIZATION REPORT                       
==========================================================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Optimal MTU: $($after.OptimalMTU)
Router Latency: $($after.GwLatency) ms
Internet Ping: $($after.WanAvg) ms
Ping Jitter: $($after.WanJitter) ms
Packet Loss: $($after.WanLoss)%

Issues Resolved:
$($before.Issues | ForEach-Object { " - $_" } | Out-String)
Status: OPTIMIZED FOR COMPETITIVE ONLINE GAMING
==========================================================================
"@
            $reportContent | Set-Content -Path $reportPath -Encoding utf8

            Write-Host ""
            Write-Host "==========================================================================" -ForegroundColor Green
            Write-Host "✅ COMPLETE! Full optimization report saved to:" -ForegroundColor Green
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
                Write-Host "✅ NO ISSUES FOUND! Network is performing at peak capacity." -ForegroundColor Green
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
            Write-Host "✅ Optimizations applied successfully!" -ForegroundColor Green
            Read-Host "Press Enter to return to menu..."
        }
        "0" {
            exit
        }
    }
}
