# verify-env section: go - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

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
