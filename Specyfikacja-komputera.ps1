# =====================================================================
# Specyfikacja-komputera.ps1
# Jednym kliknieciem zbiera parametry komputera i sklada z nich gotowy
# tekst do ogloszenia sprzedazy (OLX, Allegro itp.):
#   - kopiuje go do schowka (wystarczy Ctrl+V),
#   - zapisuje na pulpicie jako "Specyfikacja komputera.txt",
#   - otwiera w Notatniku.
# Celowo NIE zbiera: numerow seryjnych, klucza Windows, nazwy uzytkownika,
# nazwy komputera w sieci, adresow MAC/IP.
# Prosi o uprawnienia administratora (godziny pracy i zuzycie dyskow,
# wersja TPM). Po odmowie dziala dalej, tylko bez tych danych.
# Uruchamianie: "Specyfikacja komputera.cmd" (dwuklik).
# =====================================================================
param([switch]$Elevated, [string]$Desktop)

$ErrorActionPreference = 'SilentlyContinue'
if (-not $Desktop) { $Desktop = [Environment]::GetFolderPath('Desktop') }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Elevated) {
    try {
        Start-Process powershell.exe -Verb RunAs -ErrorAction Stop -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
            '-Elevated', '-Desktop', "`"$Desktop`"")
        exit
    } catch { }  # odmowa UAC - zbieramy to, co da sie bez administratora
}

Write-Host 'Zbieram dane o komputerze, chwilke...'

# ---------- pomocnicze ----------

function Q([string]$Class, [string]$Ns = 'root\cimv2', [string]$Filter) {
    try {
        if ($Filter) { @(Get-CimInstance -Namespace $Ns -ClassName $Class -Filter $Filter -ErrorAction Stop) }
        else { @(Get-CimInstance -Namespace $Ns -ClassName $Class -ErrorAction Stop) }
    } catch { @() }
}

function Clean($s) {
    if ($null -eq $s) { return '' }
    (([string]$s) -replace '\((R|TM|C)\)|®|™', '' -replace '\s+', ' ').Trim()
}

function Bogus($s) {
    $s = Clean $s
    (-not $s) -or ($s -match 'O\.?E\.?M|System Product Name|System manufacturer|System Version|Default string|To be filled|Not Applicable|^None$|^x+$|^0+$|^Type1|^Unknown')
}

function ShortMaker($s) {
    $s = Clean $s
    switch -Regex ($s) {
        '^Dell'                { return 'Dell' }
        '^(HP|Hewlett)'        { return 'HP' }
        '^LENOVO'              { return 'Lenovo' }
        'ASUSTeK|^ASUS'        { return 'ASUS' }
        'Micro-Star|^MSI'      { return 'MSI' }
        '^Acer'                { return 'Acer' }
        'Gigabyte'             { return 'Gigabyte' }
        'ASRock'               { return 'ASRock' }
        '^Microsoft'           { return 'Microsoft' }
        '^Apple'               { return 'Apple' }
        '^(TOSHIBA|Dynabook)'  { return 'Toshiba' }
        '^SAMSUNG'             { return 'Samsung' }
        '^FUJITSU'             { return 'Fujitsu' }
        '^Huawei'              { return 'Huawei' }
        '^Medion'              { return 'Medion' }
    }
    ($s -replace ',?\s*(Inc\.?|Co\.?,?\s*Ltd\.?|Ltd\.?|Corporation|Corp\.?|GmbH|Technology|COMPUTER INC\.?|International)\s*$', '').Trim()
}

# Rozmiar dysku tak, jak podaje producent (1 GB = 10^9 B): 512 GB, 1 TB...
function SizeGB([double]$bytes) {
    $gb = $bytes / 1e9
    if ($gb -ge 1000) { return ('{0:0.#} TB' -f ($gb / 1000)) }
    '{0:0} GB' -f $gb
}

# Odmiana: 1 rdzen, 2-4 rdzenie, 5+ rdzeni (12-14 rdzeni, 22-24 rdzenie)
function Plural([int]$n, [string]$one, [string]$few, [string]$many) {
    if ($n -eq 1) { return "$n $one" }
    $d = $n % 10; $t = $n % 100
    if ($d -ge 2 -and $d -le 4 -and ($t -lt 12 -or $t -gt 14)) { return "$n $few" }
    "$n $many"
}

function WStr($arr) { ((@($arr) | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '').Trim() }

# ---------- komputer ----------

$cs   = (Q Win32_ComputerSystem)[0]
$csp  = (Q Win32_ComputerSystemProduct)[0]
$bb   = (Q Win32_BaseBoard)[0]
$bios = (Q Win32_BIOS)[0]
$encl = (Q Win32_SystemEnclosure)[0]

$chassis  = @($encl.ChassisTypes)
$hasBatt  = (Q Win32_Battery).Count -gt 0
$isLaptop = $hasBatt -or (@($chassis | Where-Object { @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32) -contains $_ }).Count -gt 0)
if ($isLaptop) { $kindPc = 'laptop' }
elseif ($chassis -contains 13) { $kindPc = 'komputer all-in-one' }
elseif (@($chassis | Where-Object { @(35, 36) -contains $_ }).Count) { $kindPc = 'mini PC' }
else { $kindPc = 'komputer stacjonarny' }

$maker = ShortMaker $cs.Manufacturer
$model = Clean $cs.Model
if ($maker -eq 'Lenovo' -and -not (Bogus $csp.Version)) { $model = Clean $csp.Version }
if ($model -match ('^' + [regex]::Escape($maker) + '\s+')) { $model = $model.Substring($maker.Length).Trim() }

$boardName = ''
if (-not (Bogus $bb.Product)) { $boardName = ((ShortMaker $bb.Manufacturer) + ' ' + (Clean $bb.Product)).Trim() }

if ((Bogus $cs.Manufacturer) -or (Bogus $cs.Model)) {
    $computer = if ($boardName) { "$kindPc (składany, płyta $boardName)" } else { "$kindPc (składany)" }
    $title = $kindPc.Substring(0, 1).ToUpper() + $kindPc.Substring(1)
} else {
    $computer = "$maker $model ($kindPc)"
    $title = "$maker $model"
}

# ---------- procesor ----------

$cpus = Q Win32_Processor
$cpu  = $cpus[0]
$cpuName = (Clean $cpu.Name) -replace '\s+\d+-Core Processor', '' -replace '\s+(CPU|Processor)\b', '' -replace '\s*@.*$', ''
$cores   = [int](($cpus | Measure-Object NumberOfCores -Sum).Sum)
$threads = [int](($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
$cpuLine = $cpuName
if ($cpus.Count -gt 1) { $cpuLine = "$($cpus.Count) × $cpuName" }
$cpuLine += ', ' + (Plural $cores 'rdzeń' 'rdzenie' 'rdzeni') + ' / ' + (Plural $threads 'wątek' 'wątki' 'wątków')
if ($cpu.MaxClockSpeed) {
    $base = $cpu.MaxClockSpeed / 1000
    $cpuLine += (', taktowanie bazowe {0:0.0#} GHz' -f $base)
    # Turbo: WMI podaje tylko taktowanie bazowe, wiec mierzymy faktyczne. Jeden watek obciaza procesor
    # przez ~2 s, licznik "% Processor Performance" (100% = bazowe) pokazuje, ile realnie osiaga rdzen.
    # Mediana ze wszystkich rdzeni (reszta stoi bezczynnie) mowi, czy turbo trzyma sie caly czas.
    $load = [powershell]::Create().AddScript({ $e = [DateTime]::Now.AddSeconds(2.5); while ([DateTime]::Now -lt $e) { } })
    $h = $load.BeginInvoke()
    $null = Q Win32_PerfFormattedData_Counters_ProcessorInformation
    Start-Sleep -Milliseconds 1500
    $perf = @(Q Win32_PerfFormattedData_Counters_ProcessorInformation | Where-Object { $_.Name -notmatch '_Total' } |
              ForEach-Object { [double]$_.PercentProcessorPerformance } | Where-Object { $_ -gt 0 } | Sort-Object)
    $null = $load.EndInvoke($h); $load.Dispose()
    if ($perf.Count) {
        $max = $perf[-1]; $median = $perf[[int][math]::Floor($perf.Count / 2)]
        if ($max -ge 103) {
            $cpuLine += (', turbo do ok. {0:0.0} GHz (zmierzone)' -f ($base * $max / 100))
            if ($median -ge 105) { $cpuLine += ', turbo stale aktywne' }
        } else { $cpuLine += ', turbo nie wykryto (wyłączone lub brak)' }
    }
}

# ---------- pamiec RAM ----------

$mods = Q Win32_PhysicalMemory
$ramBytes = ($mods | Measure-Object Capacity -Sum).Sum
if (-not $ramBytes) { $ramBytes = $cs.TotalPhysicalMemory }
$ramGB = [math]::Round($ramBytes / 1GB)
$memTypes = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
$ramType = ''
if ($mods.Count) { $ramType = $memTypes[[int]$mods[0].SMBIOSMemoryType] }
$ramSpeed = ($mods | ForEach-Object { if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } else { $_.Speed } } | Measure-Object -Maximum).Maximum
$ramLine = "$ramGB GB"
if ($ramType) { $ramLine += " $ramType" }
if ($ramSpeed) { $ramLine += " $ramSpeed MHz" }
if ($mods.Count) {
    $groups = $mods | Group-Object { [math]::Round($_.Capacity / 1GB) } | Sort-Object { [int]$_.Name } -Descending
    $ramLine += ' (' + (($groups | ForEach-Object { "$($_.Count) × $($_.Name) GB" }) -join ' + ') + ')'
    $slots = [int]((Q Win32_PhysicalMemoryArray | Where-Object { $_.Use -eq 3 -or -not $_.Use } | Measure-Object MemoryDevices -Sum).Sum)
    if ($slots -ge $mods.Count -and $slots -gt 0) { $ramLine += ", zajęte gniazda: $($mods.Count) z $slots" }
}

# ---------- karta graficzna ----------

$vram = @{}
$classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
foreach ($k in @(Get-ChildItem $classKey)) {
    $p = Get-ItemProperty $k.PSPath
    if (-not $p.DriverDesc) { continue }
    $v = $p.'HardwareInformation.qwMemorySize'
    if ($null -eq $v) { $v = $p.'HardwareInformation.MemorySize' }
    if ($v -is [byte[]]) {
        if ($v.Length -ge 8) { $v = [BitConverter]::ToUInt64($v, 0) } elseif ($v.Length -ge 4) { $v = [BitConverter]::ToUInt32($v, 0) } else { $v = 0 }
    }
    if ($v) { $vram[$p.DriverDesc] = [double]$v }
}
# Karty NVIDIA w trybie obliczeniowym (TCC, np. Tesla) nie podaja pamieci przez WMI - pyta nvidia-smi.
$smiMem = @{}
$smi = (Get-Command nvidia-smi.exe).Source
if (-not $smi -and (Test-Path "$env:SystemRoot\System32\nvidia-smi.exe")) { $smi = "$env:SystemRoot\System32\nvidia-smi.exe" }
if ($smi) {
    foreach ($l in @(& $smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null)) {
        $f = $l -split ',\s*'
        if ($f.Count -ge 2 -and $f[1] -match '^\d+$') { $smiMem[$f[0].Trim()] = [double]$f[1] * 1MB }
    }
}
$gpuItems = @()
$dedicated = @()
foreach ($g in (Q Win32_VideoController)) {
    if ($g.Name -match 'Basic Display|Basic Render|Remote|Virtual|Parsec|Mirage|Citrix|DisplayLink|IddCx|Meta|Microsoft') { continue }
    $name = Clean $g.Name
    $integrated = ($name -match '^Intel' -and $name -notmatch '\bArc\b') -or ($name -match 'Radeon (Graphics|Vega)|Radeon\s*$|^AMD Radeon\s*\d{3}M')
    $mem = $vram[$g.Name]
    if (-not $mem) { $mem = [double]$g.AdapterRAM }
    if (-not $mem) { foreach ($k in $smiMem.Keys) { if ($g.Name -like "*$k") { $mem = $smiMem[$k] } } }
    if (-not $integrated -and $mem -ge 1GB) {
        if ($name -notmatch ('{0:0}\s?GB' -f ($mem / 1GB))) { $name += (' {0:0} GB' -f ($mem / 1GB)) }
        $dedicated += $name
    }
    if ($integrated) { $name += ' (zintegrowana)' }
    $gpuItems += $name
}

# ---------- ekrany ----------

$monIds    = Q WmiMonitorID 'root\wmi'
$monParams = Q WmiMonitorBasicDisplayParams 'root\wmi'
$monModes  = Q WmiMonitorListedSupportedSourceModes 'root\wmi'
$monConn   = Q WmiMonitorConnectionParams 'root\wmi'
$commonSizes = 10.1, 11.6, 12.5, 13.3, 13.5, 14, 14.5, 15.6, 16, 17.3, 18, 19, 21.5, 23.8, 24, 27, 31.5, 32, 34, 49
$internalScreen = ''
$externalScreens = @()
foreach ($m in $monIds) {
    $inst = $m.InstanceName
    $p    = $monParams | Where-Object { $_.InstanceName -eq $inst } | Select-Object -First 1
    $mode = $monModes  | Where-Object { $_.InstanceName -eq $inst } | Select-Object -First 1
    $conn = $monConn   | Where-Object { $_.InstanceName -eq $inst } | Select-Object -First 1
    $tech = [int64]$conn.VideoOutputTechnology
    $isInternal = $tech -eq 2147483648 -or $tech -eq 11 -or $tech -eq 13

    $parts = @()
    if ($p.MaxHorizontalImageSize -and $p.MaxVerticalImageSize) {
        $diag = [math]::Sqrt([math]::Pow($p.MaxHorizontalImageSize, 2) + [math]::Pow($p.MaxVerticalImageSize, 2)) / 2.54
        $near = $commonSizes | Sort-Object { [math]::Abs($_ - $diag) } | Select-Object -First 1
        if ([math]::Abs($near - $diag) -le 0.5) { $diag = $near }
        $parts += ('{0:0.#}"' -f $diag)
    }
    if ($mode -and $mode.MonitorSourceModes) {
        $pm = $mode.MonitorSourceModes[[int]$mode.PreferredMonitorSourceModeIndex]
        $w = $pm.HorizontalActivePixels; $h = $pm.VerticalActivePixels
        $hz = ($mode.MonitorSourceModes | Where-Object { $_.HorizontalActivePixels -eq $w -and $_.VerticalActivePixels -eq $h -and $_.VerticalRefreshRateDenominator } |
               ForEach-Object { $_.VerticalRefreshRateNumerator / $_.VerticalRefreshRateDenominator } | Measure-Object -Maximum).Maximum
        $res = "${w}x${h}"
        switch ($res) { '1920x1080' { $res += ' (Full HD)' } '2560x1440' { $res += ' (QHD)' } '3840x2160' { $res += ' (4K UHD)' } '1366x768' { $res += ' (HD)' } '1920x1200' { $res += ' (WUXGA)' } }
        $parts += $res
        if ($hz) { $parts += ('{0:0} Hz' -f [math]::Round($hz)) }
    }
    $desc = $parts -join ', '
    if ($isInternal -and $isLaptop) {
        if (-not $internalScreen) { $internalScreen = $desc }
    } else {
        $name = WStr $m.UserFriendlyName
        if ($name) { $desc = "$name – $desc" }
        $externalScreens += $desc.Trim(' ', '–')
    }
}

# ---------- dyski ----------

$busNames = @{ '17' = 'NVMe'; '11' = 'SATA'; '3' = 'ATA'; '7' = 'USB'; '8' = 'RAID'; '10' = 'SAS'; '12' = 'SD'; '13' = 'MMC'; '14' = 'Virtual'; '15' = 'File Backed Virtual'; '16' = 'Spaces'; '9' = 'iSCSI' }
$mediaNames = @{ '3' = 'HDD'; '4' = 'SSD'; '5' = 'SCM'; '0' = 'Unspecified' }
$diskItems = @()
$diskTitle = @()
$diskBytes = 0
foreach ($d in @(Get-PhysicalDisk | Sort-Object { [int]$_.DeviceId })) {
    $bus = [string]$d.BusType;   if ($busNames[$bus])   { $bus = $busNames[$bus] }
    $med = [string]$d.MediaType; if ($mediaNames[$med]) { $med = $mediaNames[$med] }
    if ($bus -match 'USB|Virtual|Spaces|iSCSI') { continue }

    if ($bus -eq 'NVMe') { $kind = 'SSD NVMe' }
    elseif ($bus -match 'MMC') { $kind = 'eMMC' }
    elseif ($med -eq 'SSD' -or ($med -ne 'HDD' -and $d.SpindleSpeed -eq 0)) { $kind = if ($bus -match 'SATA|ATA') { 'SSD SATA' } else { 'SSD' } }
    elseif ($med -eq 'HDD') { $kind = 'HDD' }
    else { $kind = 'dysk' }

    $size = SizeGB $d.Size
    $info = @()
    $hs = [string]$d.HealthStatus
    if ($hs -match '^(Healthy|0)$') { $info += 'sprawny' }
    elseif ($hs -match '^(Warning|1)$') { $info += 'OSTRZEŻENIE o stanie' }
    elseif ($hs -match '^(Unhealthy|2)$') { $info += 'USZKODZONY' }
    if ($isAdmin) {
        $rc = $d | Get-StorageReliabilityCounter
        if ($rc.PowerOnHours) { $info += ('{0:N0} h pracy' -f [double]$rc.PowerOnHours) }
        if ($null -ne $rc.Wear -and $kind -match 'SSD|eMMC') { $info += "zużycie $($rc.Wear)%" }
    }
    $dname = ((Clean $d.FriendlyName) -replace '^ATA\s+', '').TrimEnd('-', ' ')
    $line = "$kind $size – $dname"
    if ($info.Count) { $line += ' (' + ($info -join ', ') + ')' }
    $diskItems += $line
    $diskTitle += "$($kind -replace ' (NVMe|SATA)', '') $size"
    $diskBytes += [double]$d.Size
}

# ---------- bateria ----------

$battLine = ''
if ($hasBatt) {
    $xmlPath = Join-Path $env:TEMP 'specyfikacja-bateria.xml'
    & powercfg.exe /batteryreport /xml /output "$xmlPath" 2>$null | Out-Null
    if (Test-Path $xmlPath) {
        [xml]$x = Get-Content $xmlPath -Raw
        $bl = @()
        foreach ($b in @($x.BatteryReport.Batteries.Battery)) {
            $design = [double]$b.DesignCapacity; $full = [double]$b.FullChargeCapacity
            if ($design -le 0) { continue }
            $pct = [math]::Min(100, [math]::Round($full / $design * 100))
            $s = ('kondycja {0}% ({1:N0} z {2:N0} mWh pojemności fabrycznej)' -f $pct, $full, $design)
            if ([int]$b.CycleCount -gt 0) { $s += ", cykle ładowania: $([int]$b.CycleCount)" }
            $bl += $s
        }
        $battLine = $bl -join '; '
        Remove-Item $xmlPath -Force
    }
}

# ---------- lacznosc i wyposazenie ----------

$net = @()
$radio = $null
$adapters = @(Get-NetAdapter -Physical | Where-Object { $_.InterfaceDescription -notmatch 'Bluetooth|Virtual|VPN|TAP|Hyper-V|WAN Miniport|Wintun|WireGuard' })
foreach ($a in ($adapters | Where-Object { $_.MediaType -match '802\.11' -or $_.PhysicalMediaType -match '802\.11' -or $_.NdisPhysicalMedium -eq 9 })) {
    $std = ''
    if ($null -eq $radio) {
        $radio = ''
        if ((Get-Service WlanSvc).Status -eq 'Running') { $radio = (& netsh.exe wlan show drivers 2>$null) -join ' ' }
    }
    if ($radio -match '802\.11be') { $std = 'Wi-Fi 7' }
    elseif ($radio -match '802\.11ax') { $std = if ((Clean $a.InterfaceDescription) -match '6E|AX21\d|AX411|AX1675|AX1690|MT7922|RZ616|RZ608') { 'Wi-Fi 6E' } else { 'Wi-Fi 6' } }
    elseif ($radio -match '802\.11ac') { $std = 'Wi-Fi 5' }
    elseif ($radio -match '802\.11n') { $std = 'Wi-Fi 4' }
    $s = if ($std) { $std } else { 'Wi-Fi' }
    $net += "$s ($(Clean $a.InterfaceDescription))"
}
$eth = $adapters | Where-Object { $_.MediaType -eq '802.3' -and $_.PhysicalMediaType -notmatch '802\.11' -and $_.NdisPhysicalMedium -ne 9 } |
    Group-Object { (Clean $_.InterfaceDescription) -replace '\s+#\d+$', '' }
foreach ($g in $eth) { $net += $(if ($g.Count -gt 1) { "$($g.Count) × Ethernet ($($g.Name))" } else { "Ethernet ($($g.Name))" }) }
$pnp = @(Get-PnpDevice -PresentOnly)
if (@($pnp | Where-Object { $_.Class -eq 'Bluetooth' -and $_.FriendlyName -notmatch 'Enumerator|RFCOMM|LE Generic|Device Identification|Avrcp|Hands-?Free|Audio Gateway' }).Count) { $net += 'Bluetooth' }

$other = @()
$cams = @($pnp | Where-Object { $_.Class -in 'Camera', 'Image' -and $_.FriendlyName -notmatch 'Scanner|Skaner|Printer|Drukark|IR Camera|Virtual' })
if ($cams.Count) { $other += 'kamera internetowa' }
if (@($pnp | Where-Object { $_.Class -eq 'Biometric' }).Count) { $other += 'czytnik linii papilarnych / Windows Hello' }
if (@($pnp | Where-Object { $_.Class -in 'Camera', 'Image' -and $_.FriendlyName -match 'IR Camera' }).Count) { $other += 'kamera IR (logowanie twarzą)' }
if ((Q Win32_CDROMDrive).Count) { $other += 'napęd optyczny' }
if (@($pnp | Where-Object { $_.Class -eq 'SmartCardReader' }).Count) { $other += 'czytnik kart chipowych' }
if (@($pnp | Where-Object { $_.FriendlyName -match 'Card Reader|SD Host|SDXC|SD/MMC' }).Count) { $other += 'czytnik kart SD' }
if (@($pnp | Where-Object { $_.FriendlyName -match 'Thunderbolt|USB4' }).Count) { $other += 'Thunderbolt / USB4' }

# ---------- system i gotowosc na Windows 11 ----------

$os = (Q Win32_OperatingSystem)[0]
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$osName = (Clean $os.Caption) -replace '^Microsoft\s+', ''
$osLine = $osName
if ($cv.DisplayVersion) { $osLine += " $($cv.DisplayVersion)" }
if ($cv.CurrentBuild) { $osLine += " (kompilacja $($cv.CurrentBuild)" + $(if ($cv.UBR) { ".$($cv.UBR)" }) + ')' }
if ($os.OSArchitecture -match '32') { $osLine += ', 32-bit' }

$lic = (Q SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL")[0]
$licParts = @()
if ($lic) {
    if ([int]$lic.LicenseStatus -eq 1) { $licParts += 'aktywowany' } else { $licParts += 'NIEaktywowany' }
    $ch = [string]$lic.ProductKeyChannel
    if ($ch -match '^OEM') { $licParts += 'licencja OEM' }
    elseif ($ch -match 'Retail') { $licParts += 'licencja Retail / cyfrowa' }
    elseif ($ch -match 'Volume') { $licParts += 'licencja zbiorcza (firmowa)' }
}
$sls = (Q SoftwareLicensingService)[0]
if ($sls.OA3xOriginalProductKey) { $licParts += 'klucz zapisany w BIOS/UEFI' }
if ($licParts.Count) { $osLine += ', ' + ($licParts -join ', ') }

$w11 = @()
$tpmVer = ''
if ($isAdmin) {
    $tpm = (Q Win32_Tpm 'root\cimv2\Security\MicrosoftTpm')[0]
    if ($tpm.SpecVersion) { $tpmVer = ([string]$tpm.SpecVersion).Split(',')[0].Trim() }
}
if (-not $tpmVer) {
    # Bez administratora: po identyfikatorze sprzetu (nazwa urzadzenia zalezy od jezyka Windows).
    if (@($pnp | Where-Object { $_.InstanceId -match 'MSFT0101' }).Count) { $tpmVer = '2.0' }
    elseif (@($pnp | Where-Object { $_.InstanceId -match 'PNP0C31' }).Count) { $tpmVer = '1.2' }
}
if ($tpmVer) { $w11 += "TPM $tpmVer" } else { $w11 += 'brak TPM (lub wyłączony w BIOS)' }
$fw = $env:firmware_type
if ($fw -eq 'UEFI') { $w11 += 'UEFI' } elseif ($fw) { $w11 += "BIOS $fw" }
$sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State').UEFISecureBootEnabled
if ($sb -eq 1) { $w11 += 'Secure Boot włączony' } elseif ($fw -eq 'UEFI') { $w11 += 'Secure Boot wyłączony' }

# ---------- skladanie tekstu ----------

$cpuShort = $cpuName -replace '\s+with\s+.*$', ''
if ($cpus.Count -gt 1) { $cpuShort = "$($cpus.Count) × $cpuShort" }
$titleParts = @($title, $cpuShort, "$ramGB GB RAM")
if ($diskTitle.Count -gt 3) { $titleParts += ("{0} dysków, łącznie {1}" -f $diskTitle.Count, (SizeGB $diskBytes)) }
elseif ($diskTitle.Count) { $titleParts += ($diskTitle -join ' + ') }
if ($dedicated.Count) { $titleParts += (($dedicated | ForEach-Object { $_ -replace '^(NVIDIA|AMD|Intel)\s+', '' }) -join ' + ') }
if ($internalScreen) { $titleParts += (($internalScreen -split ',')[0..1] -join '') -replace '\s*\(.*?\)', '' }
$titleParts += ($osName -replace '^Windows (\d+) (Home|Pro|Enterprise|Education).*$', 'Windows $1 $2')

$rows = [System.Collections.Generic.List[object]]::new()
function Row($label, $value) { if ($value) { $rows.Add(@($label, $value)) } }
Row 'Komputer'       $computer
Row 'Procesor'       $cpuLine
Row 'Pamięć RAM'     $ramLine
Row 'Grafika'        ($gpuItems -join '; ')
Row 'Dyski'          ($diskItems -join "`n")
Row 'Ekran'          $internalScreen
Row 'Monitory'       ($externalScreens -join "`n")
Row 'Bateria'        $battLine
Row 'Łączność'       ($net -join ', ')
Row 'Wyposażenie'    ($other -join ', ')
Row 'System'         $osLine
Row 'Windows 11'     ($w11 -join ', ')
if ($boardName -and -not $computer.Contains($boardName)) { Row 'Płyta główna' $boardName }
if ($bios.SMBIOSBIOSVersion) { Row 'BIOS' ("$(Clean $bios.SMBIOSBIOSVersion)" + $(if ($bios.ReleaseDate) { ' (' + $bios.ReleaseDate.ToString('yyyy-MM-dd') + ')' })) }

$pad = 15
$sb2 = [System.Text.StringBuilder]::new()
[void]$sb2.AppendLine(($titleParts | Where-Object { $_ }) -join ' | ')
[void]$sb2.AppendLine()
[void]$sb2.AppendLine('SPECYFIKACJA')
foreach ($r in $rows) {
    $lines = ([string]$r[1]) -split "`n"
    $first = ('{0,-' + $pad + '}{1}') -f ($r[0] + ':'), $lines[0]
    [void]$sb2.AppendLine($first)
    foreach ($l in $lines[1..($lines.Count)]) { if ($l) { [void]$sb2.AppendLine((' ' * $pad) + $l) } }
}
[void]$sb2.AppendLine()
[void]$sb2.Append('Dane odczytane automatycznie z komputera, ' + (Get-Date -Format 'yyyy-MM-dd') + '.')
$text = $sb2.ToString()

# ---------- wynik ----------

$out = Join-Path $Desktop 'Specyfikacja komputera.txt'
try { [IO.File]::WriteAllText($out, $text, [Text.UTF8Encoding]::new($true)) } catch {
    $out = Join-Path $env:TEMP 'Specyfikacja komputera.txt'
    [IO.File]::WriteAllText($out, $text, [Text.UTF8Encoding]::new($true))
}
Set-Clipboard -Value $text

Write-Host ''
Write-Host $text
Write-Host ''
Write-Host "Gotowe. Tekst jest w schowku (Ctrl+V) i w pliku: $out" -ForegroundColor Green
if (-not $isAdmin) { Write-Host 'Bez uprawnień administratora - brak godzin pracy / zużycia dysków.' -ForegroundColor Yellow }

if (-not $env:SPEC_NO_NOTEPAD) { Start-Process notepad.exe -ArgumentList "`"$out`"" }
