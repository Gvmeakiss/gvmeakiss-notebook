<#
.SYNOPSIS
    Check in-page anchors and relative links in every tracked markdown file.

.DESCRIPTION
    Offline, no network. Reports two kinds of breakage:

      * [text](#anchor) whose anchor matches neither a heading slug nor an <a name>/<a id>
      * a relative link whose target file does not exist

    GitHub does not report either of these - a dead anchor silently jumps to the top of
    the page - so this is checked mechanically rather than by eye.

    Fenced code blocks, inline code and HTML comments are stripped before scanning,
    because documentation legitimately contains link syntax as an example and that
    must not be counted as a real link.

.PARAMETER RepoRoot
    Repository root. Defaults to the parent folder of this script.

.PARAMETER All
    Also check files that git does not track (useful before the first commit).

.NOTES
    ASCII-only on purpose: the same file runs in CI on Linux and locally on Windows.
    Exit code is 1 when anything is broken, so it works as a CI gate.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$All
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$sep = [System.IO.Path]::DirectorySeparatorChar

function Get-HeadingSlug {
    param([string]$Heading)
    # GitHub slug rule: lowercase, drop punctuation and symbols, spaces to hyphens.
    # Letters and digits are kept as-is, which is what makes CJK headings work.
    $s = $Heading.Trim().ToLowerInvariant()
    $s = $s -replace '<[^>]+>', ''
    $s = $s -replace '[^\p{L}\p{N}\s\-_]', ''
    $s = $s -replace '\s', '-'
    return $s
}

if ($All) {
    $mdFiles = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter '*.md' |
        Where-Object { $_.FullName -notmatch "[\\/]\.git[\\/]|[\\/]node_modules[\\/]" } |
        ForEach-Object { $_.FullName.Substring($RepoRoot.Length).TrimStart('\', '/') -replace '\\', '/' })
}
else {
    $mdFiles = @(& git -C $RepoRoot -c core.quotepath=false ls-files '*.md')
}
if ($mdFiles.Count -eq 0) { throw "no markdown files found under $RepoRoot" }

$ok = 0
$bad = 0
$badList = New-Object System.Collections.Generic.List[string]

foreach ($rel in ($mdFiles | Sort-Object -Unique)) {
    $full = Join-Path $RepoRoot ($rel -replace '/', $sep)
    if (-not (Test-Path -LiteralPath $full)) { continue }

    $raw = Get-Content -LiteralPath $full -Raw -Encoding UTF8
    if (-not $raw) { continue }

    # strip fenced blocks, inline code and html comments before looking at links
    $scan = [regex]::Replace($raw, '(?s)```.*?```', '')
    $scan = [regex]::Replace($scan, '(?s)~~~.*?~~~', '')
    $scan = [regex]::Replace($scan, '(?s)<!--.*?-->', '')
    $scan = [regex]::Replace($scan, '`[^`\r\n]*`', '')

    # Anchors come from the RAW text, not from $scan: GitHub keeps inline code when it
    # builds a heading slug, so stripping `code` first would compute a slug nobody uses.
    # Both the space-collapsing and the space-preserving variants are accepted, because
    # GitHub turns every space into its own hyphen ("a  b" -> "a--b").
    $anchors = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($raw, '(?m)^#{1,6}\s+(.+)$')) {
        $h = $m.Groups[1].Value
        $anchors.Add((Get-HeadingSlug $h))
        $anchors.Add(((Get-HeadingSlug $h) -replace '-+', '-'))
    }
    foreach ($m in [regex]::Matches($raw, '<a\s+(?:name|id)="([^"]+)"')) { $anchors.Add($m.Groups[1].Value) }

    # candidate links: markdown ](target) and html href="target"
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($scan, '\]\(\s*([^)\s]+)')) { $targets.Add($m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($scan, 'href="([^"]+)"')) { $targets.Add($m.Groups[1].Value) }

    $dir = Split-Path -Parent $full

    foreach ($t in $targets) {
        if ($t -match '^(https?:|mailto:|tel:|ftp:|javascript:)') { continue }
        if ($t -eq '' -or $t -eq '#') { continue }

        if ($t.StartsWith('#')) {
            $a = $t.Substring(1)
            if ($anchors -contains $a) { $ok++ }
            else {
                $bad++
                $badList.Add("$rel : dead anchor $t")
            }
            continue
        }

        $pathPart = ($t -split '#')[0]
        if (-not $pathPart) { continue }
        $decoded = [uri]::UnescapeDataString($pathPart)
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $dir ($decoded -replace '/', $sep)))
        if (Test-Path -LiteralPath $candidate) { $ok++ }
        else {
            $bad++
            $badList.Add("$rel : missing target $t")
        }
    }
}

$files = @($mdFiles | Sort-Object -Unique).Count
if ($badList.Count -gt 0) {
    Write-Output 'broken anchors / links:'
    foreach ($b in ($badList | Sort-Object -Unique)) { Write-Output "  [BAD] $b" }
}
Write-Output ("===== links: {0} file(s), {1} ok, {2} broken =====" -f $files, $ok, $bad)
if ($bad -gt 0) { exit 1 }
