# Phase 'link' - dot-sourced by setup.ps1 in execution order.
#
# The guard below ($phases -contains ...) is kept inside this file on purpose: dot-sourcing
# runs it in setup.ps1's own scope, so the block still sees that script's variables and
# helpers, and the phase only runs when it was selected.

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