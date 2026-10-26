# verify-env section: dotnet - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

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
