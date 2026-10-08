<#
.SYNOPSIS
  Take a restorable snapshot of the settings that system "optimization" scripts commonly
  change, so that damage can be diagnosed and undone afterwards.

.DESCRIPTION
  The single most useful thing an optimizer can do before touching anything is write down
  the current state. Without a baseline you cannot tell what the optimizer changed, and
  you cannot prove that a setting was already like that.

  This script captures, into one directory:
    - services            (Name, StartMode, State)       -> CSV
    - startup / Run keys  (per-hive)                     -> .reg
    - scheduled tasks     (name, state)                  -> CSV
    - power plan and a few notable registry policies     -> text

  Nothing is modified. Run it BEFORE optimizing, keep the output, and use
  compare-services.ps1 to diff against it later.

.PARAMETER OutDir
  Where to write the snapshot. Default: .\tweak-baseline-<timestamp> next to the current
  directory. A fixed name makes it easy to reference later.

.EXAMPLE
  pwsh -File snapshot-services.ps1
  pwsh -File snapshot-services.ps1 -OutDir C:\backup\before-tweak

.NOTES
  ASCII-only on purpose.
#>
[CmdletBinding()]
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Continue'
if (-not $OutDir) { $OutDir = Join-Path (Get-Location) 'tweak-baseline' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Ok { param([string]$M) Write-Output "    ok      $M" }
function Warn { param([string]$M) Write-Output "    WARN    $M" }

Write-Output '===== snapshot-services ====='
Write-Output "    writing to: $OutDir"

# ------------------------------------------------------------------- services
# StartMode from CIM uses the Auto / Manual / Disabled vocabulary, which is what a
# compare later needs. Get-Service would give a different spelling (Automatic).
$svcPath = Join-Path $OutDir 'services-snapshot.csv'
try {
    Get-CimInstance Win32_Service |
        Select-Object Name, StartMode, State |
        Sort-Object Name |
        Export-Csv -Path $svcPath -NoTypeInformation -Encoding UTF8
    $n = @(Import-Csv $svcPath).Count
    Ok "services: $n rows -> services-snapshot.csv"
} catch { Warn "could not snapshot services: $($_.Exception.Message.Split("`n")[0])" }

# -------------------------------------------------------------- startup entries
# Autostart keys are a favourite target: removing an entry there silently disables a
# component without disabling its service.
$runKeys = @{
    'Run-HKCU'        = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'
    'RunOnce-HKCU'    = 'HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    'Run-HKLM'        = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Run'
    'RunOnce-HKLM'    = 'HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    'Run-Wow6432'     = 'HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
}
foreach ($k in $runKeys.Keys) {
    $file = Join-Path $OutDir "$k.reg"
    & reg export $runKeys[$k] $file /y 2>&1 | Out-Null
    if (Test-Path $file) { Ok "$($runKeys[$k]) -> $k.reg" }
    else { Write-Output "    note    $($runKeys[$k]) absent or empty" }
}

# -------------------------------------------------------------- scheduled tasks
$taskPath = Join-Path $OutDir 'tasks-snapshot.csv'
try {
    Get-ScheduledTask -ErrorAction Stop |
        Select-Object TaskPath, TaskName, State |
        Sort-Object TaskPath, TaskName |
        Export-Csv -Path $taskPath -NoTypeInformation -Encoding UTF8
    $n = @(Import-Csv $taskPath).Count
    Ok "scheduled tasks: $n rows -> tasks-snapshot.csv"
} catch { Warn "could not snapshot tasks: $($_.Exception.Message.Split("`n")[0])" }

# ------------------------------------------------------------------ power plan
$miscPath = Join-Path $OutDir 'misc-state.txt'
$lines = @()
$lines += "snapshot taken: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += "user: $env:USERDOMAIN\$env:USERNAME"
$lines += ''
try {
    $lines += '--- active power plan ---'
    $lines += (& powercfg /getactivescheme 2>&1)
} catch {}
try {
    $lines += ''
    $lines += '--- visual effects (VisualFXSetting: 1=best appearance 2=best performance 3=custom) ---'
    $v = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -ErrorAction SilentlyContinue
    $lines += "VisualFXSetting = $($v.VisualFXSetting)"
} catch {}
try {
    $lines += ''
    $lines += '--- input method (IME) ---'
    $lines += (& sc.exe qc TabletInputService 2>&1 | Select-String 'START_TYPE')
    $lines += (& sc.exe query TabletInputService 2>&1 | Select-String 'STATE')
    # The IME language bar lives behind this service on Windows 10; a snapshot of it makes
    # an "input method vanished" regression provable.
    $ctf = Get-Process ctfmon -ErrorAction SilentlyContinue
    $lines += "ctfmon running = $([bool]$ctf)"
} catch {}
try {
    $lines += ''
    $lines += '--- background apps policy (LetAppsRunInBackground) ---'
    $p = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -ErrorAction SilentlyContinue
    $lines += "LetAppsRunInBackground = $($p.LetAppsRunInBackground)"
} catch {}
$lines | Set-Content -Path $miscPath -Encoding UTF8
Ok "power plan / visual effects / IME / background apps -> misc-state.txt"

Write-Output "`n===== done ====="
Write-Output "Keep this directory. To see what an optimizer changed:"
Write-Output "  pwsh -File compare-services.ps1 -Snapshot `"$svcPath`""
