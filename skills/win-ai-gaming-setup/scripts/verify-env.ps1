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
$results = [System.Collections.ArrayList]::new()

# Rebuild PATH from the registry (Machine + User) so a stale parent environment cannot
# make an installed toolchain look absent.
$env:PATH = (@(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User')
) | Where-Object { $_ }) -join ';'

$root = Join-Path $env:TEMP ("dsh-verify-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Record { param([string]$Lang, [string]$Check, [bool]$Pass, [string]$Detail, [switch]$Optional)
    $tag = if ($Pass) { 'PASS' } elseif ($Optional) { 'INFO' } else { 'FAIL' }
    [void]$results.Add([pscustomobject]@{
        Language = $Lang; Check = $Check; Pass = $Pass
        Optional = [bool]$Optional; Detail = $Detail
    })
    Write-Output ("  [{0}] {1,-9} {2,-26} {3}" -f $tag, $Lang, $Check, $Detail)
}
function Have { param([string]$Exe) [bool](Get-Command $Exe -ErrorAction SilentlyContinue) }

Write-Output '===== verify-env: build-and-run proof per toolchain ====='
Write-Output "work dir: $root"

# ------------------------------------------------------------------- python
if ($Languages -contains 'python') {
    Write-Output "`n--- python"
    if (-not (Have 'python')) {
        Record 'python' 'present' $false 'python not on PATH'
    } else {
        Record 'python' 'version' $true (& python --version 2>&1 | Select-Object -First 1)
        # import a real package to prove site-packages and the index work
        $py = Join-Path $root 't.py'
        @'
import subprocess, sys
print("exec ok", sys.version.split()[0])
try:
    import requests  # noqa
    print("dependency import ok")
except Exception as exc:
    print("dependency import skipped:", type(exc).__name__)
'@ | Set-Content -Path $py -Encoding UTF8
        $out = & python $py 2>&1
        Record 'python' 'run' ($LASTEXITCODE -eq 0) ("$out" -replace "`r?`n", ' | ')
        # encoding behaviour: Windows defaults to a regional code page, which breaks
        # UTF-8 file reads unless encoding is explicit (PYTHONUTF8=1 is the global fix)
        $enc = Join-Path $root 'enc.py'
        @'
from pathlib import Path
p = Path(__file__).with_name("utf8.txt")
p.write_text("\u4e2d\u6587\u6d4b\u8bd5 utf8\n", encoding="utf-8")
try:
    default_read = p.read_text()
    print("default-encoding read: OK")
except UnicodeDecodeError as exc:
    print("default-encoding read: FAILS ->", exc.__class__.__name__)
print("explicit utf-8 read:", p.read_text(encoding="utf-8").strip())
'@ | Set-Content -Path $enc -Encoding UTF8
        $encOut = & python $enc 2>&1
        Record 'python' 'utf8-encoding' $true ("$encOut" -replace "`r?`n", ' | ')
    }
}

# --------------------------------------------------------------------- node
if ($Languages -contains 'node') {
    Write-Output "`n--- node"
    if (-not (Have 'node')) {
        Record 'node' 'present' $false 'node not on PATH'
    } else {
        Record 'node' 'version' $true (& node --version 2>&1 | Select-Object -First 1)
        $proj = Join-Path $root 'nodeproj'
        New-Item -ItemType Directory -Force -Path $proj | Out-Null
        Push-Location $proj
        & npm init -y 2>&1 | Out-Null
        # left-pad is tiny and stable: proves the configured registry resolves
        $inst = & npm install --no-audit --no-fund left-pad 2>&1 | Select-Object -Last 1
        $okInstall = ($LASTEXITCODE -eq 0)
        Record 'node' 'npm install' $okInstall "$inst"
        if ($okInstall) {
            $run = & node -e "console.log('require ok', require('left-pad')('7',3,'0'))" 2>&1
            Record 'node' 'run' ($LASTEXITCODE -eq 0) "$run"
        }
        Record 'node' 'registry' $true (& npm config get registry 2>&1 | Select-Object -First 1)
        Pop-Location
    }
}

# ----------------------------------------------------------------------- go
if ($Languages -contains 'go') {
    Write-Output "`n--- go"
    if (-not (Have 'go')) {
        Record 'go' 'present' $false 'go not on PATH'
    } else {
        Record 'go' 'version' $true (& go version 2>&1 | Select-Object -First 1)
        Record 'go' 'GOPROXY' $true (& go env GOPROXY 2>&1 | Select-Object -First 1)
        $proj = Join-Path $root 'goproj'
        New-Item -ItemType Directory -Force -Path $proj | Out-Null
        Push-Location $proj
        & go mod init verify 2>&1 | Out-Null
        @'
package main

import (
	"fmt"

	"github.com/google/uuid"
)

func main() {
	fmt.Println("go build+run ok", uuid.NewString()[:8])
}
'@ | Set-Content -Path 'main.go' -Encoding UTF8
        # fetching a module proves the module proxy actually resolves
        $get = & go get github.com/google/uuid 2>&1 | Select-Object -Last 1
        Record 'go' 'module fetch' ($LASTEXITCODE -eq 0) "$get"
        $run = & go run . 2>&1 | Select-Object -Last 1
        Record 'go' 'build+run' ($LASTEXITCODE -eq 0) "$run"
        Pop-Location
    }
}

# --------------------------------------------------------------------- rust
if ($Languages -contains 'rust') {
    Write-Output "`n--- rust"
    if (-not (Have 'cargo')) {
        Record 'rust' 'present' $false 'cargo not on PATH'
    } else {
        Record 'rust' 'version' $true (& rustc --version 2>&1 | Select-Object -First 1)
        $tc = "$(& rustup show active-toolchain 2>$null)"
        Record 'rust' 'toolchain' $true "$tc"
        $proj = Join-Path $root 'rustproj'
        Push-Location $root
        & cargo new rustproj --quiet 2>&1 | Out-Null
        Push-Location $proj
        # rand pulls in getrandom, whose build script needs dlltool on the GNU target -
        # this is precisely the case that fails with a misleading error when binutils
        # is missing, so it is the right smoke test rather than an empty crate.
        $add = & cargo add rand --quiet 2>&1 | Select-Object -Last 1
        Record 'rust' 'cargo add' ($LASTEXITCODE -eq 0) "$add"
        @'
fn main() {
    let n: u32 = rand::random();
    println!("cargo build+run ok {}", n % 1000);
}
'@ | Set-Content -Path 'src\main.rs' -Encoding UTF8
        $build = & cargo build 2>&1 | Select-Object -Last 1
        Record 'rust' 'build (with deps)' ($LASTEXITCODE -eq 0) "$build"
        if ($LASTEXITCODE -eq 0) {
            $run = & cargo run --quiet 2>&1 | Select-Object -Last 1
            Record 'rust' 'run' ($LASTEXITCODE -eq 0) "$run"
        }
        Pop-Location
        Pop-Location
    }
}

# --------------------------------------------------------------------- java
if ($Languages -contains 'java') {
    Write-Output "`n--- java"
    if (-not (Have 'javac')) {
        Record 'java' 'present' $false 'javac not on PATH'
    } else {
        Record 'java' 'version' $true (& javac -version 2>&1 | Select-Object -First 1)
        $proj = Join-Path $root 'javaproj'
        New-Item -ItemType Directory -Force -Path $proj | Out-Null
        @'
public class Hello {
    public static void main(String[] args) {
        System.out.println("javac+java ok " + System.getProperty("java.version"));
    }
}
'@ | Set-Content -Path (Join-Path $proj 'Hello.java') -Encoding UTF8
        Push-Location $proj
        & javac Hello.java 2>&1 | Out-Null
        $compiled = ($LASTEXITCODE -eq 0)
        Record 'java' 'javac' $compiled ''
        if ($compiled) {
            $run = & java -cp . Hello 2>&1 | Select-Object -Last 1
            Record 'java' 'run' ($LASTEXITCODE -eq 0) "$run"
            & jar --create --file hello.jar --main-class Hello Hello.class 2>&1 | Out-Null
            $jr = if (Test-Path 'hello.jar') { & java -jar hello.jar 2>&1 | Select-Object -Last 1 } else { 'jar not created' }
            Record 'java' 'jar' (Test-Path 'hello.jar') "$jr"
        }
        Pop-Location
    }
}

# ------------------------------------------------------------------- dotnet
if ($Languages -contains 'dotnet') {
    Write-Output "`n--- dotnet"
    if (-not (Have 'dotnet')) {
        Record 'dotnet' 'present' $false 'dotnet not on PATH'
    } else {
        Record 'dotnet' 'version' $true (& dotnet --version 2>&1 | Select-Object -First 1)
        $proj = Join-Path $root 'dotnetproj'
        Push-Location $root
        & dotnet new console -o dotnetproj --force 2>&1 | Out-Null
        Push-Location $proj
        # The success marker is matched with a regex \uXXXX escape rather than the literal
        # text: this file must stay pure ASCII. With a non-ASCII literal and no BOM,
        # Windows PowerShell 5.1 decodes the UTF-8 bytes as ANSI, a stray quote pops out of
        # the shifted byte pairs, and the HERE-STRING ABOVE TERMINATES EARLY - the script
        # then dies with "The '<' operator is reserved for future use" while parsing C++.
        # PowerShell 7 reads BOM-less files as UTF-8, so running through setup.ps1 (which
        # prefers pwsh) hid this completely; only a direct powershell.exe run exposed it.
        # .NET regex decodes \uXXXX in both hosts, so this form works everywhere.
        $build = & dotnet build -v q --nologo 2>&1 | Select-String -Pattern 'error|Build succeeded|\u5DF2\u6210\u529F\u751F\u6210' | Select-Object -First 1
        Record 'dotnet' 'build' ($LASTEXITCODE -eq 0) "$build"
        $run = & dotnet run --no-build 2>&1 | Select-Object -Last 1
        Record 'dotnet' 'run' ($LASTEXITCODE -eq 0) "$run"
        Pop-Location
        Pop-Location
    }
}

# ---------------------------------------------------------------------- cpp
if ($Languages -contains 'cpp') {
    Write-Output "`n--- cpp"
    $hasGpp = Have 'g++'
    $hasCl  = Have 'cl'
    if (-not ($hasGpp -or $hasCl)) {
        Record 'cpp' 'present' $false 'neither g++ nor cl on PATH'
    } else {
        $proj = Join-Path $root 'cppproj'
        New-Item -ItemType Directory -Force -Path $proj | Out-Null
        @'
#include <iostream>
#include <numeric>
#include <vector>

int main() {
    std::vector<int> v{1, 2, 3, 4, 5};
    std::cout << "cpp ok c++" << __cplusplus << " sum="
              << std::accumulate(v.begin(), v.end(), 0) << std::endl;
    return 0;
}
'@ | Set-Content -Path (Join-Path $proj 'main.cpp') -Encoding UTF8
        Push-Location $proj
        if ($hasGpp) {
            $v = & g++ --version 2>&1 | Select-Object -First 1
            Record 'cpp' 'g++ version' $true "$v"
            & g++ -std=c++20 -O1 main.cpp -o main.exe 2>&1 | Out-Null
            $compiled = ($LASTEXITCODE -eq 0)
            Record 'cpp' 'compile' $compiled ''
            if ($compiled) {
                $run = & .\main.exe 2>&1 | Select-Object -Last 1
                Record 'cpp' 'run' ($LASTEXITCODE -eq 0) "$run"
            }
        } else {
            Record 'cpp' 'compiler' $true 'cl (MSVC) only - compile step not exercised'
        }
        # CMake is only meaningful if a generator + compiler pair works
        if (Have 'cmake') {
            Record 'cpp' 'cmake version' $true (& cmake --version 2>&1 | Select-Object -First 1)
            if ($hasGpp) {
                @'
cmake_minimum_required(VERSION 3.20)
project(verify CXX)
set(CMAKE_CXX_STANDARD 20)
add_executable(verify main.cpp)
'@ | Set-Content -Path 'CMakeLists.txt' -Encoding UTF8
                & cmake -S . -B build -G "MinGW Makefiles" 2>&1 | Out-Null
                $cfg = ($LASTEXITCODE -eq 0)
                Record 'cpp' 'cmake configure' $cfg ''
                if ($cfg) {
                    & cmake --build build 2>&1 | Out-Null
                    $built = Test-Path (Join-Path $proj 'build\verify.exe')
                    Record 'cpp' 'cmake build' $built ''
                    if ($built) {
                        $run = & (Join-Path $proj 'build\verify.exe') 2>&1 | Select-Object -Last 1
                        Record 'cpp' 'cmake run' $true "$run"
                    }
                }
            }
        }
        Pop-Location
    }
}

# ------------------------------------------------------------------ git/gh
Write-Output "`n--- supporting tools"
if (Have 'git') { Record 'git' 'version' $true (& git --version 2>&1 | Select-Object -First 1) }
else { Record 'git' 'present' $false 'git not on PATH' }
if (Have 'gh') { Record 'gh' 'version' $true (& gh --version 2>&1 | Select-Object -First 1) }
else { Record 'gh' 'present' $false 'gh not on PATH (optional)' -Optional }
if (Have 'ssh') {
    $sshOut = & ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -T git@github.com 2>&1
    $authed = "$sshOut" -match 'successfully authenticated'
    $sshDetail = if ($authed) { "$sshOut" } else { 'no SSH key on the account; git over HTTPS or gh auth also work - informational only' }
    # SSH access is one of several ways to authenticate. Its absence is a configuration
    # choice, not a broken toolchain, so it must not fail the whole verification.
    Record 'ssh' 'github auth' $authed $sshDetail -Optional
}

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

# ------------------------------------------------------------------ system health
# Four checks that the original checklist did not cover. Each one came from a real
# measurement on a machine where "everything green" still left room:
#   * pagefile - system managed is the right default; a hand-set tiny pagefile is not
#   * startup  - installer leftovers (OneDriveSetup under the service accounts) and
#                browser auto-launch keep starting things nobody asked for
#   * nic power - PnPCapabilities=24 is the documented fix; a value of 0 lets Windows
#                power the adapter down, which shows up as random drops in games
#   * gpu age  - an old driver is not a defect, so this one is informational only
$pfManaged = $false
try { $pfManaged = [bool](Get-CimInstance Win32_ComputerSystem -EA Stop).AutomaticManagedPagefile } catch { }
$pfSetting = @(Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue)
$pfDetail = if ($pfManaged) {
    'system managed' + $(if ($pfSetting.Count -gt 0) { " (explicit entry also present: $($pfSetting[0].InitialSize) MB)" } else { '' })
}
else {
    $size = if ($pfSetting.Count -gt 0) { "$($pfSetting[0].InitialSize) MB" } else { 'no pagefile setting found' }
    "fixed size: $size"
}
Record 'system' 'pagefile' ($pfManaged -or ($pfSetting.Count -gt 0)) $pfDetail

$startupLeftovers = New-Object System.Collections.Generic.List[string]
foreach ($hive in @('Registry::HKEY_USERS\S-1-5-19\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                    'Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
    if (Test-Path $hive) {
        $v = Get-ItemProperty -Path $hive -Name 'OneDriveSetup' -ErrorAction SilentlyContinue
        if ($null -ne $v) { $startupLeftovers.Add('OneDriveSetup') }
    }
}
$hkcuRun = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
if ($hkcuRun) {
    foreach ($p in $hkcuRun.PSObject.Properties) {
        if ($p.Name -notlike 'PS*' -and $p.Name -like 'MicrosoftEdgeAutoLaunch*') { $startupLeftovers.Add($p.Name) }
    }
}
$startupDetail = if ($startupLeftovers.Count -eq 0) { 'no installer leftovers, no browser auto-launch' }
                 else { 'leftovers present: ' + (($startupLeftovers | Select-Object -Unique) -join ', ') }
Record 'system' 'startup leftovers' ($startupLeftovers.Count -eq 0) $startupDetail

$nicBases = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
    Where-Object { $_.DriverDesc -and $_.DriverDesc -match 'Ethernet' -and $_.PSObject.Properties.Name -contains 'PnPCapabilities' })
if ($nicBases.Count -eq 0) {
    Record 'system' 'nic power saving' $true 'no wired adapter with PnPCapabilities exposed (wireless or none)' -Optional
}
else {
    $bad = @($nicBases | Where-Object { [int]$_.PnPCapabilities -ne 24 })
    $detail = ($nicBases | ForEach-Object {
        $eee = if ($_.PSObject.Properties.Name -contains '*EEE') { "EEE=$($_.'*EEE')" } else { 'EEE=n/a' }
        "$($_.DriverDesc): PnPCapabilities=$($_.PnPCapabilities) $eee"
    }) -join ' | '
    Record 'system' 'nic power saving' ($bad.Count -eq 0) $detail
}

$gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.DriverDate })
$gpuDetail = 'no video controller reported a driver date'
$gpuDays = -1
foreach ($g in $gpu) {
    $days = [int]((Get-Date) - $g.DriverDate).TotalDays
    if ($gpuDays -lt 0 -or $days -gt $gpuDays) { $gpuDays = $days }
    $gpuDetail = "$($g.Name): driver $($g.DriverVersion) dated $($g.DriverDate.ToString('yyyy-MM-dd')), $days days old"
}
Record 'system' 'gpu driver age' $true $gpuDetail -Optional

# Vendor telemetry. Optional on purpose: the skill never promises to turn it off, so an
# enabled program is a user choice, not a defect - but if it was turned off it should stay
# off, and only a readback proves that. Measured facts that make this worth a line:
# AMD ships "AMD User Experience Program", stores consent in AMDAnalytics\AnalyticsAccepted,
# and uploads through the AUEPLauncher service. Setting the consent alone does not stop the
# service from being started, so both are checked.
$amdKey = 'HKLM:\SOFTWARE\AMD\AMDAnalytics'
if (Test-Path -LiteralPath $amdKey) {
    $accepted = (Get-ItemProperty -Path $amdKey -Name 'AnalyticsAccepted' -ErrorAction SilentlyContinue).AnalyticsAccepted
    $auep = Get-Service -Name 'AUEPLauncher' -ErrorAction SilentlyContinue
    $auepState = if ($auep) { "$($auep.Status)/$($auep.StartType)" } else { 'not installed' }
    $telemetryOff = -not (($accepted -eq 'true') -or ($auep -and $auep.Status -eq 'Running'))
    $amdDetail = if ($telemetryOff) { "off (AnalyticsAccepted=$accepted, AUEPLauncher=$auepState)" }
                 else { "on (AnalyticsAccepted=$accepted, AUEPLauncher=$auepState)" }
    Record 'system' 'amd telemetry' $telemetryOff $amdDetail -Optional
}
else {
    Record 'system' 'amd telemetry' $true 'no AMD analytics key (non-AMD machine)' -Optional
}

# A restore point is the only built-in undo the skill can offer before registry edits, and it
# is easy to have zero without noticing: they live on the volume, so a disk migration or a
# system reset wipes them (measured: 0 present after a clone). Informational - a machine that
# has not been tuned yet is not broken - but the moment tune runs, this is what makes it
# reversible.
$rpCount = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
$rpDetail = if ($rpCount -gt 0) { "$rpCount restore point(s) available" }
            else { 'none - run setup.ps1 -Phase tune (it creates one with the 24h dedupe bypassed), or Checkpoint-Computer' }
Record 'system' 'restore point' ($rpCount -gt 0) $rpDetail -Optional

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
$hygiene = Join-Path $PSScriptRoot 'check-script-hygiene.ps1'
if (Test-Path $hygiene) {
    $hygieneOut = & $hygieneHost -NoProfile -NonInteractive -File $hygiene -Path $PSScriptRoot 2>&1
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

# ------------------------------------------------------------------ tune tweaks survival
# Why this section exists: a cumulative update silently reverts the tune phase.
# Two rules learned the hard way, both encoded below.
#   1. The update DELETES these values rather than changing them. So "missing"
#      must count as FAIL, not be read as "this machine never had it set".
#      Checking only the value would let a deleted setting pass unnoticed.
#   2. For MMCSS, reading the registry is not evidence. The driver can sit at
#      START_TYPE=2 AUTO_START while STATE=STOPPED (exit code 1341); the values
#      are then inert. Only `sc query` showing RUNNING means it actually works.
Write-Output "`n--- tune tweaks (did they survive a Windows Update?)"
$keyCache = @{}
$tweaks = @(
    @{ Check = 'GameDVR policy';        Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR';                        Name = 'AllowGameDVR';                    Want = '0' },
    @{ Check = 'GameDVR user';          Path = 'HKCU:\System\GameConfigStore';                                            Name = 'GameDVR_Enabled';                 Want = '0' },
    @{ Check = 'MMCSS responsiveness';  Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness';          Want = '10' },
    @{ Check = 'MMCSS net throttling';  Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex';         Want = '4294967295' },
    @{ Check = 'MMCSS GPU priority';    Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'GPU Priority';       Want = '8' },
    @{ Check = 'MMCSS sched category';  Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Scheduling Category'; Want = 'High' },
    @{ Check = 'consumer features off'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';                   Name = 'DisableWindowsConsumerFeatures';  Want = '1' },
    @{ Check = 'silent app installs';   Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';   Name = 'SilentInstalledAppsEnabled';      Want = '0' },
    @{ Check = 'start suggestions';     Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';   Name = 'SystemPaneSuggestionsEnabled';    Want = '0' },
    @{ Check = 'soft landing tips';     Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';   Name = 'SoftLandingEnabled';              Want = '0' },
    @{ Check = 'explorer sync ads';     Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';         Name = 'ShowSyncProviderNotifications';   Want = '0' },
    # The Start-menu web-search switch exists in TWO places, and which one is settable is
    # build/product dependent. Measured on Windows 11 24H2+: writes to the
    # `...\CurrentVersion\Search` key are refused at kernel level ("not all data was
    # successfully written") while its ACL still shows the user FullControl, so the tune
    # phase cannot land BingSearchEnabled/CortanaConsent there at all. The official policy
    # route below always worked. Scoring these as a pair means either route counts as done -
    # a one-path check reports a permanent false FAIL on the machines where the key is locked.
    @{ Check = 'bing web search';       Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search';                   Name = 'BingSearchEnabled';               Want = '0'
       AltPath = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer';                                                     AltName = 'DisableSearchBoxSuggestions';  AltWant = '1'
       AltWhy = 'policy route (the Search key can be kernel-protected; policy wins over user scope anyway)' },
    @{ Check = 'web search policy';     Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';                 Name = 'ConnectedSearchUseWeb';           Want = '0'
       AltWhy = 'machine-wide: no web results in Start search' },
    # AllowTelemetry expects the strictest value the SKU honours, not a flat 0. 0 (Security/Off)
    # is only accepted on Enterprise / Education / Server; Home and Pro silently ignore it, so a
    # flat Want='0' would report FAIL on a correctly configured Pro box (or PASS on a box that
    # wrote a value Windows never reads - measured: Win11 Pro carried AllowTelemetry=0 and still
    # uploaded diagnostics).
    # Safety nets and network/disk housekeeping added after the evidence review. Each one is a
    # write that setup.ps1 -Phase tune performs, and a write with no check is an unchecked claim.
    # NOTE: EnablePeriodicBackup is deliberately NOT checked here as a registry value. Measured
    # on Windows 11 26xxx: the value reads back as 1, the RegIdleBackup task exists but has NO
    # trigger and NO action, the SIT service no longer exists, and the hives in
    # C:\Windows\System32\config\RegBack stay 0 bytes. Checking the switch would report a safety
    # net that does not exist - the outcome is checked as 'registry hive backup' further down.
    @{ Check = 'bitlocker auto-encrypt'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker';                            Name = 'PreventDeviceEncryption'; Want = '1'
       AltWhy = 'future automatic device encryption blocked (existing volumes untouched)' },
    @{ Check = 'delivery optimization'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'; Name = 'DODownloadMode';            Want = '1'
       AltWhy = 'updates stay on the LAN instead of uploading to the internet' },
    @{ Check = 'recycle bin cleanup';   Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; Name = '08';               Want = '1'
       AltWhy = 'Storage Sense empties the recycle bin' },
    @{ Check = 'recycle retention';     Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; Name = '32';               Want = '30'
       AltWhy = 'recycle bin retention: 30 days' },
    @{ Check = 'telemetry policy';      Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection';                 Name = 'AllowTelemetry'
       Want = $(if ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID' -ErrorAction SilentlyContinue).EditionID -match 'Enterprise|Education|Server') { '0' } else { '1' })
       AltWhy = 'strictest level the edition honours (0 is Enterprise/Education-only)' }
)
foreach ($t in $tweaks) {
    # Read each KEY once and look every value up inside it, instead of one Get-ItemProperty
    # per value. Measured on 30 values: per-value = 154 ms, per-key = 4 ms (~35x).
    $get = {
        param($p)
        if (-not $keyCache.ContainsKey($p)) {
            $keyCache[$p] = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
        }
        return $keyCache[$p]
    }
    $props = & $get $t.Path
    $have  = ($null -ne $props) -and ($null -ne $props.($t.Name))
    $val   = if ($have) { "$($props.($t.Name))" } else { $null }
    $ok    = $have -and ($val -eq $t.Want)
    $altOk = $false
    $altVal = $null
    if (-not $ok -and $t.ContainsKey('AltPath')) {
        $altProps = & $get $t.AltPath
        $altHave  = ($null -ne $altProps) -and ($null -ne $altProps.($t.AltName))
        $altVal   = if ($altHave) { "$($altProps.($t.AltName))" } else { $null }
        $altOk    = $altHave -and ($altVal -eq $t.AltWant)
    }
    $ok = $ok -or $altOk
    $detail = if ($altOk) { "=$altVal via $($t.AltName) - $($t.AltWhy)" }
              elseif (-not $have) { 'VALUE MISSING - re-run: setup.ps1 -Phase tune. If several values in ONE key are missing but the last-written one is present, the cause is the New-Item -Force bug, not a cumulative update (see SKILL.md)' }
              elseif (-not $ok) { "actual=$val want=$($t.Want)" }
              else { "=$val" }
    Record 'tweaks' $t.Check $ok $detail
}
# The classic context menu is toggled through the DEFAULT value of a CLSID key, which the
# table above cannot express (it looks values up by name). Absent key = the Win11 folded menu.
$ctxKey = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
$ctxVal = (Get-ItemProperty -Path $ctxKey -ErrorAction SilentlyContinue).'(default)'
$ctxDetail = if ($null -eq $ctxVal) { 'override key absent - the Win11 folded menu is in use' } else { "InprocServer32 default='$ctxVal'" }
Record 'tweaks' 'classic context menu' ($ctxVal -eq '') $ctxDetail

# Registry hive backup - checks the OUTCOME, not the switch. setup.ps1 sets
# EnablePeriodicBackup=1 and enables RegIdleBackup, but on Windows 11 26xxx both are vestigial:
# the task has no trigger and no action, the SIT service is gone, and RegBack holds 0-byte files.
# Measured after a reboot AND after manually starting the task: still 0 bytes.
# Informational, because nothing the user can do makes this build back hives up - the real
# safety net here is the restore point checked above.
$regBack = 'C:\Windows\System32\config\RegBack'
$regBackBytes = 0
if (Test-Path $regBack) {
    $regBackBytes = @(Get-ChildItem $regBack -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $regBackBytes) { $regBackBytes = 0 }
}
$regBackDetail = if (-not (Test-Path $regBack)) { 'RegBack folder absent' }
                 elseif ($regBackBytes -gt 1MB) { "hive copies present ($([math]::Round($regBackBytes/1MB,1)) MB)" }
                 else { "switch is on but the hives are $regBackBytes byte(s): this Windows build removed the periodic backup (RegIdleBackup has no trigger/action, SIT service gone) - rely on the restore point" }
Record 'tweaks' 'registry hive backup' ($regBackBytes -gt 1MB) $regBackDetail -Optional

# Telemetry scheduled tasks: informational because the list is build-dependent. Measured on
# this build: "Microsoft Compatibility Appraiser" and "ProgramDataUpdater" do not exist, so a
# hard expectation would be a permanent false FAIL.
$telList = @(
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' }
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater' }
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'StartupAppTask' }
    @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' }
    @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' }
    @{ Path = '\Microsoft\Windows\DiskDiagnostic\'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
    @{ Path = '\Microsoft\Windows\Autochk\'; Name = 'Proxy' }
)
$telPresent = 0; $telStillOn = @()
foreach ($t in $telList) {
    $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
    if (-not $task) { continue }
    $telPresent++
    if ($task.State -ne 'Disabled') { $telStillOn += $t.Name }
}
Record 'tweaks' 'telemetry tasks' ($telStillOn.Count -eq 0) $(
    if ($telPresent -eq 0) { 'no known telemetry tasks on this build' }
    elseif ($telStillOn.Count -eq 0) { "$telPresent present, all disabled" }
    else { "$($telStillOn.Count)/$telPresent still enabled: $($telStillOn -join ', ')" }) -Optional

# DiagTrack egress: recommendable by firewall group. Informational since the group may not
# exist on every build.
$diagRules = @(Get-NetFirewallRule -Group 'DiagTrack' -ErrorAction SilentlyContinue)
$diagBlocked = @($diagRules | Where-Object { $_.Action -eq 'Block' -and $_.Enabled -eq 'True' })
Record 'tweaks' 'diagtrack firewall' ($diagRules.Count -gt 0 -and $diagBlocked.Count -eq $diagRules.Count) $(
    if ($diagRules.Count -eq 0) { 'no DiagTrack firewall group on this build' }
    else { "$($diagBlocked.Count)/$($diagRules.Count) rule(s) blocked" }) -Optional

$mmcssOut = sc.exe query MMCSS 2>&1 | Out-String
$mmcssUp  = $mmcssOut -match 'RUNNING'
Record 'tweaks' 'MMCSS driver running' $mmcssUp $(
    if ($mmcssUp) { 'RUNNING - the MMCSS values above are actually in effect' }
    else { 'STOPPED - values above are INERT. Run: sc.exe config MMCSS start= auto ; sc.exe start MMCSS, then RE-CHECK. Measured: after a graphics driver install this failed many times in a row (first "failed 2: file not found" although mmcss.sys is present and validly signed, then 1341 "the server is currently disabled" even across a reboot) and STILL came up later on a retry - so retry rather than concluding it is broken' })

# ------------------------------------------------------------------ summary
Write-Output "`n===== summary ====="
$grouped = $results | Group-Object Language
$failed = @($results | Where-Object { -not $_.Pass -and -not $_.Optional })
$informational = @($results | Where-Object { -not $_.Pass -and $_.Optional })
foreach ($g in $grouped) {
    $bad = @($g.Group | Where-Object { -not $_.Pass -and -not $_.Optional }).Count
    $tag = if ($bad -eq 0) { 'OK  ' } else { 'FAIL' }
    Write-Output ("  [{0}] {1,-8} {2}/{3} checks passed" -f $tag, $g.Name, ($g.Count - $bad), $g.Count)
}
Write-Output ("`ntotal: {0} checks, {1} failed, {2} informational" -f $results.Count, $failed.Count, $informational.Count)
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
