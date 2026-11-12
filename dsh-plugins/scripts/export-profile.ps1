<#
.SYNOPSIS
  Refresh the committed snapshot of the DSH plugin profile from the live profile.

.DESCRIPTION
  Copies the four files that define which plugins a DSH profile loads and how they are configured:

    package.json       dependencies + dsh.profile.bundles (what is installed and in which order)
    cordis.yml         profile root (normally an empty entry list)
    cordis.patch.yml   your overrides: model, UI, permission presets, per-plugin config
    pnpm-lock.yaml     resolved versions (reproducible installs)

  node_modules is NOT copied: it is a build product, and committing it would mean committing
  somebody else's published code. Credentials are not in these files either - if a future DSH
  version starts writing secrets into cordis.patch.yml, review the diff before committing.

  Every copy is verified by comparing the SHA256 of source and destination, so "exported" means
  the bytes actually landed. -WhatIf reports what would change without touching the snapshot.

.PARAMETER ProfileDir
  Live DSH profile directory. Default: %USERPROFILE%\.dsh\profiles\desktop

.PARAMETER SnapshotDir
  Snapshot directory in this project. Default: <project>/profile

.EXAMPLE
  pwsh -File scripts/export-profile.ps1 -WhatIf

.EXAMPLE
  pwsh -File scripts/export-profile.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ProfileDir = (Join-Path $env:USERPROFILE '.dsh\profiles\desktop'),
    [string]$SnapshotDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile')
)

$ErrorActionPreference = 'Stop'
$files = @('package.json', 'cordis.yml', 'cordis.patch.yml', 'pnpm-lock.yaml')

function Say { param([string]$M, [string]$C = 'Gray') Write-Host $M -ForegroundColor $C }
function Ok { param([string]$M) Write-Host "  ok    $M" -ForegroundColor Green }
function Warn { param([string]$M) Write-Host "  WARN  $M" -ForegroundColor Yellow }
function Would { param([string]$M) Write-Host "  would $M" -ForegroundColor Cyan }

Write-Host '===== export-profile: live DSH profile -> committed snapshot =====' -ForegroundColor White
Write-Host "  from : $ProfileDir"
Write-Host "  to   : $SnapshotDir"

if (-not (Test-Path -LiteralPath $ProfileDir)) {
    Say "  profile directory not found: $ProfileDir" Red
    Say '  pass -ProfileDir if this machine uses a different profile name' Yellow
    exit 2
}
if (-not (Test-Path -LiteralPath $SnapshotDir)) {
    if ($PSCmdlet.ShouldProcess($SnapshotDir, 'create snapshot directory')) {
        New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null
    }
}

$changed = 0
$same = 0
foreach ($f in $files) {
    $src = Join-Path $ProfileDir $f
    $dst = Join-Path $SnapshotDir $f
    if (-not (Test-Path -LiteralPath $src)) { Warn "not present in the live profile, skipped: $f"; continue }

    $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    $dstHash = if (Test-Path -LiteralPath $dst) { (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash } else { '' }
    if ($srcHash -eq $dstHash) { Ok "unchanged: $f"; $same++; continue }

    if (-not $PSCmdlet.ShouldProcess($dst, "copy $f from the live profile")) { Would "update $f"; continue }

    Copy-Item -LiteralPath $src -Destination $dst -Force
    $afterHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
    if ($afterHash -ne $srcHash) { throw "copy verification failed for $f (source $srcHash, destination $afterHash)" }
    Ok "updated: $f ($([math]::Round((Get-Item -LiteralPath $dst).Length / 1KB, 1)) KB, sha256 $($srcHash.Substring(0,12))...)"
    $changed++
}

Write-Host ''
if ($WhatIfPreference) { Say '  dry run: nothing was written' Yellow }
else { Say ("  done: {0} file(s) updated, {1} unchanged" -f $changed, $same) Green }
Say '  next: git diff -- dsh-plugins/profile ; then commit if the change is intended' Gray
exit 0
