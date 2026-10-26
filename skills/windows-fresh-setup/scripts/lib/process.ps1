# ---------------------------------------------------------------------------
# Sub-process helpers (extracted from setup.ps1, P2-6 modularisation).
#
# Two things live here because every phase needs them and they are easy to get wrong:
#
#   Test-ChildSupportsWhatIf - a child script that declares SupportsShouldProcess accepts
#     -WhatIf; one that does not rejects it with a parameter-binding error, so the flag cannot
#     be forwarded blindly. The answer is cached per path.
#
#   Invoke-Step - run a sibling script through the preferred PowerShell host and report whether
#     it exited 0. It forwards -WhatIf only to children that can take it, and skips writers that
#     cannot: measured, `-Phase tune -WhatIf` really wrote two snapshot CSV files before this.
#
# These rely on setup.ps1's own scope being visible (dot-sourced, not called as a child):
#   $here     - the scripts directory (NOT $PSScriptRoot: that points at this lib directory)
#   $pwshExe  - the host executable chosen by the caller
#   Bad / Step - the caller's output helpers
# ---------------------------------------------------------------------------

$script:whatIfSupport = @{}

function Test-ChildSupportsWhatIf {
    param([string]$Path)
    if ($script:whatIfSupport.ContainsKey($Path)) { return $script:whatIfSupport[$Path] }
    $ok = $false
    try { $ok = ((Get-Content -LiteralPath $Path -Raw -ErrorAction Stop) -match 'SupportsShouldProcess') } catch { }
    $script:whatIfSupport[$Path] = $ok
    return $ok
}

function Invoke-Step {
    param([string]$File, [string[]]$Arguments, [string]$What)
    $p = Join-Path $here $File
    if (-not (Test-Path $p)) { Bad "$File not found"; return $false }
    Step $What
    $callArgs = @($Arguments)
    if ($WhatIfPreference -and (Test-ChildSupportsWhatIf $p)) { $callArgs += '-WhatIf' }
    elseif ($WhatIfPreference) {
        # The child does not accept -WhatIf. Two very different cases hide here:
        #   * a read-only probe (audit-env / check-software / diagnose-ime / verify-env /
        #     compare-services) - running it is safe and makes the dry run informative;
        #   * a writer (install-portable / setup-langs / fix-env / snapshot-services /
        #     set-app-associations / clean-orphan-associations) - running it would perform
        #     the very work the dry run is supposed to preview.
        $readOnlyChildren = @('audit-env.ps1', 'check-software.ps1', 'diagnose-ime.ps1', 'verify-env.ps1', 'compare-services.ps1')
        if ($readOnlyChildren -notcontains $File) {
            Write-Host ("     would run {0} {1} (skipped: this child has no -WhatIf support)" -f $File, ($Arguments -join ' ')) -ForegroundColor Cyan
            return $true
        }
    }
    $out = & $pwshExe -NoProfile -File $p @callArgs 2>&1
    $out | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
    return ($LASTEXITCODE -eq 0)
}
