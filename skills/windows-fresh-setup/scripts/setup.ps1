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
$script:undoEntries = New-Object System.Collections.Generic.List[object]
function Add-Undo {
    param([string]$What, [string]$Revert)
    if ([string]::IsNullOrWhiteSpace($Revert)) { return }
    $script:undoEntries.Add([pscustomobject]@{ What = $What; Revert = $Revert })
}

function Write-UndoScript {
    param([string]$Dir)
    if (-not $script:undoEntries.Count) { return $null }
    $path = Join-Path $Dir ('tune-undo-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.ps1')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Revert script generated by windows-fresh-setup.')
    $lines.Add('# Run in an ELEVATED USER session:  pwsh -File <this file>')
    $lines.Add('# It restores the values that were present BEFORE the tune phase, one item at a time.')
    $lines.Add('# Items whose original state was "absent" are removed again, not set to a guessed default.')
    $lines.Add('')
    $lines.Add('$ErrorActionPreference = ''Continue''')
    $lines.Add('$failed = 0')
    foreach ($e in $script:undoEntries) {
        $lines.Add('')
        $lines.Add('# ' + $e.What)
        $lines.Add('try {')
        $lines.Add('    ' + $e.Revert)
        $lines.Add('} catch { Write-Host "  FAIL  ' + ($e.What -replace '"', '') + ': $($_.Exception.Message)"; $failed++ }')
    }
    $lines.Add('')
    $lines.Add('if ($failed -eq 0) { Write-Host "  ok    all items reverted" } else { Write-Host "  FAIL  $failed item(s) could not be reverted" }')
    $lines.Add('exit $failed')
    try {
        Set-Content -Path $path -Value ($lines -join "`r`n") -Encoding UTF8 -ErrorAction Stop
        return $path
    }
    catch { return $null }
}
# NOTE: the parameter must NOT be named $Args - that shadows the automatic variable and
# silently drops every argument passed to the child script.
# A child script that declares SupportsShouldProcess accepts -WhatIf; one that does not
# rejects it with a parameter-binding error, so the flag cannot be forwarded blindly.
$script:whatIfSupport = @{}
function Test-ChildSupportsWhatIf {
    param([string]$Path)
    if ($script:whatIfSupport.ContainsKey($Path)) { return $script:whatIfSupport[$Path] }
    $ok = $false
    try { $ok = ((Get-Content -LiteralPath $Path -Raw -ErrorAction Stop) -match 'SupportsShouldProcess') } catch { }
    $script:whatIfSupport[$Path] = $ok
    return $ok
}

function Invoke-Step { param([string]$File, [string[]]$Arguments, [string]$What)
    $p = Join-Path $here $File
    if (-not (Test-Path $p)) { Bad "$File not found"; return $false }
    Step $What
    # Forward -WhatIf to the child, otherwise a dry run of setup.ps1 is only dry for the
    # writes that happen in THIS script. Measured before this fix: all 11 Invoke-Step call
    # sites passed no -WhatIf, so `setup.ps1 -Phase dev -WhatIf` really installed toolchains,
    # `-Phase apps -WhatIf` really downloaded and installed software, and `-Phase link -WhatIf`
    # really wrote association registrations - while the banner said "nothing will be changed".
    $callArgs = @($Arguments)
    if ($WhatIfPreference -and (Test-ChildSupportsWhatIf $p)) { $callArgs += '-WhatIf' }
    elseif ($WhatIfPreference) {
        # The child does not accept -WhatIf. Two very different cases hide here:
        #   * a read-only probe (audit-env / check-software / diagnose-ime / verify-env /
        #     compare-services) - running it is safe and makes the dry run informative;
        #   * a writer (install-portable / setup-langs / fix-env / snapshot-services /
        #     set-app-associations / clean-orphan-associations) - running it would perform
        #     the very work the dry run is supposed to preview. Measured: -Phase tune -WhatIf
        #     really wrote services-snapshot.csv and tasks-snapshot.csv into the snapshot
        #     folder, because snapshot-services.ps1 has no -WhatIf parameter.
        # Read-only children are allow-listed by name; everything else is skipped, not run.
        $readOnlyChildren = @('audit-env.ps1', 'check-software.ps1', 'diagnose-ime.ps1', 'verify-env.ps1', 'compare-services.ps1')
        if ($readOnlyChildren -notcontains $File) {
            Write-Host ("     would run {0} {1} (skipped: this child has no -WhatIf support)" -f $File, ($Arguments -join ' ')) -ForegroundColor Cyan
            return $true
        }
    }
    $out = & $pwshExe -NoProfile -File $p @callArgs 2>&1
    $out | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
    return ($LASTEXITCODE -eq 0)
}
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
        if (-not $needsScoop) {
            # Measured: `-Profile minimal` failed here on an elevated shell because scoop was
            # missing - yet minimal only needs winget and portable zips, never scoop.
            Warn 'scoop missing - not needed for the selected phases (apps/link use winget and portable zips)'
        }
        elseif ($isAdmin) {
            # Measured: scoop's installer prints "Running the installer as administrator is
            # disabled by default ... Abort." and exits non-zero, which made -Phase check FAIL
            # on every elevated session. Report the real remedy instead of retrying it.
            Warn 'scoop missing and this session is ELEVATED - scoop refuses to install as administrator'
            Warn '  open a NORMAL user terminal and run:  irm get.scoop.sh | iex'
            Warn '  then re-run:  setup.ps1 -Profile dev'
            $okAll = $false
        }
        elseif ($PSCmdlet.ShouldProcess('Scoop', 'install from the official script (user-level)')) {
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

    # git comes first for the dev phase: scoop buckets need it.
    if ($needsScoop) {
        if (-not (Scoop-Install @('git'))) { $okAll = $false }
    }

    # 7-Zip is attempted through scoop because the apps phase needs an extractor, but it is
    # NOT allowed to depend on scoop alone. Measured on a real machine: scoop never bootstrapped,
    # so 7-Zip was never installed while this phase still counted the bundle as handled, and the
    # user ended up installing it from 7-zip.org by hand. The winget entry in apps.json is the
    # independent second path; the verdict is a readback of the binary, never the exit code.
    if (Get-Command 'scoop' -ErrorAction SilentlyContinue) {
        if (-not (Scoop-Install @('7zip'))) { Warn '7-Zip not installed by scoop - falling back to winget' }
    }
    if (-not (Test-ArchiveTool)) {
        if (-not (Invoke-Step 'install-portable.ps1' @('-Only', '7-Zip') '7-Zip fallback (winget entry)')) {
            Warn 'winget fallback reported a failure'
        }
        Reset-Path
    }
    if (Test-ArchiveTool) { Ok '7-Zip present' }
    else { Bad '7-Zip missing after scoop AND winget - install it from 7-zip.org, then re-run'; $okAll = $false }

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

    # Only git here. 7-Zip used to be re-attempted in this phase too, which made two phases
    # own the same tool and neither of them prove it: the check phase already ensures it with a
    # winget fallback and a readback, so repeating a scoop-only install here just adds a second
    # way to report failure for the same missing binary.
    if (-not (Scoop-Install @('git'))) { $ok = $false }
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
        # Optional entries in the manifest (e.g. the Markdown editor) are skipped by default;
        # the manifest's own notes say to ask the user first, so this flag is how that
        # intent gets expressed. See install-portable.ps1 for the mechanics.
        $ipArgs = @('-Manifest', $Manifest, '-Destination', $Destination)
        if ($IncludeOptionalApps) { $ipArgs += '-IncludeOptional' }
        $a = Invoke-Step 'install-portable.ps1' $ipArgs 'download, verify, unpack'
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
    Say '--- tune: restore point + snapshot, then gaming tweaks + turning off useless stuff ---' White
    New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null

    # ------------------------------------------------------------------ pre-flight guards
    # The tune phase writes to the machine. Before the FIRST write it must be able to prove
    # (a) that it runs in a context where those writes mean anything, and (b) that every piece
    # of rollback material can exist. Anything unproven aborts the phase with a FAIL record,
    # which becomes a non-zero exit code: a partially tuned machine with no way back is worse
    # than an untouched one.
    $tuneAbort = $null
    if (-not $isAdmin -and -not $WhatIfPreference) {
        $tuneAbort = 'not elevated: the tune phase refuses to start (partial writes are worse than none)'
    }
    if (-not $tuneAbort -and -not $WhatIfPreference) {
        # The undo script lands in the snapshot folder, so prove that folder is writable BEFORE
        # touching the registry - a read-only folder would otherwise only surface at the end,
        # after every write had already happened.
        # This probe is skipped under -WhatIf: Set-Content supports ShouldProcess, so a dry run
        # would suppress the write and the read-back would then look like a failure.
        $probe = Join-Path $SnapshotDir ('.write-probe-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            Set-Content -LiteralPath $probe -Value 'ok' -Encoding Ascii -ErrorAction Stop
            $probeBack = (Get-Content -LiteralPath $probe -Raw -ErrorAction Stop).Trim()
            if ($probeBack -ne 'ok') { $tuneAbort = "snapshot folder is not writable: $SnapshotDir" }
        }
        catch { $tuneAbort = "snapshot folder is not writable: $SnapshotDir" }
        finally { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
    }
    elseif (-not $tuneAbort) {
        Write-Host "     would verify that the snapshot folder is writable: $SnapshotDir" -ForegroundColor Cyan
    }
    if ($tuneAbort) { Bad "tune aborted before any write: $tuneAbort" }

    # A services snapshot is NOT a rollback path: it records what the services looked like,
    # not the machine. System Restore is the only built-in undo for the registry writes below.
    # Two measured facts force the shape of this block:
    #   1. Checkpoint-Computer is de-duplicated by default (SystemRestorePointCreationFrequency
    #      = 1440 minutes). A second call within 24h returns silently and creates nothing, so
    #      "I made a restore point first" can be false while the script reports success.
    #   2. Restore points live on the volume, so replacing/restoring the system disk wipes them.
    #      A machine checked after a disk migration had exactly 0 restore points.
    # Hence: drop the frequency to 0, create, read back the list, then restore the guardrail.
    # If the read-back shows no restore point, the tune phase has no coarse undo and therefore
    # does not start - the abort below records the failure and skips every write.
    if (-not $tuneAbort -and $PSCmdlet.ShouldProcess('system restore point', 'create')) {
        $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $prevFreq = (Get-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "windows-fresh-setup tune $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            $rpCount = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
            if ($rpCount -gt 0) { Ok "restore point created (listed: $rpCount)" }
            else { $tuneAbort = 'Checkpoint-Computer returned but no restore point is listed: no coarse undo available' }
        }
        catch { $tuneAbort = "restore point failed: $($_.Exception.Message)" }
        finally {
            if ($null -eq $prevFreq) { Remove-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue }
            else { Set-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value $prevFreq -Type DWord -ErrorAction SilentlyContinue }
        }
        if ($tuneAbort) { Bad "tune will not start: $tuneAbort" }
    }

    if ($tuneAbort) { $ok = $false }
    else { $ok = Invoke-Step 'snapshot-services.ps1' @('-OutDir', $SnapshotDir) 'snapshot before touching anything' }
    if (-not $ok -and -not $WhatIfPreference -and -not $tuneAbort) {
        $tuneAbort = 'service snapshot failed: no baseline to compare against or roll back to'
        Bad "tune will not start: $tuneAbort"
    }

    if ($tuneAbort) {
        Record 'tune' $false $tuneAbort
    }
    elseif ($SkipTweaks) {
        Warn 'SkipTweaks: snapshot taken, no tweak applied'
        Record 'tune' $ok 'snapshot only'
    }
    else {
        # Each entry is a single registry write with a reason. Nothing here disables a service.
        #
        # AllowTelemetry is SKU-gated on purpose. 0 (Security/Off) is only honoured on
        # Enterprise / Education / Server; on Home and Pro it is silently ignored, so writing
        # 0 there looks like a win and achieves nothing. Measured on a Windows 11 Pro machine:
        # AllowTelemetry=0 was present and diagnostics still uploaded. Sophia-Script gates this
        # the same way; winutil / Win11Debloat / Sycnex all write 0 unconditionally.
        $edition = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID' -ErrorAction SilentlyContinue).EditionID
        $telemetryMax = if ($edition -match 'Enterprise|Education|Server') { 0 } else { 1 }
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
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = $telemetryMax; Type = 'DWord';
               Why = "telemetry at the strictest level this SKU honours ($edition -> $telemetryMax)" }
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

            # --- safety nets, not perf -------------------------------------------------
            # These three come from Sophia-Script / Bloatynosy and are the "make the machine
            # recoverable" half of the tune phase. Each was measured absent on a real machine.
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'; Name = 'EnablePeriodicBackup'; Value = 1; Type = 'DWord';
               Why = 'attempt periodic registry hive backup; MEASURED no-op on Win11 26xxx (empty RegIdleBackup, SIT gone) - the restore point is the real undo' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker'; Name = 'PreventDeviceEncryption'; Value = 1; Type = 'DWord';
               Why = 'block FUTURE automatic device encryption; never touches volumes that are already encrypted' }

            # --- network politeness -----------------------------------------------------
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'; Name = 'DODownloadMode'; Value = 1; Type = 'DWord';
               Why = 'update delivery stays on the LAN instead of uploading to the internet' }

            # --- disk housekeeping ------------------------------------------------------
            # Storage Sense is on by default but only for temp files. Recycle-bin cleanup is
            # opt-in. The downloads rule is deliberately NOT enabled: auto-deleting files from
            # the Downloads folder can eat a user's installer, and the saving is trivial.
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; Name = '08'; Value = 1; Type = 'DWord';
               Why = 'Storage Sense empties the recycle bin' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; Name = '32'; Value = 30; Type = 'DWord';
               Why = 'recycle bin retention: 30 days' }            # --- attack surface & device hygiene (from winutil / Winhance, verified in their source) ---
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; Name = 'DisableWpbtExecution'; Value = 1; Type = 'DWord';
               Why = 'blocks OEM firmware-injected executables at boot (WPBT); nothing legitimate on this machine uses it' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'; Name = 'PreventDeviceMetadataFromNetwork'; Value = 1; Type = 'DWord';
               Why = 'stops "install this app" payloads when a monitor/printer is plugged in' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'; Name = 'BackupCount'; Value = 2; Type = 'DWord';
               Why = 'keeps two generations of registry hive backups instead of one (only meaningful together with EnablePeriodicBackup)' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name = 'GlobalUserDisabled'; Value = 1; Type = 'DWord';
               Why = 'Store apps cannot run in the background; foreground use is unaffected' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-310093Enabled'; Value = 0; Type = 'DWord';
               Why = 'no "what is new after the update" splash; distinct from the 338388/338389/353698 campaign IDs' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'; Name = 'LockScreenToastEnabled'; Value = 0; Type = 'DWord';
               Why = 'no notification content on the lock screen' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'; Name = 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK'; Value = 0; Type = 'DWord';
               Why = 'same switch, per-user notification setting scope' }            # --- privacy surfaces (from Win11Debloat / Sophia / Bloatynosy, paths read in their .reg files) ---
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0; Type = 'DWord';
               Why = 'removes the per-user advertising ID used to correlate apps' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Value = 0; Type = 'DWord';
               Why = 'no personalised tips derived from diagnostic data' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Value = 0; Type = 'DWord';
               Why = 'no timeline activity upload (policy scope)' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Value = 0; Type = 'DWord';
               Why = 'timeline feed off; same policy family as PublishUserActivities' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'; Name = 'AllowInputPersonalization'; Value = 0; Type = 'DWord';
               Why = 'typing/inking data is not sent for personalisation' }
            @{ Path = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; Name = 'HasAccepted'; Value = 0; Type = 'DWord';
               Why = 'cloud speech recognition consent withdrawn (local speech still works)' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'StartupBoostEnabled'; Value = 0; Type = 'DWord';
               Why = 'Edge stops keeping preloaded processes resident after boot; first launch is slower' }            # --- shell & device behaviour (Winhance GamingAndPerformance / Taskbar / Explorer, read in source) ---
            @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Value = 1; Type = 'DWord';
               Why = 'Game Mode on: Windows suppresses background work and keeps game threads scheduled; default is already 1, this pins it' }
            # MEASURED: the Dsh (Widgets) policy keys are ACL-locked on this machine - owner is
            # BUILTIN\Administrators but the interactive user holds ReadKey only, and both
            # `reg add HKCU\...\Dsh` and `reg add HKLM\...\Dsh` return "Access is denied" even
            # from an elevated prompt (a security product likely guards the path). A write that
            # cannot land must not be attempted and then reported as a tweak - it is documented
            # under the manual-items section of docs/03-system-tweaks.md instead.
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'ShowCloudFilesInQuickAccess'; Value = 0; Type = 'DWord';
               Why = 'Quick Access stops querying Office.com cloud files (clutter + a cloud call on every Explorer open)' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'; Name = 'LegacyDefaultPrinterMode'; Value = 1; Type = 'DWord';
               Why = 'Windows stops silently switching the default printer to the "last used" one' }
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
        # Build gating. A rule that is right on one Windows build can be a no-op or harmful on
        # another - measured: the periodic registry backup is dead on 26xxx, and the telemetry
        # scheduled-task list differs per build. Rules may declare MinBuild / MaxBuild, and the
        # skipped ones are named so that silence in the log always has an explanation.
        $approved = New-Object System.Collections.Generic.List[object]
        $skippedByBuild = New-Object System.Collections.Generic.List[string]
        foreach ($c in $changes) {
            if (-not (Test-BuildGate -Build $osBuildNumber -MinBuild $c.MinBuild -MaxBuild $c.MaxBuild)) {
                $why = if ($c.MinBuild) { "needs build $($c.MinBuild)+" } else { "build $($c.MaxBuild) or older only" }
                $skippedByBuild.Add("$($c.Name) ($why)")
                continue
            }
            if ($PSCmdlet.ShouldProcess("$($c.Path)\$($c.Name)", "set $($c.Value) - $($c.Why)")) { $approved.Add($c) }
        }
        if ($skippedByBuild.Count) { Warn "skipped by build gate: $($skippedByBuild -join '; ')" }

        # Previous state, captured BEFORE any write, so the undo script can restore what this
        # machine actually had rather than a guessed Microsoft default.
        $previousState = @{}
        foreach ($prevKey in @($approved | ForEach-Object { $_.Path } | Sort-Object -Unique)) {
            $previousState[$prevKey] = Get-ItemProperty -Path $prevKey -ErrorAction SilentlyContinue
        }

        # Group by key: a .reg file is written as [key] sections followed by their values.
        $byKey = [ordered]@{}
        foreach ($c in $approved) {
            if (-not $byKey.Contains($c.Path)) { $byKey[$c.Path] = New-Object System.Collections.Generic.List[object] }
            $byKey[$c.Path].Add($c)
        }

        # ConvertTo-RegDword now lives in lib/tune-core.ps1 (covered by test-tune-core.ps1).


        $regLines = New-Object System.Collections.Generic.List[string]
        $regLines.Add('Windows Registry Editor Version 5.00')
        foreach ($k in $byKey.Keys) {
            $regKey = $k -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU:\\', 'HKEY_CURRENT_USER\'
            $regLines.Add('')
            $regLines.Add("[$regKey]")
            foreach ($c in $byKey[$k]) {
                # NOTE THE EXTRA PARENTHESES. A method call splits its argument list on
                # commas BEFORE the -f operator is applied:
                #     $list.Add('"{0}"=dword:{1}' -f $c.Name, $hex)
                # parses as Add( ('...{0}...{1}' -f $c.Name), $hex ) - the format string gets
                # ONE argument while the template references {1}, and the whole script dies
                # with "Error formatting a string: Index (zero based) must be greater than or
                # equal to zero and less than the size of the argument list."
                # That is a terminating error, so the tune phase aborted right after the
                # snapshot and NOT A SINGLE registry value was written - while the only
                # visible symptom was that error text. Parenthesising the -f expression keeps
                # the comma inside it.
                if ($c.Type -eq 'DWord') {
                    $line = ('"{0}"=dword:{1}' -f $c.Name, (ConvertTo-RegDword $c.Value))
                    $regLines.Add($line)
                }
                else {
                    $line = ('"{0}"="{1}"' -f $c.Name, ("$($c.Value)" -replace '"', '\"'))
                    $regLines.Add($line)
                }
            }
        }
        $regFile = Join-Path $env:TEMP ('dsh-tune-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.reg')
        # A .reg file must be UTF-16LE ("Unicode") or reg.exe rejects it.
        $regLines -join "`r`n" | Set-Content -Path $regFile -Encoding Unicode
        # Under -WhatIf nobody is approved, so there is no .reg to import - and Set-Content
        # itself honours -WhatIf, meaning the temp file was never created. Running reg.exe
        # anyway made the PREVIEW print "FAIL reg import: ERROR: Error opening the file":
        # a failure invented by the dry-run path. Skip the import in that mode.
        $importOut = @()
        $importCode = 0
        if (-not $WhatIfPreference) {
            $importOut = & reg.exe import $regFile 2>&1
            $importCode = $LASTEXITCODE
        }
        Remove-Item $regFile -Force -ErrorAction SilentlyContinue
        if ($importCode -ne 0) { $importOut | ForEach-Object { Bad "reg import: $_" } }

        # ------------------------------------------------------------------ read back
        # Read each KEY once, not each value. Measured: 30 x (Get-ItemProperty -Name) =
        # 154 ms versus one read per key = 4 ms. A write returning success is not evidence;
        # this is the evidence.
        #
        # PER-VALUE FALLBACK, measured on Windows 11 26xxx. `reg import` reports
        # "The operation completed successfully" (exit 0) and yet silently creates NOTHING under
        # at least HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager - even a
        # brand-new value name that exists nowhere was dropped, while `reg add` and
        # Set-ItemProperty both wrote the same value successfully in the same session.
        # Two of the tune values live in that key, so the phase used to report 2 failures that
        # nothing explained. Rather than distrust the batch entirely (it is 8x faster), retry a
        # value that did not land using the registry provider, then re-read it.
        # PRESENCE IS THE WRONG PREDICATE FOR A TUNE. A tune's whole point is to set a value to
        # a SPECIFIC number; "the value exists" says nothing about that. Measured on this
        # machine: StoragePolicy\32 was already 0 and AllowTelemetry was already 0 from an
        # earlier run, so a presence-only read-back counted both as applied, the direct-write
        # fallback below never fired, and verify-env then reported
        #   recycle retention: actual=0 want=30
        #   telemetry policy : actual=0 want=1
        # with no failure logged by tune at all. Compare the VALUE, and normalize first:
        # 0xffffffff / -1 / 4294967295 are the same DWORD, and a DWORD read back by
        # Get-ItemProperty can come back as either Int32 or UInt32.
        function Test-TuneValue {
            param($Actual, $Wanted)
            if ($null -eq $Actual) { return $false }
            if ("$Actual" -eq "$Wanted") { return $true }
            $a = $null; $w = $null
            try { $a = [int64]$Actual } catch { }
            try { $w = [int64]$Wanted } catch { }
            if (($null -ne $a) -and ($null -ne $w)) {
                if ($a -lt 0) { $a += 4294967296 }
                if ($w -lt 0) { $w += 4294967296 }
                return ($a -eq $w)
            }
            return $false
        }

        $applied = 0; $failed = 0; $recovered = New-Object System.Collections.Generic.List[string]
        foreach ($k in $byKey.Keys) {
            $props = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
            foreach ($c in $byKey[$k]) {
                $ok = ($null -ne $props) -and (Test-TuneValue $props.($c.Name) $c.Value)
                if (-not $ok -and -not $WhatIfPreference) {
                    try {
                        Set-ItemProperty -Path $k -Name $c.Name -Value $c.Value -Type $c.Type -ErrorAction Stop
                        $recheck = Get-ItemProperty -Path $k -Name $c.Name -ErrorAction SilentlyContinue
                        if (($null -ne $recheck) -and (Test-TuneValue $recheck.($c.Name) $c.Value)) {
                            $ok = $true
                            $recovered.Add("$k\$($c.Name)")
                        }
                    }
                    catch { }
                }
                if ($ok) { $applied++ }
                else { $failed++; Bad "$k\$($c.Name): still not the wanted value after reg import AND a direct write (want $($c.Value))" }
            }
        }
        if ($recovered.Count -gt 0) {
            Warn "reg import silently skipped $($recovered.Count) value(s); written directly instead: $($recovered -join ', ')"
        }

        # Per-item undo: one entry per value that ended up applied, restoring the captured
        # previous value (or removing the value again when it did not exist before).
        if (-not $WhatIfPreference) {
            foreach ($c in $approved) {
                $prev = $previousState[$c.Path]
                $hadPrev = ($null -ne $prev) -and ($null -ne $prev.($c.Name))
                $pathLit = "'" + ($c.Path -replace "'", "''") + "'"
                $nameLit = "'" + ($c.Name -replace "'", "''") + "'"
                if ($hadPrev) {
                    $oldVal = $prev.($c.Name)
                    $oldType = if ($oldVal -is [int] -or $oldVal -is [long]) { 'DWord' } else { 'String' }
                    $revert = "Set-ItemProperty -Path $pathLit -Name $nameLit -Value $(Format-UndoValue $oldVal $oldType) -Type $oldType"
                }
                else {
                    $revert = "Remove-ItemProperty -Path $pathLit -Name $nameLit -ErrorAction SilentlyContinue"
                }
                Add-Undo -What "registry: $($c.Path)\$($c.Name) - $($c.Why)" -Revert $revert
            }
        }
        if ($WhatIfPreference) {
            # The preview must say how many values WOULD change. Under -WhatIf nobody is
            # approved, so the old summary read "applied 0 registry change(s)" - which looks
            # like "there is nothing to do" instead of "12 values would be set".
            $keyCount = @($changes | ForEach-Object { $_.Path } | Sort-Object -Unique).Count
            Warn ("WhatIf: {0} registry value(s) across {1} key(s) would be set; nothing written" -f $changes.Count, $keyCount)
        } else {
            Ok "applied $applied registry change(s), $failed failed (verified by reading each key back)"
        }

        # MMCSS is a KERNEL DRIVER: every MMCSS value above is INERT while it is stopped, and
        # the registry still looks perfectly correct. Measured: installing a graphics driver
        # stopped it, and it then could NOT be started on demand ("StartService failed 2:
        # the system cannot find the file" even though mmcss.sys is present and intact) - it
        # is boot-loaded, so only a reboot brings it back. Report the real state, do not
        # assume the writes took effect.
        #
        # sc.exe is an external tool, so it needs its own ShouldProcess guard: -WhatIf must be
        # a real dry run, not "the registry writes were skipped but the service was configured".
        if ($PSCmdlet.ShouldProcess('MMCSS service', 'set start= auto and start it')) {
            & sc.exe config MMCSS start= auto 2>&1 | Out-Null
            & sc.exe start MMCSS 2>&1 | Out-Null
            Start-Sleep -Seconds 2
        }
        else {
            Write-Host '     would set MMCSS to start= auto and start it (no change made)' -ForegroundColor Cyan
        }
        $mmcssLine = ((& sc.exe query MMCSS 2>&1 | Select-String 'STATE') -join ' ').Trim()
        if ($WhatIfPreference) {
            Write-Host "     MMCSS current state: $(if ($mmcssLine) { $mmcssLine } else { '(unreadable)' }) - -WhatIf did not touch it" -ForegroundColor Cyan
        }
        if ($mmcssLine -match 'RUNNING') {
            Ok 'MMCSS RUNNING - the SystemProfile / Tasks\Games values are actually in effect'
        }
        else {
            Warn "MMCSS is NOT running ($mmcssLine) - every MMCSS value above is INERT."
            Warn '  it is a boot-loaded kernel driver and cannot be started on demand: REBOOT,'
            Warn '  then confirm with  sc query MMCSS  and re-run -Phase tune if values are gone'
        }

        # ------------------------------------------------------------------ post-write
        # Win11 hides the classic context menu behind a shell extension. An EMPTY default
        # value on its InprocServer32 disables that extension, which restores the old menu.
        # It is kept out of the .reg batch above on purpose: the batch's read-back looks up
        # named values, and a default value cannot be read that way.
        $ctxKey = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
        if ($PSCmdlet.ShouldProcess($ctxKey, 'set default "" - restore the classic context menu')) {
            $ctxExisted = Test-Path -LiteralPath $ctxKey
            $ctxPrev = if ($ctxExisted) { (Get-ItemProperty -Path $ctxKey -ErrorAction SilentlyContinue).'(default)' } else { $null }
            New-Item -Path $ctxKey -Force | Out-Null
            Set-ItemProperty -Path $ctxKey -Name '(default)' -Value '' -Type String
            if ((Get-ItemProperty -Path $ctxKey -ErrorAction SilentlyContinue).'(default)' -eq '') {
                Ok 'classic context menu enabled (takes effect after Explorer restarts)'
                # The override key did not exist on a stock Win11 install, so reverting means
                # deleting the whole key - not writing an empty string back into it.
                if ($ctxExisted) {
                    Add-Undo -What 'classic context menu: restore the previous InprocServer32 default' `
                        -Revert ("Set-ItemProperty -Path '$ctxKey' -Name '(default)' -Value '" + ("$ctxPrev" -replace "'", "''") + "' -Type String")
                }
                else {
                    Add-Undo -What 'classic context menu: remove the CLSID override key' `
                        -Revert ("Remove-Item -Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force -ErrorAction SilentlyContinue")
                }
            }
            else { Bad 'classic context menu: default value is not empty after the write' }
        }

        # Registry periodic backup: the task exists on every install, but it only does anything
        # once EnablePeriodicBackup above is set, and some debloat scripts disable it outright.
        #
        # MEASURED LIMIT, Windows 11 26xxx: this build ships RegIdleBackup as an EMPTY SHELL -
        # State=Ready but zero triggers and zero actions - and the SIT service that used to do the
        # copying no longer exists. After a reboot AND after Start-ScheduledTask, the hives in
        # %SystemRoot%\System32\config\RegBack were still 0 bytes. So the switch is written (it is
        # correct and harmless on builds where it works), but it is NOT reported as a working
        # safety net. The real undo path on such a build is the restore point created earlier.
        $regTaskPath = '\Microsoft\Windows\Registry\'
        $regTask = Get-ScheduledTask -TaskPath $regTaskPath -TaskName 'RegIdleBackup' -ErrorAction SilentlyContinue
        if ($regTask) {
            if ($PSCmdlet.ShouldProcess('RegIdleBackup', 'enable scheduled registry hive backup')) {
                if ($regTask.State -eq 'Disabled') { Enable-ScheduledTask -TaskPath $regTaskPath -TaskName 'RegIdleBackup' | Out-Null }
                $regBackBytes = 0
                $regBackDir = Join-Path $env:SystemRoot 'System32\config\RegBack'
                if (Test-Path $regBackDir) {
                    $regBackBytes = @(Get-ChildItem $regBackDir -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    if ($null -eq $regBackBytes) { $regBackBytes = 0 }
                }
                if ($regBackBytes -gt 1MB) {
                    Ok "registry hive backup: hives present ($([math]::Round($regBackBytes/1MB,1)) MB)"
                }
                else {
                    # CORRECTED after a longer measurement window: this is NOT a permanent no-op.
                    # Right after enabling (and right after a manual Start-ScheduledTask) RegBack
                    # held 0-byte files, which looked conclusive. Two days and two reboots later
                    # the same folder held 110 MB of real hives - Windows fills RegBack at a later
                    # boot/idle point, not on demand. So: warn that it is not filled YET, and keep
                    # the restore point as the guaranteed undo path in the meantime.
                    Warn "registry hive backup not populated yet ($regBackBytes byte(s)) - Windows fills"
                    Warn '  RegBack at a later boot/idle point, not on demand. Measured: 0 bytes right'
                    Warn '  after enabling, 110 MB two days later. Until it fills, the restore point'
                    Warn '  created earlier in this phase is the guaranteed undo path.'
                }
            }
        }
        else { Warn 'RegIdleBackup task not present on this build - registry backups will not run' }

        # Telemetry scheduled tasks. TWO rules learned from reading these projects' code:
        #  1. The list is build-dependent. On the machine this was written on, "Microsoft
        #     Compatibility Appraiser" and "ProgramDataUpdater" DO NOT EXIST any more, so a
        #     hardcoded list must test for existence or the whole run throws.
        #  2. A full path passed as -TaskName does not resolve (W4RH4WK's script does this and
        #     silently no-ops). -TaskPath and -TaskName are separate parameters.
        $telemetryTasks = @(
            @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' }
            @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater' }
            @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'StartupAppTask' }
            @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' }
            @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' }
            @{ Path = '\Microsoft\Windows\DiskDiagnostic\'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
            @{ Path = '\Microsoft\Windows\Autochk\'; Name = 'Proxy' }
        )
        $telSeen = 0; $telOff = 0; $telMissing = 0
        foreach ($t in $telemetryTasks) {
            $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
            if (-not $task) { $telMissing++; continue }
            $telSeen++
            if ($t.Name -and $PSCmdlet.ShouldProcess($t.Name, 'disable telemetry task')) {
                $wasEnabled = ($task.State -ne 'Disabled')
                if ($wasEnabled) { Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue | Out-Null }
                if ((Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name).State -eq 'Disabled') {
                    $telOff++
                    if ($wasEnabled) {
                        Add-Undo -What "telemetry task: $($t.Name)" `
                            -Revert ("Enable-ScheduledTask -TaskPath '$($t.Path)' -TaskName '$($t.Name)' -ErrorAction SilentlyContinue | Out-Null")
                    }
                }
            }
        }
        if ($WhatIfPreference) { Warn "WhatIf: $telSeen telemetry task(s) present, would disable them ($telMissing not in this build)" }
        elseif ($telSeen -eq 0) { Warn 'no known telemetry scheduled tasks on this build' }
        else { Ok "telemetry tasks: $telOff/$telSeen disabled ($telMissing not present on this build)" }

        # DiagTrack egress blocked by FIREWALL GROUP rather than by deleting rules: the group
        # can be flipped back to Allow, a deleted rule cannot be un-deleted.
        if ($PSCmdlet.ShouldProcess('firewall group DiagTrack', 'block')) {
            $diagRules = @(Get-NetFirewallRule -Group 'DiagTrack' -ErrorAction SilentlyContinue)
            if ($diagRules.Count -gt 0) {
                # Record EVERY rule's own state first. A blanket "set the whole group back to
                # Enabled+Allow" invents a state that never existed: the group ships with a mix
                # of enabled/disabled rules and of Allow/Block actions, so undoing that way
                # leaves the machine in a third state that is neither before nor after.
                $diagBefore = @($diagRules | ForEach-Object {
                    [pscustomobject]@{
                        Name    = [string]$_.Name
                        Enabled = [string]$_.Enabled
                        Action  = [string]$_.Action
                    }
                })
                $diagRules | Set-NetFirewallRule -Enabled True -Action Block -ErrorAction SilentlyContinue
                $blocked = @(Get-NetFirewallRule -Group 'DiagTrack' -ErrorAction SilentlyContinue | Where-Object { $_.Action -eq 'Block' -and $_.Enabled -eq 'True' })
                Ok "DiagTrack firewall: $($blocked.Count)/$($diagRules.Count) rule(s) blocked (per-rule state recorded for rollback)"
                $diagUndo = @($diagBefore | ForEach-Object {
                    "Set-NetFirewallRule -Name '$($_.Name)' -Enabled $($_.Enabled) -Action $($_.Action) -ErrorAction SilentlyContinue | Out-Null"
                }) -join '; '
                Add-Undo -What "diagtrack firewall: restore $($diagBefore.Count) rule(s) to their own previous Enabled/Action" `
                    -Revert $diagUndo
            }
            else { Warn 'no DiagTrack firewall group on this build' }
        }

        if ($HighPerformancePowerPlan) {
            if ($PSCmdlet.ShouldProcess('power plan', 'switch to High performance')) {
                & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
                Ok 'power plan: High performance (costs battery life)'
            }
        }
        else { Warn 'power plan left as-is (pass -HighPerformancePowerPlan to switch)' }

        # Sleep on a desktop / mini PC. Opt-in, because it is a genuine tradeoff: the machine
        # stays powered, but it also stops failing to come back.
        #
        # MEASURED REASON: five sleep cycles in five days on a mini PC looked like this -
        #   Id=187 "wake source could not be identified" -> 42 enter sleep -> 107 resume (2-4 s
        #   later) -> hours of S0 modern standby -> 507 exit modern standby.
        # One of those standby periods never produced a 507 at all: the display stayed black and
        # the owner force-powered the machine off, which Windows then logged as Id=41 + 6008
        # ("unexpected shutdown"). No crash dump, no WHEA, no app hang - i.e. it was not a bug,
        # the machine simply never woke from S0.
        # Disabling the sleep timer (not the display timer) removes that failure class entirely.
        if ($DisableSleepOnAC) {
            if ($PSCmdlet.ShouldProcess('power timeouts', 'disable sleep/hibernate on AC power (display timeout kept)')) {
                # Read the AC index WITHOUT matching the label: powercfg prints localized
                # text (the AC index line is translated on non-English Windows), and this script
                # must stay ASCII-only. The AC and DC index lines are the LAST two hex lines,
                # AC first, so take that pair positionally - locale-independent.
                $acIndex = {
                    param($sub, $setting)
                    $out = (powercfg /query SCHEME_CURRENT $sub $setting 2>&1 | Out-String) -split "`n"
                    $hex = @($out | Where-Object { $_ -match '0x[0-9a-fA-F]{8}' })
                    if ($hex.Count -ge 2) {
                        $pair = $hex[($hex.Count - 2)..($hex.Count - 1)]
                        if ($pair[0] -match '0x([0-9a-fA-F]{8})') { return [Convert]::ToInt32($Matches[1], 16) }
                    }
                    return -1
                }
                # Two separate values are changed below, so TWO separate originals are recorded.
                # Recording only the standby timeout (as this did before) meant an undo restored
                # sleep and silently left hibernate at 0 - a state the machine was never in.
                $prevSleepSec = & $acIndex 'SUB_SLEEP' 'STANDBYIDLE'
                $prevHibSec = & $acIndex 'SUB_SLEEP' 'HIBERNATEIDLE'
                & powercfg /change standby-timeout-ac 0 | Out-Null
                & powercfg /change hibernate-timeout-ac 0 | Out-Null
                $slpSec = & $acIndex 'SUB_SLEEP' 'STANDBYIDLE'
                $hibSec = & $acIndex 'SUB_SLEEP' 'HIBERNATEIDLE'
                $dispSec = & $acIndex 'SUB_VIDEO' 'VIDEOIDLE'
                if ($slpSec -eq 0) {
                    Ok "sleep disabled on AC (display still turns off after $dispSec s; hibernate timeout now $hibSec s)"
                    if ($prevSleepSec -ge 0) {
                        Add-Undo -What "power: restore AC sleep timeout to $prevSleepSec s" `
                            -Revert ("powercfg /change standby-timeout-ac $([int]($prevSleepSec / 60))")
                    }
                    else { Warn 'sleep: the original AC standby timeout could not be read - this item is NOT fully revertable' }
                    if ($prevHibSec -ge 0) {
                        Add-Undo -What "power: restore AC hibernate timeout to $prevHibSec s" `
                            -Revert ("powercfg /change hibernate-timeout-ac $([int]($prevHibSec / 60))")
                    }
                    else { Warn 'hibernate: the original AC hibernate timeout could not be read - this item is NOT fully revertable' }
                }
                else { Warn "sleep timeout is still $slpSec s - -DisableSleepOnAC did not take effect" }
            }
        }
        else { Warn 'sleep left as-is (pass -DisableSleepOnAC on a desktop/mini PC that fails to wake)' }

        if (-not $DisableMouseAcceleration) { Warn 'mouse acceleration left as-is (pass -DisableMouseAcceleration to zero it)' }

        # Per-item undo script, written next to the snapshot so it travels with the rollback
        # material. The restore point stays as the coarse net; this is the scalpel.
        # It is read back, not assumed: a tune phase whose undo script is empty or missing has
        # silently lost its per-item rollback, and that must show up as a failed phase.
        if (-not $WhatIfPreference) {
            $undoPath = Write-UndoScript -Dir $SnapshotDir
            $undoOk = $false
            if ($undoPath -and (Test-Path -LiteralPath $undoPath)) {
                $undoSize = (Get-Item -LiteralPath $undoPath).Length
                $undoText = Get-Content -LiteralPath $undoPath -Raw -ErrorAction SilentlyContinue
                $undoOk = ($undoSize -gt 0) -and ($undoText -match '(?m)^# Revert script generated by') -and ($undoText -match '\$failed = 0') -and ($script:undoEntries.Count -gt 0)
                if ($undoOk) { Ok "per-item undo script: $undoPath ($($script:undoEntries.Count) item(s), $undoSize bytes)" }
                else { Bad "undo script at $undoPath failed read-back ($undoSize bytes, $($script:undoEntries.Count) recorded item(s))"; $failed++ }
            }
            else {
                # Nothing applied is legitimate; anything applied without an undo script is not.
                if ($script:undoEntries.Count -gt 0) {
                    Bad "no undo script written although $($script:undoEntries.Count) change(s) were applied"
                    $failed++
                }
                else { Warn 'no undo script written (nothing was applied)' }
            }
        }

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

    # The baseline drift check needs a snapshot, and only `tune` creates one. A machine where
    # verify runs on its own (no snapshot yet) used to lose this check silently: the call's
    # result was piped to Out-Null, so a missing snapshot printed FAIL inside the step and
    # then vanished from the phase table and from the exit code. Check for the file first and
    # say so plainly; feed the real result into Record when it does run.
    $driftOk = $true
    $snapCsv = Join-Path $SnapshotDir 'services-snapshot.csv'
    if (Test-Path $snapCsv) {
        $driftOk = Invoke-Step 'compare-services.ps1' @('-Snapshot', $snapCsv) 'service baseline drift'
    }
    else {
        Step 'service baseline drift'
        Warn "no snapshot at $snapCsv - skipping"
        Warn '  run -Phase tune once (it snapshots before changing anything), or point -SnapshotDir at an existing snapshot'
    }

    Record 'verify' ($a -and $b -and $c -and $driftOk) 'dev/apps/ime/service-drift'
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
if ($script:logFile) {
    Write-Host ''
    Write-Host "log: $($script:logFile)" -ForegroundColor DarkGray
    try { Stop-Transcript | Out-Null } catch { }
}
exit $fail