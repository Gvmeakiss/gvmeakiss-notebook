# verify-env section: cpp - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

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
            Record 'cpp' 'g++ version' (($LASTEXITCODE -eq 0) -and -not [string]::IsNullOrWhiteSpace($v)) "$v"
            & g++ -std=c++20 -O1 main.cpp -o main.exe 2>&1 | Out-Null
            $compiled = ($LASTEXITCODE -eq 0)
            Record 'cpp' 'compile' $compiled ''
            if ($compiled) {
                $run = & .\main.exe 2>&1 | Select-Object -Last 1
                Record 'cpp' 'run' ($LASTEXITCODE -eq 0) "$run"
            }
        } else {
            # A missing g++ does not mean the C++ toolchain works: it means this check could not
            # run. Recorded as SKIP so it can never be read as proof (it used to be a hard $true).
            Record 'cpp' 'compiler' 'SKIP' 'no g++ found (MSVC-only machine): compile/run not exercised'
        }
        # CMake is only meaningful if a generator + compiler pair works
        if (Have 'cmake') {
            $cv = & cmake --version 2>&1 | Select-Object -First 1
            Record 'cpp' 'cmake version' (($LASTEXITCODE -eq 0) -and -not [string]::IsNullOrWhiteSpace($cv)) "$cv"
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
                        Record 'cpp' 'cmake run' ($LASTEXITCODE -eq 0) "$run"
                    }
                    else { Record 'cpp' 'cmake run' 'SKIP' 'build produced no verify.exe' }
                }
            }
        }
        Pop-Location
    }
}
