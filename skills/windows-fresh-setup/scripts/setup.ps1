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

.PARAMETER IncludeOptionalApps
  Also install manifest entries marked "optional": true. They are skipped by default because
  their own notes say to ask the user first (the Markdown editor is the current example: an
  Electron app that is the slowest thing in the manifest to start, where Notepad++ usually
  wins a "fast and simple" comparison). Naming one with -Only installs it regardless.

.PARAMETER HighPerformancePowerPlan
  Optional, off by default: switch the active power plan to High performance.
  Left off because it costs battery life on a laptop.

.PARAMETER DisableSleepOnAC
  Optional, off by default: never sleep on AC power (the display still turns off).
  Intended for desktops and mini PCs, where S0 modern standby can fail to wake: measured
  evidence was five sleep cycles that each "resumed" within seconds and then sat in standby,
  one of which never woke at all and ended as a forced power-off (logged as Id=41 + 6008).

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
    # Named bundles instead of asking the user to combine nine switches. Overrides -Phase.
    [ValidateSet('', 'minimal', 'dev', 'full')]
    [string]$Profile = '',
    [string]$Manifest,
    [string]$Destination = (Join-Path $env:USERPROFILE 'Apps'),
    [string]$SnapshotDir,
    # These must be the REAL scoop manifest names. 'node' and 'dotnet' do not exist in the
    # main bucket (they are 'nodejs' and 'dotnet-sdk'): `scoop install` aborts the WHOLE
    # batch as soon as one manifest is missing, so the wrong names here silently skipped the
    # entire toolchain while every later phase still reported success.
    [string[]]$Languages = @('python', 'nodejs', 'go', 'cmake', 'dotnet-sdk', 'mingw', 'uv'),
    [switch]$NoEditor,
    [switch]$IncludeOptionalApps,
    [switch]$HighPerformancePowerPlan,
    [switch]$DisableMouseAcceleration,
    [switch]$DisableSleepOnAC,
    [switch]$InstallDrivers,
    [switch]$RegisterAssociations,
    [switch]$SkipTweaks,
    [switch]$Help
)

if ($Help) { Get-Help $PSCommandPath -Detailed; return }

# ------------------------------------------------------------------ context guards
# RUN-AS-SYSTEM TRAP. Under the SYSTEM account, HKCU resolves to the SYSTEM hive, not the
# interactive user's. Every user-scope write in the tune/link phases would land in the wrong
# profile - and, worse, the read-back added later in those phases would read that SAME wrong
# hive and report PASS. A machine that silently "passes" while the user gets nothing is the one
# failure mode this project cannot detect afterwards, so refuse instead of producing it.
$identityName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$isSystemContext = ($identityName -match '(^|\\)SYSTEM$')
$osBuildNumber = [Environment]::OSVersion.Version.Build
if ($isSystemContext) {
    $wantsUserScope = @($Phase | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() }) |
        Where-Object { $_ -in @('tune', 'link', 'all') }
    if ($wantsUserScope) {
        Write-Host '     FAIL  running as SYSTEM - refusing the phases that write HKCU' -ForegroundColor Red
        Write-Host "           identity : $identityName" -ForegroundColor Red
        Write-Host '           under SYSTEM, HKCU is the SYSTEM hive: user-scope tweaks would be written' -ForegroundColor Red
        Write-Host '           to the wrong profile AND the read-back would still report PASS.' -ForegroundColor Red
        Write-Host '           run this from an elevated USER prompt (right-click > Run as administrator),' -ForegroundColor Red
        Write-Host '           not from a scheduled task whose principal is SYSTEM.' -ForegroundColor Red
        exit 3
    }
}

# ------------------------------------------------------------------ persistent log
# Without a transcript, a failure investigated later is guesswork: the "2 registry writes
# failed" bug in this project took hours to chase precisely because nothing was on disk. The
# log lands next to the snapshot so it travels with the rollback material.
$logDir = if ($SnapshotDir) { $SnapshotDir } else { Join-Path $Destination '_backup' }
$script:logFile = $null
try {
    New-Item -ItemType Directory -Force -Path $logDir -ErrorAction Stop | Out-Null
    $script:logFile = Join-Path $logDir ('setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    Start-Transcript -Path $script:logFile -Force -ErrorAction Stop | Out-Null
}
catch {
    $script:logFile = $null
    Write-Host "     WARN  transcript disabled: $($_.Exception.Message)" -ForegroundColor Yellow
}

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
# Pure helpers (DWORD rendering, undo formatting, build gating) live in lib/ so that
# scripts/test-tune-core.ps1 can exercise them without touching a live machine.
. (Join-Path $here 'lib/tune-core.ps1')
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

# ------------------------------------------------------------------ per-item undo
# A system restore point is a coarse undo: it reverts EVERY change made since it was taken, so a
# single bad tweak costs the good ones too. Mature projects solve this with per-feature undo
# metadata (Win11Debloat pairs every feature with a RegistryUndoKey and a 1:1 undo .reg).
# This goes one step further and records the ACTUAL previous state, because "restore the
# Microsoft default" is not the same as "restore what this machine had".
# Every write site appends one entry; the whole list is emitted as a runnable revert script.
# Per-item undo state + writer live in lib/undo.ps1 (P2-6). Dot-sourcing keeps them in this
# script scope, so every write site below can keep calling Add-Undo unchanged.
. (Join-Path $PSScriptRoot 'lib\undo.ps1')
# NOTE: the parameter must NOT be named $Args - that shadows the automatic variable and
# silently drops every argument passed to the child script.
# A child script that declares SupportsShouldProcess accepts -WhatIf; one that does not
# rejects it with a parameter-binding error, so the flag cannot be forwarded blindly.
# Sub-process helpers (Test-ChildSupportsWhatIf / Invoke-Step) live in lib/process.ps1.
. (Join-Path $here 'lib\process.ps1')
# scoop list writes its table through the host stream, so it cannot be captured reliably.
# Ask the filesystem instead: an installed app has scoop\apps\<name>\current.
function Test-ScoopApp { param([string]$Name) Test-Path (Join-Path $env:USERPROFILE "scoop\apps\$Name\current") }

# Readback for the archive tool. 7-Zip installs to Program Files and does not have to be on
# PATH, so asking 'Get-Command 7z' alone is exactly the kind of probe that reports "missing"
# for a working install - or, worse in the other direction, misses a real absence when a stale
# shim exists. Check the known install locations first, then fall back to PATH.
function Test-ArchiveTool {
    $candidates = @((Join-Path $env:ProgramFiles '7-Zip\7z.exe'))
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe') }
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $true } }
    return [bool](Get-Command '7z' -ErrorAction SilentlyContinue)
}
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

# ------------------------------------------------------------------ profiles
# The nine switches below are fine for someone who has read README.md; a profile is for the
# "new machine, one command" case. A profile WINS over -Phase on purpose: mixing both would
# silently apply half of each.
if ($Profile) {
    $profilePhases = switch ($Profile) {
        'minimal' { @('check', 'apps', 'link') }
        'dev' { @('check', 'dev', 'apps', 'link', 'verify') }
        'full' { @('check', 'dev', 'apps', 'drivers', 'tune', 'link', 'verify') }
    }
    if ($Profile -eq 'minimal') { $SkipTweaks = $true }
    $phases = @($profilePhases)
    Write-Host "  profile     : $Profile (overrides -Phase)" -ForegroundColor Gray
}
# scoop is only needed by the dev phase. Measured: -Profile minimal (check/apps/link) exited 1 on
# an elevated shell because the check phase tried to bootstrap scoop, and scoop's installer
# refuses to run as administrator - even though minimal never needs scoop at all.
$needsScoop = ($phases -contains 'dev')

if (-not $Manifest) { $Manifest = Join-Path (Split-Path $here -Parent) 'apps.json' }
if (-not $SnapshotDir) { $SnapshotDir = Join-Path $Destination '_backup' }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isPS7 = $PSVersionTable.PSEdition -eq 'Core'

Write-Host ''
Write-Host '===== windows-fresh-setup =====' -ForegroundColor White
Write-Host "  phases      : $($phases -join ', ')"
Write-Host "  apps root   : $Destination"
Write-Host "  manifest    : $Manifest"
Write-Host "  shell       : PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)) -> child host: $pwshExe"
Write-Host "  elevated    : $isAdmin"
Write-Host "  identity    : $identityName"
Write-Host "  windows     : build $osBuildNumber"
Write-Host "  log         : $(if ($script:logFile) { $script:logFile } else { '(transcript off)' })"
if ($WhatIfPreference) { Warn 'WhatIf: nothing will be changed' }
Write-Host ''

# ------------------------------------------------------------------ check + bootstrap
. (Join-Path $PSScriptRoot 'lib/phases/1-check.ps1')

# ------------------------------------------------------------------ dev
. (Join-Path $PSScriptRoot 'lib/phases/2-dev.ps1')

# ------------------------------------------------------------------ apps
. (Join-Path $PSScriptRoot 'lib/phases/3-apps.ps1')

# ------------------------------------------------------------------ drivers
. (Join-Path $PSScriptRoot 'lib/phases/4-drivers.ps1')
# ------------------------------------------------------------------ tune
. (Join-Path $PSScriptRoot 'lib/phases/5-tune.ps1')

# ------------------------------------------------------------------ link
. (Join-Path $PSScriptRoot 'lib/phases/6-link.ps1')

# ------------------------------------------------------------------ verify
. (Join-Path $PSScriptRoot 'lib/phases/7-verify.ps1')

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
if ($script:logFile) {
    Write-Host ''
    Write-Host "log: $($script:logFile)" -ForegroundColor DarkGray
    try { Stop-Transcript | Out-Null } catch { }
}
exit $fail