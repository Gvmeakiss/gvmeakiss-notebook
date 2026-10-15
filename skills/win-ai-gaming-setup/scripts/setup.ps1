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
  Scoop packages for the dev phase. Default (real scoop manifest names):
  python,nodejs,go,cmake,dotnet-sdk,mingw,uv
  Friendly aliases are accepted and normalised: node -> nodejs, dotnet -> dotnet-sdk,
  python3 -> python, golang -> go.

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
    # These must be the REAL scoop manifest names. 'node' and 'dotnet' do not exist in the
    # main bucket (they are 'nodejs' and 'dotnet-sdk'): `scoop install` aborts the WHOLE
    # batch as soon as one manifest is missing, so the wrong names here silently skipped the
    # entire toolchain while every later phase still reported success.
    [string[]]$Languages = @('python', 'nodejs', 'go', 'cmake', 'dotnet-sdk', 'mingw', 'uv'),
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
    # Install one package per invocation. `scoop install a b c` aborts the ENTIRE batch as
    # soon as one manifest is missing, so a single bad name silently skips every package
    # after it. Individually, one failure costs exactly one package, and the per-package
    # read-back below names precisely which ones did not land.
    $still = @()
    foreach ($pkg in $missing) {
        Step "scoop install $pkg"
        & scoop install $pkg 2>&1 | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
        Reset-Path
        if (-not (Test-ScoopApp ($pkg -split '/')[-1])) { $still += $pkg }
    }
    if ($still.Count) { Bad "still missing: $($still -join ', ')"; return $false }
    return $true
}

# Normalise friendly package names to real scoop manifest names before anything installs.
# Only the leaf is mapped, so 'bucket/app' still resolves to 'bucket/app'.
$scoopAliases = @{ 'node' = 'nodejs'; 'dotnet' = 'dotnet-sdk'; 'python3' = 'python'; 'golang' = 'go' }
$Languages = @($Languages | ForEach-Object {
        $leaf = ($_ -split '/')[-1]
        if ($scoopAliases.ContainsKey($leaf)) {
            $_.Substring(0, $_.Length - $leaf.Length) + $scoopAliases[$leaf]
        }
        else { $_ }
    })
$aliasNote = @($Languages | Where-Object { $_ -notin @('python', 'nodejs', 'go', 'cmake', 'dotnet-sdk', 'mingw', 'uv') })
if ($aliasNote.Count) { Write-Host "  languages   : $($Languages -join ', ')" -ForegroundColor Gray }

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
            # Same hazard as the tune loop below: -Force on an existing key wipes its values.
            $amKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
            if (-not (Test-Path $amKey)) { New-Item -Path $amKey -Force -ErrorAction SilentlyContinue | Out-Null }
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

    # AI-specific mirror. pip/npm/go/cargo mirrors are configured by setup-langs.ps1.
    if ($PSCmdlet.ShouldProcess('HF_ENDPOINT', 'set to https://hf-mirror.com (user)')) {
        [Environment]::SetEnvironmentVariable('HF_ENDPOINT', 'https://hf-mirror.com', 'User')
        Ok 'HF_ENDPOINT = https://hf-mirror.com  (HuggingFace downloads via the mirror)'
    }
    # Report what is ACTUALLY configured. Every mirror in setup-langs.ps1 is guarded by
    # "is this tool on PATH yet", so a toolchain that failed to install leaves the machine
    # only half-mirrored - while a hardcoded success line would still claim otherwise.
    # This was measured: nodejs failed to download, so `npm config set registry` never ran,
    # yet the summary still announced npm=registry.npmmirror.com. Read each one back.
    Warn 'mirror state (read back, not assumed):'
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if ($npmCmd) { Warn "  npm   -> $((& npm config get registry 2>&1 | Select-Object -First 1))" }
    else { Warn '  npm   -> NOT configured (npm not on PATH; install nodejs, then re-run -Phase dev)' }
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pyCmd) { Warn "  pip   -> $(((& python -m pip config get global.index-url 2>&1) | Select-Object -First 1))" }
    else { Warn '  pip   -> NOT configured (python not on PATH)' }
    $goCmd = Get-Command go -ErrorAction SilentlyContinue
    if ($goCmd) { Warn "  go    -> $((& go env GOPROXY 2>&1 | Select-Object -First 1))" }
    else { Warn '  go    -> NOT configured (go not on PATH)' }
    # cargo honours CARGO_HOME; scoop's rustup package points it at its own persist dir,
    # so ~/.cargo is NOT always where the config has to live.
    $cargoHome = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $env:USERPROFILE '.cargo' }
    if (Test-Path (Join-Path $cargoHome 'config.toml')) { Warn "  cargo -> rsproxy.cn  ($cargoHome\config.toml)" }
    else { Warn "  cargo -> NOT configured (no config.toml under $cargoHome; needs rust)" }
    Warn "  hf    -> $([Environment]::GetEnvironmentVariable('HF_ENDPOINT', 'User'))"
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
            # The Games task class. verify-env.ps1 checks GPU Priority and Scheduling
            # Category, so they have to be written here or those two checks fail on every
            # single machine - the two halves of the project have to agree.
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'GPU Priority'; Value = 8; Type = 'DWord';
               Why = 'MMCSS: game task GPU priority (verify-env checks this)' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Priority'; Value = 6; Type = 'DWord';
               Why = 'MMCSS: game task CPU priority' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Scheduling Category'; Value = 'High'; Type = 'String';
               Why = 'MMCSS: game task scheduling category (verify-env checks this)' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'SFIO Priority'; Value = 'High'; Type = 'String';
               Why = 'MMCSS: game task storage IO priority' }
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
            # Start-menu web search. The obvious key (`...\CurrentVersion\Search`:
            # BingSearchEnabled / CortanaConsent) is NOT reliably writable: measured on
            # Windows 11 24H2+, writes there are refused at kernel level with "Not all data
            # was successfully written to the registry" while the key's ACL still shows the
            # user FullControl - so it is not an ACL problem and cannot be fixed by taking
            # ownership. The policy keys below are the official route and were verified to
            # accept the write. Policy also outranks the user-scope value, so this is not a
            # downgrade. verify-env.ps1 accepts EITHER route.
            @{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Value = 1; Type = 'DWord'; Why = 'Start search stops offering web suggestions' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'ConnectedSearchUseWeb'; Value = 0; Type = 'DWord'; Why = 'no web results in Start search (machine policy)' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Value = 0; Type = 'DWord'; Why = 'no cloud search consent' }
        )
        if ($DisableMouseAcceleration) {
            $changes += @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseSpeed'; Value = 0; Type = 'String'; Why = 'mouse acceleration off (gaming preference)' }
            $changes += @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold1'; Value = 0; Type = 'String'; Why = 'mouse acceleration off' }
            $changes += @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold2'; Value = 0; Type = 'String'; Why = 'mouse acceleration off' }
        }

        # ------------------------------------------------------------------ write
        # ONE .reg file imported once, instead of one Set-ItemProperty per value.
        #
        # Why - all measured on a 30-value set on a real machine:
        #     Set-ItemProperty x30 :  94 ms
        #     reg add x30          : 381 ms   (a process spawn per call)
        #     reg import x1        :  12 ms   <- ~8x faster than the loop
        # It is also structurally safer: `reg import` MERGES into an existing key, so it
        # cannot recreate a key and wipe its siblings the way `New-Item <key> -Force` did.
        # That bug made this loop leave only the LAST value of each key while still
        # reporting "applied N, 0 failed" - SKILL.md has the controlled experiment.
        #
        # ONE CAVEAT, measured: `reg import` is a PARTIAL write when a key is refused.
        # A file containing an unwritable key returns exit 1, keeps the keys it managed to
        # write, and SKIPS THE REMAINING SECTIONS. So do not put a key of unknown
        # writability in the middle of this batch - the read-back below would then report
        # the tail as "not present after the write" and the real cause (one locked key)
        # would look like N unrelated failures. That is why the Start-menu search values
        # now go to their policy keys instead of `...\CurrentVersion\Search`.
        $approved = New-Object System.Collections.Generic.List[object]
        foreach ($c in $changes) {
            if ($PSCmdlet.ShouldProcess("$($c.Path)\$($c.Name)", "set $($c.Value) - $($c.Why)")) { $approved.Add($c) }
        }

        # Group by key: a .reg file is written as [key] sections followed by their values.
        $byKey = [ordered]@{}
        foreach ($c in $approved) {
            if (-not $byKey.Contains($c.Path)) { $byKey[$c.Path] = New-Object System.Collections.Generic.List[object] }
            $byKey[$c.Path].Add($c)
        }

        # Both -1 and 0xffffffff must render as the 8-digit hex ff ff ff ff.
        function ConvertTo-RegDword { param($v) $n = [int64]$v; if ($n -lt 0) { $n += 4294967296 }; return ('{0:x8}' -f $n) }

        $regLines = New-Object System.Collections.Generic.List[string]
        $regLines.Add('Windows Registry Editor Version 5.00')
        foreach ($k in $byKey.Keys) {
            $regKey = $k -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU:\\', 'HKEY_CURRENT_USER\'
            $regLines.Add('')
            $regLines.Add("[$regKey]")
            foreach ($c in $byKey[$k]) {
                if ($c.Type -eq 'DWord') {
                    $regLines.Add('"{0}"=dword:{1}' -f $c.Name, (ConvertTo-RegDword $c.Value))
                }
                else {
                    $regLines.Add('"{0}"="{1}"' -f $c.Name, ("$($c.Value)" -replace '"', '\"'))
                }
            }
        }
        $regFile = Join-Path $env:TEMP ('dsh-tune-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.reg')
        # A .reg file must be UTF-16LE ("Unicode") or reg.exe rejects it.
        $regLines -join "`r`n" | Set-Content -Path $regFile -Encoding Unicode
        $importOut = & reg.exe import $regFile 2>&1
        $importCode = $LASTEXITCODE
        Remove-Item $regFile -Force -ErrorAction SilentlyContinue
        if ($importCode -ne 0) { $importOut | ForEach-Object { Bad "reg import: $_" } }

        # ------------------------------------------------------------------ read back
        # Read each KEY once, not each value. Measured: 30 x (Get-ItemProperty -Name) =
        # 154 ms versus one read per key = 4 ms. A write returning success is not evidence;
        # this is the evidence.
        $applied = 0; $failed = 0
        foreach ($k in $byKey.Keys) {
            $props = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
            foreach ($c in $byKey[$k]) {
                if (($null -ne $props) -and ($null -ne $props.($c.Name))) { $applied++ }
                else { $failed++; Bad "$k\$($c.Name): not present after the write" }
            }
        }
        Ok "applied $applied registry change(s), $failed failed (verified by reading each key back)"

        # MMCSS is a KERNEL DRIVER: every MMCSS value above is INERT while it is stopped, and
        # the registry still looks perfectly correct. Measured: installing a graphics driver
        # stopped it, and it then could NOT be started on demand ("StartService failed 2:
        # the system cannot find the file" even though mmcss.sys is present and intact) - it
        # is boot-loaded, so only a reboot brings it back. Report the real state, do not
        # assume the writes took effect.
        & sc.exe config MMCSS start= auto 2>&1 | Out-Null
        & sc.exe start MMCSS 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        $mmcssLine = ((& sc.exe query MMCSS 2>&1 | Select-String 'STATE') -join ' ').Trim()
        if ($mmcssLine -match 'RUNNING') {
            Ok 'MMCSS RUNNING - the SystemProfile / Tasks\Games values are actually in effect'
        }
        else {
            Warn "MMCSS is NOT running ($mmcssLine) - every MMCSS value above is INERT."
            Warn '  it is a boot-loaded kernel driver and cannot be started on demand: REBOOT,'
            Warn '  then confirm with  sc query MMCSS  and re-run -Phase tune if values are gone'
        }

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
                # Keep the manifest's RELATIVE path. Some apps nest their binary
                # (JPEGView ships JPEGView64\JPEGView.exe), and Split-Path -Leaf here would
                # drop the subdirectory and register an association pointing at a file that
                # does not exist - which then shows up as a dead entry in the Settings page.
                $exe = Join-Path (Join-Path $Destination $app.name) $app.exe
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
