<#
.SYNOPSIS
  Check that the numbers quoted in the documentation still match the files.

.DESCRIPTION
  Every count in this project ("16 tool scripts", "13 apps") is written by hand in several
  places. Hand-written numbers drift: one doc says 14 tools while another says 15, and the only
  way to notice used to be a reader complaining.

  This script derives each number from the source of truth and compares it with every claim it
  can find in the docs:

    tool scripts -> files under scripts/ except setup.ps1
    apps         -> entries in apps.json

  The tune/verify counts ("43 tweak values", "49 tweak checks", "98 acceptance checks") are NOT
  checked here on purpose. Those numbers come from a live run - the tune phase reports what it
  applied and verify-env counts what it exercised - and a regex over the source would also count
  comments and helper rows. A checker that is itself wrong is worse than no checker, so those
  numbers are verified by running the scripts and are quoted from their output.

  Exit code 0 when every claim matches, 1 when something drifted. A mismatch is a documentation
  bug, not a code bug, but it must fail: otherwise "the docs are consistent" is just a wish.

.PARAMETER Quiet
  Only report mismatches.

.EXAMPLE
  pwsh -File scripts/check-counts.ps1
#>
[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot

function Say { param([string]$M, [string]$C = 'Gray') Write-Host $M -ForegroundColor $C }

$problems = New-Object System.Collections.Generic.List[string]

# ------------------------------------------------------------------ source of truth
$toolScripts = @(Get-ChildItem (Join-Path $PSScriptRoot '*.ps1') -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'setup.ps1' })

$appCount = 0
$appsPath = Join-Path $root 'apps.json'
if (Test-Path -LiteralPath $appsPath) {
    try { $appCount = @((Get-Content -LiteralPath $appsPath -Raw -Encoding UTF8 | ConvertFrom-Json).apps).Count }
    catch { $problems.Add("apps.json cannot be parsed: $($_.Exception.Message)") }
}
else { $problems.Add("apps.json not found at $appsPath") }

function Get-TuneWriteCount {
    param([string]$File)
    if (-not (Test-Path -LiteralPath $File)) { return 0 }
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$tokens, [ref]$errors)
    $assign = $ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$TuneWrites'
        }, $true) | Select-Object -First 1
    if (-not $assign) { return 0 }
    $start = $assign.Extent.StartOffset; $end = $assign.Extent.EndOffset
    $count = 0
    foreach ($h in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)) {
        if ($h.Extent.StartOffset -lt $start -or $h.Extent.EndOffset -gt $end) { continue }
        $keys = @($h.KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text })
        if (($keys -contains 'Path') -and ($keys -contains 'Name') -and ($keys -contains 'Value')) { $count++ }
    }
    return $count
}
$tuneWrites = Get-TuneWriteCount (Join-Path $PSScriptRoot 'lib/tune-writes.ps1')
$facts = [ordered]@{ tools = $toolScripts.Count; apps = $appCount; tweaks = $tuneWrites }

if (-not $Quiet) {
    Say '===== check-counts =====' White
    Say ("  facts: tools={0} apps={1} tweakWrites={2}" -f $facts.tools, $facts.apps, $facts.tweaks)
    Say ''
}

# ------------------------------------------------------------------ claims in the docs
$docFiles = New-Object System.Collections.Generic.List[string]
foreach ($p in @(
        (Join-Path $root 'README.md'),
        (Join-Path $root 'AGENTS.md'),
        (Join-Path $root 'SKILL.md')
    )) {
    if (Test-Path -LiteralPath $p) { $docFiles.Add($p) }
}
foreach ($d in @((Join-Path $root 'docs'), (Join-Path $root 'games'))) {
    if (-not (Test-Path -LiteralPath $d)) { continue }
    foreach ($f in @(Get-ChildItem $d -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue)) { $docFiles.Add($f.FullName) }
}

# Rules are deliberately narrow so a match is always a real claim. Chinese alternatives are
# written as \uXXXX escapes because this directory must stay ASCII-only: Windows PowerShell 5.1
# decodes a BOM-less file as ANSI, and a multi-byte character breaks parsing silently.
$rules = @(
    @{ Name = 'tool scripts'; Fact = 'tools'; Rx = '(\d+)\s*(?:tool scripts|standalone tool scripts)' }
    @{ Name = 'tool scripts'; Fact = 'tools'; Rx = '(\d+)\s*(?:\u5de5\u5177\u811a\u672c)' }
    @{ Name = 'tool scripts'; Fact = 'tools'; Rx = '(\d+)\s*\u4e2a\u53ef\u5355(?:\u72ec\u7528|\u8dd1)\u7684?\u5de5\u5177' }
    @{ Name = 'tune writes';  Fact = 'tweaks'; Rx = '(\d+)\s*(?:\u4e2a\u8c03\u4f18\u503c)' }
    @{ Name = 'apps';         Fact = 'apps';  Rx = '(\d+)\s*(?:apps|applications)' }
    @{ Name = 'apps';         Fact = 'apps';  Rx = '(\d+)\s*(?:\u9879\u8f6f\u4ef6|\u4e2a\u5e94\u7528)' }
)

$checked = 0
foreach ($file in @($docFiles | Select-Object -Unique)) {
    $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction SilentlyContinue)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($rule in $rules) {
            foreach ($m in [regex]::Matches($lines[$i], $rule.Rx)) {
                $claimed = [int]$m.Groups[1].Value
                $actual = $facts[$rule.Fact]
                $checked++
                if ($claimed -ne $actual) {
                    $rel = $file.Replace($root, '').TrimStart('\', '/') -replace '\\', '/'
                    $problems.Add(("{0}:{1}: claims {2} {3}, actual {4}" -f $rel, ($i + 1), $claimed, $rule.Name, $actual))
                }
            }
        }
    }
}

if (-not $Quiet) { Say ("  checked {0} numeric claim(s) across {1} file(s)" -f $checked, @($docFiles | Select-Object -Unique).Count) }

if ($problems.Count -gt 0) {
    Say ''
    Say "  $($problems.Count) mismatch(es):" Red
    foreach ($p in $problems) { Say "    - $p" Red }
    exit 1
}
if (-not $Quiet) { Say '  ok: every quoted number matches the files' Green }
exit 0
