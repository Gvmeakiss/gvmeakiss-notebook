# Phase 'verify' - dot-sourced by setup.ps1 in execution order.
#
# The guard below ($phases -contains ...) is kept inside this file on purpose: dot-sourcing
# runs it in setup.ps1's own scope, so the block still sees that script's variables and
# helpers, and the phase only runs when it was selected.

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