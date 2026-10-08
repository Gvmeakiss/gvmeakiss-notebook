<#
.SYNOPSIS
  Triage devices that are not in a healthy state, and optionally reset them.

.DESCRIPTION
  A device showing up as Error in Device Manager very often gets blamed on whatever
  optimization ran last. Usually it is not: it is a missing/incorrect vendor driver, or a
  radio/adapter stuck in a bad state that only a full power-off clears.

  This script keeps that distinction explicit. It reports every device whose status is not
  OK together with its problem code, translates the common codes, and only touches the
  device when -Reset is passed.

  Read-only by default. -Reset disables and re-enables each affected device, then asks the
  system to rescan hardware. Supports -WhatIf.

.PARAMETER Reset
  Disable/enable each affected device and run `pnputil /scan-devices`. Needs an elevated
  session. Without this switch the script only reports.

.PARAMETER Class
  Limit the report to one device class (for example Bluetooth, Net, USB). Optional.

.PARAMETER Help
  Show this help.

.EXAMPLE
  pwsh -File reset-failed-devices.ps1
  pwsh -File reset-failed-devices.ps1 -Class Bluetooth
  pwsh -File reset-failed-devices.ps1 -Reset -WhatIf
  pwsh -File reset-failed-devices.ps1 -Reset

.NOTES
  ASCII-only on purpose. Requires Windows + PowerShell 7+.
  Order of attempts for a stubborn device:
    1. FULL power-off (shut down, unplug / hold the power button 10s) - a reboot does NOT
       power-cycle a USB or PCIe radio
    2. install/refresh the VENDOR driver (a generic Microsoft driver may be all you have)
    3. only then treat it as hardware failure
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Reset,
    [string]$Class,
    [switch]$Help
)

if ($Help) { Get-Help $PSCommandPath -Detailed; return }

$ErrorActionPreference = 'Continue'

function Say { param([string]$M, [string]$C = 'Gray') Write-Host $M -ForegroundColor $C }
function Ok { param([string]$M) Write-Host "    ok      $M" -ForegroundColor Green }
function Warn { param([string]$M) Write-Host "    WARN    $M" -ForegroundColor Yellow }
function Bad { param([string]$M) Write-Host "    FAIL    $M" -ForegroundColor Red }

# Common Configuration Manager problem codes. Anything else is printed verbatim.
$codeMeaning = @{
    1  = 'not configured (no driver)'
    3  = 'driver corrupt'
    10 = 'cannot start'
    12 = 'not enough resources'
    14 = 'needs a restart'
    18 = 'reinstall the driver'
    19 = 'registry corrupt'
    21 = 'being removed'
    22 = 'disabled by the user or by policy'
    24 = 'device not present'
    28 = 'no driver installed'
    43 = 'the device reported a failure and Windows stopped it'
    45 = 'not currently connected'
    52 = 'driver signature not verified'
}

Write-Output '===== reset-failed-devices ====='
if ($Reset) {
    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $elevated -and -not $WhatIfPreference) {
        Bad 'Reset needs an elevated session. Re-run as administrator, or use -WhatIf to preview.'
        return
    }
    Say 'RESET mode: affected devices will be disabled, re-enabled and rescanned' Yellow
}
else { Say 'report-only mode (pass -Reset to actually reset)' }

$devices = @(Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })
if ($Class) { $devices = @($devices | Where-Object { $_.Class -eq $Class }) }

if (-not $devices.Count) {
    Ok 'every device is in OK state'
    return
}

Say ''
Say "found $($devices.Count) device(s) not in OK state:"
$rows = foreach ($d in $devices) {
    $code = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue).Data
    $driver = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion' -ErrorAction SilentlyContinue).Data
    $provider = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_DriverProvider' -ErrorAction SilentlyContinue).Data
    [pscustomobject]@{
        Name    = $d.FriendlyName
        Class   = $d.Class
        Status  = $d.Status
        Code    = $code
        Meaning = $(if ($code -and $codeMeaning.ContainsKey([int]$code)) { $codeMeaning[[int]$code] } else { '' })
        Driver  = "$provider $driver".Trim()
    }
}
$rows | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Output

Say 'reading the result:'
Say '    Code 43 / 10 / 12  -> the device itself reported a problem. Driver, firmware or a stuck radio.'
Say '    Code 28 / 1 / 18   -> no usable driver installed. Install the VENDOR driver.'
Say '    Code 22            -> soft-disabled. Re-enable it (this script) or check policy.'
Say '    Code 45 / 24       -> the device is simply not attached right now. Not a fault.'
Say ''
Say 'before blaming an optimizer: check whether the device ever worked. A device problem is'
Say 'rarely caused by a service tweak - usually it is the driver. See the SKILL for the'
Say 'three-step order (full power-off -> vendor driver -> treat as hardware).'
Say ''

if (-not $Reset) {
    Say "re-run with -Reset to disable/enable these devices and rescan. Use -WhatIf first."
    return
}

foreach ($d in $devices) {
    if ($PSCmdlet.ShouldProcess("$($d.FriendlyName) ($($d.InstanceId))", 'disable, re-enable, rescan')) {
        try {
            Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 2
            Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 3
            Ok "$($d.FriendlyName): reset attempted"
        }
        catch { Bad "$($d.FriendlyName): reset failed - $($_.Exception.Message)" }
    }
}

if ($PSCmdlet.ShouldProcess('hardware rescan', 'pnputil /scan-devices')) {
    & pnputil.exe /scan-devices | Out-Null
    Start-Sleep -Seconds 3
}

Say ''
Say 'after the reset:'
foreach ($d in $devices) {
    $now = (Get-PnpDevice -InstanceId $d.InstanceId -ErrorAction SilentlyContinue).Status
    if ($now -eq 'OK') { Ok "$($d.FriendlyName) is OK now" }
    else { Warn "$($d.FriendlyName) is still $now - do a FULL power-off, then install the vendor driver" }
}
Say ''
Say 'reminder: a reboot does not power-cycle a USB or PCIe radio. Shut down, unplug or hold the'
Say 'power button for ~10s, then boot again.'
