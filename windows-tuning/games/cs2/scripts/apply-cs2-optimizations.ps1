<#
.SYNOPSIS
  Apply or revert the three system-level CS2 tweaks WITHOUT touching anything else.

.DESCRIPTION
  The three tweaks, each independently revertable:

    1. Power scheme: create/select a "High performance (Game)" scheme with the minimum
       processor state kept at 80% (not 100%) and active cooling.
    2. Fullscreen optimizations OFF for cs2.exe, so the game can run exclusive fullscreen.
    3. Optionally write an autoexec.cfg with frame-cap / network settings only.

  Design notes, each from a measured failure:

  * The registry layer value is written with New-ItemProperty, never New-Item -Force.
    `New-Item -Path <key> -Force` recreates the key and WIPES every sibling value, which
    would silently delete other games' compatibility flags.
  * Every step is read back. "The command returned success" is not evidence.
  * -WhatIf must actually be dry: external tools (powercfg, Set-Content) are all inside
    ShouldProcess guards, and the summary states what WOULD change.
  * ASCII-only: Windows PowerShell 5.1 decodes a BOM-less file as ANSI, so a multi-byte
    character would break parsing and the script would exit with code 0x1 saying nothing.

.PARAMETER SteamPath
  Steam install root. Auto-detected from the registry when omitted.

.PARAMETER MinProcessorState
  Minimum processor state for the created power scheme, 0-100. Default 80.
  Do not use a very low value: measured, 10-20 makes clock ramp-up visible as sluggish aim.

.PARAMETER WriteAutoExec
  Also write autoexec.cfg (frame cap + network only). Backs up an existing file to .bak.
  Note: CS2 does NOT run autoexec.cfg by itself - add "+exec autoexec.cfg" to the Steam
  launch options.

.PARAMETER Revert
  Undo: switch back to Balanced, remove the compatibility layer value, delete autoexec.cfg
  (restoring .bak if present).

.EXAMPLE
  pwsh -File apply-cs2-optimizations.ps1 -WhatIf

.EXAMPLE
  pwsh -File apply-cs2-optimizations.ps1

.EXAMPLE
  pwsh -File apply-cs2-optimizations.ps1 -Revert

.NOTES
  ASCII-only on purpose. Run elevated if powercfg refuses to set the scheme.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SteamPath,
    [ValidateRange(0, 100)][int]$MinProcessorState = 80,
    [switch]$WriteAutoExec,
    [switch]$Revert,
    [string]$SchemeName = 'High performance (Game)'
)

$ErrorActionPreference = 'Continue'
$failures = New-Object System.Collections.Generic.List[string]
$changes  = New-Object System.Collections.Generic.List[string]

function Write-Head { param([string]$T) Write-Output ""; Write-Output "===== $T =====" }
function Ok   { param([string]$M) Write-Output "    ok      $M" }
function Warn { param([string]$M) Write-Output "    WARN    $M" }
function Bad  { param([string]$M) Write-Output "    FAIL    $M"; $script:failures.Add($M) }
function Info { param([string]$M) Write-Output "    $M" }
function Would{ param([string]$M) Write-Output "    would   $M" }

Write-Output '===== apply-cs2-optimizations ====='
if ($WhatIfPreference) { Write-Output '  DRY RUN (-WhatIf): no system change will be made' }
if ($Revert)          { Write-Output '  MODE: revert' }

# ------------------------------------------------------------------ resolve Steam
Write-Head '0. Locate Steam and CS2'
if (-not $SteamPath) {
    $candidates = @(
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam',
        'HKCU:\Software\Valve\Steam'
    )
    foreach ($k in $candidates) {
        if (Test-Path $k) {
            $p = (Get-ItemProperty $k -ErrorAction SilentlyContinue).InstallPath
            if (-not $p) { $p = (Get-ItemProperty $k -ErrorAction SilentlyContinue).SteamPath }
            if ($p -and (Test-Path $p)) { $SteamPath = $p; break }
        }
    }
    if (-not $SteamPath) {
        foreach ($g in @('C:\Program Files (x86)\Steam', 'C:\Program Files\Steam')) {
            if (Test-Path $g) { $SteamPath = $g; break }
        }
    }
}
if (-not $SteamPath -or -not (Test-Path $SteamPath)) {
    Bad 'Steam not found. Pass -SteamPath explicitly.'
    Write-Output ''
    Write-Output 'Aborting.'
    exit 1
}
Info "Steam: $SteamPath"

$gameRoot = Join-Path $SteamPath 'steamapps\common\Counter-Strike Global Offensive'
$exePath  = Join-Path $gameRoot 'game\bin\win64\cs2.exe'
$cfgDir   = Join-Path $gameRoot 'game\csgo\cfg'
Info "CS2 root: $gameRoot"
Info "cs2.exe : $(if (Test-Path $exePath) { 'present' } else { 'MISSING' })"
if (-not (Test-Path $gameRoot)) {
    Warn 'CS2 does not look installed in this library - the fullscreen-optimization step will be skipped.'
}

# ------------------------------------------------------------------ 1. power scheme
Write-Head '1. Power scheme'

$balancedGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
$highPerfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$minSetting   = '893dee8e-2bef-41e0-89c6-b55d0929964c'
$maxSetting   = 'bc5038f7-23e0-4960-96da-33abaf5935ec'
$coolSetting  = '94d3a615-a899-4ac5-ae2b-e4d8f634367f'

function Get-PowerSchemes {
    $list = & powercfg /list 2>&1
    $out = @()
    foreach ($line in $list) {
        if ($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+(.*)$') {
            $g = $Matches[1]
            $n = $Matches[2].Trim()
            # Trailing '*' marks the ACTIVE scheme; it is not part of the name.
            $n = $n -replace '\s*\*+\s*$', ''
            # The name is wrapped in exactly one outer pair of parentheses and may contain
            # inner parentheses of its own, e.g. "(High performance (Game))". Strip ONLY the
            # outer pair. A blanket [()] replace mangles the name to "High performance Game",
            # after which the -like lookup below never matches and the script creates a
            # duplicate scheme on every run. That is not theoretical: it happened during
            # testing and left an extra scheme behind.
            if ($n -match '^\((.*)\)$') { $n = $Matches[1].Trim() }
            $out += [pscustomobject]@{ Guid = $g; Name = $n }
        }
    }
    return $out
}
function Get-ActiveSchemeGuid {
    $s = (& powercfg /getactivescheme 2>&1) -join ' '
    if ($s -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { return $Matches[1] }
    return ''
}
function Get-ProcessorState {
    param([string]$SchemeGuid, [string]$SettingGuid)
    $q = & powercfg /query $SchemeGuid SUB_PROCESSOR $SettingGuid 2>&1
    $line = @($q | Where-Object { $_ -match '0x[0-9a-fA-F]+' } | Where-Object { $_ -match '(?i)AC|\u4ea4\u6d41' }) | Select-Object -First 1
    if (-not $line) { $line = @($q | Where-Object { $_ -match '0x[0-9a-fA-F]+' }) | Select-Object -First 1 }
    if ($line -and $line -match '0x([0-9a-fA-F]+)') { return [Convert]::ToInt32($Matches[1], 16) }
    return $null
}

$activeBefore = Get-ActiveSchemeGuid
Info "active scheme before: $activeBefore"

if ($Revert) {
    if ($activeBefore -eq $balancedGuid) {
        Ok 'already on Balanced'
    }
    elseif ($PSCmdlet.ShouldProcess('Power scheme', "switch back to Balanced ($balancedGuid)")) {
        & powercfg /setactive $balancedGuid 2>&1 | Out-Null
        if ((Get-ActiveSchemeGuid) -eq $balancedGuid) { Ok 'switched back to Balanced'; $changes.Add('power scheme -> Balanced') }
        else { Bad 'could not switch back to Balanced (run elevated?)' }
    }
    else { Would "switch back to Balanced ($balancedGuid)" }
}
else {
    $schemes = Get-PowerSchemes
    $mine = @($schemes | Where-Object { $_.Name -like "*$SchemeName*" }) | Select-Object -First 1

    if (-not $mine) {
        if ($PSCmdlet.ShouldProcess('Power scheme', "create '$SchemeName' from the High performance template")) {
            $dup = (& powercfg -duplicatescheme $highPerfGuid 2>&1) -join ' '
            if ($dup -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
                $newGuid = $Matches[1]
                & powercfg /changename $newGuid $SchemeName 2>&1 | Out-Null
                & powercfg /setacvalueindex $newGuid SUB_PROCESSOR PROCTHROTTLEMIN $MinProcessorState 2>&1 | Out-Null
                & powercfg /setacvalueindex $newGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>&1 | Out-Null
                & powercfg /setacvalueindex $newGuid SUB_PROCESSOR SYSCOOLPOL 1 2>&1 | Out-Null
                $mine = [pscustomobject]@{ Guid = $newGuid; Name = $SchemeName }
                Ok "created scheme '$SchemeName' ($newGuid)"
                $changes.Add("created power scheme $newGuid")
            }
            else { Bad "powercfg -duplicatescheme failed: $dup" }
        }
        else { Would "create '$SchemeName' from the High performance template" }
    }
    else { Ok "scheme exists: $($mine.Name) ($($mine.Guid))" }

    if ($mine) {
        if ($activeBefore -eq $mine.Guid) { Ok 'scheme is already active' }
        elseif ($PSCmdlet.ShouldProcess('Power scheme', "activate $($mine.Guid)")) {
            & powercfg /setactive $mine.Guid 2>&1 | Out-Null
            if ((Get-ActiveSchemeGuid) -eq $mine.Guid) { Ok 'activated'; $changes.Add('power scheme activated') }
            else { Bad 'could not activate the scheme (run elevated?)' }
        }
        else { Would "activate $($mine.Guid)" }

        # Read back only when the scheme is actually active - querying a scheme that was
        # never applied would report the template values and look like a success.
        if ((Get-ActiveSchemeGuid) -eq $mine.Guid) {
            $mn = Get-ProcessorState $mine.Guid $minSetting
            $mx = Get-ProcessorState $mine.Guid $maxSetting
            Info "read back: min=$mn %  max=$mx %"
            if ($mn -ne $null -and $mn -ne $MinProcessorState) { Bad "min processor state is $mn, expected $MinProcessorState" }
            if ($mx -ne $null -and $mx -ne 100) { Bad "max processor state is $mx, expected 100" }
            if ($mn -eq $MinProcessorState -and $mx -eq 100) { Ok 'processor state verified by readback' }
        }
    }
}

# ------------------------------------------------------------------ 2. fullscreen optimizations
Write-Head '2. Fullscreen optimizations for cs2.exe'

$layersKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$layerFlag = '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'

if (-not (Test-Path $exePath)) {
    Warn "cs2.exe not found - skipping: $exePath"
}
else {
    $exists = Test-Path $layersKey
    $beforeCount = if ($exists) { @((Get-Item $layersKey).Property).Count } else { 0 }
    $current = ''
    if ($exists) {
        $props = Get-ItemProperty $layersKey -ErrorAction SilentlyContinue
        if ($props -and $props.PSObject.Properties.Name -contains $exePath) { $current = "$($props.$exePath)" }
    }
    Info "layer entries before: $beforeCount"
    Info "current value: $(if ($current) { $current } else { '(none)' })"

    if ($Revert) {
        if (-not $current) { Ok 'nothing to remove' }
        elseif ($PSCmdlet.ShouldProcess($exePath, 'remove compatibility layer entry')) {
            Remove-ItemProperty -Path $layersKey -Name $exePath -ErrorAction SilentlyContinue
            $after = ''
            $p2 = Get-ItemProperty $layersKey -ErrorAction SilentlyContinue
            if ($p2 -and $p2.PSObject.Properties.Name -contains $exePath) { $after = "$($p2.$exePath)" }
            if (-not $after) { Ok 'layer entry removed'; $changes.Add('fullscreen-optimization flag removed') }
            else { Bad 'layer entry still present after removal' }
        }
        else { Would "remove the compatibility layer entry for cs2.exe" }
    }
    else {
        if ($current -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE') { Ok 'already disabled' }
        elseif ($PSCmdlet.ShouldProcess($exePath, 'set DISABLEDXMAXIMIZEDWINDOWEDMODE')) {
            if (-not $exists) { New-Item -Path $layersKey -Force | Out-Null }
            # New-ItemProperty on purpose: New-Item -Force would wipe sibling values.
            New-ItemProperty -Path $layersKey -Name $exePath -Value $layerFlag -PropertyType String -Force | Out-Null
            $p3 = Get-ItemProperty $layersKey -ErrorAction SilentlyContinue
            $after = if ($p3 -and $p3.PSObject.Properties.Name -contains $exePath) { "$($p3.$exePath)" } else { '' }
            $afterCount = @((Get-Item $layersKey).Property).Count
            Info "layer entries after: $afterCount"
            if ($after -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE') {
                Ok 'flag verified by readback'
                $changes.Add('fullscreen-optimization flag set')
                if ($beforeCount -gt 0 -and $afterCount -ne ($beforeCount + 1)) {
                    Warn "entry count went $beforeCount -> $afterCount; expected +1. Check that no sibling value was lost."
                }
            }
            else { Bad 'flag not present after write' }
        }
        else { Would "set $layerFlag on cs2.exe" }
    }
}

# ------------------------------------------------------------------ 3. autoexec
Write-Head '3. autoexec.cfg'

$autoexecPath = Join-Path $cfgDir 'autoexec.cfg'
if (-not $WriteAutoExec -and -not $Revert) {
    Info 'skipped (pass -WriteAutoExec to write it)'
}
elseif ($Revert) {
    if (-not (Test-Path $autoexecPath)) { Ok 'no autoexec.cfg to delete' }
    elseif ($PSCmdlet.ShouldProcess($autoexecPath, 'delete autoexec.cfg')) {
        Remove-Item -Path $autoexecPath -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $autoexecPath)) { Ok 'deleted'; $changes.Add('autoexec.cfg deleted') } else { Bad 'could not delete autoexec.cfg' }
        $bak = "$autoexecPath.bak"
        if (Test-Path $bak) {
            Move-Item -Path $bak -Destination $autoexecPath -Force -ErrorAction SilentlyContinue
            if (Test-Path $autoexecPath) { Ok 'previous autoexec.cfg restored from .bak' }
        }
    }
    else { Would 'delete autoexec.cfg (and restore .bak if present)' }
}
else {
    if (-not (Test-Path $cfgDir)) {
        Warn "cfg directory not found - launch CS2 once first: $cfgDir"
    }
    else {
        $content = @'
// autoexec.cfg - frame pacing and network only.
// Personal preferences (sensitivity, crosshair, viewmodel) are deliberately NOT set here:
// they would override whatever you change in the in-game menu later.
// Delete this file to return to defaults.

fps_max 120
fps_max_ui 120
r_dynamic 0

cl_interp_ratio 1
cl_predict 1
cl_predictweapons 1

echo "[autoexec] loaded: fps_max 120 / r_dynamic 0"
'@
        if ($PSCmdlet.ShouldProcess($autoexecPath, 'write autoexec.cfg')) {
            if (Test-Path $autoexecPath) { Copy-Item $autoexecPath "$autoexecPath.bak" -Force -ErrorAction SilentlyContinue; Info 'existing file backed up to .bak' }
            Set-Content -Path $autoexecPath -Value $content -Encoding UTF8
            if (Test-Path $autoexecPath) { Ok "written ($((Get-Item $autoexecPath).Length) bytes)"; $changes.Add('autoexec.cfg written') }
            else { Bad 'autoexec.cfg not created' }
        }
        else { Would "write $autoexecPath" }
        if (-not $WhatIfPreference) {
            Info 'reminder: CS2 does not execute autoexec.cfg by itself.'
            Info '          add "+exec autoexec.cfg" to the Steam launch options.'
        }
    }
}

# ------------------------------------------------------------------ summary
Write-Head 'summary'
if ($changes.Count -gt 0) {
    Write-Output '  changes:'
    foreach ($c in $changes) { Write-Output "    - $c" }
}
else {
    Write-Output '  no change was needed (or -WhatIf was used)'
}
if ($failures.Count -gt 0) {
    Write-Output "  failures ($($failures.Count)):"
    foreach ($f in $failures) { Write-Output "    - $f" }
    exit 1
}
Write-Output ''
Write-Output 'Revert everything with:  apply-cs2-optimizations.ps1 -Revert'
exit 0
