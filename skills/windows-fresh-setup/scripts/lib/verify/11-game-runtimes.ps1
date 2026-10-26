# verify-env section: game runtimes - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

# ------------------------------------------------------------------ game runtimes
# A freshly cloned or freshly installed Windows can pass every language check and still be
# unable to start a game, because the Visual C++ runtimes are not part of the OS. Measured on
# a real machine after a disk migration: VC++ 2008 / 2010 / 2012 / 2013 were ALL absent while
# every other check was green, and League of Legends is exactly the kind of title that trips
# on that. So the generations are checked one by one instead of being assumed.
#
# Two different installation models have to be handled, and mixing them up produces false
# results in both directions:
#   VC++ 2005 / 2008 -> side-by-side assemblies, present only as WinSxS folders
#   VC++ 2010+       -> plain DLLs in System32 (x64) and SysWOW64 (x86)
function Test-SxSVersion {
    param([string]$Tag)
    return (@(Get-ChildItem 'C:\Windows\WinSxS' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "${Tag}_*" }).Count -gt 0)
}
function Test-CrtFiles {
    param([string]$Dll)
    $x86 = Test-Path -LiteralPath (Join-Path $env:SystemRoot "SysWOW64\$Dll")
    $x64 = Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32\$Dll")
    return ($x86 -and $x64)
}

$vc80 = Test-SxSVersion 'x86_microsoft.vc80.crt'
$vc90 = Test-SxSVersion 'x86_microsoft.vc90.crt'
Record 'runtimes' 'vc++ 2005/2008 (SxS)' ($vc80 -and $vc90) "vc80=$vc80 vc90=$vc90 (side-by-side assemblies; no files in System32 is normal here)"

foreach ($vc in @(
    @{ Name = 'vc++ 2010'; Dll = 'msvcr100.dll' },
    @{ Name = 'vc++ 2012'; Dll = 'msvcr110.dll' },
    @{ Name = 'vc++ 2013'; Dll = 'msvcr120.dll' },
    @{ Name = 'vc++ 2015-2022'; Dll = 'vcruntime140.dll' }
)) {
    $ok = Test-CrtFiles $vc.Dll
    $d = "$($vc.Dll) x86=$(Test-Path -LiteralPath "$env:SystemRoot\SysWOW64\$($vc.Dll)") x64=$(Test-Path -LiteralPath "$env:SystemRoot\System32\$($vc.Dll)")"
    Record 'runtimes' $vc.Name $ok $d
}

# .NET 3.5: informational only. On current Windows images the payload is removed, so enabling
# it needs Windows Update or an ISO source - its absence is a choice, not a defect.
$netfx3 = $false
try {
    $feat = & dism.exe /english /online /get-features /format:table 2>$null | Select-String 'NetFx3 '
    $netfx3 = ($feat -join ' ') -match 'Enabled'
}
catch { }
$netfx3Detail = if ($netfx3) { 'enabled' } else { 'not enabled - needs a Windows Update or ISO payload; only very old titles require it' }
Record 'runtimes' '.net 3.5' $netfx3 $netfx3Detail -Optional
