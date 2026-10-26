# verify-env section: node - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

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
