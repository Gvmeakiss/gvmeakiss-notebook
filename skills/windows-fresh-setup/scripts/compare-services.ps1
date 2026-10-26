<#
.SYNOPSIS
  Compare the current Windows service state against a pre-optimization snapshot, report
  every deviation, and optionally restore the baseline.

.DESCRIPTION
  System "optimization" scripts routinely disable services. The reasoning is usually
  plausible and sometimes wrong, because a Windows service often does more than its
  display name suggests - and the damage only appears after the next reboot.

  The defence is a snapshot taken BEFORE optimizing, and a way to diff against it
  afterwards. This script provides the diff and the rollback.

  It reports:
    - services whose start type differs from the baseline (the real changes)
    - services the baseline already had Disabled (so they are NOT your doing)
    - running services that the baseline had stopped
    - any service in a built-in WATCHLIST, flagged with what breaks when it is disabled

  The WATCHLIST encodes hard-won knowledge: each entry names a service that looks safe
  to disable but is not.

.PARAMETER Snapshot
  Path to a CSV with columns Name,StartMode,State. StartMode uses the CIM vocabulary:
  Auto / Manual / Disabled. A companion backup may be produced by snapshot-services.ps1.

.PARAMETER Restore
  Apply the baseline start types back to the system. REQUIRES ELEVATION, because
  changing a service start type is a machine-wide operation. Without it the script only
  reports.

.PARAMETER Only
  Restrict restore to these service names (comma separated).

.EXAMPLE
  pwsh -File compare-services.ps1 -Snapshot ..\services-snapshot.csv
  pwsh -File compare-services.ps1 -Snapshot ..\services-snapshot.csv -Restore -WhatIf
  pwsh -File compare-services.ps1 -Snapshot ..\services-snapshot.csv -Restore -Only TabletInputService

.NOTES
  ASCII-only on purpose.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Snapshot,
    [switch]$Restore,
    [string[]]$Only
)

$ErrorActionPreference = 'Continue'
$Cmdlet = $PSCmdlet

function Info { param([string]$M) Write-Output "    $M" }
function Ok   { param([string]$M) Write-Output "    ok      $M" }
function Warn { param([string]$M) Write-Output "    WARN    $M" }
function Bad  { param([string]$M) Write-Output "    FAIL    $M" }

# ------------------------------------------------------------------ watchlist
# Every entry here is a service that a "safe tweak" list is likely to disable, with the
# real consequence. Keep this list short and evidence-based.
$watchlist = @{
    'TabletInputService' = 'Touch Keyboard and Handwriting Panel Service. On Windows 10 it ALSO hosts the input-method language bar and input indicator. Disabling it makes the IME disappear: no Chinese input, Win+Space dead, ctfmon.exe exits immediately with code 1.'
    'XblAuthManager'     = 'Xbox Live Auth Manager. Also used for Microsoft Store sign-in, purchases and Game Pass. Disabling it breaks Store apps that need authentication, not just Xbox.'
    'XblGameSave'        = 'Xbox Live Game Save. Needed by games that sync cloud saves, including many non-Xbox titles.'
    'XboxNetApiSvc'      = 'Xbox Live Networking Service. Required by some Store games for multiplayer and by Game Pass titles.'
    'XboxGipSvc'         = 'Xbox Accessory Management. Needed for Xbox controllers. Harmless only if you truly never use one.'
    'SEMgrSvc'           = 'Payments and NFC/SE Manager. Only matters if you use NFC payments or certain wallet features.'
    'stisvc'             = 'Windows Image Acquisition. Needed by scanners, cameras and some printing workflows. Note the baseline is Auto, so disabling it IS a deviation.'
    'WMPNetworkSvc'      = 'WMP Network Sharing Service. Only needed for Windows Media Player library sharing over the network.'
    'RemoteRegistry'     = 'Remote Registry. Commonly Disabled ALREADY on a stock install - check the baseline before crediting yourself with a hardening win.'
    'RetailDemo'         = 'Retail Demo Mode. Safe on a normal install.'
    'Fax'                = 'Fax. Safe on a normal install.'
    'Windows Search'     = 'Windows Search. Disabling it kills Start-menu file search and Explorer search.'
    'Themes'             = 'Themes. Disabling it removes the entire visual style - windows go back to the classic look.'
    'AudioSrv'           = 'Windows Audio. No sound at all.'
    'AudioEndpointBuilder' = 'Windows Audio Endpoint Builder. No audio device enumeration. Windows Audio depends on it.'
    'Dhcp'               = 'DHCP Client. No automatic IP address - network dies on most setups.'
    'Dnscache'           = 'DNS Client. Name resolution degrades badly.'
    'wuauserv'           = 'Windows Update. No security patches. Deferring updates is a choice; disabling the service is a trap.'
    'WinDefend'          = 'Microsoft Defender Antivirus. Also blocks Defender from re-enabling itself cleanly.'
    'BITS'               = 'Background Intelligent Transfer Service. Used by Windows Update, Store downloads and some installers.'
    'WSearch'            = 'Windows Search (alias). See Windows Search above.'
    'SysMain'            = 'SysMain / Superfetch. On spinning disks it helps; on SSDs it is mostly harmless to keep. Widely disabled with little gain and occasional stutter complaints.'
    'Print Spooler'      = 'Print Spooler. No printing at all. Also a known attack surface - if you disable it, do so knowingly and expect printing to break.'
    'Spooler'            = 'Print Spooler (alias). See Print Spooler above.'
}

# ------------------------------------------------------------------ privilege
$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {}

Write-Output '===== compare-services ====='
Info "snapshot : $Snapshot"
Info "elevated : $isAdmin"
if ($Restore -and -not $isAdmin) {
    Bad '-Restore requires an elevated shell (changing a service start type is machine-wide)'
    exit 1
}

if (-not (Test-Path $Snapshot)) { Bad "snapshot not found: $Snapshot"; exit 1 }
$baseline = @{}
try {
    foreach ($row in Import-Csv $Snapshot) {
        if ($row.Name) { $baseline[$row.Name] = $row }
    }
} catch { Bad "cannot parse snapshot: $($_.Exception.Message.Split("`n")[0])"; exit 1 }
Info "baseline services: $($baseline.Count)"

# ------------------------------------------------------------------ current
# Get-Service reports StartType but not in the Auto/Manual/Disabled vocabulary on all
# builds, so read it from CIM, which the snapshot was taken from.
$current = @{}
try {
    foreach ($s in Get-CimInstance Win32_Service -ErrorAction Stop) {
        $current[$s.Name] = $s
    }
} catch { Bad "cannot enumerate services: $($_.Exception.Message.Split("`n")[0])"; exit 1 }
Info "current services : $($current.Count)"

# CIM StartMode values: Boot, System, Auto, Manual, Disabled
function NormalizeStart {
    param($Mode)
    if (-not $Mode) { return 'Unknown' }
    switch -Regex ("$Mode") {
        '^(Auto|Automatic)$' { return 'Auto' }
        '^Manual$'           { return 'Manual' }
        '^Disabled$'         { return 'Disabled' }
        default              { return "$Mode" }
    }
}

# ------------------------------------------------------- 1. real deviations
Write-Output "`n--- 1. start-type deviations from the baseline"
$deviations = @()
foreach ($name in $baseline.Keys) {
    if (-not $current.ContainsKey($name)) { continue }
    $was = NormalizeStart $baseline[$name].StartMode
    $now = NormalizeStart $current[$name].StartMode
    if ($was -ne $now) {
        $deviations += [pscustomobject]@{
            Name = $name
            Was  = $was
            Now  = $now
            Watch = $watchlist.ContainsKey($name)
        }
    }
}
if ($deviations.Count -eq 0) {
    Ok 'no service start-type differs from the baseline'
} else {
    Write-Output "    $($deviations.Count) deviation(s):"
    foreach ($d in $deviations | Sort-Object -Property @{Expression='Watch';Descending=$true}, @{Expression='Name';Descending=$false}) {
        $flag = if ($d.Watch) { ' <-- WATCHLIST' } else { '' }
        '      {0,-30} {1,-10} -> {2,-10}{3}' -f $d.Name, $d.Was, $d.Now, $flag | Write-Output
    }
}

# ------------------------------------------------------- 2. watchlist status
Write-Output "`n--- 2. watchlist services currently Disabled"
$hits = @()
foreach ($name in $watchlist.Keys) {
    if (-not $current.ContainsKey($name)) { continue }
    $now = NormalizeStart $current[$name].StartMode
    if ($now -eq 'Disabled') {
        $was = if ($baseline.ContainsKey($name)) { NormalizeStart $baseline[$name].StartMode } else { 'not in baseline' }
        # Distinguish a service YOU disabled from one that shipped disabled. The second
        # group is not a consequence of optimizing and should not be "fixed" blindly.
        $changed = ($was -ne 'Disabled')
        $hits += [pscustomobject]@{ Name = $name; Was = $was; Changed = $changed; Why = $watchlist[$name] }
    }
}
$changedHits = @($hits | Where-Object { $_.Changed })
$preHits     = @($hits | Where-Object { -not $_.Changed })
if ($changedHits.Count -gt 0) {
    Write-Output "    (a) disabled BY THE OPTIMIZATION - these are the ones to review:"
    foreach ($h in $changedHits | Sort-Object Name) {
        '      {0,-24} baseline was {1}' -f $h.Name, $h.Was | Write-Output
        Write-Output "        RISK: $($h.Why)"
    }
} else { Ok 'nothing on the watchlist was disabled by the optimization' }
if ($preHits.Count -gt 0) {
    Write-Output ''
    Write-Output "    (b) disabled in the baseline too - NOT your doing, leave as shipped:"
    foreach ($h in $preHits | Sort-Object Name) {
        '      {0,-24} RISK: {1}' -f $h.Name, $h.Why | Write-Output
    }
}

# ------------------------------------------------------- 3. already-disabled
Write-Output "`n--- 3. disabled in the baseline too (NOT your doing)"
$preDisabled = @($baseline.Keys | Where-Object {
    (NormalizeStart $baseline[$_].StartMode) -eq 'Disabled' -and $current.ContainsKey($_)
})
if ($preDisabled.Count -eq 0) { Ok 'none' }
else { $preDisabled | Sort-Object | ForEach-Object { "      $_" | Write-Output } }

# ------------------------------------------------------- 4. unexpected running
Write-Output "`n--- 4. running now but stopped in the baseline"
$newlyRunning = @()
foreach ($name in $baseline.Keys) {
    if (-not $current.ContainsKey($name)) { continue }
    $wasRun = "$($baseline[$name].State)" -match 'Running'
    $isRun  = "$($current[$name].State)" -match 'Running'
    if (-not $wasRun -and $isRun) { $newlyRunning += $name }
}
if ($newlyRunning.Count -eq 0) { Ok 'none' }
else { $newlyRunning | Sort-Object | ForEach-Object { "      $_" | Write-Output } }

# ------------------------------------------------------------------ restore
if ($Restore) {
    Write-Output "`n--- restoring baseline start types"
    $targets = @($deviations)
    if ($Only) {
        $wanted = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $targets = @($targets | Where-Object { $wanted -contains $_.Name })
    }
    if ($targets.Count -eq 0) { Ok 'nothing to restore' }
    foreach ($t in $targets) {
        # sc.exe is used deliberately: the Service Control Manager caches the previous
        # start type, and a plain registry edit is not always picked up. Measured on
        # Windows 10, a registry-only change to TabletInputService did not take effect
        # until `sc config` notified the SCM.
        $scStart = $null
        if ($t.Was -eq 'Auto') { $scStart = 'auto' }
        elseif ($t.Was -eq 'Manual') { $scStart = 'demand' }
        elseif ($t.Was -eq 'Disabled') { $scStart = 'disabled' }
        if (-not $scStart) { Warn "$($t.Name): cannot map baseline '$($t.Was)'"; continue }
        if ($Cmdlet.ShouldProcess($t.Name, "set start type to $($t.Was) (sc config start= $scStart)")) {
            $out = & sc.exe config $t.Name start= $scStart 2>&1
            if ($LASTEXITCODE -eq 0) {
                Ok "$($t.Name): $($t.Now) -> $($t.Was)"
                # a service the baseline had Running should be started again
                if ("$($baseline[$t.Name].State)" -match 'Running') {
                    & sc.exe start $t.Name 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) { Ok "$($t.Name): started" }
                    else { Warn "$($t.Name): could not start (a reboot may be needed)" }
                }
            } else {
                Bad "$($t.Name): sc config failed - $($out -join ' ')"
            }
        }
    }
    Write-Output ''
    Write-Output '    Some changes only take effect after a reboot or a fresh sign-in.'
}

Write-Output "`n===== summary ====="
Write-Output ("deviations: {0}   watchlist-disabled: {1}   pre-disabled in baseline: {2}" -f `
    $deviations.Count, $hits.Count, $preDisabled.Count)
if (-not $Restore) { Write-Output 'Report only. Use -Restore (elevated) to apply the baseline.' }
