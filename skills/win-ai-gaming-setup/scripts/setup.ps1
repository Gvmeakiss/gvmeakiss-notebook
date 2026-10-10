<#
.SYNOPSIS
  One entry point that turns a fresh Windows box into an AI-development + gaming machine.

.DESCRIPTION
  Everything in this skill hangs off this script. Phases run in order:

    check    prerequisites AND bootstrap: PowerShell 7, Scoop, git, 7-Zip, long paths,
             developer mode, network, disk, elevation
    dev      dev toolchain via Scoop (python/node/go/rust/cmake/dotnet/mingw/uv) with
             domestic mirrors (pip/npm/go/cargo), VS Code + Windows Terminal,
             AI cache mirror (HuggingFace), PATH / Store-stub repair
    apps     portable apps from apps.json (SHA256 verified, no elevation needed)
    tune     snapshot first, then: gaming tweaks (GameDVR off, MMCSS) and the
             turn-off-useless-stuff list (ads/recommendations, Bing in Start, telemetry).
             Never disables a service, never touches UAC.
    link     file associations: register the apps, report what still needs one manual click
    verify   acceptance: dev env, apps present, input method healthy, baseline drift

  Design rules, learned the hard way (see SKILL.md):
    * never disable a service here - demand-start services cost nothing and break things
    * take a snapshot before touching the system, so "changed" and "was always like that" differ
    * after any service/tweak change, reboot before believing the result
    * a command returning success is not evidence; read the state back

.PARAMETER Phase
  check | dev | apps | drivers | tune | link | verify | all      (default: all)

.PARAMETER Manifest
  Portable app manifest. Default: apps.json in the skill root.

.PARAMETER Destination
  Portable app root. Default: $env:USERPROFILE\Apps

.PARAMETER SnapshotDir
  Where the pre-tweak snapshot goes. Default: <Destination>\_backup

.PARAMETER Languages
  Scoop packages for the dev phase. Default: python,node,go,cmake,dotnet,mingw,uv

.PARAMETER NoEditor
  Skip VS Code + Windows Terminal in the dev phase.

.PARAMETER HighPerformancePowerPlan
  Optional, off by default: switch the active power plan to High performance.
  Left off because it costs battery life on a laptop.

.PARAMETER DisableMouseAcceleration
  Optional, off by default: zero the Windows mouse acceleration curve (a gaming preference,
  not a universal win).

.PARAMETER RegisterAssociations
  In the link phase, actually write the HKCU association entries (user-level only).

.PARAMETER SkipTweaks
  Take the snapshot but apply no tweaks.

.PARAMETER Help
  Show this help.

.EXAMPLE
  pwsh -File scripts/setup.ps1                      # everything, in order
  pwsh -File scripts/setup.ps1 -Phase check         # prerequisites + bootstrap report
  pwsh -File scripts/setup.ps1 -Phase dev,apps      # toolchain + portable apps
  pwsh -File scripts/setup.ps1 -Phase tune -WhatIf  # preview every registry change
  pwsh -File scripts/setup.ps1 -Phase verify

.NOTES
  ASCII-only on purpose. Runs on Windows PowerShell 5.1 or PowerShell 7; child scripts are
  invoked with pwsh when available and fall back to powershell.exe.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # No ValidateSet here on purpose: invoked with -File, "dev,tune" arrives as ONE string
    # (only -Command splits comma lists). The body splits and validates instead.
    [string[]]$Phase = @('all'),
    [string]$Manifest,
    [string]$Destination = (Join-Path $env:USERPROFILE 'Apps'),
    [string]$SnapshotDir,
    [string[]]$Languages = @('python', 'node', 'go', 'cmake', 'dotnet', 'mingw', 'uv'),
    [switch]$NoEditor,
    [switch]$HighPerformancePowerPlan,
    [switch]$DisableMouseAcceleration,
    [switch]$InstallDrivers,
    [switch]$RegisterAssociations,
    [switch]$SkipTweaks,
    [switch]$Help
)

if ($Help) { Get-Help $PSCommandPath -Detailed; return }

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$gitExe = Join-Path $env:USERPROFILE 'scoop\shims\git.exe'

# Rebuild PATH from the registry: a stale parent environment must not decide what is installed.
function Reset-Path {
    $env:PATH = (@(
            [Environment]::GetEnvironmentVariable('Path', 'Machine'),
            [Environment]::GetEnvironmentVariable('Path', 'User')
        ) | Where-Object { $_ }) -join ';'
}
Reset-Path

# Child scripts need PowerShell 7 when present; a fresh box only has 5.1.
$pwshExe = (Get-Command 'pwsh' -ErrorAction SilentlyContinue).Source
if (-not $pwshExe) { $pwshExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }

function Say { param([string]$M, [string]$C = 'Gray') Write-Host $M -ForegroundColor $C }
function Step { param([string]$M) Write-Host "  -> $M" -ForegroundColor Cyan }
function Ok { param([string]$M) Write-Host "     ok    $M" -ForegroundColor Green }
function Warn { param([string]$M) Write-Host "     WARN  $M" -ForegroundColor Yellow }
function Bad { param([string]$M) Write-Host "     FAIL  $M" -ForegroundColor Red }

$results = New-Object System.Collections.Generic.List[object]
function Record { param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $script:results.Add([pscustomobject]@{ Phase = $Name; Result = $(if ($Ok) { 'PASS' } else { 'FAIL' }); Detail = $Detail })
}
# NOTE: the parameter must NOT be named $Args - that shadows the automatic variable and
# silently drops every argument passed to the child script.
function Invoke-Step { param([string]$File, [string[]]$Arguments, [string]$What)
    $p = Join-Path $here $File
    if (-not (Test-Path $p)) { Bad "$File not found"; return $false }
    Step $What
    $out = & $pwshExe -NoProfile -File $p @Arguments 2>&1
    $out | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
    return ($LASTEXITCODE -eq 0)
}
# scoop list writes its table through the host stream, so it cannot be captured reliably.
# Ask the filesystem instead: an installed app has scoop\apps\<name>\current.
function Test-ScoopApp { param([string]$Name) Test-Path (Join-Path $env:USERPROFILE "scoop\apps\$Name\current") }
function Get-ScoopInstalled {
    Get-ChildItem (Join-Path $env:USERPROFILE 'scoop\apps') -Directory -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name
}
function Scoop-Install { param([string[]]$Packages, [switch]$Bucket)
    $scoop = Get-Command 'scoop' -ErrorAction SilentlyContinue
    if (-not $scoop) { Bad 'scoop not available'; return $false }
    if ($Bucket) {
        foreach ($b in $Packages) {
            if (-not (Test-Path (Join-Path $env:USERPROFILE "scoop\buckets\$b"))) {
                if ($PSCmdlet.ShouldProcess($b, 'scoop bucket add')) { & scoop bucket add $b 2>&1 | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray } }
            }
        }
        return $true
    }
    $installed = Get-ScoopInstalled
    $missing = @()
    foreach ($p in $Packages) {
        $leaf = ($p -split '/')[-1]
        if (-not (Test-ScoopApp $leaf)) { $missing += $p }
    }
    if (-not $missing.Count) { Ok "already installed: $($Packages -join ', ')"; return $true }
    # In -WhatIf the change is simply not made; that is not a failure.
    if (-not $PSCmdlet.ShouldProcess(($missing -join ', '), 'scoop install')) { return $true }
    Step "scoop install $($missing -join ' ')"
    & scoop install @missing 2>&1 | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
    Reset-Path
    $still = @($missing | Where-Object { -not (Test-ScoopApp ($_ -split '/')[-1]) })
    if ($still.Count) { Bad "still missing: $($still -join ', ')"; return $false }
    return $true
}

$phases = @($Phase | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
$validPhase = @('check', 'dev', 'apps', 'drivers', 'tune', 'link', 'verify', 'all')
$badPhase = @($phases | Where-Object { $validPhase -notcontains $_ })
if ($badPhase.Count) {
    Write-Host "unknown phase(s): $($badPhase -join ', ')" -ForegroundColor Red
    Write-Host "valid: $($validPhase -join ', ')" -ForegroundColor Gray
    exit 2
}
if ($phases -contains 'all') { $phases = @('check', 'dev', 'apps', 'drivers', 'tune', 'link', 'verify') }
if (-not $Manifest) { $Manifest = Join-Path (Split-Path $here -Parent) 'apps.json' }
if (-not $SnapshotDir) { $SnapshotDir = Join-Path $Destination '_backup' }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isPS7 = $PSVersionTable.PSEdition -eq 'Core'

Write-Host ''
Write-Host '===== win-ai-gaming-setup =====' -ForegroundColor White
Write-Host "  phases      : $($phases -join ', ')"
Write-Host "  apps root   : $Destination"
Write-Host "  manifest    : $Manifest"
Write-Host "  shell       : PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)) -> child host: $pwshExe"
Write-Host "  elevated    : $isAdmin"
if ($WhatIfPreference) { Warn 'WhatIf: nothing will be changed' }
Write-Host ''

# ------------------------------------------------------------------ check + bootstrap
if ($phases -contains 'check') {
    Say '--- check/bootstrap: prerequisites ---' White
    $okAll = $true

    if ($isPS7) { Ok "PowerShell $($PSVersionTable.PSVersion) (Core)" }
    else {
        Warn "running on Windows PowerShell $($PSVersionTable.PSVersion) - this plan prefers PowerShell 7"
        $scoopNow = Get-Command 'scoop' -ErrorAction SilentlyContinue
        if ($scoopNow) { if (-not (Scoop-Install @('pwsh'))) { $okAll = $false } }
        else { Warn 'install PowerShell 7 later with: scoop install pwsh   (or: winget install Microsoft.PowerShell)' }
    }

    if (-not (Get-Command 'scoop' -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess('Scoop', 'install from the official script (user-level)')) {
            Step 'scoop missing - installing it (user-level, no elevation)'
            try {
                Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
                Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
                Reset-Path
                if (Get-Command 'scoop' -ErrorAction SilentlyContinue) { Ok 'scoop installed' } else { Bad 'scoop installed but not on PATH - open a new terminal and re-run'; $okAll = $false }
            }
            catch { Bad "scoop install failed: $($_.Exception.Message)"; $okAll = $false }
        }
    }
    else { Ok 'scoop present' }

    # git and 7zip come first: buckets need git, and the .7z app asset needs 7z.
    if (-not (Scoop-Install @('git', '7zip'))) { $okAll = $false }

    if (Test-Path $gitExe) {
        if ($PSCmdlet.ShouldProcess('git config --global core.longpaths', 'set true')) {
            & $gitExe config --global core.longpaths true 2>&1 | Out-Null
            Ok 'git core.longpaths = true (AI repos nest deeply)'
        }
    }
    $lp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction SilentlyContinue).LongPathsEnabled
    if ($lp -eq 1) { Ok 'LongPathsEnabled already 1' }
    elseif ($isAdmin) {
        if ($PSCmdlet.ShouldProcess('HKLM FileSystem\LongPathsEnabled', 'set 1')) {
            Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Ok 'LongPathsEnabled = 1 (needs reboot)'
        }
    }
    else { Warn 'LongPathsEnabled = 0 and not elevated - git core.longpaths covers git, but pip/HF caches prefer the machine setting' }

    $dev = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
    if ($dev -eq 1) { Ok 'developer mode already on' }
    elseif ($isAdmin) {
        if ($PSCmdlet.ShouldProcess('Developer Mode', 'enable (symlinks without elevation)')) {
            New-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Ok 'developer mode enabled (needed by HF cache / pnpm symlinks)'
        }
    }
    else { Warn 'developer mode off and not elevated - some AI tooling cannot create symlinks' }

    if ($isAdmin) { Ok 'elevated: machine-level changes are possible' } else { Warn 'not elevated: run as administrator for tune/long-paths/dev-mode' }

    $net = Test-Connection -ComputerName 'github.com' -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($net) { Ok 'github.com reachable' } else { Warn 'github.com not reachable - mirrors or a proxy are required'; $okAll = $false }

    $drive = (Get-Item $env:USERPROFILE).PSDrive
    $freeGB = [math]::Round((Get-PSDrive $drive.Name).Free / 1GB, 1)
    if ($freeGB -ge 30) { Ok "free space on $($drive.Name): $freeGB GB" } else { Warn "only $freeGB GB free - toolchain + apps + AI caches want 30 GB+"; $okAll = $false }

    $wu = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue)
    Ok "windows build $($wu.CurrentBuild).$($wu.UBR) (judge patch level by UBR, not Get-HotFix)"

    Record 'check' $okAll 'bootstrap: pwsh/scoop/git/7z/longpaths/devmode'
}

# ------------------------------------------------------------------ dev
if ($phases -contains 'dev') {
    Say '--- dev: toolchain + editors + AI mirrors ---' White
    $ok = $true

    if (-not (Scoop-Install @('git', '7zip'))) { $ok = $false }
    # Do NOT pass the package list through -File as a comma string: -File does not split
    # comma lists, so setup-langs would see one bogus package name and skip everything.
    # Install the requested packages here (array binding works in-process), then let
    # setup-langs.ps1 add its defaults plus the mirror configuration.
    if (-not (Scoop-Install $Languages)) { $ok = $false }
    if (-not (Invoke-Step 'setup-langs.ps1' @() 'languages (defaults) + mirrors + rust')) { $ok = $false }

    if (-not $NoEditor) {
        Scoop-Install @('extras') -Bucket | Out-Null
        if (-not (Scoop-Install @('extras/vscode', 'extras/windows-terminal'))) { Warn 'editor install failed - install VS Code manually from code.visualstudio.com if needed' }
    }
    else { Warn 'NoEditor: skipped VS Code + Windows Terminal' }

    if (-not (Invoke-Step 'fix-env.ps1' @() 'repair PATH, Store stubs, credential helper')) { $ok = $false }

    # AI-specific mirror. pip/npm/go/cargo mirrors are already handled by setup-langs.ps1.
    if ($PSCmdlet.ShouldProcess('HF_ENDPOINT', 'set to https://hf-mirror.com (user)')) {
        [Environment]::SetEnvironmentVariable('HF_ENDPOINT', 'https://hf-mirror.com', 'User')
        Ok 'HF_ENDPOINT = https://hf-mirror.com  (HuggingFace downloads via the mirror)'
    }
    Warn 'mirrors in effect: pip=pypi.tuna.tsinghua.edu.cn  npm=registry.npmmirror.com  go=goproxy.cn  cargo=rsproxy.cn  hf=hf-mirror.com'
    Warn 'GPU stack (CUDA/torch) is vendor-specific and NOT automated - install the driver, then the matching torch build'
    Record 'dev' $ok 'toolchain + editors + mirrors'
    Warn 'open a NEW terminal afterwards: the current one still has the old PATH'
}

# ------------------------------------------------------------------ apps
if ($phases -contains 'apps') {
    Say '--- apps: portable software (SHA256 verified) ---' White
    if (-not (Test-Path $Manifest)) {
        Bad "manifest not found: $Manifest"; Record 'apps' $false 'manifest missing'
    }
    else {
        $a = Invoke-Step 'install-portable.ps1' @('-Manifest', $Manifest, '-Destination', $Destination) 'download, verify, unpack'
        Invoke-Step 'check-software.ps1' @('-PortableRoot', $Destination) 'inventory' | Out-Null
        Record 'apps' $a 'portable apps installed'
    }
}

# ------------------------------------------------------------------ drivers
if ($phases -contains 'drivers') {
    Say '--- drivers: problem devices + Windows Update driver updates ---' White
    $bad = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })
    foreach ($d in $bad) {
        $code = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue).Data
        Warn "$($d.FriendlyName) [$($d.Class)] status=$($d.Status) problemCode=$code"
    }
    if ($bad.Count) {
        Warn 'a device in a failed state is usually a MISSING VENDOR DRIVER, not an optimizer side effect'
        Warn '  1) reset-failed-devices.ps1 -Reset clears the state (it may come back)'
        Warn '  2) a GENERIC Microsoft driver that cannot load the device firmware looks exactly like broken hardware.'
        Warn '     Example: MT7921 Bluetooth + Microsoft generic driver => Code 43, "adapter command timed out".'
        Warn '     The vendor/UWD driver ships the firmware and fixes it.'
        Warn '  3) hard-to-find drivers: search the Microsoft Update Catalog, then CHECK THE INF lists your'
        Warn '     hardware ID (USB\VID_xxxx&PID_xxxx) before installing - never install blind.'
    }
    else { Ok 'no device is in a failed state' }

    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $res = $searcher.Search("IsInstalled=0 and Type='Driver'")
        Ok "Windows Update offers $($res.Updates.Count) driver update(s)"
        for ($i = 0; $i -lt $res.Updates.Count; $i++) { Write-Host "       + $($res.Updates.Item($i).Title)" -ForegroundColor DarkGray }
        if ($res.Updates.Count -and $InstallDrivers) {
            if ($PSCmdlet.ShouldProcess("$($res.Updates.Count) driver update(s)", 'download and install')) {
                $coll = New-Object -ComObject Microsoft.Update.UpdateColl
                for ($i = 0; $i -lt $res.Updates.Count; $i++) {
                    $u = $res.Updates.Item($i); if (-not $u.EulaAccepted) { $u.AcceptEula() }; $coll.Add($u) | Out-Null
                }
                $dl = $session.CreateUpdateDownloader(); $dl.Updates = $coll; $null = $dl.Download()
                $inst = $session.CreateUpdateInstaller(); $inst.Updates = $coll
                $r = $inst.Install()
                Ok "installed: ResultCode=$($r.ResultCode) (2 = success)  RebootRequired=$($r.RebootRequired)"
            }
        }
        elseif ($res.Updates.Count) { Warn 'pass -InstallDrivers to install them (a reboot may be required)' }
        Record 'drivers' $true "failed devices: $($bad.Count) / WU driver updates: $($res.Updates.Count)"
    }
    catch { Bad "driver search failed: $($_.Exception.Message)"; Record 'drivers' $false 'WU driver search failed' }
}
# ------------------------------------------------------------------ tune
if ($phases -contains 'tune') {
    Say '--- tune: snapshot, then gaming tweaks + turning off useless stuff ---' White
    New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null
    $ok = Invoke-Step 'snapshot-services.ps1' @('-OutDir', $SnapshotDir) 'snapshot before touching anything'

    if ($SkipTweaks) {
        Warn 'SkipTweaks: snapshot taken, no tweak applied'
        Record 'tune' $ok 'snapshot only'
    }
    else {
        # Each entry is a single registry write with a reason. Nothing here disables a service.
        $changes = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; Name = 'AllowGameDVR'; Value = 0; Type = 'DWord';
               Why = 'GameDVR background recording costs frames' }
            @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Value = 0; Type = 'DWord';
               Why = 'same switch, user scope' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Value = 10; Type = 'DWord';
               Why = 'MMCSS: give the game thread more CPU (default 20)' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Value = 0xffffffff; Type = 'DWord';
               Why = 'MMCSS: no network throttling while gaming' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Value = 1; Type = 'DWord';
               Why = 'stop silent app installs / promoted apps' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 0; Type = 'DWord';
               Why = 'telemetry off (policy, not a service kill)' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Value = 0; Type = 'DWord'; Why = 'no silent Store installs' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Value = 0; Type = 'DWord'; Why = 'no Start menu suggestions' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Value = 0; Type = 'DWord'; Why = 'no Start recommendations' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Value = 0; Type = 'DWord'; Why = 'no Windows welcome suggestions' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353698Enabled'; Value = 0; Type = 'DWord'; Why = 'no Timeline suggestions' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Value = 0; Type = 'DWord'; Why = 'no Windows tips popups' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenOverlayEnabled'; Value = 0; Type = 'DWord'; Why = 'no lock-screen ads' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'PreInstalledAppsEnabled'; Value = 0; Type = 'DWord'; Why = 'no preinstalled app promotion' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'OemPreInstalledAppsEnabled'; Value = 0; Type = 'DWord'; Why = 'no OEM app promotion' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSyncProviderNotifications'; Value = 0; Type = 'DWord'; Why = 'no "sync your settings" ads in Explorer' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Value = 0; Type = 'DWord'; Why = 'Start search stays local' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'CortanaConsent'; Value = 0; Type = 'DWord'; Why = 'no cloud search consent' }
        )
        if ($DisableMouseAcceleration) {
            $changes += @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseSpeed'; Value = 0; Type = 'String'; Why = 'mouse acceleration off (gaming preference)' }
            $changes += @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold1'; Value = 0; Type = 'String'; Why = 'mouse acceleration off' }
            $changes += @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold2'; Value = 0; Type = 'String'; Why = 'mouse acceleration off' }
        }

        $applied = 0; $failed = 0
        foreach ($c in $changes) {
            if (-not $PSCmdlet.ShouldProcess("$($c.Path)\$($c.Name)", "set $($c.Value) - $($c.Why)")) { continue }
            try {
                New-Item $c.Path -Force -ErrorAction SilentlyContinue | Out-Null
                Set-ItemProperty -Path $c.Path -Name $c.Name -Value $c.Value -Type $c.Type -ErrorAction Stop
                $applied++
            }
            catch { $failed++; Bad "$($c.Path)\$($c.Name): $($_.Exception.Message)" }
        }
        Ok "applied $applied registry change(s), $failed failed"

        if ($HighPerformancePowerPlan) {
            if ($PSCmdlet.ShouldProcess('power plan', 'switch to High performance')) {
                & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
                Ok 'power plan: High performance (costs battery life)'
            }
        }
        else { Warn 'power plan left as-is (pass -HighPerformancePowerPlan to switch)' }
        if (-not $DisableMouseAcceleration) { Warn 'mouse acceleration left as-is (pass -DisableMouseAcceleration to zero it)' }

        Warn 'deliberately NOT done: no service disabled, no UAC change, no DPI change, no update policy change'
        Record 'tune' ($ok -and $failed -eq 0) "tweaks applied: $applied"
    }
}

# ------------------------------------------------------------------ link
if ($phases -contains 'link') {
    Say '--- link: file associations ---' White
    if ($RegisterAssociations) {
        $appsHash = @{}
        if (Test-Path $Manifest) {
            foreach ($app in (Get-Content $Manifest -Raw | ConvertFrom-Json).apps) {
                if (-not $app.assoc) { continue }
                $exe = Join-Path (Join-Path $Destination $app.name) (Split-Path $app.exe -Leaf)
                $appsHash[$app.name] = @{ Exe = $exe; Exts = @($app.assoc) }
            }
        }
        Step ("register: " + (($appsHash.GetEnumerator() | ForEach-Object { "$($_.Key)($($_.Value.Exts.Count))" }) -join ', '))
        $scr = Join-Path $here 'set-app-associations.ps1'
        if (Test-Path $scr) { & $scr -Register -Apps $appsHash -BackupDir (Join-Path $SnapshotDir 'assoc-backup') }
        else { Bad 'set-app-associations.ps1 not found' }
    }
    else {
        Invoke-Step 'set-app-associations.ps1' @() 'report current associations' | Out-Null
    }
    Invoke-Step 'clean-orphan-associations.ps1' @('-Root', $Destination) 'check for orphaned associations' | Out-Null
    Warn 'Windows protects DEFAULT programs (UserChoice): one manual click per file type is required'
    Warn '  right-click a file > Open with > Choose another app > pick it > Always'
    Record 'link' $true 'associations registered / reported'
}

# ------------------------------------------------------------------ verify
if ($phases -contains 'verify') {
    Say '--- verify: acceptance ---' White
    $a = Invoke-Step 'verify-env.ps1' @() 'dev toolchain'
    $b = Invoke-Step 'check-software.ps1' @('-PortableRoot', $Destination) 'portable apps present'
    $c = Invoke-Step 'diagnose-ime.ps1' @() 'input method health'
    Invoke-Step 'compare-services.ps1' @('-Snapshot', (Join-Path $SnapshotDir 'services-snapshot.csv')) 'service baseline drift' | Out-Null
    Record 'verify' ($a -and $b -and $c) 'dev/apps/ime'
    if (-not $c) { Warn 'input method unhealthy: run diagnose-ime.ps1 -Repair (elevated), then REBOOT' }
}

# ------------------------------------------------------------------ summary
Write-Host ''
Write-Host '===== result =====' -ForegroundColor White
$results | Format-Table -AutoSize | Out-String | Write-Host
$fail = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count
if ($fail -eq 0) { Ok 'all selected phases passed' } else { Bad "$fail phase(s) failed - read the log above" }
Write-Host ''
Write-Host 'next steps that no script can do for you:' -ForegroundColor Yellow
Write-Host '  1. REBOOT, then open a NEW terminal (PATH, long paths and the input stack rebuild at logon)'
Write-Host '  2. set default programs: one manual click per file type you care about'
Write-Host '  3. GPU stack if you need it: driver -> then the matching CUDA/torch build for AI work'
Write-Host '  4. a device showing an error: reset-failed-devices.ps1 -Reset, else a FULL power-off'
exit $fail
