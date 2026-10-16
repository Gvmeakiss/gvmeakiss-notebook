<#
.SYNOPSIS
  Pre-flight check for every PowerShell script in this skill: encoding + dual-host parse.

.DESCRIPTION
  This script does NOT execute the scripts it checks. It answers one question that has
  already caused two real incidents in this project:

      "Will this file even parse when the OTHER PowerShell host runs it?"

  Why that question keeps biting:

    * A BOM-less file is decoded as UTF-8 by [Parser]::ParseFile (PowerShell 7 and 5.1
      both do this for the AST) but as ANSI by `powershell.exe -File`. So the same file
      can report "parse OK" in a validation step and then die at runtime. This is the
      documented trap in SKILL.md, and it still happened again - the failure mode is a
      false pass, which is exactly what a checklist entry does not catch.
    * Task Scheduler ALWAYS spawns Windows PowerShell 5.1. A script validated only under
      pwsh (PS7) is therefore untested for its real host.
    * setup.ps1 picks `pwsh` when present and silently falls back to `powershell.exe`,
      so day-to-day runs rarely exercise the 5.1 path.

  Verdicts:
    PASS        ASCII-only, or has a BOM. Parses identically under PS7 and PS5.1.
    WARN        Non-ASCII without a BOM, but PS5.1 still parses THIS file. It works today
                by luck of byte alignment; any later edit can break it. Prefer ASCII-only
                or add a BOM.
    FAIL        PS7 parses it but PS5.1 does not. This kills a scheduled task with exit
                code 0x1 while Task Scheduler still reports "action completed".
    FAIL        Neither host parses it.
    INFO        Parse-only mismatch with no encoding cause. Behaviour of each host differs
                for a reason other than encoding - worth reading the messages.

.PARAMETER Path
  One or more files or directories to check. Default: the directory of this script.

.PARAMETER Recurse
  Recurse into subdirectories of any directory passed in -Path.

.OUTPUTS
  Plain text report. Exit code 0 when nothing FAILED, 1 otherwise, so the skill's verify
  chain can treat it as a gate.

.EXAMPLE
  pwsh -File check-script-hygiene.ps1
  pwsh -File check-script-hygiene.ps1 -Path C:\Jobs -Recurse

.NOTES
  ASCII-only on purpose: Windows PowerShell 5.1 decodes a BOM-less file as ANSI, so any
  multi-byte character here would break the very host this script exists to protect.
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [switch]$Recurse
)

$ErrorActionPreference = 'Continue'

if (-not $Path -or $Path.Count -eq 0) {
    $Path = @($PSScriptRoot)
}

# ---------------------------------------------------------------- collect targets
$files = New-Object System.Collections.Generic.List[string]
foreach ($p in $Path) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    if (Test-Path -LiteralPath $p -PathType Container) {
        $items = if ($Recurse) {
            Get-ChildItem -LiteralPath $p -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue
        } else {
            Get-ChildItem -LiteralPath $p -Filter '*.ps1' -File -ErrorAction SilentlyContinue
        }
        foreach ($i in $items) { $files.Add($i.FullName) }
    }
    elseif (Test-Path -LiteralPath $p -PathType Leaf) {
        $files.Add((Resolve-Path -LiteralPath $p).Path)
    }
    else {
        Write-Host "  [skip] not found: $p"
    }
}

$targets = @($files | Sort-Object -Unique)
if ($targets.Count -eq 0) {
    Write-Host 'No .ps1 files to check.'
    exit 0
}

# ---------------------------------------------------------------- encoding facts
$meta = @()
foreach ($f in $targets) {
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $nonAscii = 0
    foreach ($b in $bytes) { if ($b -gt 127) { $nonAscii++ } }
    $meta += [pscustomobject]@{
        Path     = $f
        Name     = Split-Path $f -Leaf
        HasBom   = $hasBom
        NonAscii = $nonAscii
        Ps7Ok    = $false
        Ps7Err   = ''
        Ps51Ok   = $false
        Ps51Err  = ''
    }
}

# ---------------------------------------------------------------- PS7 parse (in-process)
foreach ($m in $meta) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($m.Path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $m.Ps7Err = $errors[0].Message
    } else {
        $m.Ps7Ok = $true
    }
}

# ---------------------------------------------------------------- PS5.1 parse (one batch, one process)
# Batch on purpose: a process per file would take seconds each. The probe passes file paths
# via the environment because the command line would be fragile with many or spaced paths.
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$ps51Available = Test-Path -LiteralPath $ps51

if (-not $ps51Available) {
    Write-Host ''
    Write-Host 'WARNING: Windows PowerShell 5.1 not found at the expected path.'
    Write-Host '         The 5.1 half of this check cannot run - a PASS here is not evidence'
    Write-Host '         for scheduled tasks, which always spawn 5.1.'
} else {
    $probe = @'
$out = @()
$list = $env:DSH_HYG_CHECK_FILES -split [char]10
foreach ($f in $list) {
    if ([string]::IsNullOrWhiteSpace($f)) { continue }
    $t = $null
    $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$t, [ref]$e)
    if ($e -and $e.Count -gt 0) {
        $msg = $e[0].Message -replace "`r?`n", " "
        $out += ($f + "|FAIL|" + $msg)
    } else {
        $out += ($f + "|OK|")
    }
}
$out -join [char]10
'@

    $env:DSH_HYG_CHECK_FILES = ($targets -join "`n")
    $raw = & $ps51 -NoProfile -NonInteractive -Command $probe 2>&1
    $env:DSH_HYG_CHECK_FILES = $null

    $map = @{}
    foreach ($line in @($raw)) {
        $s = [string]$line
        if ([string]::IsNullOrWhiteSpace($s)) { continue }
        $parts = $s -split '\|', 3
        if ($parts.Count -ge 2) { $map[$parts[0]] = $parts }
    }
    foreach ($m in $meta) {
        if ($map.ContainsKey($m.Path)) {
            $row = $map[$m.Path]
            if ($row[1] -eq 'OK') { $m.Ps51Ok = $true } else { $m.Ps51Err = if ($row.Count -ge 3) { $row[2] } else { 'parse failed' } }
        } else {
            $m.Ps51Err = 'no result returned by the 5.1 probe'
        }
    }
}

# ---------------------------------------------------------------- verdicts
function Get-Verdict {
    param($M)
    $encAscii = ($M.HasBom -or $M.NonAscii -eq 0)

    if ($M.Ps7Ok -and $M.Ps51Ok) {
        if ($encAscii) { return 'PASS' }
        return 'WARN'
    }
    if ($M.Ps7Ok -and -not $M.Ps51Ok) { return 'FAIL' }
    if (-not $M.Ps7Ok -and $M.Ps51Ok) { return 'FAIL' }
    return 'FAIL'
}

Write-Host ''
Write-Host '=== script hygiene: encoding + dual-host parse ==='
Write-Host ("  files checked : {0}" -f $targets.Count)
Write-Host ("  PS 5.1 probe  : {0}" -f $(if ($ps51Available) { $ps51 } else { 'UNAVAILABLE' }))
Write-Host ''
# Parenthesised on purpose: unparenthesised, `-f` is bound as -ForegroundColor and throws.
Write-Host ('  {0,-34} {1,-6} {2,-9} {3,-7} {4,-7} {5}' -f 'file', 'bytes', 'BOM', 'PS 7', 'PS 5.1', 'verdict')
Write-Host ('  ' + ('-' * 88))

$failed = 0
$warned = 0
foreach ($m in $meta) {
    $v = Get-Verdict -M $m
    if ($v -eq 'FAIL') { $failed++ }
    if ($v -eq 'WARN') { $warned++ }
    $enc = if ($m.NonAscii -eq 0) { 'ascii' } else { 'non-ascii x' + $m.NonAscii }
    Write-Host ('  {0,-34} {1,-6} {2,-9} {3,-7} {4,-7} {5}' -f `
        $m.Name,
        $enc,
        $(if ($m.HasBom) { 'yes' } else { 'no' }),
        $(if ($m.Ps7Ok) { 'ok' } else { 'FAIL' }),
        $(if ($m.Ps51Ok) { 'ok' } else { 'FAIL' }),
        $v)
}

# ---------------------------------------------------------------- detail + guidance
$problems = @($meta | Where-Object { (Get-Verdict -M $_) -ne 'PASS' })
if ($problems.Count -gt 0) {
    Write-Host ''
    Write-Host '--- detail ---'
    foreach ($m in $problems) {
        $v = Get-Verdict -M $m
        Write-Host ("  [{0}] {1}" -f $v, $m.Path)
        if (-not $m.Ps7Ok)  { Write-Host ("         PS 7  : " + $m.Ps7Err) }
        if (-not $m.Ps51Ok) { Write-Host ("         PS 5.1: " + $m.Ps51Err) }
        if ($v -eq 'WARN') {
            Write-Host  '         cause : non-ASCII bytes without a BOM. A BOM-less file is read'
            Write-Host  '                 as UTF-8 by ParseFile but as ANSI by `powershell.exe -File`.'
            Write-Host  '         fix   : keep the file ASCII-only (preferred), or save it as UTF-8 WITH BOM.'
        }
        if ($v -eq 'FAIL') {
            Write-Host  '         cause : the two hosts disagree. A scheduled task would die with exit'
            Write-Host  '                 code 0x1 while Task Scheduler still logs "action completed".'
            Write-Host  '         fix   : make the file ASCII-only, or save it as UTF-8 WITH BOM, then re-run this check.'
        }
    }
}

Write-Host ''
Write-Host '--- how to read this ---'
Write-Host '  PASS  safe for both hosts.'
Write-Host '  WARN  parses under 5.1 today, but by byte-alignment luck. Any later edit can break it.'
Write-Host '  FAIL  a script that runs in a scheduled task or a 5.1 child host will not start.'
Write-Host ''
Write-Host '  ASCII-only is the cheapest way to stay safe: it removes the encoding question entirely.'
Write-Host '  A BOM also works, but tooling that rewrites the file may drop it silently.'
Write-Host ''
Write-Host ("=== hygiene summary: {0} file(s), {1} FAIL, {2} WARN ===" -f $targets.Count, $failed, $warned)

if ($failed -gt 0) { exit 1 }
exit 0
