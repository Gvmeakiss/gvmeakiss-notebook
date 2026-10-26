<#
.SYNOPSIS
  Bootstrap the windows-fresh-setup skill on a machine that has nothing installed yet.

.DESCRIPTION
  The skill installs git, which is a circular dependency when the only way to GET the skill is
  to clone the repository: a fresh Windows box has no git, so `git clone` fails before the
  script that installs git can run. Every mature project sidesteps this with a one-line
  downloader; this is the same idea, kept plain so it can be pasted into a fresh terminal.

  It downloads the repository zip over HTTPS (no git required), extracts it into a local folder,
  and then hands over to scripts/setup.ps1 with whatever arguments you passed.

  If this script is already running from inside a checkout, the download step is skipped.

.PARAMETER Ref
  Branch or tag to fetch. Default: main. The reference type is auto-detected: a branch is
  fetched from refs/heads/, and if that does not exist the same name is tried from refs/tags/,
  so both `-Ref main` and `-Ref v1.2.0` work.

.PARAMETER InstallRoot
  Where the zip is extracted. Default: %LOCALAPPDATA%\windows-fresh-setup.

.PARAMETER Force
  Re-download even when an extracted copy is already present.

.PARAMETER DownloadOnly
  Stop after the files are on disk; do not run setup.ps1.

.PARAMETER DryRun
  Print the resolved URL, target paths and the exact command that would run, then exit 0.
  This is handled before any other branch: a dry run can never download, extract or call
  setup.ps1, whether or not a checkout is present. -WhatIf is treated identically.

.PARAMETER SetupArguments
  Everything after this is forwarded verbatim to setup.ps1, e.g.
    -SetupArguments '-Profile','full'

.EXAMPLE
  pwsh -File bootstrap.ps1 -DryRun

.EXAMPLE
  pwsh -File bootstrap.ps1 -SetupArguments '-Profile','minimal','-WhatIf'
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Ref = 'main',
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'windows-fresh-setup'),
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

$repoSlug = 'Gvmeakiss/gvmeakiss-notebook'
$skillRel = 'skills/windows-fresh-setup'
$headsUrl = "https://codeload.github.com/$repoSlug/zip/refs/heads/$Ref"
$tagsUrl = "https://codeload.github.com/$repoSlug/zip/refs/tags/$Ref"

$localSetup = Join-Path $here 'setup.ps1'
$localLib = Join-Path $here 'lib/tune-core.ps1'
$inCheckout = (Test-Path -LiteralPath $localSetup) -and (Test-Path -LiteralPath $localLib) -and -not $Force

# Resolve which zip would be fetched. A branch wins when it exists; otherwise the same name is
# treated as a tag. Only a dry run needs the answer up front, so the probe is best-effort.
function Resolve-ZipUrl {
    param([string]$Ref)
    if ($Ref -match '^v?\d+\.\d+') {
        return @{ Url = $tagsUrl; Kind = 'tag' }
    }
    return @{ Url = $headsUrl; Kind = 'branch' }
}
$resolved = Resolve-ZipUrl -Ref $Ref

# ---------------------------------------------------------------------------
# Dry run / -WhatIf: handled before every other branch.
# A dry run must never download, extract, or invoke setup.ps1 - including from a checkout,
# which used to fall through to the hand-over and could start a full default run.
# ---------------------------------------------------------------------------
if ($DryRun -or $WhatIfPreference) {
    Say '===== windows-fresh-setup bootstrap (dry run) =====' White
    Say "  ref         : $Ref ($($resolved.Kind))"
    Say "  url         : $($resolved.Url)"
    if ($resolved.Kind -eq 'branch') { Say "  url (tag)   : $tagsUrl  (tried only if the branch is missing)" }
    else { Say "  url (branch): $headsUrl  (tried only if the tag is missing)" }
    Say "  install to  : $InstallRoot"
    Say ''
    if ($inCheckout) {
        Say "  mode        : existing checkout - nothing to download" Yellow
        $plannedSetup = $localSetup
    }
    else {
        Say "  mode        : download + extract" Yellow
        $plannedSetup = Join-Path (Join-Path (Join-Path $InstallRoot 'src') $skillRel) 'scripts/setup.ps1'
    }
    Say "  setup path  : $plannedSetup"
    $pwshGuess = (Get-Command 'pwsh' -ErrorAction SilentlyContinue).Source
    if (-not $pwshGuess) { $pwshGuess = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
    $plannedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $plannedSetup) + $SetupArguments
    Say ''
    Say "  would run   : $pwshGuess $($plannedArgs -join ' ')" Cyan
    Say ''
    Say '  dry run: nothing was downloaded, written or executed' Green
    exit 0
}

Say '===== windows-fresh-setup bootstrap =====' White
Say "  ref         : $Ref ($($resolved.Kind))"
Say "  url         : $($resolved.Url)"
Say "  install to  : $InstallRoot"

# Already inside a checkout? Then there is nothing to download.
if ($inCheckout) {
    Ok "running from an existing checkout: $localSetup"
    $setupPath = $localSetup
}
else {
    $tmpZip = Join-Path $env:TEMP ('wfs-bootstrap-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.zip')
    $tmpDir = Join-Path $env:TEMP ('wfs-bootstrap-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Say '  downloading...'
        $downloaded = $false
        $fallbackUrl = if ($resolved.Kind -eq 'branch') { $tagsUrl } else { $headsUrl }
        $fallbackKind = if ($resolved.Kind -eq 'branch') { 'tag' } else { 'branch' }
        try {
            Invoke-WebRequest -Uri $resolved.Url -OutFile $tmpZip -UseBasicParsing -ErrorAction Stop
            $downloaded = $true
            Say "  source      : $($resolved.Url) ($($resolved.Kind))"
        }
        catch {
            Warn "could not fetch $($resolved.Url) as a $($resolved.Kind): $($_.Exception.Message)"
            Warn "trying the same name as a $fallbackKind"
            try {
                Invoke-WebRequest -Uri $fallbackUrl -OutFile $tmpZip -UseBasicParsing -ErrorAction Stop
                $downloaded = $true
                Say "  source      : $fallbackUrl ($fallbackKind)"
            }
            catch {
                Warn "could not fetch $fallbackUrl either: $($_.Exception.Message)"
            }
        }
        if (-not $downloaded) { throw "could not download ref '$Ref' as either a branch or a tag" }
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

        $setupPath = Join-Path (Join-Path $target $skillRel) 'scripts/setup.ps1'
        if (-not (Test-Path -LiteralPath $setupPath)) { throw "setup.ps1 not found under $target (expected $setupPath)" }
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
