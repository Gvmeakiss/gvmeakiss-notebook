<#
.SYNOPSIS
  Apply or revert the three system-level CS2 tweaks WITHOUT touching anything else.

.DESCRIPTION
  The three tweaks, each independently revertable:

    1. Power scheme: create/select a "High performance (Game)" scheme with the minimum
       processor state kept at 80% (not 100%) and active cooling.
    2. Fullscreen optimizations OFF for cs2.exe, so the game can run exclusive fullscreen.
    3. Optionally write an autoexec.cfg with frame-cap / network settings only.

  Revert is state-based, not guess-based. Applying writes a state file under
  %LOCALAPPDATA%\windows-fresh-setup\games\cs2\state.json that records, for every item:

    * what existed before (compatibility-layer value, autoexec presence and SHA256),
    * what this run wrote (SHA256 of the generated autoexec),
    * which power scheme was active before, and whether this run created its scheme.

  -Revert refuses to do anything it cannot prove: it only deletes an autoexec.cfg whose
  hash matches what this script wrote, only restores a backup whose hash matches the one
  recorded at apply time, only removes a compatibility-layer value it wrote itself, and
  restores the previously active power scheme instead of assuming "Balanced".

  Design notes, each from a measured failure:

  * The registry layer value is written with New-ItemProperty, never New-Item -Force.
    `New-Item -Path <key> -Force` recreates the key and WIPES every sibling value, which
    would silently delete other games' compatibility flags.
  * Power scheme values are written and read back whether the scheme already existed or was
    created by this script; otherwise a stale scheme keeps whatever values it had and the
    re-run silently converges to nothing.
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
  Also write autoexec.cfg (frame cap + network only). Backs up an existing file to .bak and
  records both hashes in the state file so a later -Revert can prove what it is touching.
  Note: CS2 does NOT run autoexec.cfg by itself - add "+exec autoexec.cfg" to the Steam
  launch options.

.PARAMETER Revert
  Restore the state recorded at apply time: reactivate the previously active power scheme,
  put back (or remove) the compatibility-layer value, and restore (or remove) autoexec.cfg
  only when the recorded hashes prove it is safe. Without a state file, revert refuses to
  change anything and explains why.

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
$skipped  = New-Object System.Collections.Generic.List[string]

function Write-Head { param([string]$T) Write-Output ""; Write-Output "===== $T =====" }
function Ok   { param([string]$M) Write-Output "    ok      $M" }
function Warn { param([string]$M) Write-Output "    WARN    $M" }
function Bad  { param([string]$M) Write-Output "    FAIL    $M"; $script:failures.Add($M) }
function Info { param([string]$M) Write-Output "    $M" }
function Would{ param([string]$M) Write-Output "    would   $M" }
function Skip { param([string]$M) Write-Output "    skip    $M"; $script:skipped.Add($M) }

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash } catch { return $null }
}

# State lives outside the repo: it describes this machine, not the project.
$stateDir  = Join-Path $env:LOCALAPPDATA 'windows-fresh-setup\games\cs2'
$statePath = Join-Path $stateDir 'state.json'

function Read-State {
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }
    try { return (Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json) } catch { return $null }
}
function Save-State {
    param([object]$State)
    if ($WhatIfPreference) { Would "write state file $statePath"; return }
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

Write-Output '===== apply-cs2-optimizations ====='
if ($WhatIfPreference) { Write-Output '  DRY RUN (-WhatIf): no system change will be made' }
if ($Revert)          { Write-Output '  MODE: revert (state-based)' }
$opId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
Info "operation id: $opId"
Info "state file  : $statePath"

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

$steamFound = ($SteamPath -and (Test-Path $SteamPath))
$gameRoot = $null; $exePath = $null; $cfgDir = $null
if ($steamFound) {
    Info "Steam: $SteamPath"
    $gameRoot = Join-Path $SteamPath 'steamapps\common\Counter-Strike Global Offensive'
    $exePath  = Join-Path $gameRoot 'game\bin\win64\cs2.exe'
    $cfgDir   = Join-Path $gameRoot 'game\csgo\cfg'
    Info "CS2 root: $gameRoot"
    Info "cs2.exe : $(if (Test-Path $exePath) { 'present' } else { 'MISSING' })"
    if (-not (Test-Path $gameRoot)) {
        Warn 'CS2 does not look installed in this library - the fullscreen-optimization step will be skipped.'
    }
}
elseif ($Revert) {
    Warn 'Steam not found - power and state may still be reverted, file steps will be skipped.'
}
else {
    Bad 'Steam not found. Pass -SteamPath explicitly.'
    Write-Output ''
    Write-Output 'Aborting.'
    exit 1
}

# ------------------------------------------------------------------ power helpers
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
    if (-not $SchemeGuid) { return $null }
    $q = & powercfg /query $SchemeGuid SUB_PROCESSOR $SettingGuid 2>&1
    # Prefer the AC line. Both localized ("\u4ea4\u6d41") and English words are matched; the
    # numeric regex is the real parse, the text only disambiguates AC from DC.
    $line = @($q | Where-Object { $_ -match '0x[0-9a-fA-F]+' } | Where-Object { $_ -match '(?i)AC|\u4ea4\u6d41' }) | Select-Object -First 1
    if (-not $line) { $line = @($q | Where-Object { $_ -match '0x[0-9a-fA-F]+' }) | Select-Object -First 1 }
    if ($line -and $line -match '0x([0-9a-fA-F]+)') { return [Convert]::ToInt32($Matches[1], 16) }
    return $null
}

$state = if ($Revert) { Read-State } else { $null }

if ($Revert -and -not $state) {
    Bad "no state file at $statePath"
    Write-Output ''
    Write-Output '  Nothing was recorded by a previous apply run, so nothing here can be proven safe'
    Write-Output '  to touch. Refusing to guess: this script will not delete autoexec.cfg, will not'
    Write-Output '  clear compatibility flags, and will not switch power schemes without a record.'
    Write-Output ''
    Write-Output '  If you know what to undo by hand:'
    Write-Output '    - powercfg /list, then powercfg /setactive <guid>'
    Write-Output '    - remove the cs2.exe value under HKCU\...\AppCompatFlags\Layers if you set it'
    Write-Output '    - delete game\csgo\cfg\autoexec.cfg if you created it'
    exit 1
}

# ------------------------------------------------------------------ 1. power scheme
Write-Head '1. Power scheme'

$activeBefore = Get-ActiveSchemeGuid
Info "active scheme before: $(if ($activeBefore) { $activeBefore } else { '(could not read)' })"

$newState = [ordered]@{
    opId      = $opId
    tool      = 'apply-cs2-optimizations.ps1'
    timestamp = (Get-Date).ToString('o')
    power     = $null
    layer     = $null
    autoexec  = $null
}

if ($Revert) {
    $p = $state.power
    if (-not $p -or -not $p.activeBefore) {
        Skip 'power: the state file records no previous scheme'
    }
    elseif ($activeBefore -eq $p.activeBefore) {
        Ok "already on the recorded scheme ($($p.activeBefore))"
    }
    elseif ($PSCmdlet.ShouldProcess('Power scheme', "restore previous active scheme $($p.activeBefore)")) {
        & powercfg /setactive $p.activeBefore 2>&1 | Out-Null
        $now = Get-ActiveSchemeGuid
        if ($now -eq $p.activeBefore) { Ok "restored active scheme $($p.activeBefore)"; $changes.Add("power scheme restored to $($p.activeBefore)") }
        else { Bad "could not restore scheme $($p.activeBefore) (now: $now)" }
    }
    else { Would "restore previous active scheme $($p.activeBefore)" }

    if ($p -and $p.createdByUs -and $p.schemeGuid -and $p.schemeGuid -ne $p.activeBefore) {
        $stillThere = @(Get-PowerSchemes | Where-Object { $_.Guid -eq $p.schemeGuid })
        if ($stillThere.Count -eq 0) { Ok "our scheme $($p.schemeGuid) is already gone" }
        elseif ($PSCmdlet.ShouldProcess('Power scheme', "delete the scheme this tool created ($($p.schemeGuid))")) {
            & powercfg /delete $p.schemeGuid 2>&1 | Out-Null
            $gone = @(Get-PowerSchemes | Where-Object { $_.Guid -eq $p.schemeGuid }).Count -eq 0
            if ($gone) { Ok "deleted our scheme $($p.schemeGuid)"; $changes.Add('created scheme deleted') }
            else { Warn "could not delete scheme $($p.schemeGuid) (it may be in use); it is harmless" }
        }
        else { Would "delete the scheme this tool created ($($p.schemeGuid))" }
    }
}
else {
    $schemes = Get-PowerSchemes
    $mine = @($schemes | Where-Object { $_.Name -like "*$SchemeName*" }) | Select-Object -First 1
    $createdByUs = $false

    if (-not $mine) {
        if ($PSCmdlet.ShouldProcess('Power scheme', "create '$SchemeName' from the High performance template")) {
            $dup = (& powercfg -duplicatescheme $highPerfGuid 2>&1) -join ' '
            if ($dup -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
                $newGuid = $Matches[1]
                & powercfg /changename $newGuid $SchemeName 2>&1 | Out-Null
                $mine = [pscustomobject]@{ Guid = $newGuid; Name = $SchemeName }
                $createdByUs = $true
                Ok "created scheme '$SchemeName' ($newGuid)"
                $changes.Add("created power scheme $newGuid")
            }
            else { Bad "powercfg -duplicatescheme failed: $dup" }
        }
        else { Would "create '$SchemeName' from the High performance template" }
    }
    else { Ok "scheme exists: $($mine.Name) ($($mine.Guid))" }

    if ($mine) {
        # Write the processor values whether the scheme is new or pre-existing, then read them
        # back. Skipping this for an existing scheme is how a re-run silently converges to the
        # old (wrong) values while claiming success.
        if ($PSCmdlet.ShouldProcess('Power scheme', "set min=$MinProcessorState% max=100% cooling=active on $($mine.Guid)")) {
            & powercfg /setacvalueindex $mine.Guid SUB_PROCESSOR PROCTHROTTLEMIN $MinProcessorState 2>&1 | Out-Null
            & powercfg /setacvalueindex $mine.Guid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>&1 | Out-Null
            & powercfg /setacvalueindex $mine.Guid SUB_PROCESSOR SYSCOOLPOL 1 2>&1 | Out-Null
            Ok 'processor values written'
        }
        else { Would "set min=$MinProcessorState% max=100% cooling=active on $($mine.Guid)" }

        if ($activeBefore -eq $mine.Guid) { Ok 'scheme is already active' }
        elseif ($PSCmdlet.ShouldProcess('Power scheme', "activate $($mine.Guid)")) {
            & powercfg /setactive $mine.Guid 2>&1 | Out-Null
            if ((Get-ActiveSchemeGuid) -eq $mine.Guid) { Ok 'activated'; $changes.Add('power scheme activated') }
            else { Bad 'could not activate the scheme (run elevated?)' }
        }
        else { Would "activate $($mine.Guid)" }

        # Read back only when the scheme is actually active - querying a scheme that was never
        # applied would report the template values and look like a success.
        if ((Get-ActiveSchemeGuid) -eq $mine.Guid) {
            $mn = Get-ProcessorState $mine.Guid $minSetting
            $mx = Get-ProcessorState $mine.Guid $maxSetting
            $cl = Get-ProcessorState $mine.Guid $coolSetting
            Info "read back: min=$(if ($null -ne $mn) { "$mn %" } else { '?' })  max=$(if ($null -ne $mx) { "$mx %" } else { '?' })  cooling=$(if ($null -ne $cl) { $cl } else { '?' })"
            if ($null -eq $mn) { Bad 'could not read back the minimum processor state' }
            elseif ($mn -ne $MinProcessorState) { Bad "min processor state is $mn, expected $MinProcessorState" }
            if ($null -eq $mx) { Bad 'could not read back the maximum processor state' }
            elseif ($mx -ne 100) { Bad "max processor state is $mx, expected 100" }
            if ($null -ne $mn -and $null -ne $mx -and $mn -eq $MinProcessorState -and $mx -eq 100) { Ok 'processor state verified by readback' }
            $newState.power = [ordered]@{
                activeBefore = $activeBefore
                schemeGuid   = $mine.Guid
                schemeName   = $mine.Name
                createdByUs  = $createdByUs
                min          = $mn
                max          = $mx
                cooling      = $cl
            }
        }
        else {
            $newState.power = [ordered]@{
                activeBefore = $activeBefore
                schemeGuid   = $mine.Guid
                schemeName   = $mine.Name
                createdByUs  = $createdByUs
                min          = $null
                max          = $null
                cooling      = $null
            }
        }
    }
    else {
        $newState.power = [ordered]@{ activeBefore = $activeBefore; schemeGuid = $null; schemeName = $null; createdByUs = $false }
    }
}

# ------------------------------------------------------------------ 2. fullscreen optimizations
Write-Head '2. Fullscreen optimizations for cs2.exe'

$layersKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$layerFlag = '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'

if (-not $exePath -or -not (Test-Path $exePath)) {
    Warn "cs2.exe not found - skipping: $exePath"
}
else {
    $exists = Test-Path $layersKey
    $beforeCount = if ($exists) { @((Get-Item $layersKey).Property).Count } else { 0 }
    $current = $null
    if ($exists) {
        $props = Get-ItemProperty $layersKey -ErrorAction SilentlyContinue
        if ($props -and $props.PSObject.Properties.Name -contains $exePath) { $current = "$($props.$exePath)" }
    }
    Info "layer entries before: $beforeCount"
    Info "current value: $(if ($null -ne $current) { $current } else { '(none)' })"

    if ($Revert) {
        $ls = $state.layer
        if (-not $ls) { Skip 'layer: the state file records no compatibility-layer change' }
        elseif ($null -ne $current -and $current -ne $ls.writtenValue) {
            Skip "layer: current value '$current' is not what this tool wrote ('$($ls.writtenValue)'); leaving it alone"
        }
        elseif ($ls.existed -and $ls.previousValue) {
            if ($PSCmdlet.ShouldProcess($exePath, "restore previous layer value '$($ls.previousValue)'")) {
                New-ItemProperty -Path $layersKey -Name $exePath -Value $ls.previousValue -PropertyType String -Force | Out-Null
                $p2 = Get-ItemProperty $layersKey -ErrorAction SilentlyContinue
                $after = if ($p2 -and $p2.PSObject.Properties.Name -contains $exePath) { "$($p2.$exePath)" } else { '' }
                if ($after -eq $ls.previousValue) { Ok "previous layer value restored"; $changes.Add('fullscreen flag restored to previous value') }
                else { Bad "layer value after restore is '$after', expected '$($ls.previousValue)'" }
            }
            else { Would "restore previous layer value '$($ls.previousValue)'" }
        }
        elseif (-not $current) { Ok 'nothing to remove' }
        elseif ($PSCmdlet.ShouldProcess($exePath, 'remove compatibility layer entry this tool set')) {
            Remove-ItemProperty -Path $layersKey -Name $exePath -ErrorAction SilentlyContinue
            $p2 = Get-ItemProperty $layersKey -ErrorAction SilentlyContinue
            $after = if ($p2 -and $p2.PSObject.Properties.Name -contains $exePath) { "$($p2.$exePath)" } else { '' }
            if (-not $after) { Ok 'layer entry removed'; $changes.Add('fullscreen-optimization flag removed') }
            else { Bad 'layer entry still present after removal' }
        }
        else { Would 'remove the compatibility layer entry for cs2.exe' }
    }
    else {
        if ($current -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE') { Ok 'already disabled'; $newState.layer = [ordered]@{ existed = ($null -ne $current); previousValue = $current; writtenValue = $current } }
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
                $newState.layer = [ordered]@{ existed = ($null -ne $current); previousValue = $current; writtenValue = $after }
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

if ($Revert) {
    $as = $state.autoexec
    if (-not $as) { Skip 'autoexec: the state file records nothing, leaving the file untouched' }
    else {
        $autoexecPath = if ($as.path) { $as.path } elseif ($cfgDir) { Join-Path $cfgDir 'autoexec.cfg' } else { $null }
        if (-not $autoexecPath) { Skip 'autoexec: cannot resolve the path (Steam not found and no recorded path)' }
        else {
            $currentHash = Get-FileSha256 $autoexecPath
            if (-not $as.existed) {
                if (-not $currentHash) { Ok 'no autoexec.cfg present' }
                elseif ($currentHash -ne $as.writtenSha256) {
                    Skip "autoexec.cfg exists but its hash does not match what this tool wrote; leaving it alone ($autoexecPath)"
                }
                elseif ($PSCmdlet.ShouldProcess($autoexecPath, 'delete the autoexec.cfg this tool created')) {
                    Remove-Item -LiteralPath $autoexecPath -Force -ErrorAction SilentlyContinue
                    if (-not (Get-FileSha256 $autoexecPath)) { Ok 'deleted autoexec.cfg created by this tool'; $changes.Add('autoexec.cfg deleted') }
                    else { Bad 'could not delete autoexec.cfg' }
                }
                else { Would 'delete the autoexec.cfg created by this tool' }
            }
            else {
                # A pre-existing file was backed up before it was overwritten.
                $bak = $as.backupPath
                $bakHash = Get-FileSha256 $bak
                if (-not $bakHash) { Skip "the recorded backup is gone ($bak); the current autoexec.cfg is left untouched" }
                elseif ($as.backupSha256 -and $bakHash -ne $as.backupSha256) {
                    Skip "the backup hash changed since apply ('$bakHash' vs recorded '$($as.backupSha256)'); not restoring it"
                }
                elseif ($currentHash -and $as.writtenSha256 -and $currentHash -ne $as.writtenSha256) {
                    Skip "autoexec.cfg changed since this tool wrote it; leaving both files alone (backup kept at $bak)"
                }
                elseif ($PSCmdlet.ShouldProcess($autoexecPath, 'restore the pre-apply autoexec.cfg from its backup')) {
                    Copy-Item -LiteralPath $bak -Destination $autoexecPath -Force -ErrorAction SilentlyContinue
                    $restored = Get-FileSha256 $autoexecPath
                    if ($restored -eq $as.backupSha256) { Ok 'previous autoexec.cfg restored from the recorded backup'; $changes.Add('autoexec.cfg restored from backup') }
                    else { Bad 'restored autoexec.cfg does not match the recorded backup hash' }
                }
                else { Would 'restore the pre-apply autoexec.cfg from its backup' }
            }
        }
    }
}
elseif (-not $WriteAutoExec) {
    Info 'skipped (pass -WriteAutoExec to write it)'
}
else {
    $autoexecPath = if ($cfgDir) { Join-Path $cfgDir 'autoexec.cfg' } else { $null }
    if (-not $autoexecPath -or -not (Test-Path $cfgDir)) {
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
        $existed = Test-Path -LiteralPath $autoexecPath
        $existedHash = Get-FileSha256 $autoexecPath
        $bakPath = "$autoexecPath.bak"
        if ($PSCmdlet.ShouldProcess($autoexecPath, 'write autoexec.cfg')) {
            if ($existed) {
                Copy-Item -LiteralPath $autoexecPath -Destination $bakPath -Force -ErrorAction SilentlyContinue
                $bakHash = Get-FileSha256 $bakPath
                if ($bakHash -eq $existedHash) { Info "existing file backed up to $bakPath"; $changes.Add('existing autoexec.cfg backed up') }
                else { Bad 'backup copy does not match the original file; refusing to overwrite it' }
            }
            if ($bakHash -eq $existedHash -or -not $existed) {
                Set-Content -Path $autoexecPath -Value $content -Encoding UTF8
                $writtenHash = Get-FileSha256 $autoexecPath
                if ($writtenHash) {
                    Ok "written ($((Get-Item -LiteralPath $autoexecPath).Length) bytes, sha256 $($writtenHash.Substring(0,12))...)"
                    $changes.Add('autoexec.cfg written')
                    $newState.autoexec = [ordered]@{
                        path          = $autoexecPath
                        existed       = $existed
                        previousSha256 = $existedHash
                        backupPath    = if ($existed) { $bakPath } else { $null }
                        backupSha256  = if ($existed) { $bakHash } else { $null }
                        writtenSha256 = $writtenHash
                    }
                }
                else { Bad 'autoexec.cfg not readable after write' }
            }
        }
        else { Would "write $autoexecPath" }
        if (-not $WhatIfPreference) {
            Info 'reminder: CS2 does not execute autoexec.cfg by itself.'
            Info '          add "+exec autoexec.cfg" to the Steam launch options.'
        }
    }
}

# ------------------------------------------------------------------ persist state
Write-Head 'state'
if ($Revert) {
    if ($state -and -not $WhatIfPreference) {
        $archived = Join-Path $stateDir ("state.reverted-" + $state.opId + '.json')
        try {
            Move-Item -LiteralPath $statePath -Destination $archived -Force -ErrorAction Stop
            Ok "state file archived to $archived"
        }
        catch { Warn "could not archive the state file: $($_.Exception.Message)" }
    }
    elseif ($state) { Would "archive the state file to $stateDir\state.reverted-$($state.opId).json" }
}
else {
    $anyRecord = ($newState.power -or $newState.layer -or $newState.autoexec)
    if ($anyRecord) { Save-State $newState; Ok "state recorded for operation $opId" }
    else { Warn 'nothing was recorded (every step was skipped or -WhatIf was used)' }
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
if ($skipped.Count -gt 0) {
    Write-Output "  skipped ($($skipped.Count)) - left untouched on purpose:"
    foreach ($s in $skipped) { Write-Output "    - $s" }
}
if ($failures.Count -gt 0) {
    Write-Output "  failures ($($failures.Count)):"
    foreach ($f in $failures) { Write-Output "    - $f" }
    exit 1
}
Write-Output ''
Write-Output 'Revert with:  apply-cs2-optimizations.ps1 -Revert   (state-based; refuses anything it cannot prove)'
exit 0
