<#
.SYNOPSIS
  Diagnose a missing Windows input method (IME), and repair the specific cause that a
  system optimizer usually introduces.

.DESCRIPTION
  Symptom this targets: after an "optimization" and a reboot, typing no longer produces
  Chinese; Win+Space does nothing; the language indicator is gone from the taskbar; and
  ctfmon.exe exits immediately.

  Root cause more often than not is that TabletInputService was set to Disabled. Its
  display name is "Touch Keyboard and Handwriting Panel Service", which makes it look
  safe to disable on a machine without a touchscreen - but on Windows 10 it also hosts
  the input-method language bar and the input indicator. Disable it and the IME stack
  cannot come up.

  The script:
    1. reports the facts (service start type and state, ctfmon, TextInputHost, language
       registration, language-bar mode, background-apps policy, IFEO hijack keys)
    2. names the most likely cause rather than dumping everything
    3. with -Repair and elevation, restores the service via `sc config` + `sc start`

  Why `sc config` and not a registry edit: measured on Windows 10, writing the service's
  Start value in the registry alone did NOT take effect - the Service Control Manager
  keeps its own cached copy of the start type, so the change must be announced with
  `sc config` (ChangeServiceConfig) and then started with `sc start`.

.PARAMETER Repair
  Attempt the repair. Requires an elevated shell.

.EXAMPLE
  pwsh -File diagnose-ime.ps1
  pwsh -File diagnose-ime.ps1 -Repair

.NOTES
  ASCII-only on purpose.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Repair,
    [int]$TargetStartType = 3   # 3 = Manual (DEMAND_START), matching a stock Windows 10 install
)

$ErrorActionPreference = 'Continue'
$Cmdlet = $PSCmdlet

function Head { param([string]$M) Write-Output "`n--- $M" }
function Info { param([string]$M) Write-Output "    $M" }
function Ok   { param([string]$M) Write-Output "    ok      $M" }
function Warn { param([string]$M) Write-Output "    WARN    $M" }
function Bad  { param([string]$M) Write-Output "    FAIL    $M" }

$startNames = @{ 0='Boot'; 1='System'; 2='Auto'; 3='Manual'; 4='Disabled' }

Write-Output '===== diagnose-ime ====='

$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {}
Info "elevated: $isAdmin"

# ------------------------------------------------------- 1. the service itself
Head '1. TabletInputService (the usual culprit)'
# Read via CIM rather than parsing `sc qc` text: the state comes back as typed properties,
# and it is the same source the snapshot uses, so comparisons stay consistent.
$svc = Get-CimInstance Win32_Service -Filter "Name='TabletInputService'" -ErrorAction SilentlyContinue
$startLabel = 'unknown'; $stateLabel = 'unknown'; $badService = $false
if ($svc) {
    $startLabel = "$($svc.StartMode)"
    $stateLabel = "$($svc.State)"
    Info "start mode = $startLabel"
    Info "state      = $stateLabel"
    # CIM reports Boot/System/Auto/Manual/Disabled; only 'Disabled' is the failure mode
    $badService = ($startLabel -eq 'Disabled')
} else {
    Bad 'TabletInputService not found - the service is missing entirely, not merely stopped'
}

if ($badService) {
    Bad 'TabletInputService is DISABLED - this alone explains a vanished IME'
    Write-Output '         On Windows 10 this service also hosts the input-method language bar'
    Write-Output '         and the input indicator, not just the touch keyboard.'
} elseif ($startLabel -eq 'Manual' -or $startLabel -eq 'Auto') {
    Ok "start mode looks normal ($startLabel)"
} else {
    Warn "unexpected start mode: $startLabel"
}

# ------------------------------------------------------- 2. the IME processes
Head '2. input-method processes'
$ctfmon = Get-Process ctfmon -ErrorAction SilentlyContinue
$tih    = Get-Process TextInputHost -ErrorAction SilentlyContinue
if ($ctfmon) { Ok "ctfmon running (pid $($ctfmon.Id), started $($ctfmon.StartTime))" }
else { Bad 'ctfmon is NOT running' }
if ($tih) { Ok "TextInputHost running (pid $($tih.Id))" }
else { Warn 'TextInputHost is not running (may be normal before first input)' }

if (-not $ctfmon) {
    # ctfmon failing to start is a strong signal; capture the reason instead of guessing.
    Info 'attempting to start ctfmon to capture its exit code...'
    try {
        $p = Start-Process "$env:SystemRoot\System32\ctfmon.exe" -PassThru -WindowStyle Hidden -ErrorAction Stop
        Start-Sleep -Seconds 3
        if ($p.HasExited) {
            Bad "ctfmon exited immediately with code $($p.ExitCode)"
            if ($p.ExitCode -eq 1) {
                Write-Output '         exit code 1 with TabletInputService disabled is the expected signature'
                Write-Output '         of this failure - fix the service, not ctfmon.'
            }
        } else {
            Ok "ctfmon started and stayed alive (pid $($p.Id))"
        }
    } catch { Warn "could not launch ctfmon: $($_.Exception.Message.Split("`n")[0])" }
}

# ------------------------------------------------------- 3. registration
Head '3. language and input-method registration'
# Get-WinUserLanguageList cannot be marshalled from PowerShell 7 (WinRT type), so read the
# same facts from the registry. Measured layout on Windows 10:
#   HKCU\Control Panel\International\User Profile\Languages  = "zh-Hans-CN en-US"  (one value)
#   HKCU\Keyboard Layout\Preload                             = 00000409, 00000804
#     (00000804 = Chinese Simplified - US Keyboard)
#   User Profile\InputMethodOverride                         = 0804:{...}{...}
#     (the CLSID pair selects which IME serves that language)
$langsFound = $false
try {
    $up = Get-ItemProperty 'HKCU:\Control Panel\International\User Profile' -ErrorAction Stop
    if ($up.Languages) {
        Info "languages: $($up.Languages)"
        $langsFound = $true
    }
} catch {}
if (-not $langsFound) { Warn 'no language list in HKCU\Control Panel\International\User Profile' }

# Keyboard layouts actually preloaded for the user
try {
    $pre = Get-ItemProperty 'HKCU:\Keyboard Layout\Preload' -ErrorAction Stop
    $ids = @($pre.PSObject.Properties | Where-Object { $_.Name -match '^\d+$' } |
             Sort-Object { [int]$_.Name } | ForEach-Object { "$($_.Value)" })
    if ($ids.Count -gt 0) {
        Info "preloaded keyboard layouts: $($ids -join ', ')"
        if ($ids -match '00000804') { Ok 'Chinese (Simplified) layout 00000804 is preloaded' }
        else { Warn 'Chinese (Simplified) layout 00000804 is NOT preloaded' }
    } else { Warn 'no preloaded keyboard layouts' }
} catch { Warn 'could not read HKCU\Keyboard Layout\Preload' }

# Which IME is selected for the language
try {
    $ovr = (Get-ItemProperty 'HKCU:\Control Panel\International\User Profile' -ErrorAction Stop).InputMethodOverride
    if ($ovr) {
        Info "InputMethodOverride: $ovr"
        # 81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E is the Microsoft Pinyin IME class id
        if ($ovr -match '81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E') { Ok 'Microsoft Pinyin is the selected IME' }
        else { Warn 'a different IME is selected for this language' }
    }
} catch {}

$chs = Join-Path $env:SystemRoot 'System32\InputMethod\CHS'
if (Test-Path $chs) {
    $n = @(Get-ChildItem $chs -File -ErrorAction SilentlyContinue).Count
    Ok "Microsoft Pinyin files present in System32\InputMethod\CHS ($n files)"
} else { Bad 'System32\InputMethod\CHS is missing - the IME files may be damaged' }

# ------------------------------------------------------- 4. language bar mode
Head '4. language bar mode'
# An old-style language bar with Win+Space disabled is a separate, user-level problem that
# mimics a broken IME.
$ctf = 'HKCU:\Software\Microsoft\CTF'
$show = (Get-ItemProperty $ctf -Name 'ShowStatus' -ErrorAction SilentlyContinue).ShowStatus
if ($null -ne $show) {
    Info "CTF\ShowStatus = $show  (3 = docked in the taskbar, 4 = floating, 0 = hidden)"
} else {
    Info 'CTF\ShowStatus not set (defaults apply - the language bar follows the modern mode)'
}
$lb = 'HKCU:\Software\Microsoft\CTF\LangBar'
$lbv = Get-ItemProperty $lb -ErrorAction SilentlyContinue
if ($lbv) {
    $props = @($lbv.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })
    if ($props.Count -gt 0) {
        foreach ($p in $props) { Info "LangBar\$($p.Name) = $($p.Value)" }
    } else { Ok 'LangBar key exists but is empty (modern mode)' }
} else { Ok 'no LangBar override (modern language bar mode)' }
$tip = (Get-ItemProperty $ctf -Name 'DisableThreadInputManager' -ErrorAction SilentlyContinue).DisableThreadInputManager
if ($tip -eq 1) { Warn 'DisableThreadInputManager = 1 : this suppresses input-method UI' }
else { Ok 'DisableThreadInputManager not set' }

# ------------------------------------------------------- 5. known confounders
Head '5. known confounders (checked so you can rule them out)'
$ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\ctfmon.exe'
if (Test-Path $ifeo) { Bad "IFEO hijack key exists for ctfmon.exe - inspect: $ifeo" }
else { Ok 'no IFEO hijack for ctfmon.exe' }

$priv = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -ErrorAction SilentlyContinue
if ($priv.LetAppsRunInBackground -eq 2) {
    Warn 'LetAppsRunInBackground = 2 (force-deny): can suppress Store-style components'
} else { Ok "LetAppsRunInBackground = $($priv.LetAppsRunInBackground) (not force-deny)" }

# security software is a frequent cause of a blocked process launch
$av = @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'HipsTray|HipsDaemon|wsctrl|usysdiag|360|QQPCTray|ZhuDongFangYu' })
if ($av) { Warn ("security software running (may intercept process launch): " + (($av | Select-Object -ExpandProperty Name -Unique) -join ', ')) }
else { Ok 'no known security-software process detected' }

# ------------------------------------------------------- 6. verdict
Head '6. verdict'
if ($badService) {
    Write-Output '    Most likely cause: TabletInputService was disabled.'
    Write-Output '    Fix it with -Repair (elevated), then REBOOT. A broken input stack does not'
    Write-Output '    always recover inside the same session - ctfmon may refuse to come up until'
    Write-Output '    the next sign-in rebuilds it.'
} elseif (-not $ctfmon) {
    Write-Output '    The service state looks fine but ctfmon is not running. Try a reboot first;'
    Write-Output '    if it persists, check the security software and reinstall the IME:'
    Write-Output '      Settings -> Time and language -> Language -> Chinese (Simplified) ->'
    Write-Output '      Options -> add the Microsoft Pinyin keyboard.'
} else {
    Write-Output '    The IME stack looks healthy.'
}

# ------------------------------------------------------- 7. repair
if ($Repair) {
    Head '7. repair'
    if (-not $isAdmin) {
        Bad '-Repair requires an elevated shell'
        Write-Output '         Right-click your terminal -> Run as administrator, then re-run.'
        exit 1
    }
    if (-not $badService) {
        Ok 'TabletInputService is not disabled - nothing to repair here'
    } else {
        if ($Cmdlet.ShouldProcess('TabletInputService', "set start type to $($startNames[$TargetStartType]) and start it")) {
            # sc.exe talks to the Service Control Manager, which owns the authoritative
            # start type. A registry-only edit was measured NOT to take effect.
            $out1 = & sc.exe config TabletInputService start= demand 2>&1
            if ($LASTEXITCODE -eq 0) { Ok 'sc config TabletInputService start= demand' }
            else { Bad "sc config failed: $($out1 -join ' ')" }

            $out2 = & sc.exe start TabletInputService 2>&1
            if ($LASTEXITCODE -eq 0) { Ok 'sc start TabletInputService' }
            else { Warn "sc start returned $LASTEXITCODE (it may already be starting)" }

            Start-Sleep -Seconds 2
            $q3 = & sc.exe query TabletInputService 2>&1
            if ($q3 -match 'RUNNING') { Ok 'service is RUNNING' } else { Warn 'service is not running yet' }
        }
    }
    Write-Output ''
    Write-Output '    Now REBOOT, then verify:'
    Write-Output '      sc query TabletInputService     -> RUNNING'
    Write-Output '      sc qc TabletInputService        -> START_TYPE : 3  DEMAND_START'
    Write-Output '      Win+Space should show the input switcher'
}

Write-Output "`n===== done ====="
if (-not $Repair) { Write-Output 'Report only. Use -Repair (elevated) if the verdict above names the service.' }
