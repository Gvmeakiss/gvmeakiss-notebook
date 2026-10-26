<#
.SYNOPSIS
  Prove each toolchain works by actually compiling and running code.

.DESCRIPTION
  A version string is not evidence: a toolchain can print "--version" and still be
  unusable (misconfigured PATH, wrong target, missing linker, mirror unreachable).
  This script performs a real build+run per language in a temp directory, and fetches
  a dependency where that exercises the configured mirror.

  Everything runs under the system temp directory and is removed afterwards.

.PARAMETER Languages
  Subset to verify. Default: python node go rust java dotnet cpp
  Accepted: python node go rust java dotnet cpp

.PARAMETER KeepArtifacts
  Leave the temp working directory in place for inspection.

.EXAMPLE
  pwsh -File verify-env.ps1
  pwsh -File verify-env.ps1 -Languages python,go,rust

.NOTES
  ASCII-only on purpose.
#>
[CmdletBinding()]
param(
    [string[]]$Languages = @('python','node','go','rust','java','dotnet','cpp'),
    [switch]$KeepArtifacts
)

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot   # modules use $here: $PSScriptRoot would point at their own directory
$results = [System.Collections.ArrayList]::new()

# Rebuild PATH from the registry (Machine + User) so a stale parent environment cannot
# make an installed toolchain look absent.
$env:PATH = (@(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User')
) | Where-Object { $_ }) -join ';'

$root = Join-Path $env:TEMP ("dsh-verify-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $root | Out-Null

# Pass is deliberately untyped: 'SKIP' means "this check could not be exercised here".
# SKIP is NOT a pass: it is printed as SKIP and counted separately, because a check that never
# ran must never be reported as proof that the toolchain works.
function Record {
    param([string]$Lang, [string]$Check, $Pass, [string]$Detail, [switch]$Optional)
    $isSkip = ($Pass -is [string]) -and ($Pass -eq 'SKIP')
    $passBool = (-not $isSkip) -and [bool]$Pass
    $tag = if ($isSkip) { 'SKIP' } elseif ($passBool) { 'PASS' } elseif ($Optional) { 'INFO' } else { 'FAIL' }
    [void]$results.Add([pscustomobject]@{
        Language = $Lang; Check = $Check; Pass = $passBool; Skipped = $isSkip
        Optional = [bool]$Optional; Detail = $Detail
    })
    Write-Output ("  [{0}] {1,-9} {2,-26} {3}" -f $tag, $Lang, $Check, $Detail)
}
function Have { param([string]$Exe) [bool](Get-Command $Exe -ErrorAction SilentlyContinue) }

Write-Output '===== verify-env: build-and-run proof per toolchain ====='
Write-Output "work dir: $root"

. (Join-Path $PSScriptRoot 'lib/verify/01-python.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/02-node.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/03-go.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/04-rust.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/05-java.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/06-dotnet.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/07-cpp.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/08-git-gh.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/09-archive-tools.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/10-system-health.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/11-game-runtimes.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/12-script-hygiene.ps1')
. (Join-Path $PSScriptRoot 'lib/verify/13-tune-tweaks-survival.ps1')
# ------------------------------------------------------------------ summary
Write-Output "`n===== summary ====="
$grouped = $results | Group-Object Language
$failed = @($results | Where-Object { -not $_.Pass -and -not $_.Optional -and -not $_.Skipped })
$informational = @($results | Where-Object { -not $_.Pass -and $_.Optional -and -not $_.Skipped })
$skippedChecks = @($results | Where-Object { $_.Skipped })
foreach ($g in $grouped) {
    $bad = @($g.Group | Where-Object { -not $_.Pass -and -not $_.Optional -and -not $_.Skipped }).Count
    $sk = @($g.Group | Where-Object { $_.Skipped }).Count
    $tag = if ($bad -eq 0) { 'OK  ' } else { 'FAIL' }
    $extra = if ($sk -gt 0) { " ($sk skipped)" } else { '' }
    Write-Output ("  [{0}] {1,-8} {2}/{3} checks passed{4}" -f $tag, $g.Name, ($g.Count - $bad - $sk), ($g.Count - $sk), $extra)
}
Write-Output ("`ntotal: {0} checks, {1} failed, {2} informational, {3} skipped" -f $results.Count, $failed.Count, $informational.Count, $skippedChecks.Count)
if ($skippedChecks.Count -gt 0) {
    Write-Output 'skipped (not exercised on this machine - NOT a pass):'
    $skippedChecks | ForEach-Object { "  - $($_.Language)/$($_.Check): $($_.Detail)" }
}
if ($informational.Count -gt 0) {
    Write-Output 'informational (not a toolchain defect):'
    $informational | ForEach-Object { "  - $($_.Language)/$($_.Check): $($_.Detail)" }
}
if ($failed.Count -gt 0) {
    Write-Output 'failing checks:'
    $failed | ForEach-Object { "  - $($_.Language)/$($_.Check): $($_.Detail)" }
}
if (-not $KeepArtifacts) { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
else { Write-Output "artifacts kept at: $root" }
if ($failed.Count -gt 0) { exit 1 }