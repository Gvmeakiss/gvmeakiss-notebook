<#
.SYNOPSIS
  Bootstrap the win-ai-gaming-setup skill on a machine that has nothing installed yet.

.DESCRIPTION
  The skill installs git, which is a circular dependency when the only way to GET the skill is
  to clone the repository: a fresh Windows box has no git, so `git clone` fails before the
  script that installs git can run. Every mature project sidesteps this with a one-line
  downloader; this is the same idea, kept plain so it can be pasted into a fresh terminal.

  It downloads the repository zip over HTTPS (no git required), extracts it into a local folder,
  and then hands over to scripts/setup.ps1 with whatever arguments you passed.

  If this script is already running from inside a checkout, the download step is skipped.

.PARAMETER Ref
  Branch or tag to fetch. Default: main.

.PARAMETER InstallRoot
  Where the zip is extracted. Default: %LOCALAPPDATA%\win-ai-gaming-setup.

.PARAMETER Force
  Re-download even when an extracted copy is already present.

.PARAMETER DownloadOnly
  Stop after the files are on disk; do not run setup.ps1.

.PARAMETER DryRun
  Print the resolved URL and target paths, change nothing.

.PARAMETER SetupArguments
  Everything after this is forwarded verbatim to setup.ps1, e.g.
    -SetupArguments '-Profile','full'

.EXAMPLE
  pwsh -File bootstrap.ps1 -DryRun

.EXAMPLE
  pwsh -File bootstrap.ps1 -SetupArguments '-Profile','minimal','-WhatIf'
#>
[CmdletBinding()]
param(
    [string]$Ref = 'main',
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'win-ai-gaming-setup'),
    [switch]$Force,
    [switch]$DownloadOnly,
    [switch]$DryRun,
    [string[]]$SetupArguments = @()
)

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot

function Say { param([string]$M, [string]$C = 'Gray') Write-Host $M -ForegroundColor $C }
function Ok { param([string]$M) Write-Host "  ok    $M" -ForegroundColor Green }
function Warn { param([string]$M) Write-Host "  WARN  $M" -ForegroundColor Yellow }
function Bad { param([string]$M) Write-Host "  FAIL  $M" -ForegroundColor Red }

$zipUrl = "https://codeload.github.com/Gvmeakiss/gvmeakiss-notebook/zip/refs/heads/$Ref"
$localSetup = Join-Path $here 'setup.ps1'
$localLib = Join-Path $here 'lib/tune-core.ps1'

Say '===== win-ai-gaming-setup bootstrap =====' White
Say "  ref         : $Ref"
Say "  url         : $zipUrl"
Say "  install to  : $InstallRoot"

# Already inside a checkout? Then there is nothing to download.
if ((Test-Path -LiteralPath $localSetup) -and (Test-Path -LiteralPath $localLib) -and -not $Force) {
    Ok "running from an existing checkout: $localSetup"
    $setupPath = $localSetup
}
else {
    if ($DryRun) {
        Say ''
        Say "  dry run: would download $zipUrl" Yellow
        Say "           and extract to $InstallRoot" Yellow
        Say "           then run $InstallRoot\<zip-root>\skills\win-ai-gaming-setup\scripts\setup.ps1"
        exit 0
    }

    $tmpZip = Join-Path $env:TEMP ('wagsetup-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.zip')
    $tmpDir = Join-Path $env:TEMP ('wagsetup-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Say '  downloading...'
        Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing -ErrorAction Stop
        $sizeMb = [math]::Round((Get-Item -LiteralPath $tmpZip).Length / 1MB, 1)
        Ok "downloaded $sizeMb MB"

        Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpDir -Force -ErrorAction Stop
        $extracted = @(Get-ChildItem -LiteralPath $tmpDir -Directory -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not $extracted) { throw 'zip did not contain a top-level folder' }

        New-Item -ItemType Directory -Force -Path $InstallRoot -ErrorAction Stop | Out-Null
        $target = Join-Path $InstallRoot 'src'
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue }
        Move-Item -LiteralPath $extracted[0].FullName -Destination $target -ErrorAction Stop
        Ok "extracted to $target"

        $setupPath = Join-Path $target 'skills/win-ai-gaming-setup/scripts/setup.ps1'
        if (-not (Test-Path -LiteralPath $setupPath)) { throw "setup.ps1 not found under $target" }
        Ok "setup script: $setupPath"
    }
    catch {
        Bad "bootstrap failed: $($_.Exception.Message)"
        Warn 'fallback: install git (winget install Git.Git), clone the repo, then run setup.ps1 directly'
        exit 1
    }
    finally {
        Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($DownloadOnly) { Ok 'download only: stopping here'; exit 0 }

# Hand over to the real entry point. Same host preference as setup.ps1: pwsh when present.
$pwshExe = (Get-Command 'pwsh' -ErrorAction SilentlyContinue).Source
if (-not $pwshExe) { $pwshExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
$allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $setupPath) + $SetupArguments
Say ''
Say "  -> $pwshExe $($allArgs -join ' ')" Gray
& $pwshExe @allArgs
$code = $LASTEXITCODE
Say ''
if ($code -eq 0) { Ok 'setup finished' } else { Bad "setup exited with $code" }
exit $code
