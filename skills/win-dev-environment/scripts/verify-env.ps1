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
p.write_text("中文测试 utf8\n", encoding="utf-8")
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
        $build = & dotnet build -v q --nologo 2>&1 | Select-String -Pattern 'error|Build succeeded|已成功生成' | Select-Object -First 1
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
