<#
.SYNOPSIS
  Verify that the tune writes and their acceptance checks are the same set.

.DESCRIPTION
  A tuning item lives in three places: the write in lib/tune-writes.ps1 ($TuneWrites), the acceptance check in
  verify-env.ps1 ($tweaks), and the row in docs/03-system-tweaks.md. Nothing kept them in sync,
  so a write could be added without a check (or a check left behind after a write was removed)
  and the only symptom would be a quote in the docs that no longer matches reality.

  This script reads both arrays through the PowerShell AST - not by regex, which would count
  comments and helper rows - and enforces:

    1. every write has an acceptance check with the same Path + Name,
       either as the check's own Path/Name or as its AltPath/AltName;
    2. the check's Want equals the write's Value, compared after normalising
       0xFFFFFFFF / 4294967295 / -1; a write whose Value is a variable (SKU-gated, for example)
       is only required to have a check, because its value is decided at run time;
    3. every check refers to a write, unless it is an outcome check listed below;
    4. writes that are proven by an OUTCOME rather than by the switch are allowed, but they must
       be listed in $outcomeChecked with the reason, so "no check" is a decision, never an omission;
    5. the counts derived here match the numbers quoted in the docs (unless -SkipDocs).

  Exit code 0 when everything agrees, 1 otherwise.

.PARAMETER CheckDocs
  Also compare the counts with the numbers quoted in docs/03-system-tweaks.md.
  Off by default: the docs quote the size of the verify-env TWEAKS GROUP (44 value checks plus
  the classic-context-menu check and four outcome checks = 49), not the number of rows in
  `$tweaks`, so that number is a run-time fact and is verified by running the suite.

.PARAMETER Quiet
  Only report problems.

.EXAMPLE
  pwsh -File scripts/check-tune-consistency.ps1
#>
[CmdletBinding()]
param(
    [switch]$CheckDocs,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot

function Say { param([string]$M, [string]$C = 'Gray') Write-Host $M -ForegroundColor $C }

$problems = New-Object System.Collections.Generic.List[string]

# A write whose effect is proven by an outcome (the switch can be on while nothing happens).
# Key = 'Path|Name'. Keep this list tiny and give every entry a reason.
$outcomeChecked = @{
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager|EnablePeriodicBackup' =
        'the switch is only permission; the RegBack folder being non-empty is the real proof'
}

# ------------------------------------------------------------------ AST helpers
function Get-AssignedHashtables {
    param([string]$File, [string]$Variable, [string[]]$RequiredKeys)
    $tokens = $null; $errors = $null
    if (-not (Test-Path -LiteralPath $File)) { throw "file not found: $File" }
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$tokens, [ref]$errors)
    $assign = $ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $Variable
        }, $true) | Select-Object -First 1
    if (-not $assign) { return @() }
    $start = $assign.Extent.StartOffset
    $end = $assign.Extent.EndOffset
    $found = @()
    foreach ($h in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)) {
        if ($h.Extent.StartOffset -lt $start -or $h.Extent.EndOffset -gt $end) { continue }
        $keys = @($h.KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text })
        $ok = $true
        foreach ($required in $RequiredKeys) { if ($keys -notcontains $required) { $ok = $false } }
        if ($ok) { $found += $h }
    }
    return $found
}

# Extent text without the surrounding quotes; leaves expressions ($var, $(...)) untouched so a
# dynamic value stays recognisable.
function Get-RawText {
    param($Node)
    if ($null -eq $Node) { return $null }
    $text = $Node.Extent.Text
    if ($text.Length -ge 2) {
        $first = $text[0]; $last = $text[$text.Length - 1]
        if (($first -eq "'" -and $last -eq "'") -or ($first -eq '"' -and $last -eq '"')) {
            return $text.Substring(1, $text.Length - 2)
        }
    }
    return $text
}

function ConvertTo-Comparable {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    $s = $Value.Trim()
    if ($s -match '^0x([0-9a-fA-F]+)$') { return [string]([Convert]::ToInt64($Matches[1], 16)) }
    if ($s -eq '-1') { return '4294967295' }
    if ($s -eq '$true') { return '1' }
    if ($s -eq '$false') { return '0' }
    return $s
}

# ------------------------------------------------------------------ collect both sides
$writes = @()
foreach ($h in (Get-AssignedHashtables (Join-Path $PSScriptRoot 'lib/tune-writes.ps1') '$TuneWrites' @('Path', 'Name', 'Value'))) {
    $map = @{}
    foreach ($kv in $h.KeyValuePairs) { $map[$kv.Item1.Extent.Text] = $kv.Item2 }
    $writes += [pscustomobject]@{
        Path     = Get-RawText $map['Path']
        Name     = Get-RawText $map['Name']
        Value    = Get-RawText $map['Value']
        Dynamic  = ("$(Get-RawText $map['Value'])" -match '^\$')
        Line     = $h.Extent.StartLineNumber
    }
}

$checks = @()
# verify-env.ps1 is only the entry point now: each section lives in lib/verify/*.ps1. The $tweaks
# table is in 13-tune-tweaks-survival.ps1, so the definition is searched across the whole suite -
# otherwise this checker silently reports every write as unchecked.
$verifySources = @(Join-Path $PSScriptRoot 'verify-env.ps1') +
    @(Get-ChildItem (Join-Path $PSScriptRoot 'lib/verify') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
$verifyFile = $null
foreach ($candidate in $verifySources) {
    if (-not (Test-Path -LiteralPath $candidate)) { continue }
    $rawText = Get-Content -LiteralPath $candidate -Raw -ErrorAction SilentlyContinue
    if ($rawText -match '(?m)^\s*\$tweaks\s*=') { $verifyFile = $candidate; break }
}
if (-not $verifyFile) { throw 'could not find the $tweaks table in verify-env.ps1 or lib/verify/*.ps1' }
foreach ($h in (Get-AssignedHashtables $verifyFile '$tweaks' @('Check', 'Path', 'Name'))) {
    $map = @{}
    foreach ($kv in $h.KeyValuePairs) { $map[$kv.Item1.Extent.Text] = $kv.Item2 }
    $checks += [pscustomobject]@{
        Check    = Get-RawText $map['Check']
        Path     = Get-RawText $map['Path']
        Name     = Get-RawText $map['Name']
        Want     = Get-RawText $map['Want']
        AltPath  = Get-RawText $map['AltPath']
        AltName  = Get-RawText $map['AltName']
        AltWant  = Get-RawText $map['AltWant']
        Line     = $h.Extent.StartLineNumber
    }
}

# Index checks by every key they can satisfy: their own pair and the alternate route.
$byKey = @{}
foreach ($c in $checks) {
    $byKey[("$($c.Path)|$($c.Name)")] = $c
    if ($c.AltPath -and $c.AltName) { $byKey[("$($c.AltPath)|$($c.AltName)")] = $c }
}

if (-not $Quiet) {
    Say '===== check-tune-consistency =====' White
    Say ("  writes: {0}   checks: {1}   outcome-checked: {2}" -f $writes.Count, $checks.Count, $outcomeChecked.Count)
    Say ''
}

# ------------------------------------------------------------------ 1 & 2: every write is checked
foreach ($w in $writes) {
    $key = "$($w.Path)|$($w.Name)"
    $c = $byKey[$key]
    if (-not $c) {
        if ($outcomeChecked.ContainsKey($key)) { continue }
        $problems.Add("lib/tune-writes.ps1:$($w.Line): write '$($w.Name)' has no acceptance check (add one to verify-env.ps1's `$tweaks, or list it in `$outcomeChecked)")
        continue
    }
    if ($w.Dynamic) { continue }   # value decided at run time; presence of a check is the contract
    # Which Want applies to this write: the primary one, or the alt when the write is the alt pair.
    $want = if ($c.Path -eq $w.Path -and $c.Name -eq $w.Name) { $c.Want } else { $c.AltWant }
    if (-not $want) { $want = $c.Want }
    if ((ConvertTo-Comparable $w.Value) -ne (ConvertTo-Comparable $want)) {
        $problems.Add(("write '{0}' sets {1} but check '{2}' expects {3} (lib/tune-writes.ps1:{4} vs verify-env.ps1:{5})" -f
                $w.Name, $w.Value, $c.Check, $want, $w.Line, $c.Line))
    }
}

# ------------------------------------------------------------------ 3: every check has a write
$writeKeys = @{}
foreach ($w in $writes) { $writeKeys["$($w.Path)|$($w.Name)"] = $true }
foreach ($c in $checks) {
    $own = $writeKeys.ContainsKey("$($c.Path)|$($c.Name)")
    $alt = ($c.AltPath -and $c.AltName -and $writeKeys.ContainsKey("$($c.AltPath)|$($c.AltName)"))
    if (-not ($own -or $alt)) {
        $problems.Add(("verify-env.ps1:{0}: check '{1}' refers to {2}\{3}, which the tune write list never sets (stale check?)" -f
                $c.Line, $c.Check, $c.Path, $c.Name))
    }
}

# ------------------------------------------------------------------ 5: counts quoted in the docs
$docPath = Join-Path $root 'docs/03-system-tweaks.md'
if ($CheckDocs -and (Test-Path -LiteralPath $docPath)) {
    $doc = Get-Content -LiteralPath $docPath -Raw -Encoding UTF8
    $writeCount = $writes.Count
    $checkCount = $checks.Count
    foreach ($m in [regex]::Matches($doc, '(\d+)\s*(?:\u4e2a)?\u8c03\u4f18\u503c')) {
        if ([int]$m.Groups[1].Value -ne $writeCount) {
            $problems.Add(("docs/03-system-tweaks.md claims {0} tuning values, the code has {1}" -f $m.Groups[1].Value, $writeCount))
        }
    }
    foreach ($m in [regex]::Matches($doc, '(\d+)\s*\u6761\u68c0\u67e5')) {
        if ([int]$m.Groups[1].Value -ne $checkCount) {
            $problems.Add(("docs/03-system-tweaks.md claims {0} checks, verify-env has {1}" -f $m.Groups[1].Value, $checkCount))
        }
    }
}

if ($problems.Count -gt 0) {
    Say ("  {0} problem(s):" -f $problems.Count) Red
    foreach ($p in $problems) { Say "    - $p" Red }
    exit 1
}
if (-not $Quiet) { Say ("  ok: {0} writes <-> {1} checks, values agree, no stale rows" -f $writes.Count, $checks.Count) Green }
exit 0
