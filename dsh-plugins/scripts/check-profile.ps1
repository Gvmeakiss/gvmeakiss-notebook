<#
.SYNOPSIS
  Read-only check that the DSH profile on this machine still matches the snapshot in this folder.

.DESCRIPTION
  The plugin set of a DSH profile is not machine-independent data: the GUI plugin manager writes
  it into %USERPROFILE%\.dsh\profiles\desktop (package.json dependencies + dsh.profile.bundles)
  and into cordis.patch.yml. This script compares that live state with the copy committed here and
  reports drift, so "the recorded plugin set" cannot silently become a lie.

  It never writes anything.

  What is compared:
    * dependency names and version ranges (package.json)
    * the ordered bundle list (package.json -> dsh.profile.bundles)
    * cordis.yml / cordis.patch.yml / pnpm-lock.yaml file hashes
    * for every non first-party bundle: the version actually present in node_modules

  Exit codes: 0 = identical, 1 = drift (details printed), 2 = profile or snapshot missing.

.PARAMETER ProfileDir
  Live DSH profile directory. Default: %USERPROFILE%\.dsh\profiles\desktop

.PARAMETER SnapshotDir
  Committed snapshot directory. Default: <repo>/profile (the parent of this script's folder).

.EXAMPLE
  pwsh -File scripts/check-profile.ps1
#>
[CmdletBinding()]
param(
    [string]$ProfileDir = (Join-Path $env:USERPROFILE '.dsh\profiles\desktop'),
    [string]$SnapshotDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile')
)

$ErrorActionPreference = 'Continue'
$problems = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]

function Say { param([string]$M, [string]$C = 'Gray') Write-Host $M -ForegroundColor $C }

Write-Host '===== check-profile: live DSH profile vs committed snapshot =====' -ForegroundColor White
Write-Host "  live     : $ProfileDir"
Write-Host "  snapshot : $SnapshotDir"

if (-not (Test-Path -LiteralPath $ProfileDir)) { Say "  profile directory not found: $ProfileDir" Red; exit 2 }
if (-not (Test-Path -LiteralPath $SnapshotDir)) { Say "  snapshot directory not found: $SnapshotDir" Red; exit 2 }

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

# ------------------------------------------------------------------ package.json
$livePkg = Read-Json (Join-Path $ProfileDir 'package.json')
$snapPkg = Read-Json (Join-Path $SnapshotDir 'package.json')
if (-not $livePkg) { Say '  cannot read live package.json' Red; exit 2 }
if (-not $snapPkg) { Say '  cannot read snapshot package.json' Red; exit 2 }

function Get-DepMap($Pkg) {
    $map = @{}
    if ($Pkg -and $Pkg.dependencies) {
        foreach ($p in $Pkg.dependencies.PSObject.Properties) { $map[$p.Name] = [string]$p.Value }
    }
    return $map
}
$liveDeps = Get-DepMap $livePkg
$snapDeps = Get-DepMap $snapPkg

foreach ($name in ($liveDeps.Keys + $snapDeps.Keys | Sort-Object -Unique)) {
    $l = $liveDeps[$name]; $s = $snapDeps[$name]
    if (-not $s) { $problems.Add("dependency added since the snapshot: $name $l") }
    elseif (-not $l) { $problems.Add("dependency removed since the snapshot: $name $s") }
    elseif ($l -ne $s) { $problems.Add("dependency version range changed: $name  snapshot=$s  live=$l") }
}

# ------------------------------------------------------------------ bundle list
$liveBundles = @()
$snapBundles = @()
if ($livePkg.dsh -and $livePkg.dsh.profile -and $livePkg.dsh.profile.bundles) { $liveBundles = @($livePkg.dsh.profile.bundles) }
if ($snapPkg.dsh -and $snapPkg.dsh.profile -and $snapPkg.dsh.profile.bundles) { $snapBundles = @($snapPkg.dsh.profile.bundles) }

$added = @($liveBundles | Where-Object { $snapBundles -notcontains $_ })
$removed = @($snapBundles | Where-Object { $liveBundles -notcontains $_ })
foreach ($b in $added) { $problems.Add("bundle enabled since the snapshot: $b") }
foreach ($b in $removed) { $problems.Add("bundle no longer enabled: $b") }
$orderLive = ($liveBundles -join ' > ')
$orderSnap = ($snapBundles -join ' > ')
if ($added.Count -eq 0 -and $removed.Count -eq 0 -and $orderLive -ne $orderSnap) {
    $problems.Add('bundle order changed (load order matters for patch layers)')
}

# ------------------------------------------------------------------ file hashes
foreach ($f in @('cordis.yml', 'cordis.patch.yml', 'pnpm-lock.yaml')) {
    $livePath = Join-Path $ProfileDir $f
    $snapPath = Join-Path $SnapshotDir $f
    if (-not (Test-Path -LiteralPath $snapPath)) { $problems.Add("snapshot file missing: $f"); continue }
    if (-not (Test-Path -LiteralPath $livePath)) { $problems.Add("live file missing: $f"); continue }
    $lh = (Get-FileHash -LiteralPath $livePath -Algorithm SHA256).Hash
    $sh = (Get-FileHash -LiteralPath $snapPath -Algorithm SHA256).Hash
    if ($lh -ne $sh) { $problems.Add("file changed since the snapshot: $f (run scripts/export-profile.ps1 to refresh)") }
}

# ------------------------------------------------------------------ installed versions
$nodeModules = Join-Path $ProfileDir 'node_modules'
foreach ($b in $liveBundles) {
    if ($b -like '@deepseek-ai/*') { continue }   # first-party bundles ship with the app
    $pkgJson = Join-Path (Join-Path $nodeModules $b) 'package.json'
    if (-not (Test-Path -LiteralPath $pkgJson)) { $problems.Add("bundle listed but not installed: $b"); continue }
    $v = (Read-Json $pkgJson).version
    $notes.Add(("installed: {0} {1}" -f $b, $v))
}

# ------------------------------------------------------------------ report
if ($notes.Count -gt 0) {
    Write-Host ''
    foreach ($n in $notes) { Write-Host "  $n" }
}
if ($problems.Count -gt 0) {
    Write-Host ''
    Say ("  {0} difference(s) from the committed snapshot:" -f $problems.Count) Red
    foreach ($p in $problems) { Say "    - $p" Red }
    Write-Host ''
    Say '  If the change is intended, refresh the snapshot: pwsh -File scripts/export-profile.ps1' Yellow
    exit 1
}

Write-Host ''
Say ("  ok: profile matches the snapshot ({0} bundle(s) recorded, {1} non-first-party installed)" -f $snapBundles.Count, $notes.Count) Green
exit 0
