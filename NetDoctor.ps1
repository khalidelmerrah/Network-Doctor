# NetDoctor - Standalone Windows network diagnostics and latency optimizer
# Run directly: irm https://raw.githubusercontent.com/khalidelmerrah/Network-Doctor/main/NetDoctor.ps1 | iex
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$script:Version = "1.3.0"
try { $Host.UI.RawUI.WindowTitle = "NetDoctor v$script:Version - Network Diagnostics & Latency Optimizer" } catch { }

$script:Line = "=========================================================================="
$script:Thin = "--------------------------------------------------------------------------"

# --- Output Helpers ---
function Write-Status {
    param(
        [ValidateSet("OK", "WARN", "FAIL", "INFO")] [string]$Level,
        [string]$Message
    )
    $ts = Get-Date -Format "HH:mm:ss"
    $tag, $color = switch ($Level) {
        "OK"   { " OK ", "Green" }
        "WARN" { "WARN", "Yellow" }
        "FAIL" { "FAIL", "Red" }
        "INFO" { "INFO", "Gray" }
    }
    Write-Host "  $ts  [$tag]  $Message" -ForegroundColor $color
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "  $script:Thin" -ForegroundColor DarkGray
}

# --- 1. Check Administrator Privileges ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Clear-Host
    Write-Host $script:Line -ForegroundColor Yellow
    Write-Host " NetDoctor v$script:Version - Administrator privileges required" -ForegroundColor White
    Write-Host $script:Line -ForegroundColor Yellow
    Write-Host ""
    Write-Host " NetDoctor changes network adapter and registry settings, which requires" -ForegroundColor Gray
    Write-Host " an elevated session. Open PowerShell as Administrator and run:" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   irm https://raw.githubusercontent.com/khalidelmerrah/Network-Doctor/main/NetDoctor.ps1 | iex" -ForegroundColor Cyan
    Write-Host ""
    Read-Host " Press Enter to exit"
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
    $os = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption } catch { "Windows" }
    Write-Host ""
    Write-Host "  $script:Line" -ForegroundColor DarkCyan
    Write-Host "   NetDoctor v$script:Version" -ForegroundColor White
    Write-Host "   Windows Network Diagnostics & Latency Optimizer" -ForegroundColor Gray
    Write-Host "   $os | PowerShell $($PSVersionTable.PSVersion) | Elevated session" -ForegroundColor DarkGray
    Write-Host "  $script:Line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Run-CloudflareTest {
    Write-Section "Throughput benchmark (Cloudflare edge)"
    Write-Status INFO "Downloading 10 MB from speed.cloudflare.com..."

    $client = $null
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromSeconds(30)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $data = $client.GetByteArrayAsync("https://speed.cloudflare.com/__down?bytes=10000000").GetAwaiter().GetResult()
        $sw.Stop()
        if ($sw.ElapsedMilliseconds -gt 0) {
            $downMbps = [math]::Round(($data.Length * 8 / 1000000) / ($sw.ElapsedMilliseconds / 1000), 2)
            Write-Status OK "Download: $downMbps Mbps ($([math]::Round($data.Length / 1MB, 1)) MB in $($sw.ElapsedMilliseconds) ms)"
        }
    } catch {
        Write-Status WARN "Download test failed or timed out after 30 s."
    } finally {
        if ($client) { $client.Dispose() }
    }

    Write-Host ""
    $openBrowser = Read-Host "  Open speed.cloudflare.com in your browser for a full benchmark (latency under load, jitter)? (Y/N)"
    if ($openBrowser -eq "Y" -or $openBrowser -eq "y") {
        Start-Process "https://speed.cloudflare.com/"
    }
}

function Run-Diagnostics {
    param([switch]$Silent)

    if (-not $Silent) { Write-Section "[1/5] Network adapters" }

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
            Write-Status INFO "$($a.Name): $($a.InterfaceDescription)"
            Write-Status INFO "  link $($a.LinkSpeed) | IPv4 MTU $mtu"
        }

        if ($a.LinkSpeed -like "*100 Mbps*" -or $a.LinkSpeed -like "*10 Mbps*") {
            $issues += "'$($a.Name)' negotiated at $($a.LinkSpeed). On gigabit hardware this usually means a damaged cable or a bad switch/router port."
        }
    }

    # 2. Path MTU discovery
    if (-not $Silent) { Write-Section "[2/5] Path MTU discovery" }
    $target = "8.8.8.8"
    $optimalPayload = Find-OptimalPayload -Target $target
    $optimalMTU = if ($optimalPayload -gt 0) { $optimalPayload + 28 } else { 1492 }
    if (-not $Silent) {
        if ($optimalPayload -gt 0) {
            Write-Status OK "Largest unfragmented payload: $optimalPayload bytes (+28 header = path MTU $optimalMTU)"
        } else {
            Write-Status WARN "Sweep inconclusive (no unfragmented replies). Assuming PPPoE-safe MTU 1492."
        }
    }

    foreach ($ad in $adapterDetails) {
        if ($ad.MTU -gt $optimalMTU) {
            $issues += "MTU mismatch on '$($ad.Name)': interface is set to $($ad.MTU) but the path maximum is $optimalMTU. Oversized packets get fragmented or silently dropped."
        }
    }

    # 3. NIC driver latency settings (vendor-neutral)
    if (-not $Silent) { Write-Section "[3/5] NIC driver settings (Intel / Realtek / Killer / Marvell)" }
    foreach ($a in $adapters) {
        $props = Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue
        if ($props) {
            # Power saving / Green Ethernet / EEE across vendors
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
                $issues += "Power-saving features (Green Ethernet / EEE) enabled on '$($a.Name)'. These let the NIC idle and can add latency spikes when traffic resumes."
                if (-not $Silent) { Write-Status WARN "$($a.Name): power saving / Green Ethernet enabled" }
            } elseif (-not $Silent) {
                Write-Status OK "$($a.Name): power saving / Green Ethernet disabled"
            }

            # Large Send Offload
            $lsoProps = $props | Where-Object { $_.RegistryKeyword -like "*LsoV2*" -or $_.DisplayName -like "*Large Send Offload*" }
            $hasLSO = ($lsoProps | Where-Object { $_.DisplayValue -eq "Enabled" -or $_.RegistryValue -eq 1 })
            if ($hasLSO) {
                $issues += "Large Send Offload enabled on '$($a.Name)'. LSO batches outgoing packets, which can add jitter for time-sensitive traffic."
                if (-not $Silent) { Write-Status WARN "$($a.Name): Large Send Offload enabled" }
            } elseif (-not $Silent) {
                Write-Status OK "$($a.Name): Large Send Offload disabled"
            }

            # Flow Control
            $flowProps = $props | Where-Object { $_.RegistryKeyword -eq "*FlowControl" -or $_.DisplayName -like "*Flow Control*" }
            $hasFlow = ($flowProps | Where-Object { $_.DisplayValue -ne "Disabled" -and $_.RegistryValue -ne 0 })
            if ($hasFlow) {
                $issues += "Flow Control enabled on '$($a.Name)'. Pause frames can hold back traffic during congestion."
                if (-not $Silent) { Write-Status WARN "$($a.Name): Flow Control enabled" }
            } elseif (-not $Silent) {
                Write-Status OK "$($a.Name): Flow Control disabled"
            }
        }
    }

    # 4. Latency, jitter, packet loss
    if (-not $Silent) { Write-Section "[4/5] Latency, jitter and packet loss" }
    $gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway }).IPv4DefaultGateway.NextHop | Select-Object -First 1
    $gwLatency = 0
    if ($gw) {
        $gwStats = Get-PingStats -Target $gw -Count 5
        $gwLatency = $gwStats.Avg
        if (-not $Silent) {
            $lvl = if ($gwStats.LossPct -eq 0) { "OK" } else { "WARN" }
            Write-Status $lvl "Gateway $gw`: avg $($gwStats.Avg) ms, jitter $($gwStats.Jitter) ms, loss $($gwStats.LossPct)% (5 probes)"
        }
    }

    $wanStats = Get-PingStats -Target "8.8.8.8" -Count 10
    $wanAvg = $wanStats.Avg; $wanJitter = $wanStats.Jitter; $wanLoss = $wanStats.LossPct
    if (-not $Silent) {
        $lvl = if ($wanLoss -eq 0) { "OK" } else { "FAIL" }
        Write-Status $lvl "Internet 8.8.8.8: avg $wanAvg ms, jitter $wanJitter ms, loss $wanLoss% (10 probes)"
    }
    if ($wanLoss -gt 0) {
        $issues += "Packet loss to 8.8.8.8 measured at $wanLoss%. Any loss above 0% is noticeable in real-time applications."
    }

    # 5. Windows multimedia network throttling
    if (-not $Silent) { Write-Section "[5/5] Windows multimedia network throttling" }
    $sysProfile = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -ErrorAction SilentlyContinue
    $throttleVal = if ($sysProfile) { $sysProfile.NetworkThrottlingIndex } else { $null }
    $isThrottlingDisabled = ($throttleVal -eq 4294967295 -or $throttleVal -eq -1 -or $throttleVal -eq 0xFFFFFFFF)
    if ($null -ne $throttleVal -and -not $isThrottlingDisabled) {
        $issues += "Windows multimedia network throttling is active (NetworkThrottlingIndex = $throttleVal). It caps network packet processing while multimedia runs."
        if (-not $Silent) { Write-Status WARN "NetworkThrottlingIndex = $throttleVal (throttling active)" }
    } elseif (-not $Silent) {
        Write-Status OK "NetworkThrottlingIndex disabled (no multimedia throttling)"
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

    Write-Section "Applying optimizations"

    $optimalMTU = $Diag.OptimalMTU
    $adapters = $Diag.Adapters

    # 0. Backup current state (first run only)
    if (Save-SettingsBackup -Adapters $adapters) {
        Write-Status INFO "Original settings backed up to $script:BackupPath"
    } else {
        Write-Status INFO "Keeping existing backup at $script:BackupPath"
    }

    # 1. Set MTU
    foreach ($a in $adapters) {
        netsh interface ipv4 set subinterface "$($a.Name)" mtu=$optimalMTU store=persistent | Out-Null
        $applied = (Get-NetIPInterface -InterfaceAlias $a.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue).NlMtu
        if ($applied -eq $optimalMTU) {
            Write-Status OK "$($a.Name): MTU set and verified at $optimalMTU"
        } else {
            Write-Status WARN "$($a.Name): requested MTU $optimalMTU but interface reports $applied"
        }
    }

    # 2. NIC driver properties (vendor-neutral: Intel, Realtek, Killer, Marvell)
    $vendorKeywords = @(
        "EnableGreenEthernet", "GigaLite", "PowerSavingMode", "AdvancedEEE", "EEELinkAdvertisement",
        "*EnergyEfficientEthernet", "*ReduceSpeedOnPowerDown", "*PowerDownPcie", "*ModernStandby",
        "*FlowControl", "*LsoV2IPv4", "*LsoV2IPv6"
    )

    foreach ($a in $adapters) {
        foreach ($kw in $vendorKeywords) {
            Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword $kw -RegistryValue 0 -ErrorAction SilentlyContinue
        }
        # Fallback wildcard matching for proprietary display names
        $displayPatterns = @("*Green*", "*Gigabit Lite*", "*Power Saving*", "*Energy Efficient*", "*Flow Control*", "*Large Send Offload*")
        foreach ($pattern in $displayPatterns) {
            Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName $pattern -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        }

        # Verify: re-read the driver and report anything still enabled
        $props = Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue
        $stillActive = @($props | Where-Object {
            $p = $_
            $matchesDisplay = $false
            foreach ($pattern in $displayPatterns) {
                if ($p.DisplayName -like $pattern) { $matchesDisplay = $true; break }
            }
            ($p.RegistryKeyword -in $vendorKeywords -or $matchesDisplay) -and
            ($p.DisplayValue -eq "Enabled" -or $p.RegistryValue -contains 1 -or $p.RegistryValue -contains "1")
        })
        if ($stillActive.Count -eq 0) {
            Write-Status OK "$($a.Name): latency-related driver flags disabled and verified"
        } else {
            $names = ($stillActive | ForEach-Object { if ($_.DisplayName) { $_.DisplayName } else { $_.RegistryKeyword } } | Select-Object -Unique) -join ", "
            Write-Status WARN "$($a.Name): driver refused to change: $names"
        }
    }

    # 3. Windows multimedia scheduler
    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Status OK "NetworkThrottlingIndex disabled, SystemResponsiveness set to 0"

    # 4. TCP stack and DNS cache
    netsh int tcp set global autotuninglevel=normal | Out-Null
    netsh int tcp set global rss=enabled | Out-Null
    netsh int tcp set global fastopen=enabled | Out-Null
    Clear-DnsClientCache
    Write-Status OK "TCP autotuning normal, RSS enabled, TCP Fast Open enabled, DNS cache flushed"
}

function Show-ResultsComparison {
    param($Before, $After)
    Write-Section "Results (before / after)"
    $rows = @(
        @{ Label = "Internet latency"; Before = "$($Before.WanAvg) ms";    After = "$($After.WanAvg) ms" }
        @{ Label = "Jitter";           Before = "$($Before.WanJitter) ms"; After = "$($After.WanJitter) ms" }
        @{ Label = "Packet loss";      Before = "$($Before.WanLoss)%";     After = "$($After.WanLoss)%" }
        @{ Label = "Gateway latency";  Before = "$($Before.GwLatency) ms"; After = "$($After.GwLatency) ms" }
        @{ Label = "Path MTU";         Before = "$($Before.OptimalMTU)";   After = "$($After.OptimalMTU) (applied)" }
    )
    foreach ($r in $rows) {
        Write-Host ("  {0,-18} {1,12}  ->  {2}" -f $r.Label, $r.Before, $r.After) -ForegroundColor White
    }
}

function Restore-Defaults {
    Show-Header
    $hasBackup = Test-Path $script:BackupPath
    Write-Section "Restore network settings"
    if ($hasBackup) {
        $backupDate = try { (Get-Content $script:BackupPath -Raw | ConvertFrom-Json).CreatedAt } catch { "unknown date" }
        Write-Host "  A backup of your original settings exists (taken $backupDate)." -ForegroundColor White
        Write-Host "  Restoring will replay, per adapter, exactly what NetDoctor found before optimizing:" -ForegroundColor Gray
        Write-Host "    - Original IPv4 MTU values" -ForegroundColor Gray
        Write-Host "    - Original NIC advanced driver properties" -ForegroundColor Gray
        Write-Host "    - Original NetworkThrottlingIndex / SystemResponsiveness registry values" -ForegroundColor Gray
    } else {
        Write-Host "  No NetDoctor backup found - falling back to stock Windows defaults:" -ForegroundColor White
        Write-Host "    - IPv4 MTU 1500 on physical adapters" -ForegroundColor Gray
        Write-Host "    - NIC advanced properties reset to driver defaults" -ForegroundColor Gray
        Write-Host "    - NetworkThrottlingIndex = 10, SystemResponsiveness = 20" -ForegroundColor Gray
    }
    Write-Host "    - TCP autotuning back to normal, DNS cache flushed" -ForegroundColor Gray
    Write-Host ""

    $confirm = Read-Host "  Proceed with restore? (Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Status INFO "Operation cancelled."
        Write-Host ""
        Read-Host "  Press Enter to return to the menu"
        return
    }

    Write-Section "Restoring"
    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"

    if ($hasBackup) {
        $backup = Get-Content $script:BackupPath -Raw | ConvertFrom-Json

        foreach ($ba in $backup.Adapters) {
            if (-not (Get-NetAdapter -Name $ba.Name -ErrorAction SilentlyContinue)) {
                Write-Status WARN "Adapter '$($ba.Name)' from backup no longer present - skipped"
                continue
            }
            netsh interface ipv4 set subinterface "$($ba.Name)" mtu=$($ba.Mtu) store=persistent | Out-Null
            $restored = 0; $failed = 0
            foreach ($p in $ba.Properties) {
                Set-NetAdapterAdvancedProperty -Name $ba.Name -RegistryKeyword $p.Keyword -RegistryValue @($p.Value) -ErrorAction SilentlyContinue
                if ($?) { $restored++ } else { $failed++ }
            }
            Write-Status OK "$($ba.Name): MTU restored to $($ba.Mtu), $restored driver properties restored$(if ($failed) { ", $failed skipped" })"
        }

        foreach ($regName in @("NetworkThrottlingIndex", "SystemResponsiveness")) {
            $val = $backup.Registry.$regName
            if ($null -ne $val -and "$val" -ne "") {
                Set-ItemProperty -Path $sysProfile -Name $regName -Value ([uint32]"$val") -Type DWord -Force -ErrorAction SilentlyContinue
                Write-Status OK "$regName restored to $val"
            } else {
                Remove-ItemProperty -Path $sysProfile -Name $regName -Force -ErrorAction SilentlyContinue
                Write-Status OK "$regName removed (was not set originally)"
            }
        }

        Remove-Item $script:BackupPath -Force -ErrorAction SilentlyContinue
        Write-Status INFO "Backup consumed and removed - the next optimization takes a fresh snapshot"
    } else {
        # Stock defaults path. Only touch physical adapters: forcing MTU 1500 on
        # a VPN/virtual interface (WireGuard, Hyper-V) can break its tunnel.
        $adapters = Get-PhysicalAdapters
        foreach ($a in $adapters) {
            netsh interface ipv4 set subinterface "$($a.Name)" mtu=1500 store=persistent | Out-Null
            Reset-NetAdapterAdvancedProperty -Name $a.Name -DisplayName "*" -ErrorAction SilentlyContinue
            Write-Status OK "$($a.Name): MTU reset to 1500, NIC properties reset to driver defaults"
        }
        Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 20 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Status OK "NetworkThrottlingIndex = 10, SystemResponsiveness = 20 (Windows defaults)"
    }

    netsh int tcp set global autotuninglevel=normal | Out-Null
    Clear-DnsClientCache
    Write-Status OK "TCP autotuning set to normal, DNS cache flushed"

    Write-Host ""
    Write-Host "  Network settings restored successfully." -ForegroundColor Green
    Write-Host ""
    Read-Host "  Press Enter to return to the menu"
}

# --- Interactive Main Loop ---
while ($true) {
    Show-Header
    Write-Host "   1  Full optimization     diagnose, apply, verify, save report" -ForegroundColor White
    Write-Host "   2  Diagnostics only      read-only health check, no changes" -ForegroundColor White
    Write-Host "   3  Apply optimizations   apply without the pre-diagnosis output" -ForegroundColor White
    Write-Host "   4  Speed test            Cloudflare download benchmark" -ForegroundColor White
    Write-Host "   5  Restore settings      revert to backup or Windows defaults" -ForegroundColor White
    Write-Host "   0  Exit" -ForegroundColor DarkGray
    Write-Host ""
    $choice = Read-Host "  Select an option (0-5)"

    switch ($choice) {
        "1" {
            Show-Header
            Write-Host "  Phase 1/3: initial diagnosis" -ForegroundColor Cyan
            $before = Run-Diagnostics

            Write-Section "Findings"
            if ($before.Issues.Count -gt 0) {
                Write-Status WARN "$($before.Issues.Count) issue(s) found:"
                foreach ($iss in $before.Issues) { Write-Host "    - $iss" -ForegroundColor Yellow }
            } else {
                Write-Status OK "No issues found. Applying preventive optimizations anyway."
            }

            Write-Host ""
            Write-Host "  Phase 2/3: applying optimizations" -ForegroundColor Cyan
            Apply-Optimizations -Diag $before

            Write-Host ""
            Write-Host "  Phase 3/3: post-optimization verification" -ForegroundColor Cyan
            $after = Run-Diagnostics

            Show-ResultsComparison -Before $before -After $after

            # Save report
            $desktopDir = [Environment]::GetFolderPath("Desktop")
            $reportPath = if ($PSScriptRoot) { [System.IO.Path]::Combine($PSScriptRoot, "NetDoctor_Report.txt") } else { [System.IO.Path]::Combine($desktopDir, "NetDoctor_Report.txt") }

            $reportContent = @"
==========================================================================
 NetDoctor v$script:Version - Optimization Report
==========================================================================
 Date:             $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

 Measurements                  Before          After
   Internet latency            $($before.WanAvg) ms$(" " * [math]::Max(1, 16 - "$($before.WanAvg) ms".Length))$($after.WanAvg) ms
   Jitter                      $($before.WanJitter) ms$(" " * [math]::Max(1, 16 - "$($before.WanJitter) ms".Length))$($after.WanJitter) ms
   Packet loss                 $($before.WanLoss)%$(" " * [math]::Max(1, 16 - "$($before.WanLoss)%".Length))$($after.WanLoss)%
   Gateway latency             $($before.GwLatency) ms$(" " * [math]::Max(1, 16 - "$($before.GwLatency) ms".Length))$($after.GwLatency) ms
   Path MTU (applied)          $($after.OptimalMTU)

 Issues found before optimizing:
$(if ($before.Issues.Count) { $before.Issues | ForEach-Object { "   - $_" } | Out-String } else { "   (none)`n" })
 Settings backup:  $(if (Test-Path $script:BackupPath) { $script:BackupPath } else { "consumed by a restore" })
 Revert anytime:   re-run NetDoctor and choose option 5 (Restore settings)
==========================================================================
"@
            $reportContent | Set-Content -Path $reportPath -Encoding utf8

            Write-Host ""
            Write-Status OK "Optimization complete. Report saved to $reportPath"
            Write-Host ""
            Read-Host "  Press Enter to return to the menu"
        }
        "2" {
            Show-Header
            $diag = Run-Diagnostics
            Write-Section "Findings"
            if ($diag.Issues.Count -eq 0) {
                Write-Status OK "No issues found. Network configuration looks healthy."
            } else {
                Write-Status WARN "$($diag.Issues.Count) issue(s) found:"
                foreach ($iss in $diag.Issues) { Write-Host "    - $iss" -ForegroundColor Yellow }
                Write-Host ""
                Write-Status INFO "Run option 1 or 3 to fix these automatically. A backup is taken first."
            }
            Write-Host ""
            Read-Host "  Press Enter to return to the menu"
        }
        "3" {
            Show-Header
            Write-Status INFO "Running silent diagnosis to determine optimal values..."
            $diag = Run-Diagnostics -Silent
            Apply-Optimizations -Diag $diag
            Write-Host ""
            Write-Status OK "Optimizations applied. Revert anytime with option 5."
            Read-Host "  Press Enter to return to the menu"
        }
        "4" {
            Show-Header
            Run-CloudflareTest
            Write-Host ""
            Read-Host "  Press Enter to return to the menu"
        }
        "5" {
            Restore-Defaults
        }
        "0" {
            exit
        }
        default {
            Write-Status WARN "Invalid selection '$choice' - choose 0-5."
            Start-Sleep -Seconds 1
        }
    }
}
