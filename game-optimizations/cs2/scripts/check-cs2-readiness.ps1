<#
.SYNOPSIS
  Read-only readiness check for Counter-Strike 2 on this machine.

.DESCRIPTION
  Answers one question: "what is the actual bottleneck for CS2 here, and what should the
  video settings be?" It changes nothing - every check is a read.

  The order matters. Refresh rate and GPU class decide the target frame rate, and the
  iGPU memory-channel count can halve performance on its own, so those are measured before
  any settings advice is printed.

  Why ASCII-only: Windows PowerShell 5.1 decodes a BOM-less file as ANSI, so any multi-byte
  character breaks parsing and the script dies at startup with exit code 0x1.

.PARAMETER SteamPath
  Steam install root. Auto-detected from the registry when omitted.

.PARAMETER Json
  Emit a single JSON object instead of the human-readable report.

.EXAMPLE
  pwsh -File check-cs2-readiness.ps1

.EXAMPLE
  pwsh -File check-cs2-readiness.ps1 -Json

.NOTES
  ASCII-only on purpose. Read-only: safe to run at any time.
#>
[CmdletBinding()]
param(
    [string]$SteamPath,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'

function Write-Head { param([string]$Text) if (-not $Json) { Write-Output ""; Write-Output "===== $Text =====" } }
function Write-Row  { param([string]$Label, $Value) if (-not $Json) { Write-Output ("  {0,-26} {1}" -f $Label, $Value) } }
function Write-Note { param([string]$Text) if (-not $Json) { Write-Output "      $Text" } }

$report = [ordered]@{}
$warnings = New-Object System.Collections.Generic.List[string]

# ------------------------------------------------------------------ CPU / RAM
Write-Head 'CPU and memory'
$cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
$cpuName = if ($cpu) { $cpu.Name.Trim() } else { 'unknown' }
$cores = if ($cpu) { $cpu.NumberOfCores } else { 0 }
$threads = if ($cpu) { $cpu.NumberOfLogicalProcessors } else { 0 }
Write-Row 'CPU' $cpuName
Write-Row 'Cores / threads' ("{0}C / {1}T" -f $cores, $threads)

$mem = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
$memTotalGB = 0
$memSpeed = 0
$channels = 0
if ($mem.Count -gt 0) {
    $memTotalGB = [math]::Round((($mem | Measure-Object -Property Capacity -Sum).Sum) / 1GB, 1)
    $memSpeed = ($mem | Select-Object -First 1).ConfiguredClockSpeed
    $channels = @($mem | ForEach-Object { $_.BankLabel } | Sort-Object -Unique).Count
}
$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$memUsableGB = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { 0 }
Write-Row 'Memory modules' ("{0} x {1} GB @ {2} MT/s" -f $mem.Count, $(if ($mem.Count -gt 0) { [math]::Round($mem[0].Capacity / 1GB, 0) } else { 0 }), $memSpeed)
Write-Row 'Memory channels' $channels
Write-Row 'Usable memory' ("$memUsableGB GB")

# ------------------------------------------------------------------ GPU
Write-Head 'Graphics'
$vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
$gpuName = if ($vc) { $vc.Name } else { 'unknown' }
$vramMB = if ($vc) { [math]::Round($vc.AdapterRAM / 1MB, 0) } else { 0 }
Write-Row 'GPU' $gpuName
Write-Row 'Dedicated VRAM' ("$vramMB MB")
Write-Row 'Driver version' $(if ($vc) { $vc.DriverVersion } else { '' })
Write-Row 'Driver date' $(if ($vc -and $vc.DriverDate) { ([datetime]$vc.DriverDate).ToString('yyyy-MM-dd') } else { '' })

# Heuristic: these name patterns are integrated GPUs. A wrong guess only changes the
# wording of the advice, never a system setting, so it is safe to be approximate here.
$isIntegrated = $false
if ($gpuName -match '(?i)Radeon.*(Graphics|Vega|6[0-9]M|7[0-9]M|8[0-9]M|Graphics)|Intel.*(UHD|Iris|HD Graphics)|Microsoft Basic') {
    $isIntegrated = $true
}
Write-Row 'GPU class' $(if ($isIntegrated) { 'integrated (uses system RAM)' } else { 'discrete' })

if ($isIntegrated -and $channels -lt 2) {
    $warnings.Add('Integrated GPU with a SINGLE memory channel: expect roughly half the usual frame rate. Filling the second channel matters more than any game setting.')
}

# ------------------------------------------------------------------ display
Write-Head 'Display'
$hres = if ($vc) { $vc.CurrentHorizontalResolution } else { 0 }
$vres = if ($vc) { $vc.CurrentVerticalResolution } else { 0 }
$hz = if ($vc) { $vc.CurrentRefreshRate } else { 0 }
Write-Row 'Desktop resolution' ("{0}x{1}" -f $hres, $vres)
Write-Row 'Refresh rate' ("$hz Hz")
try {
    $mon = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop)
    foreach ($m in $mon) {
        $n = ($m.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ''
        if ($n) { Write-Row 'Monitor' $n }
    }
} catch { }

$maxHz = 0
try {
    $modes = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedSourceModes -ErrorAction Stop)
    foreach ($mm in $modes) {
        foreach ($sm in $mm.MonitorSourceModes) {
            $r = [int]($sm.VerticalRefreshRateNumerator / 1000)
            if ($r -gt $maxHz -and $r -le 500) { $maxHz = $r }
        }
    }
} catch { }
if ($maxHz -gt 0) { Write-Row 'Highest listed mode' ("$maxHz Hz") }

# ------------------------------------------------------------------ Steam / CS2
Write-Head 'Steam and CS2 install'
if (-not $SteamPath) {
    $regs = @(
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam',
        'HKCU:\Software\Valve\Steam'
    )
    foreach ($k in $regs) {
        if (Test-Path $k) {
            $p = (Get-ItemProperty $k -ErrorAction SilentlyContinue).InstallPath
            if (-not $p) { $p = (Get-ItemProperty $k -ErrorAction SilentlyContinue).SteamPath }
            if ($p -and (Test-Path $p)) { $SteamPath = $p; break }
        }
    }
    if (-not $SteamPath) {
        foreach ($guess in @('C:\Program Files (x86)\Steam', 'C:\Program Files\Steam')) {
            if (Test-Path $guess) { $SteamPath = $guess; break }
        }
    }
}
Write-Row 'Steam path' $(if ($SteamPath) { $SteamPath } else { 'NOT FOUND' })
if (-not $SteamPath) { $warnings.Add('Steam not found. Pass -SteamPath or install Steam first.') }

$acf = if ($SteamPath) { Join-Path $SteamPath 'steamapps\appmanifest_730.acf' } else { '' }
$installed = $false
$stateFlags = 0
$sizeGB = 0
$buildId = ''
if ($acf -and (Test-Path $acf)) {
    $txt = Get-Content $acf -Raw -ErrorAction SilentlyContinue
    if ($txt -match '"StateFlags"\s+"(\d+)"') { $stateFlags = [int]$Matches[1] }
    if ($txt -match '"SizeOnDisk"\s+"(\d+)"') { $sizeGB = [math]::Round([int64]$Matches[1] / 1GB, 2) }
    if ($txt -match '"buildid"\s+"(\d+)"') { $buildId = $Matches[1] }
    $installed = ($stateFlags -eq 4)
}
Write-Row 'CS2 installed' $installed
Write-Row 'SizeOnDisk' ("$sizeGB GB")
Write-Row 'buildid' $buildId
if ($acf -and -not (Test-Path $acf)) { $warnings.Add('appmanifest_730.acf not found: CS2 is not installed in this library.') }
if ($stateFlags -ne 0 -and $stateFlags -ne 4) { $warnings.Add("StateFlags is ${stateFlags}, not 4: the install is not complete (4 = fully installed).") }

$gameRoot = if ($SteamPath) { Join-Path $SteamPath 'steamapps\common\Counter-Strike Global Offensive' } else { '' }
$exePath = if ($gameRoot) { Join-Path $gameRoot 'game\bin\win64\cs2.exe' } else { '' }
$exeExists = ($exePath -and (Test-Path $exePath))
Write-Row 'cs2.exe' $(if ($exeExists) { 'present' } else { 'MISSING' })

# The video config only exists after the game has been launched at least once. Its absence
# is the best evidence that the FIRST launch is still pending - and that first launch would
# otherwise pick the desktop resolution, which is the single most common reason an iGPU
# sees 20 FPS on the first run.
$videoCfg = if ($gameRoot) { Join-Path $gameRoot 'game\csgo\cfg\cs2_video.txt' } else { '' }
$everLaunched = ($videoCfg -and (Test-Path $videoCfg))
Write-Row 'Launched before' $everLaunched
if ($exeExists -and -not $everLaunched) {
    $warnings.Add('CS2 has never been launched: the first run will use the DESKTOP resolution. Set 1920x1080 (or enable FSR) in Video settings before playing.')
}

# ------------------------------------------------------------------ current tweaks
Write-Head 'Current tuning state'
$activeScheme = (& powercfg /getactivescheme 2>&1) -join ' '
$activeGuid = if ($activeScheme -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { $Matches[1] } else { '' }
Write-Row 'Active power scheme' $activeScheme.Trim()

$minAc = ''
$maxAc = ''
# powercfg output is localized: English prints "Current AC Power Setting Index", Chinese
# prints the same idea with different characters. Matching only 'AC' silently falls back to
# the FIRST 0x line, which is "minimum possible setting" (= 0) - a wrong reading that looks
# like a real value. Match both, using \u escapes so the file stays pure ASCII.
$acPattern = '(?i)AC|\u4ea4\u6d41'
if ($activeGuid) {
    $q = & powercfg /query $activeGuid SUB_PROCESSOR 893dee8e-2bef-41e0-89c6-b55d0929964c 2>&1
    $line = @($q | Where-Object { $_ -match '0x[0-9a-fA-F]+' -and $_ -match $acPattern }) | Select-Object -First 1
    if ($line -and $line -match '0x([0-9a-fA-F]+)') { $minAc = [Convert]::ToInt32($Matches[1], 16) }
    $q2 = & powercfg /query $activeGuid SUB_PROCESSOR bc5038f7-23e0-4960-96da-33abaf5935ec 2>&1
    $line2 = @($q2 | Where-Object { $_ -match '0x[0-9a-fA-F]+' -and $_ -match $acPattern }) | Select-Object -First 1
    if ($line2 -and $line2 -match '0x([0-9a-fA-F]+)') { $maxAc = [Convert]::ToInt32($Matches[1], 16) }
}
Write-Row 'Min processor state (AC)' $(if ($minAc -ne '') { "$minAc %" } else { 'unreadable' })
Write-Row 'Max processor state (AC)' $(if ($maxAc -ne '') { "$maxAc %" } else { 'unreadable' })
if ($minAc -ne '' -and $minAc -lt 30) {
    $warnings.Add("Min processor state is $minAc %: clocks may take a moment to ramp up. 50-80 is usually smoother for a first-shot-latency complaint.")
}

$layersKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$layerValue = ''
if ($exePath -and (Test-Path $layersKey)) {
    $props = Get-ItemProperty $layersKey -ErrorAction SilentlyContinue
    if ($props -and $props.PSObject.Properties.Name -contains $exePath) { $layerValue = "$($props.$exePath)" }
}
Write-Row 'Fullscreen optimizations off' $(if ($layerValue -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE') { 'yes' } else { 'no' })

$gdvrPolicy = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name AllowGameDVR -ErrorAction SilentlyContinue).AllowGameDVR
$gdvrUser = (Get-ItemProperty 'HKCU:\System\GameConfigStore' -Name GameDVR_Enabled -ErrorAction SilentlyContinue).GameDVR_Enabled
$gameMode = (Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name AllowAutoGameMode -ErrorAction SilentlyContinue).AllowAutoGameMode
Write-Row 'GameDVR (policy / user)' ("{0} / {1}" -f $gdvrPolicy, $gdvrUser)
Write-Row 'Game Mode' $gameMode

$autoexec = if ($gameRoot) { Join-Path $gameRoot 'game\csgo\cfg\autoexec.cfg' } else { '' }
Write-Row 'autoexec.cfg' $(if ($autoexec -and (Test-Path $autoexec)) { 'present' } else { 'absent' })

# ------------------------------------------------------------------ hardware faults
Write-Head 'Hardware fault evidence (last 30 days)'
$since = (Get-Date).AddDays(-30)
$whea = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$since} -ErrorAction SilentlyContinue)
$tdr = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101,4102; StartTime=$since} -ErrorAction SilentlyContinue)
$dumps = @(Get-ChildItem 'C:\Windows\Minidump\*.dmp' -ErrorAction SilentlyContinue)
Write-Row 'WHEA errors' $whea.Count
Write-Row 'GPU TDR events' $tdr.Count
Write-Row 'Crash dumps' $dumps.Count

# ------------------------------------------------------------------ verdict
$targetRes = '1920x1080'
$targetHz = if ($maxHz -gt 0) { $maxHz } else { $hz }
if ($isIntegrated -and $hres -ge 3840) {
    $targetRes = '1920x1080 (desktop is 4K - do NOT play at native resolution)'
}
$fpsExpect = if ($isIntegrated) { '60-100 (1080p low + FSR)' } else { 'display-limited' }

Write-Head 'Verdict'
Write-Row 'Target resolution' $targetRes
Write-Row 'Target refresh' ("$targetHz Hz")
Write-Row 'Expected frames' $fpsExpect

if ($warnings.Count -gt 0) {
    if ($Json) { } else { Write-Output ''; Write-Output '  Attention:' }
    foreach ($w in $warnings) { if (-not $Json) { Write-Output "    - $w" } }
} else {
    if (-not $Json) { Write-Output ''; Write-Output '  No blocking issues found.' }
}

$report = [ordered]@{
    Cpu            = $cpuName
    Cores          = $cores
    Threads        = $threads
    MemoryGB       = $memUsableGB
    MemoryChannels = $channels
    MemorySpeed    = $memSpeed
    Gpu            = $gpuName
    GpuIntegrated  = $isIntegrated
    VramMB         = $vramMB
    GpuDriver      = $(if ($vc) { $vc.DriverVersion } else { '' })
    DesktopWidth   = $hres
    DesktopHeight  = $vres
    RefreshHz      = $hz
    MaxListedHz    = $maxHz
    SteamPath      = $SteamPath
    Cs2Installed   = $installed
    Cs2SizeGB      = $sizeGB
    Cs2BuildId     = $buildId
    Cs2ExePath     = $exePath
    EverLaunched   = $everLaunched
    PowerScheme    = $activeScheme.Trim()
    MinProcessorAc = $minAc
    MaxProcessorAc = $maxAc
    FullscreenOptOff = [bool]($layerValue -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE')
    GameDvrPolicy  = $gdvrPolicy
    GameDvrUser    = $gdvrUser
    GameMode       = $gameMode
    Autoexec       = [bool]($autoexec -and (Test-Path $autoexec))
    Whea30d        = $whea.Count
    Tdr30d         = $tdr.Count
    CrashDumps     = $dumps.Count
    TargetResolution = $targetRes
    Warnings       = @($warnings)
}

if ($Json) {
    Write-Output ($report | ConvertTo-Json -Depth 4)
}
else {
    Write-Output ''
    Write-Output 'Read-only check: nothing was changed.'
    Write-Output 'To apply the system-level tweaks, run apply-cs2-optimizations.ps1 -WhatIf first.'
}

exit 0
