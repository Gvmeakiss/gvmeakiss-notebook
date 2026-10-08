<#
.SYNOPSIS
  One entry point that turns a fresh Windows box into an AI-development + gaming machine.

.DESCRIPTION
  Everything in this skill hangs off this script. Phases run in order:

    check    prerequisites - elevation, scoop, git, 7-Zip, network, free space
    dev      dev toolchain via Scoop (languages + build tools + domestic mirrors),
             then PATH / Store-stub repair
    apps     portable apps from apps.json (SHA256 verified, no elevation needed),
             unpacked under the portable root
    tune     snapshot the system first, then apply the small SAFE tweak set
             (GameDVR off, MMCSS latency) - never disables a service, never touches UAC
    link     file associations: register the apps so Windows offers them, and report
             which types still need one manual click (defaults are OS-protected)
    verify   acceptance run: dev env, apps present, input method healthy, baseline drift

  Design rules, learned the hard way (see SKILL.md):
    * never disable a service from here - demand-start services cost nothing and break things
    * take a snapshot before touching the system, so "changed" and "was always like that" differ
    * after any service/tweak change, reboot before believing the result
    * a command returning success is not evidence; read the state back

.PARAMETER Phase
  check | dev | apps | tune | link | verify | all      (default: all)

.PARAMETER Manifest
  Portable app manifest. Default: apps.json in the skill root.

.PARAMETER Destination
  Portable app root. Default: $env:USERPROFILE\Apps

.PARAMETER SnapshotDir
  Where the pre-tweak snapshot goes. Default: <Destination>\_backup

.PARAMETER Languages
  Scoop packages for the dev phase. Default: python,node,go,cmake,dotnet,mingw

.PARAMETER HighPerformancePowerPlan
  Optional, off by default: switch the active power plan to High performance.
  Left off because it costs battery life on a laptop.

.PARAMETER RegisterAssociations
  In the link phase, actually write the HKCU association entries (user-level only).

.PARAMETER SkipTweaks
  Take the snapshot but apply no tweaks.

.PARAMETER Help
  Show this help.

.EXAMPLE
  pwsh -File scripts/setup.ps1                      # everything, in order
  pwsh -File scripts/setup.ps1 -Phase check         # just the prerequisite report
  pwsh -File scripts/setup.ps1 -Phase dev,apps      # dev toolchain + portable apps
  pwsh -File scripts/setup.ps1 -Phase tune -WhatIf  # preview the tweaks
  pwsh -File scripts/setup.ps1 -Phase verify

.NOTES
  ASCII-only on purpose. Requires Windows + PowerShell 7+.
  Only the dev phase needs elevation (Scoop is user-level, but some installers are not).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('check', 'dev', 'apps', 'tune', 'link', 'verify', 'all')]
    [string[]]$Phase = @('all'),
    [string]$Manifest,
    [string]$Destination = (Join-Path $env:USERPROFILE 'Apps'),
    [string]$SnapshotDir,
    [string[]]$Languages = @('python', 'node', 'go', 'cmake', 'dotnet', 'mingw'),
    [switch]$HighPerformancePowerPlan,
    [switch]$RegisterAssociations,
    [switch]$SkipTweaks,
    [switch]$Help
)

if ($Help) { Get-Help $PSCommandPath -Detailed; return }

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot

# Rebuild PATH from the registry: a stale parent environment must not decide what is installed.
$env:PATH = (@(
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) | Where-Object { $_ }) -join ';'

function Say { param([string]$M, [string]$C = 'Gray') Write-Host $M -ForegroundColor $C }
function Step { param([string]$M) Write-Host "  -> $M" -ForegroundColor Cyan }
function Ok { param([string]$M) Write-Host "     ok    $M" -ForegroundColor Green }
function Warn { param([string]$M) Write-Host "     WARN  $M" -ForegroundColor Yellow }
function Bad { param([string]$M) Write-Host "     FAIL  $M" -ForegroundColor Red }

$results = New-Object System.Collections.Generic.List[object]
function Record { param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $script:results.Add([pscustomobject]@{ Phase = $Name; Result = $(if ($Ok) { 'PASS' } else { 'FAIL' }); Detail = $Detail })
}
function Script-Path { param([string]$Name) Join-Path $here $Name }
function Invoke-Step { param([string]$File, [string[]]$Args, [string]$What)
    $p = Script-Path $File
    if (-not (Test-Path $p)) { Bad "$File not found"; return $false }
    Step $What
    $out = & pwsh -NoProfile -File $p @Args 2>&1
    $code = $LASTEXITCODE
    $out | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
    if ($code -ne 0) { Warn "$File exited with $code" }
    return ($code -eq 0)
}

$phases = if ($Phase -contains 'all') { @('check', 'dev', 'apps', 'tune', 'link', 'verify') } else { $Phase }
if (-not $Manifest) { $Manifest = Join-Path (Split-Path $here -Parent) 'apps.json' }
if (-not $SnapshotDir) { $SnapshotDir = Join-Path $Destination '_backup' }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ''
Write-Host '===== win-ai-gaming-setup =====' -ForegroundColor White
Write-Host "  phases      : $($phases -join ', ')"
Write-Host "  apps root   : $Destination"
Write-Host "  manifest    : $Manifest"
Write-Host "  elevated    : $isAdmin"
if ($WhatIfPreference) { Warn 'WhatIf: nothing will be changed' }
Write-Host ''

# ------------------------------------------------------------------ check
if ($phases -contains 'check') {
    Say '--- check: prerequisites ---' White
    $okAll = $true

    foreach ($cmd in 'scoop', 'git', '7z') {
        $c = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($c) { Ok "$cmd found ($($c.Source))" } else { Warn "$cmd missing - the dev/apps phases need it"; if ($cmd -ne '7z') { $okAll = $false } }
    }
    if (-not (Get-Command '7z' -ErrorAction SilentlyContinue)) {
        Warn 'no 7z: zip archives still install, but the .7z app asset will not extract'
    }
    if ($isAdmin) { Ok 'elevated: machine-level tweaks are possible' } else { Warn 'not elevated: run as administrator for the dev/tune phases' }

    $net = Test-Connection -ComputerName 'github.com' -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($net) { Ok 'github.com reachable' } else { Warn 'github.com not reachable - mirrors or a proxy are needed'; $okAll = $false }

    $drive = (Get-Item $env:USERPROFILE).PSDrive
    $freeGB = [math]::Round((Get-PSDrive $drive.Name).Free / 1GB, 1)
    if ($freeGB -ge 20) { Ok "free space on $($drive.Name): $freeGB GB" } else { Warn "only $freeGB GB free - the toolchain plus apps want ~15 GB"; $okAll = $false }

    $wu = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue)
    Ok "windows build $($wu.CurrentBuild).$($wu.UBR) (judge patch level by UBR, not Get-HotFix)"

    Record 'check' $okAll "scoop/git/network/disk"
}

# ------------------------------------------------------------------ dev
if ($phases -contains 'dev') {
    Say '--- dev: toolchain + PATH repair ---' White
    # A brand-new box has no Scoop. Installing it is user-level (no elevation) and is the
    # only way the rest of this phase can work.
    if (-not (Get-Command 'scoop' -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess('Scoop', 'install from the official script (user-level)')) {
            Step 'scoop missing - installing it (user-level, no elevation)'
            try {
                Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
                Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
                $env:PATH = (@(
                        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
                        [Environment]::GetEnvironmentVariable('Path', 'User')
                    ) | Where-Object { $_ }) -join ';'
                if (Get-Command 'scoop' -ErrorAction SilentlyContinue) { Ok 'scoop installed' }
                else { Bad 'scoop installed but not on PATH yet - open a new terminal and re-run this phase' }
            }
            catch { Bad "scoop install failed: $($_.Exception.Message)" }
        }
    }
    else { Ok 'scoop already present' }
    $a = Invoke-Step 'setup-langs.ps1' @('-Packages', ($Languages -join ',')) "scoop packages: $($Languages -join ', ')"
    $b = Invoke-Step 'fix-env.ps1' @() 'repair PATH, Store stubs, credential helper'
    Record 'dev' ($a -and $b) 'languages + PATH'
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
        $b = Invoke-Step 'check-software.ps1' @('-PortableRoot', $Destination) 'inventory'
        Record 'apps' $a 'portable apps installed'
    }
}

# ------------------------------------------------------------------ tune
if ($phases -contains 'tune') {
    Say '--- tune: snapshot, then the safe set only ---' White
    New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null
    $a = Invoke-Step 'snapshot-services.ps1' @('-OutDir', $SnapshotDir) 'snapshot before touching anything'

    if ($SkipTweaks) {
        Warn 'SkipTweaks: snapshot taken, no tweak applied'
        Record 'tune' $a 'snapshot only'
    }
    else {
        $okAll = $a
        # 1) GameDVR off - pure gaming win, no functional loss
        if ($PSCmdlet.ShouldProcess('GameDVR', 'disable (policy + user)')) {
            New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Ok 'GameDVR disabled (background recording costs frames)'
        }
        # 2) MMCSS - give the game thread priority, no service touched
        if ($PSCmdlet.ShouldProcess('MMCSS', 'SystemResponsiveness=10, NetworkThrottlingIndex=off')) {
            $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Set-ItemProperty $mm -Name 'SystemResponsiveness' -Value 10 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty $mm -Name 'NetworkThrottlingIndex' -Value 0xffffffff -Type DWord -ErrorAction SilentlyContinue
            Ok 'MMCSS tuned (multimedia priority, network throttling off)'
        }
        # 3) optional power plan
        if ($HighPerformancePowerPlan) {
            if ($PSCmdlet.ShouldProcess('power plan', 'switch to High performance')) {
                & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
                Ok 'power plan: High performance (costs battery life)'
            }
        }
        else { Warn 'power plan left as-is (pass -HighPerformancePowerPlan to switch)' }

        Warn 'deliberately NOT done: no service disabled, no UAC change, no DPI change, no update policy change'
        Record 'tune' $okAll 'GameDVR + MMCSS'
    }
}

# ------------------------------------------------------------------ link
if ($phases -contains 'link') {
    Say '--- link: file associations ---' White
    $args = @()
    if ($RegisterAssociations) {
        $appsHash = @{}
        if (Test-Path $Manifest) {
            foreach ($app in (Get-Content $Manifest -Raw | ConvertFrom-Json).apps) {
                if (-not $app.assoc) { continue }
                $exe = Join-Path (Join-Path $Destination $app.name) (Split-Path $app.exe -Leaf)
                $appsHash[$app.name] = @{ Exe = $exe; Exts = @($app.assoc) }
            }
        }
        $words = $appsHash.GetEnumerator() | ForEach-Object { "$($_.Key)($($_.Value.Exts.Count))" }
        Step "register: $($words -join ', ')"
        $scr = Script-Path 'set-app-associations.ps1'
        if (Test-Path $scr) {
            # A hashtable cannot cross a pwsh -File boundary, so dot-source it in-process.
            $hashCopy = $appsHash
            & $scr -Register -Apps $hashCopy -BackupDir (Join-Path $SnapshotDir 'assoc-backup')
        }
        else { Bad 'set-app-associations.ps1 not found' }
    }
    else {
        $a = Invoke-Step 'set-app-associations.ps1' @() 'report current associations'
    }
    $b = Invoke-Step 'clean-orphan-associations.ps1' @('-Root', $Destination) 'check for orphaned associations'
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
    $d = Invoke-Step 'compare-services.ps1' @('-Snapshot', (Join-Path $SnapshotDir 'services-snapshot.csv')) 'service baseline drift'
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
Write-Host '  1. REBOOT, then open a NEW terminal (PATH and the input stack are rebuilt at logon)'
Write-Host '  2. set default programs: one manual click per file type you care about'
Write-Host '  3. if a device shows an error, run reset-failed-devices.ps1 -Reset (elevated)'
exit $fail
