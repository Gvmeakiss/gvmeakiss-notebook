# Phase 'drivers' - dot-sourced by setup.ps1 in execution order.
#
# The guard below ($phases -contains ...) is kept inside this file on purpose: dot-sourcing
# runs it in setup.ps1's own scope, so the block still sees that script's variables and
# helpers, and the phase only runs when it was selected.

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