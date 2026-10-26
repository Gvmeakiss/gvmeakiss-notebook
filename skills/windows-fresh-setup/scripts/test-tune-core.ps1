# Zero-dependency tests for the pure tune helpers.
#
# No Pester: the skill must run on a fresh machine where nothing is installed, and a test suite
# that needs a module is a test suite that never runs there. Each case is one assertion; the
# script exits non-zero on the first failure so it can be wired into any gate.
#
#   pwsh -File scripts/test-tune-core.ps1

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'lib/tune-core.ps1')

$script:passed = 0
$script:failed = 0

function Assert-Equal {
    param([string]$Name, $Expected, $Actual)
    if ("$Expected" -eq "$Actual") { $script:passed++; Write-Host "  ok    $Name" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  FAIL  $Name : expected [$Expected] got [$Actual]" -ForegroundColor Red }
}

function Assert-Throws {
    param([string]$Name, [scriptblock]$Block)
    try { & $Block; $script:failed++; Write-Host "  FAIL  $Name : expected a throw, none happened" -ForegroundColor Red }
    catch { $script:passed++; Write-Host "  ok    $Name" -ForegroundColor Green }
}

Write-Host '--- ConvertTo-RegDword' -ForegroundColor Cyan
Assert-Equal 'zero' '00000000' (ConvertTo-RegDword 0)
Assert-Equal 'one' '00000001' (ConvertTo-RegDword 1)
Assert-Equal 'thirty' '0000001e' (ConvertTo-RegDword 30)
Assert-Equal 'negative one is ffffffff' 'ffffffff' (ConvertTo-RegDword -1)
Assert-Equal 'uint max is ffffffff' 'ffffffff' (ConvertTo-RegDword 4294967295)
Assert-Equal '0xffffffff literal' 'ffffffff' (ConvertTo-RegDword 0xffffffff)
Assert-Throws 'out of range rejects' { ConvertTo-RegDword 4294967296 }

Write-Host '--- Format-UndoValue' -ForegroundColor Cyan
Assert-Equal 'dword stays numeric' '10' (Format-UndoValue 10 'DWord')
Assert-Equal 'dword negative stays numeric' '-1' (Format-UndoValue -1 'DWord')
Assert-Equal 'string gets quoted' "'High'" (Format-UndoValue 'High' 'String')
Assert-Equal 'empty string is two quotes' "''" (Format-UndoValue '' 'String')
Assert-Equal 'inner quote escaped' "'a''b'" (Format-UndoValue "a'b" 'String')

Write-Host '--- Test-BuildGate' -ForegroundColor Cyan
Assert-Equal 'no bounds applies' 'True' (Test-BuildGate -Build 26100)
Assert-Equal 'min satisfied' 'True' (Test-BuildGate -Build 26100 -MinBuild 22000)
Assert-Equal 'min not satisfied' 'False' (Test-BuildGate -Build 19045 -MinBuild 22000)
Assert-Equal 'max satisfied' 'True' (Test-BuildGate -Build 22621 -MaxBuild 22621)
Assert-Equal 'max exceeded' 'False' (Test-BuildGate -Build 26100 -MaxBuild 22621)
Assert-Equal 'both bounds inside' 'True' (Test-BuildGate -Build 22621 -MinBuild 22000 -MaxBuild 26100)

Write-Host ''
if ($script:failed -eq 0) {
    Write-Host "  ok    $($script:passed) assertion(s) passed" -ForegroundColor Green
    exit 0
}
Write-Host "  FAIL  $($script:failed) failed, $($script:passed) passed" -ForegroundColor Red
exit 1
