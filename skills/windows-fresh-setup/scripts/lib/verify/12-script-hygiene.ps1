# verify-env section: script hygiene - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

# ------------------------------------------------------------------ script hygiene
# Why this is a verification step and not just a note in SKILL.md:
# a BOM-less file is decoded as UTF-8 by [Parser]::ParseFile but as ANSI by
# `powershell.exe -File`, so a "parse OK" validation produces a FALSE PASS and the script
# then dies at runtime in any 5.1 child host (Task Scheduler always spawns 5.1). Documenting
# that trap did not prevent it from happening twice, so it is checked mechanically here.
#
# Called as a CHILD process, and the verdict is read from the reported table rather than
# from $LASTEXITCODE. Two traps were hit while writing this block:
#   * $LASTEXITCODE is NOT set by an in-process `& script.ps1` call - it keeps a stale value
#     from an earlier child process, which yields a false PASS.
#   * this file has no $pwshExe (that variable belongs to setup.ps1); calling it silently
#     produced "no summary line".
Write-Output "`n--- script hygiene (encoding + dual-host parse)"
$hygieneHost = (Get-Command 'pwsh' -ErrorAction SilentlyContinue).Source
if (-not $hygieneHost) { $hygieneHost = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
$hygiene = Join-Path $here 'check-script-hygiene.ps1'
if (Test-Path $hygiene) {
    $hygieneOut = & $hygieneHost -NoProfile -NonInteractive -File $hygiene -Path $here 2>&1
    $hygieneCode = $LASTEXITCODE
    $summary = @($hygieneOut | Where-Object { [string]$_ -match 'hygiene summary' })
    $detail  = if ($summary.Count -gt 0) { $summary[0].ToString().Trim() } else { 'no summary line' }
    $fails   = @($hygieneOut | Where-Object { [string]$_ -match '\[FAIL\] ' })
    foreach ($f in $fails) { Write-Output ("      " + $f.ToString().Trim()) }
    # Both FAIL and WARN block. The directory policy is "ASCII-only, or UTF-8 with BOM";
    # a WARN means non-ASCII without a BOM, which parses today only by byte-alignment luck.
    # Measured: a small Chinese comment passed 5.1, a larger one died with
    # "The string is missing the terminator" - the same file shape, opposite outcomes.
    $hygieneOk = ($summary.Count -gt 0) -and ($detail -match '0 FAIL') -and ($detail -match '0 WARN') -and ($hygieneCode -eq 0)
    Record 'hygiene' 'scripts parse under PS 7 and PS 5.1' $hygieneOk $detail
} else {
    Record 'hygiene' 'check-script-hygiene.ps1 present' $false 'script missing' -Optional
}
