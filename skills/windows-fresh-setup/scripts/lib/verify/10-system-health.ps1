# verify-env section: system health - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

# ------------------------------------------------------------------ system health
# Four checks that the original checklist did not cover. Each one came from a real
# measurement on a machine where "everything green" still left room:
#   * pagefile - system managed is the right default; a hand-set tiny pagefile is not
#   * startup  - installer leftovers (OneDriveSetup under the service accounts) and
#                browser auto-launch keep starting things nobody asked for
#   * nic power - PnPCapabilities=24 is the documented fix; a value of 0 lets Windows
#                power the adapter down, which shows up as random drops in games
#   * gpu age  - an old driver is not a defect, so this one is informational only
$pfManaged = $false
try { $pfManaged = [bool](Get-CimInstance Win32_ComputerSystem -EA Stop).AutomaticManagedPagefile } catch { }
$pfSetting = @(Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue)
$pfDetail = if ($pfManaged) {
    'system managed' + $(if ($pfSetting.Count -gt 0) { " (explicit entry also present: $($pfSetting[0].InitialSize) MB)" } else { '' })
}
else {
    $size = if ($pfSetting.Count -gt 0) { "$($pfSetting[0].InitialSize) MB" } else { 'no pagefile setting found' }
    "fixed size: $size"
}
Record 'system' 'pagefile' ($pfManaged -or ($pfSetting.Count -gt 0)) $pfDetail

# Desktop integrity label. A non-Medium label (typically Low, left behind by a sandbox or
# agent tooling that confined the workspace) makes the shell refuse to resolve shortcut
# target icons, so every .lnk under the Desktop shows the generic document icon. Nothing
# about the icon file is wrong in that state, which is why icon-cache rebuilds and
# IconLocation edits appear to do nothing. See docs/reference/pitfalls.md section 6.
#
# Read the label from the security descriptor (LABEL_SECURITY_INFORMATION) rather than
# parsing `icacls` output: that output is localised, so matching "Low Mandatory Level"
# silently fails on a non-English Windows. A failed query, a missing folder, or an
# unparsable descriptor must NEVER be reported as Medium.
$deskPath = $null
try { $deskPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop) } catch { }
if ([string]::IsNullOrWhiteSpace($deskPath)) {
    $deskPath = [Environment]::ExpandEnvironmentVariables([string](
        (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name 'Desktop' -ErrorAction SilentlyContinue).Desktop))
}
$ilOk = $false
$ilDetail = ''
if ([string]::IsNullOrWhiteSpace($deskPath) -or -not (Test-Path -LiteralPath $deskPath)) {
    $ilDetail = "cannot locate the Desktop folder (resolved: '$deskPath')"
}
else {
    if (-not ('IlLabel' -as [type])) {
        Add-Type -TypeDefinition ([string]::Join([Environment]::NewLine, @(
            'using System;',
            'using System.Runtime.InteropServices;',
            'public static class IlLabel {',
            '    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]',
            '    static extern uint GetNamedSecurityInfoW(string objectName, int objectType, uint securityInfo,',
            '        out IntPtr owner, out IntPtr group, out IntPtr dacl, out IntPtr sacl, out IntPtr sd);',
            '    [DllImport("kernel32.dll")]',
            '    static extern IntPtr LocalFree(IntPtr handle);',
            '    public static string Read(string path) {',
            '        IntPtr owner, group, dacl, sacl, sd;',
            '        uint rc = GetNamedSecurityInfoW(path, 1, 0x10, out owner, out group, out dacl, out sacl, out sd);',
            '        if (rc != 0) { return "Error:" + rc; }',
            '        try {',
            '            if (sacl == IntPtr.Zero) { return "None"; }',
            '            int count = Marshal.ReadInt16(sacl, 4);',
            '            int offset = 8;',
            '            for (int i = 0; i < count; i++) {',
            '                byte aceType = Marshal.ReadByte(sacl, offset);',
            '                int aceSize = (int)Marshal.ReadInt16(sacl, offset + 2);',
            '                if (aceSize <= 0) { return "Error:badace"; }',
            '                if (aceType == 0x11) {',
            '                    IntPtr sid = new IntPtr(sacl.ToInt64() + offset + 8);',
            '                    int level = Marshal.ReadInt32(sid, 8);',
            '                    if (level == 0x0000) { return "Untrusted"; }',
            '                    if (level == 0x1000) { return "Low"; }',
            '                    if (level == 0x2000) { return "Medium"; }',
            '                    if (level == 0x3000) { return "High"; }',
            '                    if (level == 0x4000) { return "System"; }',
            '                    return "Unknown:" + level;',
            '                }',
            '                offset += aceSize;',
            '            }',
            '            return "None";',
            '        } finally { LocalFree(sd); }',
            '    }',
            '}'
        )))
    }
    $ilResult = 'Error:threw'
    try { $ilResult = [IlLabel]::Read($deskPath) } catch { $ilResult = 'Error:exception' }
    if ($ilResult -eq 'Medium') {
        $ilOk = $true; $ilDetail = "Medium ('$deskPath')"
    } elseif ($ilResult -eq 'None') {
        $ilOk = $true; $ilDetail = "no explicit label - defaults to Medium ('$deskPath')"
    } elseif ($ilResult -eq 'Low') {
        $ilDetail = "Low - the shell will show generic icons for .lnk files; fix: icacls `"$deskPath`" /setintegritylevel (OI)(CI)M /t"
    } elseif ($ilResult -eq 'High') {
        $ilDetail = 'High - unexpected for the Desktop folder; shortcut icons and drag-and-drop may misbehave'
    } elseif ($ilResult -eq 'System') {
        $ilDetail = 'System - unexpected for the Desktop folder; investigate before trusting icon behaviour'
    } elseif ($ilResult -eq 'Untrusted') {
        $ilDetail = 'Untrusted - the shell refuses most operations under the Desktop'
    } else {
        $ilDetail = "could not determine the integrity label ($ilResult)"
    }
}
Record 'system' 'desktop integrity level' $ilOk $ilDetail
$startupLeftovers = New-Object System.Collections.Generic.List[string]
foreach ($hive in @('Registry::HKEY_USERS\S-1-5-19\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                    'Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
    if (Test-Path $hive) {
        $v = Get-ItemProperty -Path $hive -Name 'OneDriveSetup' -ErrorAction SilentlyContinue
        if ($null -ne $v) { $startupLeftovers.Add('OneDriveSetup') }
    }
}
$hkcuRun = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
if ($hkcuRun) {
    foreach ($p in $hkcuRun.PSObject.Properties) {
        if ($p.Name -notlike 'PS*' -and $p.Name -like 'MicrosoftEdgeAutoLaunch*') { $startupLeftovers.Add($p.Name) }
    }
}
$startupDetail = if ($startupLeftovers.Count -eq 0) { 'no installer leftovers, no browser auto-launch' }
                 else { 'leftovers present: ' + (($startupLeftovers | Select-Object -Unique) -join ', ') }
Record 'system' 'startup leftovers' ($startupLeftovers.Count -eq 0) $startupDetail

$nicBases = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
    Where-Object { $_.DriverDesc -and $_.DriverDesc -match 'Ethernet' -and $_.PSObject.Properties.Name -contains 'PnPCapabilities' })
if ($nicBases.Count -eq 0) {
    Record 'system' 'nic power saving' $true 'no wired adapter with PnPCapabilities exposed (wireless or none)' -Optional
}
else {
    $bad = @($nicBases | Where-Object { [int]$_.PnPCapabilities -ne 24 })
    $detail = ($nicBases | ForEach-Object {
        $eee = if ($_.PSObject.Properties.Name -contains '*EEE') { "EEE=$($_.'*EEE')" } else { 'EEE=n/a' }
        "$($_.DriverDesc): PnPCapabilities=$($_.PnPCapabilities) $eee"
    }) -join ' | '
    Record 'system' 'nic power saving' ($bad.Count -eq 0) $detail
}

$gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.DriverDate })
$gpuDetail = 'no video controller reported a driver date'
$gpuDays = -1
foreach ($g in $gpu) {
    $days = [int]((Get-Date) - $g.DriverDate).TotalDays
    if ($gpuDays -lt 0 -or $days -gt $gpuDays) { $gpuDays = $days }
    $gpuDetail = "$($g.Name): driver $($g.DriverVersion) dated $($g.DriverDate.ToString('yyyy-MM-dd')), $days days old"
}
Record 'system' 'gpu driver age' $true $gpuDetail -Optional

# Vendor telemetry. Optional on purpose: the skill never promises to turn it off, so an
# enabled program is a user choice, not a defect - but if it was turned off it should stay
# off, and only a readback proves that. Measured facts that make this worth a line:
# AMD ships "AMD User Experience Program", stores consent in AMDAnalytics\AnalyticsAccepted,
# and uploads through the AUEPLauncher service. Setting the consent alone does not stop the
# service from being started, so both are checked.
$amdKey = 'HKLM:\SOFTWARE\AMD\AMDAnalytics'
if (Test-Path -LiteralPath $amdKey) {
    $accepted = (Get-ItemProperty -Path $amdKey -Name 'AnalyticsAccepted' -ErrorAction SilentlyContinue).AnalyticsAccepted
    $auep = Get-Service -Name 'AUEPLauncher' -ErrorAction SilentlyContinue
    $auepState = if ($auep) { "$($auep.Status)/$($auep.StartType)" } else { 'not installed' }
    $telemetryOff = -not (($accepted -eq 'true') -or ($auep -and $auep.Status -eq 'Running'))
    $amdDetail = if ($telemetryOff) { "off (AnalyticsAccepted=$accepted, AUEPLauncher=$auepState)" }
                 else { "on (AnalyticsAccepted=$accepted, AUEPLauncher=$auepState)" }
    Record 'system' 'amd telemetry' $telemetryOff $amdDetail -Optional
}
else {
    Record 'system' 'amd telemetry' $true 'no AMD analytics key (non-AMD machine)' -Optional
}

# A restore point is the only built-in undo the skill can offer before registry edits, and it
# is easy to have zero without noticing: they live on the volume, so a disk migration or a
# system reset wipes them (measured: 0 present after a clone). Informational - a machine that
# has not been tuned yet is not broken - but the moment tune runs, this is what makes it
# reversible.
$rpCount = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
$rpDetail = if ($rpCount -gt 0) { "$rpCount restore point(s) available" }
            else { 'none - run setup.ps1 -Phase tune (it creates one with the 24h dedupe bypassed), or Checkpoint-Computer' }
Record 'system' 'restore point' ($rpCount -gt 0) $rpDetail -Optional
