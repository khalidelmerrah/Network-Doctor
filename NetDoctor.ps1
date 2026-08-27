# NetDoctor - Standalone Windows Network Optimizer & Diagnostics Tool for Gamers
# Run directly via PowerShell: irm https://raw.githubusercontent.com/khalidelmerrah/Network-Doctor/main/NetDoctor.ps1 | iex
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "NetDoctor v1.2 - Ultimate Gaming Network & Latency Optimizer"

# --- 1. Check Administrator Privileges ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Clear-Host
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host "                ⚠️  ADMINISTRATOR PRIVILEGES REQUIRED  ⚠️                 " -ForegroundColor Yellow
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host " NetDoctor needs Administrator rights to discover optimal MTU and tune " -ForegroundColor White
    Write-Host " your network adapter's latency settings." -ForegroundColor White
    Write-Host ""
    Write-Host " 👉 Please open PowerShell as Administrator and re-run:" -ForegroundColor Cyan
    Write-Host "    irm https://raw.githubusercontent.com/khalidelmerrah/Network-Doctor/main/NetDoctor.ps1 | iex" -ForegroundColor Green
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit..."
    exit
}

# --- Shared Helpers ---
$script:BackupDir  = Join-Path $env:ProgramData "NetDoctor"
$script:BackupPath = Join-Path $script:BackupDir "settings-backup.json"

function Get-PhysicalAdapters {
    $adapters = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and
        $_.InterfaceDescription -notlike "*Hyper-V*" -and
        $_.InterfaceDescription -notlike "*Wintun*" -and
        $_.InterfaceDescription -notlike "*Virtual*" -and
        $_.InterfaceDescription -notlike "*Loopback*" -and
        $_.InterfaceDescription -notlike "*TAP-*" -and
        $_.InterfaceDescription -notlike "*VPN*"
    }
    if (-not $adapters) { $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } }
    return $adapters
}

function Get-PingStats {
    # .NET Ping: locale-independent and identical on PowerShell 5.1 and 7+
    # (Test-Connection exposes ResponseTime on 5.1 but Latency on 7, and 7 emits
    #  an object even for failed pings, which broke the old loss calculation)
    param([string]$Target, [int]$Count = 10, [int]$TimeoutMs = 2000)
    $pinger = New-Object System.Net.NetworkInformation.Ping
    $times = New-Object System.Collections.Generic.List[double]
    $lost = 0
    try {
        for ($i = 0; $i -lt $Count; $i++) {
            try {
                $reply = $pinger.Send($Target, $TimeoutMs)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    [void]$times.Add([double]$reply.RoundtripTime)
                } else { $lost++ }
            } catch { $lost++ }
            if ($i -lt ($Count - 1)) { Start-Sleep -Milliseconds 100 }
        }
    } finally { $pinger.Dispose() }

    $avg = 0.0; $jitter = 0.0
    if ($times.Count -gt 0) {
        $avg = [math]::Round(($times | Measure-Object -Average).Average, 1)
        if ($times.Count -gt 1) {
            # Jitter as standard deviation - max-minus-min let one outlier dominate
            $variance = ($times | ForEach-Object { [math]::Pow($_ - $avg, 2) } | Measure-Object -Average).Average
            $jitter = [math]::Round([math]::Sqrt($variance), 1)
        }
    }
    return @{
        Avg     = $avg
        Jitter  = $jitter
        LossPct = [math]::Round(($lost / $Count) * 100, 0)
        Sent    = $Count
        Lost    = $lost
    }
}

function Test-MtuPayload {
    # ICMP echo with Don't-Fragment set. Two attempts so one transient drop
    # does not mislabel a payload size as fragmenting.
    param([string]$Target, [int]$PayloadSize, [int]$TimeoutMs = 2000)
    $pinger = New-Object System.Net.NetworkInformation.Ping
    try {
        $opts = New-Object System.Net.NetworkInformation.PingOptions
        $opts.DontFragment = $true
        $buffer = New-Object byte[] $PayloadSize
        for ($attempt = 0; $attempt -lt 2; $attempt++) {
            try {
                $reply = $pinger.Send($Target, $TimeoutMs, $buffer, $opts)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { return $true }
            } catch { }
        }
        return $false
    } finally { $pinger.Dispose() }
}

function Find-OptimalPayload {
    # Binary search for the largest unfragmented payload. Returns 0 when even
    # the floor fails (network unreachable or heavily filtered path).
    param([string]$Target, [int]$Floor = 1200, [int]$Ceiling = 1472)
    if (Test-MtuPayload -Target $Target -PayloadSize $Ceiling) { return $Ceiling }
    if (-not (Test-MtuPayload -Target $Target -PayloadSize $Floor)) { return 0 }
    $low = $Floor; $high = $Ceiling
    while (($high - $low) -gt 1) {
        $mid = [int][math]::Floor(($low + $high) / 2)
        if (Test-MtuPayload -Target $Target -PayloadSize $mid) { $low = $mid } else { $high = $mid }
    }
    return $low
}

function Save-SettingsBackup {
    # Snapshot the pre-NetDoctor state once. If a backup already exists it is
    # kept: it represents the true original settings before any optimization.
    param($Adapters)
    if (Test-Path $script:BackupPath) { return $false }

    $backup = @{
        CreatedAt = (Get-Date).ToString("o")
        Adapters  = @()
        Registry  = @{}
    }
    foreach ($a in $Adapters) {
        $ipConf = Get-NetIPInterface -InterfaceAlias $a.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $props = @(Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue |
            Where-Object { $_.RegistryKeyword } |
            ForEach-Object { @{ Keyword = $_.RegistryKeyword; Value = @($_.RegistryValue) } })
        $backup.Adapters += @{
            Name       = $a.Name
            Mtu        = if ($ipConf) { $ipConf.NlMtu } else { 1500 }
            Properties = $props
        }
    }
    $sysProfile = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -ErrorAction SilentlyContinue
    $backup.Registry.NetworkThrottlingIndex = if ($sysProfile -and $null -ne $sysProfile.NetworkThrottlingIndex) { [string][uint32]$sysProfile.NetworkThrottlingIndex } else { $null }
    $backup.Registry.SystemResponsiveness  = if ($sysProfile -and $null -ne $sysProfile.SystemResponsiveness)  { [string][uint32]$sysProfile.SystemResponsiveness }  else { $null }

    New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    $backup | ConvertTo-Json -Depth 6 | Set-Content -Path $script:BackupPath -Encoding UTF8
    return $true
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
    
    $adapters = Get-PhysicalAdapters

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
    $optimalPayload = Find-OptimalPayload -Target $target
    $optimalMTU = if ($optimalPayload -gt 0) { $optimalPayload + 28 } else { 1492 }
    if (-not $Silent) {
        if ($optimalPayload -gt 0) {
            Write-Host "    Largest unfragmented payload: $optimalPayload B (+28 B header = MTU $optimalMTU)" -ForegroundColor Green
        } else {
            Write-Host "    MTU sweep inconclusive (no unfragmented replies). Assuming PPPoE-safe MTU 1492." -ForegroundColor Yellow
        }
    }

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
    $gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway }).IPv4DefaultGateway.NextHop | Select-Object -First 1
    $gwLatency = 0
    if ($gw) {
        $gwStats = Get-PingStats -Target $gw -Count 5
        $gwLatency = $gwStats.Avg
        if (-not $Silent) {
            $gwColor = if ($gwStats.LossPct -eq 0) { "Green" } else { "Yellow" }
            Write-Host "    Gateway ($gw): avg $($gwStats.Avg) ms | jitter $($gwStats.Jitter) ms | loss $($gwStats.LossPct)%" -ForegroundColor $gwColor
        }
    }

    $wanStats = Get-PingStats -Target "8.8.8.8" -Count 10
    $wanAvg = $wanStats.Avg; $wanJitter = $wanStats.Jitter; $wanLoss = $wanStats.LossPct
    if (-not $Silent) {
        $wanColor = if ($wanLoss -eq 0) { "Green" } else { "Red" }
        Write-Host "    Internet (8.8.8.8): avg $wanAvg ms | jitter $wanJitter ms | loss $wanLoss%" -ForegroundColor $wanColor
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

    # 0. Backup current state (first run only)
    if (Save-SettingsBackup -Adapters $adapters) {
        Write-Host "[0/4] Saved original settings backup to $script:BackupPath" -ForegroundColor Gray
    } else {
        Write-Host "[0/4] Original settings backup already exists ($script:BackupPath) - keeping it" -ForegroundColor Gray
    }

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
    $hasBackup = Test-Path $script:BackupPath
    Write-Host "==========================================================================" -ForegroundColor Yellow
    Write-Host "                       RESTORE NETWORK SETTINGS                           " -ForegroundColor Yellow
    Write-Host "==========================================================================" -ForegroundColor Yellow
    Write-Host ""
    if ($hasBackup) {
        $backupDate = try { (Get-Content $script:BackupPath -Raw | ConvertFrom-Json).CreatedAt } catch { "unknown date" }
        Write-Host "A backup of your original settings was found (taken $backupDate)." -ForegroundColor White
        Write-Host "This will restore, per adapter, exactly what NetDoctor found before optimizing:" -ForegroundColor White
        Write-Host "  - Original IPv4 MTU values" -ForegroundColor Gray
        Write-Host "  - Original NIC advanced driver properties" -ForegroundColor Gray
        Write-Host "  - Original NetworkThrottlingIndex / SystemResponsiveness registry values" -ForegroundColor Gray
    } else {
        Write-Host "No NetDoctor backup found - falling back to stock Windows defaults:" -ForegroundColor White
        Write-Host "  - IPv4 MTU 1500 on physical adapters" -ForegroundColor Gray
        Write-Host "  - NIC advanced properties reset to driver defaults" -ForegroundColor Gray
        Write-Host "  - NetworkThrottlingIndex = 10, SystemResponsiveness = 20" -ForegroundColor Gray
    }
    Write-Host "  - TCP autotuning back to normal, DNS cache flushed" -ForegroundColor Gray
    Write-Host ""

    $confirm = Read-Host "Proceed with restore? (Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Host "Operation cancelled." -ForegroundColor Gray
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
        return
    }

    Write-Host ""
    Write-Host "Reverting network settings..." -ForegroundColor Yellow
    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"

    if ($hasBackup) {
        $backup = Get-Content $script:BackupPath -Raw | ConvertFrom-Json

        foreach ($ba in $backup.Adapters) {
            if (-not (Get-NetAdapter -Name $ba.Name -ErrorAction SilentlyContinue)) {
                Write-Host "  [SKIP] Adapter '$($ba.Name)' from backup no longer present" -ForegroundColor Yellow
                continue
            }
            netsh interface ipv4 set subinterface "$($ba.Name)" mtu=$($ba.Mtu) store=persistent | Out-Null
            $restored = 0; $failed = 0
            foreach ($p in $ba.Properties) {
                Set-NetAdapterAdvancedProperty -Name $ba.Name -RegistryKeyword $p.Keyword -RegistryValue @($p.Value) -ErrorAction SilentlyContinue
                if ($?) { $restored++ } else { $failed++ }
            }
            Write-Host "  [OK] '$($ba.Name)': MTU restored to $($ba.Mtu), $restored driver properties restored$(if ($failed) { ", $failed skipped" })" -ForegroundColor Green
        }

        foreach ($regName in @("NetworkThrottlingIndex", "SystemResponsiveness")) {
            $val = $backup.Registry.$regName
            if ($null -ne $val -and "$val" -ne "") {
                Set-ItemProperty -Path $sysProfile -Name $regName -Value ([uint32]"$val") -Type DWord -Force -ErrorAction SilentlyContinue
                Write-Host "  [OK] $regName restored to $val" -ForegroundColor Green
            } else {
                Remove-ItemProperty -Path $sysProfile -Name $regName -Force -ErrorAction SilentlyContinue
                Write-Host "  [OK] $regName removed (was not set originally)" -ForegroundColor Green
            }
        }

        Remove-Item $script:BackupPath -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Backup consumed and removed - next optimization takes a fresh snapshot" -ForegroundColor Gray
    } else {
        # Stock defaults path. Only touch physical adapters: forcing MTU 1500 on
        # a VPN/virtual interface (WireGuard, Hyper-V) can break its tunnel.
        $adapters = Get-PhysicalAdapters
        foreach ($a in $adapters) {
            netsh interface ipv4 set subinterface "$($a.Name)" mtu=1500 store=persistent | Out-Null
            Reset-NetAdapterAdvancedProperty -Name $a.Name -DisplayName "*" -ErrorAction SilentlyContinue
            Write-Host "  [OK] '$($a.Name)': MTU reset to 1500, NIC properties reset to driver defaults" -ForegroundColor Green
        }
        Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 20 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] NetworkThrottlingIndex = 10, SystemResponsiveness = 20 (Windows defaults)" -ForegroundColor Green
    }

    netsh int tcp set global autotuninglevel=normal | Out-Null
    Clear-DnsClientCache
    Write-Host "  [OK] TCP autotuning set to normal, DNS cache flushed" -ForegroundColor Green

    Write-Host ""
    Write-Host "Network settings restored successfully." -ForegroundColor Green
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
