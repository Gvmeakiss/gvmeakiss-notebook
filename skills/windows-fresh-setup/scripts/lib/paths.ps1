# ---------------------------------------------------------------------------
# Path containment (extracted from install-portable.ps1, P2-6 modularisation).
#
# Manifest fields become filesystem paths, and a manifest is just JSON:
# `"name": "..\\..\\Windows"` would install OUTSIDE the destination root. Every join must go
# through Get-SafeChildPath, which rejects absolute paths, drive-qualified names and `..` by
# comparing full paths against the root rather than by pattern-matching the input.
#
# The check is deliberately fail-closed: an unparsable candidate throws instead of returning a
# path that "looks fine".
# ---------------------------------------------------------------------------

function Get-SafeChildPath {
    param([string]$Root, [string]$Relative, [string]$What)
    $rootFull = [IO.Path]::GetFullPath($Root)
    # Reject rooted input EXPLICITLY. Join-Path happily concatenates 'C:\Windows\x' onto the root,
    # producing 'C:\Apps\C:\Windows\x' - a path that is under the root as TEXT but nonsense on
    # disk. Failing here is clearer than letting the check "pass" and the copy fail later.
    if ([IO.Path]::IsPathRooted($Relative)) { throw "$What must be relative, but '$Relative' is rooted" }
    try { $candidate = [IO.Path]::GetFullPath((Join-Path $rootFull $Relative)) }
    catch { throw "$What is not a valid relative path: '$Relative'" }
    $rootWithSep = $rootFull.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($rootWithSep, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$What escapes the root: '$Relative' resolves to '$candidate' (root: '$rootFull')"
    }
    return $candidate
}

# True/false variant for callers that only need to probe (no exception).
function Test-PathContained {
    param([string]$Root, [string]$Relative)
    try { $null = Get-SafeChildPath -Root $Root -Relative $Relative -What 'path'; return $true }
    catch { return $false }
}
