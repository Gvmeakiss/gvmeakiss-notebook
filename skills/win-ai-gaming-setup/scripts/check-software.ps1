<#
.SYNOPSIS
  Inventory the software present on a Windows machine, by category, and report how each
  item was installed (portable folder / Scoop / MSI) plus what still needs manual work.

.DESCRIPTION
  Read-only. Scans, in priority order:
    1. a portable-app root (default ~\Apps) - folder-per-app layout
    2. Scoop apps
    3. registry uninstall entries (for MSI/exe installers)
  Then reports PATH coverage and file-association state.

  The point is to answer "what do I actually have, and what still needs a click?"
  without relying on memory or on the Windows "Apps & features" list, which omits
  portable software entirely.

.PARAMETER PortableRoot
  Directory holding portable applications. Default: $env:USERPROFILE\Apps

.PARAMETER Json
  Emit JSON instead of the human-readable report.

.EXAMPLE
  pwsh -File check-software.ps1
  pwsh -File check-software.ps1 -Json | Out-File software.json

.NOTES
  ASCII-only on purpose.
#>
[CmdletBinding()]
param(
    [string]$PortableRoot = (Join-Path $env:USERPROFILE 'Apps'),
    # Manifest for the "declared apps" readback section. Defaults to the one in the skill root.
    # If it is absent that section just says so; nothing else changes.
    [string]$Manifest = (Join-Path $PSScriptRoot '..\apps.json'),
    [switch]$Json
)

$ErrorActionPreference = 'Continue'
$report = [ordered]@{}

# A GUI/agent parent process may predate the current PATH configuration, so its inherited
# environment can be stale and make installed tools look absent. Rebuild the process PATH
# from the registry (Machine + User) before probing anything.
$env:PATH = (@(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User')
) | Where-Object { $_ }) -join ';'

function Section { param([string]$T) if (-not $Json) { Write-Output "`n===== $T =====" } }
function Row     { param([string]$L, $V) if (-not $Json) { '{0,-30} {1}' -f $L, $V } }

# ------------------------------------------------------------------ context
Section 'Context'
$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {}
$ctx = [ordered]@{
    User          = "$env:USERDOMAIN\$env:USERNAME"
    IsAdmin       = $isAdmin
    PortableRoot  = $PortableRoot
    PortableRootExists = (Test-Path $PortableRoot)
}
# winget decides whether a package manager is even an option
foreach ($pm in @('winget','scoop','choco')) {
    $ctx["Has_$pm"] = [bool](Get-Command $pm -ErrorAction SilentlyContinue)
}
$report.Context = $ctx
foreach ($k in $ctx.Keys) { Row $k $ctx[$k] }

if (-not $isAdmin) {
    if (-not $Json) {
        Write-Output ''
        Write-Output 'NOTE: not an administrator. Machine-wide MSI installers and "all users"'
        Write-Output '      installs will either fail or leave a partial install. Prefer the'
        Write-Output '      portable route (see README) or a user-level package manager.'
    }
}

# ----------------------------------------------------- portable applications
Section 'Portable applications'
$portable = @()
if (Test-Path $PortableRoot) {
    foreach ($d in Get-ChildItem $PortableRoot -Directory -Force -ErrorAction SilentlyContinue) {
        # skip bookkeeping folders
        if ($d.Name -in @('.installers', '_backup', '_cache')) { continue }
        $exes = @(Get-ChildItem $d.FullName -Recurse -File -Filter '*.exe' -ErrorAction SilentlyContinue)
        if ($exes.Count -eq 0) { continue }
        # pick the most likely main executable: shallowest path, prefer a name match
        $main = $exes | Sort-Object { ($_.FullName -split '\\').Count } |
                Where-Object { $_.BaseName -like "*$($d.Name)*" } |
                Select-Object -First 1
        if (-not $main) { $main = $exes | Sort-Object { ($_.FullName -split '\\').Count } | Select-Object -First 1 }
        $sizeMb = [math]::Round(((Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Measure-Object Length -Sum).Sum / 1MB), 1)
        $portable += [pscustomobject]@{
            Category = 'portable'
            Name     = $d.Name
            Version  = ''
            MainExe  = $main.FullName
            SizeMB   = $sizeMb
        }
    }
}
if ($portable.Count -eq 0) {
    Row 'portable apps' "none found under $PortableRoot"
} else {
    foreach ($p in $portable | Sort-Object Name) {
        if (-not $Json) { '  {0,-14} {1,8} MB  {2}' -f $p.Name, $p.SizeMB, $p.MainExe | Write-Output }
    }
}

# ------------------------------------------------ declared apps (manifest readback)
# The scan above GUESSES a main exe by filename. Fine for an inventory, but it cannot answer
# what the manifest actually promises: "is the app I declared really there?". Measured reason
# to care - an entry whose 'exe' path was wrong installed, produced no shortcut, and still read
# as healthy. So verify the declared path directly:
#   verifyPath - absolute path for winget entries ('%VAR%' is expanded)
#   exe        - path relative to <PortableRoot>\<name> for portable entries
Section 'Declared apps (manifest)'
$declared = @()
if (-not (Test-Path -LiteralPath $Manifest)) {
    Row 'manifest' "not found: $Manifest"
}
else {
    $man = $null
    try { $man = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Row 'manifest' "cannot parse: $($_.Exception.Message)" }
    if ($man -and $man.apps) {
        foreach ($app in $man.apps) {
            $foundPath = $null
            $foundWhere = ''
            if ($app.verifyPath) {
                $candidate = [Environment]::ExpandEnvironmentVariables([string]$app.verifyPath)
                if (Test-Path -LiteralPath $candidate) { $foundPath = $candidate; $foundWhere = 'vendor' }
            }
            elseif ($app.exe) {
                $candidate = Join-Path (Join-Path $PortableRoot $app.name) ([string]$app.exe)
                if (Test-Path -LiteralPath $candidate) { $foundPath = $candidate; $foundWhere = 'portable' }
            }
            # altPaths: places the same app legitimately lives when it was installed by winget or
            # by hand instead of through this skill. Measured need - Notepad++ and TrafficMonitor
            # were winget-installed on a real machine, so a portable-only check called them
            # missing and turned a correct install into a false alarm. Wildcards are allowed.
            if (-not $foundPath -and $app.altPaths) {
                foreach ($alt in @($app.altPaths)) {
                    $candidate = [Environment]::ExpandEnvironmentVariables([string]$alt)
                    if (Test-Path -LiteralPath $candidate) { $foundPath = $candidate; $foundWhere = 'alt'; break }
                    if ($candidate -match '[*?]') {
                        $hit = @(Get-Item -Path $candidate -ErrorAction SilentlyContinue) | Select-Object -First 1
                        if ($hit) { $foundPath = $hit.FullName; $foundWhere = 'alt'; break }
                    }
                }
            }
            $declared += [pscustomobject]@{
                Name   = $app.name
                Source = $(if ($app.source) { [string]$app.source } else { 'portable' })
                Found  = [bool]$foundPath
                Where  = $foundWhere
                Path   = $foundPath
            }
        }
    }
}

$declaredMissing = @($declared | Where-Object { -not $_.Found })
if ($declared.Count -gt 0) {
    if (-not $Json) {
        foreach ($d in $declared | Sort-Object Name) {
            $mark = if ($d.Found) { 'OK   ' } else { 'MISS ' }
            $shown = if ($d.Found) { "$($d.Path)  [$($d.Where)]" } else { 'not found at any known path' }
            '  {0} {1,-14} {2}' -f $mark, $d.Name, $shown | Write-Output
        }
        Row 'declared apps' "$($declared.Count - $declaredMissing.Count)/$($declared.Count) present"
    }
    if ($declaredMissing.Count -gt 0) {
        Row 'missing' (($declaredMissing | ForEach-Object { $_.Name }) -join ', ')
    }
}
$report['declaredApps'] = $declared

# Recover versions from the main executable's file metadata
foreach ($p in $portable) {
    try {
        $vi = (Get-Item $p.MainExe).VersionInfo
        $p.Version = if ($vi.ProductVersion) { $vi.ProductVersion } elseif ($vi.FileVersion) { $vi.FileVersion } else { '' }
    } catch {}
}
$report.PortableApps = $portable

# ------------------------------------------------------------------- scoop
Section 'Scoop applications'
$scoopApps = @()
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    try {
        $lines = @(& scoop list 2>&1)
        foreach ($l in $lines | Select-Object -Skip 1) {
            if ($l -match '^(\S+)\s+(\S+)') {
                $scoopApps += [pscustomobject]@{ Category='scoop'; Name=$Matches[1]; Version=$Matches[2] }
            }
        }
    } catch {}
    foreach ($a in $scoopApps) { if (-not $Json) { '  {0,-16} {1}' -f $a.Name, $a.Version | Write-Output } }
} else {
    Row 'scoop' 'not installed'
}
$report.ScoopApps = $scoopApps

# ------------------------------------------------------- MSI / exe installs
Section 'Registered (MSI / installer) applications'
# These come from uninstall registry keys. Portable software never appears here -
# which is exactly why a portable inventory has to be done separately.
$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$registered = @()
foreach ($rp in $regPaths) {
    try {
        $registered += Get-ItemProperty $rp -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object @{n='Name';e={$_.DisplayName}},
                          @{n='Version';e={$_.DisplayVersion}},
                          @{n='Publisher';e={$_.Publisher}}
    } catch {}
}
$registered = $registered | Sort-Object Name -Unique
Row 'count' $registered.Count
foreach ($r in $registered) {
    if (-not $Json) { '  {0,-46} {1}' -f $r.Name, $r.Version | Write-Output }
}
$report.RegisteredApps = $registered

# -------------------------------------------------------------------- PATH
Section 'PATH coverage for portable tools'
$userPath = @(([Environment]::GetEnvironmentVariable('Path','User')) -split ';' | Where-Object { $_ })
$portableOnPath = @($userPath | Where-Object { $_ -like "$PortableRoot*" })
if ($portableOnPath.Count -eq 0) {
    Row 'portable dirs on PATH' 'none - CLI tools inside them must be called by full path'
} else {
    foreach ($p in $portableOnPath) { Row 'on PATH' $p }
}
$report.PortableOnPath = $portableOnPath

# --------------------------------------------------------- file associations
Section 'File association state'
# Windows 10/11 protects the UserChoice key with a DENY ACE on SetValue, so no script
# can silently change a default program. Report only whether the common extensions
# already resolve to something, so the operator knows what still needs a manual click.
$assoc = [ordered]@{}
foreach ($ext in @('.md','.txt','.png','.jpg','.jpeg','.gif','.webp','.bmp','.mp4','.mkv','.avi','.mov','.mp3','.flac','.wav')) {
    $progId = $null
    try {
        $v = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice" `
                -ErrorAction SilentlyContinue
        if ($v) { $progId = $v.ProgId }
    } catch {}
    if (-not $progId) {
        try {
            $openWith = (Get-ItemProperty "HKCU:\Software\Classes\$ext" -ErrorAction SilentlyContinue).'(default)'
            if ($openWith) { $progId = $openWith }
        } catch {}
    }
    $assoc[$ext] = if ($progId) { $progId } else { '<unset>' }
    Row $ext $assoc[$ext]
}
$report.FileAssociations = $assoc
if (-not $Json) {
    Write-Output ''
    Write-Output '  NOTE: a UserChoice entry carries a hash and a SETVALUE-DENY ACE. Scripts'
    Write-Output '        cannot change it. Anything showing <unset> or an AppX* (built-in Store'
    Write-Output '        app) must be changed once by hand: right-click a file -> Open with ->'
    Write-Output '        Choose another app -> tick "Always use this app".'
}

# ------------------------------------------------------------------- output
if ($Json) { $report | ConvertTo-Json -Depth 6 }
else {
    Write-Output "`n===== inventory complete ====="
    Write-Output "portable: $($portable.Count)   scoop: $($scoopApps.Count)   registered: $($registered.Count)"
}
