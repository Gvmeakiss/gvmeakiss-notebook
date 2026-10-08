<#
.SYNOPSIS
  Find and clean registry entries left behind after a portable application's folder is
  deleted, and report associations that broke as a result.

.DESCRIPTION
  Uninstalling a portable app is just deleting its folder - convenient, but the registry
  keeps pointing at it afterwards. Three kinds of leftovers result, with very different
  severity:

    1. HIGH  A UserChoice entry whose Program ID points at a deleted executable.
             The default "open with" for that file type is now broken: double-clicking
             such a file does nothing, or raises an error. This must be fixed.
    2. LOW   A Program ID (HKCU\Software\Classes\<ProgID>) pointing at a deleted
             executable, with no extension referencing it any more. Harmless, but the
             dead app still appears in the "Open with" list. Worth cleaning.
    3. LOW   A RegisteredApplications / Capabilities entry naming a deleted app, so
             Settings shows a program that is not installed. Worth cleaning.

  So this script does two things: report which associations are actually BROKEN, and
  optionally remove the dead Program IDs.

  Speed note: enumerating HKCU\Software\Classes with PowerShell cmdlets takes minutes
  (853 subkeys measured at 281 s). This script therefore shells out to the native
  `reg query`, which returns the same information in about a second.

.PARAMETER Clean
  Actually delete the dead Program IDs. Without it the script only reports.

.PARAMETER Root
  Portable app root; used to recognise paths that belong to portable apps.
  Default: $env:USERPROFILE\Apps

.EXAMPLE
  pwsh -File clean-orphan-associations.ps1
  pwsh -File clean-orphan-associations.ps1 -Clean

.NOTES
  ASCII-only on purpose.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Clean,
    [string]$Root = (Join-Path $env:USERPROFILE 'Apps')
)

$ErrorActionPreference = 'Continue'
$Cmdlet = $PSCmdlet

# Rebuild PATH from the registry so a stale parent environment cannot affect behaviour.
$env:PATH = (@(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User')
) | Where-Object { $_ }) -join ';'

function Info { param([string]$M) Write-Output "    $M" }
function Ok   { param([string]$M) Write-Output "    ok      $M" }
function Warn { param([string]$M) Write-Output "    WARN    $M" }
function Bad  { param([string]$M) Write-Output "    FAIL    $M" }

Write-Output '===== clean-orphan-associations ====='
if ($Clean) { Info 'CLEAN mode: dead Program IDs will be removed' }
else { Info 'report-only mode: nothing will be changed (pass -Clean to remove)' }

# ------------------------------------------------------------------ helpers
# Reads a default (unnamed) registry value via the native tool instead of a cmdlet.
function Get-DefaultValue {
    param([string]$KeyPath)
    $out = & reg query $KeyPath /ve 2>$null
    $line = @($out | Where-Object { $_ -match 'REG_SZ' }) | Select-Object -First 1
    if ($line -match 'REG_SZ\s+(.*)$') { return $Matches[1].Trim() }
    return $null
}

function Get-ExeFromCommand {
    param([string]$Command)
    if (-not $Command) { return $null }
    if ($Command -match '^"([^"]+)"') { return $Matches[1] }
    if ($Command -match '^(\S+\.exe)') { return $Matches[1] }
    return $null
}

# An app is "dead" if its executable no longer exists on disk.
function Test-ExeAlive {
    param([string]$Exe)
    if (-not $Exe) { return $false }
    # Test-Path can be unreliable for paths with unusual characters, so fall back to
    # the .NET file API as a second opinion before declaring it missing.
    if (Test-Path -LiteralPath $Exe) { return $true }
    try { return [System.IO.File]::Exists($Exe) } catch { return $false }
}

# ------------------------------------------------------------------ 1. broken defaults
Write-Output "`n--- 1. broken default associations (UserChoice -> deleted exe)"
$brokenDefaults = @()
$exts = @('.md','.txt','.png','.jpg','.jpeg','.gif','.webp','.bmp','.mp4','.mkv','.avi',
          '.mov','.mp3','.flac','.wav','.m4a','.zip','.7z','.pdf')
foreach ($ext in $exts) {
    $progId = Get-DefaultValue "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice"
    if (-not $progId) {
        $progId = Get-DefaultValue "HKCU\Software\Classes\$ext"
    }
    if (-not $progId) { continue }
    # AppX* are built-in Store apps; they never point at a local exe
    if ($progId -like 'AppX*') { continue }
    $cmd = Get-DefaultValue "HKCU\Software\Classes\$progId\shell\open\command"
    $exe = Get-ExeFromCommand $cmd
    if ($exe -and -not (Test-ExeAlive $exe)) {
        $brokenDefaults += [pscustomobject]@{ Extension = $ext; ProgId = $progId; MissingExe = $exe }
    }
}
if ($brokenDefaults.Count -eq 0) {
    Ok 'no broken default associations'
} else {
    Write-Output "    $($brokenDefaults.Count) broken:"
    foreach ($b in $brokenDefaults) {
        '      {0,-8} {1,-26} -> missing {2}' -f $b.Extension, $b.ProgId, $b.MissingExe | Write-Output
    }
    Write-Output ''
    Write-Output '    Fix by re-pointing the extension at an app that still exists, or by'
    Write-Output '    choosing a default once by hand (see the skill README on UserChoice).'
}

# ------------------------------------------------------------------ 2. dead ProgIDs
Write-Output "`n--- 2. dead Program IDs (HKCU\Software\Classes)"
# Dump the whole hive with the native tool and filter in memory.
#
# Two traps here, both measured:
#   - Enumerating this hive with PowerShell cmdlets took 281 s for 853 subkeys.
#   - `reg query /f 'shell\open\command' /k` matches only a SINGLE key name, so the
#     pattern never matches across the backslashes and always returns 0 rows.
# A full `reg query /s` dump is ~25k lines and completes in well under a second.
$sw = [Diagnostics.Stopwatch]::StartNew()
$dump = & reg query 'HKCU\Software\Classes' /s 2>$null
$sw.Stop()
Info ("registry dump: {0:N0} lines in {1:N1}s" -f @($dump).Count, $sw.Elapsed.TotalSeconds)

# Walk the dump linearly: track the current key, and read the (Default) value under any
# ...\shell\open\command key. This avoids a second lookup per key.
$cmdMap = @{}       # ProgID -> command line
$currentKey = $null
foreach ($line in $dump) {
    if ($line -match '^(HKEY_[A-Z_]+\\\S.*)$') {
        $currentKey = $Matches[1]
        continue
    }
    if ($currentKey -and $currentKey -match '\\shell\\open\\command$' -and $line -match 'REG_SZ\s+(.*)$') {
        $progKey = $currentKey -replace '\\shell\\open\\command$', ''
        $cmdMap[$progKey] = $Matches[1].Trim()
    }
}
Info ("parsed {0} shell\open\command entries" -f $cmdMap.Count)

$deadProgIds = @()
foreach ($progKey in $cmdMap.Keys) {
    $exe = Get-ExeFromCommand $cmdMap[$progKey]
    if ($exe -and -not (Test-ExeAlive $exe)) {
        # a ProgID is only worth reporting if something still references it, OR if it is
        # a portable-app ProgID (those are the ones that show up in the Open-with list)
        $shortName = $progKey -replace '^HKEY_CURRENT_USER\\Software\\Classes\\', ''
        $deadProgIds += [pscustomobject]@{
            Key         = $progKey
            Short       = $shortName
            MissingExe  = $exe
        }
    }
}
if ($deadProgIds.Count -eq 0) {
    Ok 'no dead Program IDs found'
} else {
    Write-Output "    $($deadProgIds.Count) Program ID(s) point at a missing executable:"
    foreach ($d in $deadProgIds | Sort-Object Short) {
        '      {0,-42} -> missing {1}' -f $d.Short, ($d.MissingExe.Replace($env:USERPROFILE,'~')) | Write-Output
    }
    Write-Output ''
    Write-Output '    These are harmless while no extension references them, but the deleted app'
    Write-Output '    still appears in the "Open with" list. Re-run with -Clean to remove them.'
}

# ---------------------------------------------------------------- 3. dead apps
Write-Output "`n--- 3. RegisteredApplications naming a missing exe"
$regApps = Get-Item -Path 'HKCU:\Software\RegisteredApplications' -ErrorAction SilentlyContinue
$deadRegApps = @()
if ($regApps) {
    foreach ($name in $regApps.GetValueNames()) {
        $capPath = "HKCU:\" + ($regApps.GetValue($name) -replace '^Software','Software')
        $cmdKey = "$capPath\FileAssociations"
        # Resolve one ProgID from this app's capabilities and test its exe
        $fa = Get-Item -Path $cmdKey -ErrorAction SilentlyContinue
        if (-not $fa) { continue }
        $extsMapped = $fa.GetValueNames()
        if ($extsMapped.Count -eq 0) { continue }
        $progId = $fa.GetValue($extsMapped[0])
        $cmd = Get-DefaultValue "HKCU\Software\Classes\$progId\shell\open\command"
        $exe = Get-ExeFromCommand $cmd
        if ($exe -and -not (Test-ExeAlive $exe)) {
            $deadRegApps += [pscustomobject]@{ Name = $name; Capabilities = $regApps.GetValue($name); MissingExe = $exe }
        }
    }
}
if ($deadRegApps.Count -eq 0) {
    Ok 'no RegisteredApplications entries point at a missing exe'
} else {
    foreach ($d in $deadRegApps) {
        '      {0,-16} -> missing {1}' -f $d.Name, $d.MissingExe | Write-Output
        if ($Clean -and $Cmdlet.ShouldProcess($d.Name, 'remove RegisteredApplications entry')) {
            Remove-ItemProperty -Path 'HKCU:\Software\RegisteredApplications' -Name $d.Name -ErrorAction SilentlyContinue
            Ok "removed RegisteredApplications entry: $($d.Name)"
        }
    }
}

# ------------------------------------------------------------------- clean up
if ($Clean -and $deadProgIds.Count -gt 0) {
    Write-Output "`n--- removing dead Program IDs"
    foreach ($d in $deadProgIds) {
        if ($Cmdlet.ShouldProcess($d.Key, 'delete dead Program ID')) {
            & reg delete $d.Key /f 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "deleted $($d.Key -replace '^HKEY_CURRENT_USER\\Software\\Classes\\','')" }
            else { Warn "could not delete $($d.Key)" }
        }
    }
}

Write-Output "`n===== summary ====="
Write-Output ("broken defaults: {0}   dead ProgIDs: {1}   dead registered apps: {2}" -f `
    $brokenDefaults.Count, $deadProgIds.Count, $deadRegApps.Count)
if (-not $Clean) { Write-Output 'Report only. Re-run with -Clean to remove dead Program IDs.' }
