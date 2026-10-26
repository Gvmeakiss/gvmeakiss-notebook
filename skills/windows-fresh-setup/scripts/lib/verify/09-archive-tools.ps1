# verify-env section: archive tools - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

# ------------------------------------------------------------------ archive tools
# 7-Zip and WinRAR are declared as winget entries in apps.json, and a missing archiver blocks
# the whole apps phase (.7z assets cannot be unpacked). Each gets its own line instead of
# hiding inside an aggregate claim, and the probe reads the install location first because
# 7-Zip does not have to be on PATH - asking only 'Get-Command 7z' is what let a missing
# install read as healthy before.
$pfRoot   = $env:ProgramFiles
$pfRoot86 = ${env:ProgramFiles(x86)}
$sevenCandidates = @((Join-Path $pfRoot '7-Zip\7z.exe'))
if ($pfRoot86) { $sevenCandidates += (Join-Path $pfRoot86 '7-Zip\7z.exe') }
$sevenHit = @($sevenCandidates | Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1
if (-not $sevenHit) { $sevenHit = (Get-Command '7z' -ErrorAction SilentlyContinue).Source }
Record 'archives' '7-Zip' ([bool]$sevenHit) $(if ($sevenHit) { $sevenHit } else { 'missing - the winget entry 7zip.7zip did not land' })

$rarCandidates = @((Join-Path $pfRoot 'WinRAR\WinRAR.exe'))
if ($pfRoot86) { $rarCandidates += (Join-Path $pfRoot86 'WinRAR\WinRAR.exe') }
$rarHit = @($rarCandidates | Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1
Record 'archives' 'WinRAR' ([bool]$rarHit) $(if ($rarHit) { $rarHit } else { 'missing - the winget entry RARLab.WinRAR did not land' })
