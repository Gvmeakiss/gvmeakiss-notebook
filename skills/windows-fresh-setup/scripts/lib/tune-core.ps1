# Pure helpers for the tune phase.
#
# Why these live in their own file: they are the only part of setup.ps1 that can be tested
# without touching a live machine. Everything else in the script reads or writes real state, so
# the only way to check it was to run the whole phase and inspect the result. Extracting the
# pure functions makes a zero-dependency test possible (scripts/test-tune-core.ps1) and keeps
# the arithmetic - which is where the 0xffffffff bug lived - under a test that runs in a second.
#
# ASCII-only, like every other script in this folder: Windows PowerShell 5.1 decodes a
# BOM-less file as ANSI, so a non-ASCII byte here would break parsing in a 5.1 child host.

function ConvertTo-RegDword {
    # .reg files want either a small decimal or an 8-digit hex. Both -1 and 0xffffffff must
    # render as ffffffff: NetworkThrottlingIndex is written as 0xffffffff, and PowerShell hands
    # it over as either -1 (int) or 4294967295 (uint) depending on how it was parsed.
    param($Value)
    $n = [int64]$Value
    if ($n -lt 0) { $n += 4294967296 }
    if ($n -lt 0 -or $n -gt 4294967295) { throw "value out of DWORD range: $Value" }
    return ('{0:x8}' -f $n)
}

function Format-UndoValue {
    # Renders a captured value back into PowerShell source for the generated undo script.
    # Strings are single-quoted with '' escaping, so a value containing quotes still round-trips.
    param($Value, [string]$Type)
    if ($Type -eq 'DWord') { return [string]([int64]$Value) }
    return "'" + ("$Value" -replace "'", "''") + "'"
}

function Test-BuildGate {
    # A rule may declare MinBuild / MaxBuild. Returns $true when the rule applies to this build.
    # Measured reason this exists: the periodic registry backup is dead on build 26xxx while the
    # same registry value is meaningful on older builds - a rule that cannot express that either
    # lies on one of them or has to be removed for both.
    param([int]$Build, $MinBuild, $MaxBuild)
    if ($MinBuild -and $Build -lt [int]$MinBuild) { return $false }
    if ($MaxBuild -and $Build -gt [int]$MaxBuild) { return $false }
    return $true
}
