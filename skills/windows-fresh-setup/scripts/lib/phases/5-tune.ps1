# Phase 'tune' - dot-sourced by setup.ps1 in execution order.
#
# The guard below ($phases -contains ...) is kept inside this file on purpose: dot-sourcing
# runs it in setup.ps1's own scope, so the block still sees that script's variables and
# helpers, and the phase only runs when it was selected.

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
        # The write list lives in lib/tune-writes.ps1 so that the writes, the acceptance checks
        # and the documented counts can be checked against one source instead of three copies.
        . (Join-Path $here 'lib\tune-writes.ps1')   # $here is setup.ps1's scripts directory (this file lives in lib/phases)
        $changes = @($TuneWrites)
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