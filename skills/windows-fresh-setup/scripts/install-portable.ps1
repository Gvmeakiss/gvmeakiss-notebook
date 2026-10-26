<#
.SYNOPSIS
  Install portable (no-installer) applications on Windows from a manifest, with
  cryptographic verification.

.DESCRIPTION
  Portable installation is the only route that works when the account is not an
  administrator: nothing is written to Program Files, no MSI runs, and uninstalling
  means deleting a folder.

  For every entry the script:
    1. downloads the release archive into a cache directory (skips if already present)
    2. verifies the SHA256 against the manifest - and REFUSES to install on mismatch
    3. extracts with an installed 7-Zip, or a fetched standalone 7zr.exe
    4. promotes the single top-level directory, if any, to the app root
    5. optionally creates a Start Menu shortcut
    6. optionally appends a CLI directory to the user PATH

  A missing hash is treated as a warning that requires -AllowUnverified, never as a
  silent pass. Supply hashes: they are the only thing standing between you and a
  tampered download.

.PARAMETER Manifest
  Path to a JSON manifest. The schema is defined by apps.json in the skill root; the two
  rules that bite are documented in README section 4.4 and in SKILL.md's trap table: every
  entry needs a SHA256, and each "exe" is a path RELATIVE to the install root (consumers
  must not reduce it with Split-Path -Leaf).

.PARAMETER Destination
  Root directory for installed apps. Default: $env:USERPROFILE\Apps

.PARAMETER Only
  Install only these app names. Accepts a comma-separated string; PowerShell's -File
  argument parsing does NOT split "A,B" into an array, so the script splits it itself.

.PARAMETER AllowUnverified
  Permit entries whose sha256 is empty. Not recommended.

.PARAMETER SkipShortcuts
  Do not create Start Menu shortcuts.

.EXAMPLE
  pwsh -File install-portable.ps1 -Manifest .\apps.example.json -WhatIf
  pwsh -File install-portable.ps1 -Manifest .\apps.example.json -Only Notepad++,rclone

.NOTES
  ASCII-only on purpose.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Manifest,
    [string]$Destination = (Join-Path $env:USERPROFILE 'Apps'),
    [string[]]$Only,
    [switch]$AllowUnverified,
    [switch]$SkipShortcuts,
    [switch]$IncludeOptional
)

$ErrorActionPreference = 'Continue'
$Cmdlet = $PSCmdlet

# Rebuild PATH from the registry so a stale parent environment cannot hide 7-Zip.
$env:PATH = (@(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User')
) | Where-Object { $_ }) -join ';'

function Info { param([string]$M) Write-Output "    $M" }
function Ok   { param([string]$M) Write-Output "    ok      $M" }
function Warn { param([string]$M) Write-Output "    WARN    $M" }
function Bad  { param([string]$M) Write-Output "    FAIL    $M" }

# Resolve the path a manifest entry says proves an app is really there.
#
# ONE implementation for both entry kinds, deliberately: the first version only checked the
# portable exe INSIDE the shortcut branch and only raised a Warn, so a wrong 'exe' path
# (measured: JPEGView needs 'JPEGView64\JPEGView.exe', a bare name never matches) printed
# "installed to ..." and still counted as success. That is the exact "installed but unusable"
# failure this repo keeps hitting, so verification is now a hard readback for every entry:
#   verifyPath - absolute path (winget entries); '%VAR%' is expanded
#   exe        - path relative to the install root (portable entries)
# Returns the resolved path, or $null when nothing was found.
# Path containment (Get-SafeChildPath) lives in lib/paths.ps1.
. (Join-Path $PSScriptRoot 'lib\paths.ps1')
function Resolve-InstalledPath {
    param($Entry, [string]$Root)
    if ($Entry.verifyPath) {
        $p = [Environment]::ExpandEnvironmentVariables([string]$Entry.verifyPath)
        if (Test-Path -LiteralPath $p) { return $p }
        return $null
    }
    if ($Entry.exe -and $Root) {
        try { $p = Get-SafeChildPath $Root ([string]$Entry.exe) "exe" } catch { return $null }
        if (Test-Path -LiteralPath $p) { return $p }
        return $null
    }
    return $null
}

# ------------------------------------------------------------------- manifest
if (-not (Test-Path $Manifest)) { Bad "manifest not found: $Manifest"; exit 1 }
try {
    $cfg = Get-Content $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Bad "manifest is not valid JSON: $($_.Exception.Message.Split("`n")[0])"; exit 1
}
$allApps = @($cfg.apps)
if ($allApps.Count -eq 0) { Bad 'manifest contains no apps'; exit 1 }

$apps = $allApps
$explicitNames = @()
if ($Only) {
    # PowerShell's -File argument parsing does NOT split "A,B" into an array: the whole
    # string arrives as one element. Accept comma-separated text as well as a real array
    # so both of these work:
    #   pwsh -File install-portable.ps1 -Manifest m.json -Only A,B
    #   pwsh -Command "& ./install-portable.ps1 -Manifest m.json -Only A,B"
    $wanted = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $explicitNames = $wanted
    $apps = @($apps | Where-Object { $n = $_.name; $wanted -contains $n })
}

# Optional entries ("optional": true) are SKIPPED by default.
#
# Why this exists: the manifest's own notes said to ask the user before installing the
# Markdown editor, and the README called that entry conditional - but the code installed it
# unconditionally, so the documented intent was never enforced. An entry the docs call
# conditional must be conditional in code, otherwise the docs describe a different program
# than the one that runs.
#
# Naming an entry explicitly with -Only counts as intent and installs it regardless.
$skippedOptional = @()
if (-not $IncludeOptional) {
    $skippedOptional = @($apps | Where-Object { $_ -and $_.optional -eq $true -and ($explicitNames -notcontains $_.name) })
    $apps = @($apps | Where-Object { -not ($_ -and $_.optional -eq $true -and ($explicitNames -notcontains $_.name)) })
}
if ($apps.Count -eq 0) {
    Bad 'no apps selected'
    if ($Only) {
        Info "requested : $($Only -join ' | ')"
        Info "available : $((@($allApps) | ForEach-Object { $_.name }) -join ', ')"
    }
    exit 1
}

Write-Output '===== install-portable ====='
Info "manifest : $Manifest"
Info "target   : $Destination"
Info "apps     : $($apps.Count)"
if ($WhatIfPreference) { Info 'DRY RUN (-WhatIf): nothing will be written' }

$cache = Join-Path $Destination '.installers'
if (-not $WhatIfPreference) { New-Item -ItemType Directory -Force -Path $cache, $Destination | Out-Null }

# ------------------------------------------------------------------- extractor
# Two different jobs, two different tools - do not conflate them:
#   * a FULL 7-Zip (7z.exe) reads both .7z and .zip.
#   * 7zr.exe is the standalone REDUCED build: it reads 7z but has NO ZIP CODEC. Using it
#     for .zip assets fails with exit code 2 on every archive - which is exactly what
#     happened here: the single .7z app installed fine while all three .zip apps failed,
#     and the comment that used to sit here ("7zr handles both .zip and .7z") was simply
#     wrong.
# So a full 7-Zip is preferred; without it, .zip entries use the in-box ZIP support and
# only .7z entries need the 7zr download.
$sevenZip = $null           # full 7-Zip: handles .7z and .zip
$sevenZr  = $null           # reduced standalone: handles .7z only
foreach ($cand in @(
    (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
    (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'),
    (Join-Path $env:USERPROFILE 'scoop\apps\7zip\current\7z.exe')
)) {
    if ($cand -and (Test-Path $cand)) { $sevenZip = $cand; break }
}
if (-not $sevenZip) {
    $cmd = Get-Command 7z -ErrorAction SilentlyContinue
    if ($cmd) { $sevenZip = $cmd.Source }
}
if ($sevenZip) {
    Ok "extractor: $sevenZip (full 7-Zip - handles .7z and .zip)"
} else {
    Ok 'no full 7-Zip found: .zip assets will use the in-box ZIP support'
    $sevenZr = Join-Path $cache '7zr.exe'
    if (Test-Path $sevenZr) {
        Ok "using standalone 7zr.exe for .7z assets only: $sevenZr"
    } else {
        $sevenZipUrl = 'https://www.7-zip.org/a/7zr.exe'
        if ($Cmdlet.ShouldProcess($sevenZipUrl, 'download 7zr.exe (needed only for .7z assets)')) {
            try {
                Invoke-WebRequest -Uri $sevenZipUrl -OutFile $sevenZr -TimeoutSec 120 -UseBasicParsing -ErrorAction Stop
                Ok 'fetched standalone 7zr.exe (.7z assets only)'
            } catch {
                # Not fatal any more: .zip entries no longer depend on it.
                Warn "cannot fetch 7zr.exe: $($_.Exception.Message.Split("`n")[0])"
                Warn '.zip entries will still install; .7z entries will be skipped'
                $sevenZr = $null
            }
        }
    }
}

$failures = @()
$verified = @()      # apps whose declared path was read back successfully - reported in the summary

# Report the skipped optional entries up front, so the reason is visible next to the run
# instead of only in the manifest. Not a failure: skipping is the documented default.
foreach ($s in $skippedOptional) {
    Write-Output "`n--- $($s.name)"
    Warn 'optional - skipped (pass -IncludeOptional, or name it with -Only, to install)'
    if ($s.optionalReason) { Info $s.optionalReason }
}

foreach ($app in $apps) {
    Write-Output "`n--- $($app.name)"

    # ---------------------------------------------------------------------- winget entries
    # Some tools have no portable archive worth trusting (7-Zip, WinRAR). The manifest marks
    # those with source=winget, and this branch deliberately bypasses the scoop path: on a
    # real machine scoop failed to bootstrap, so 7-Zip was never installed even though the
    # check phase reported the bundle as handled. A second, independent path is what makes
    # the archive tools actually appear.
    #
    # Verification is by readback, not by command success: verifyPath must exist AFTER the
    # install. A winget exit code of 0 has been wrong before, and "installed" that cannot be
    # located on disk is exactly the failure this repo keeps hitting.
    if ($app.source -eq 'winget') {
        $found = Resolve-InstalledPath $app $null
        if ($found) {
            Ok "already installed: $found"
            $verified += $app.name
            continue
        }
        if (-not $app.wingetId) { Bad 'manifest entry has source=winget but no wingetId'; $failures += $app.name; continue }
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Bad 'winget not available - install "App Installer" from the Microsoft Store, then re-run'
            $failures += $app.name
            continue
        }
        if ($Cmdlet.ShouldProcess($app.wingetId, 'winget install')) {
            & winget install --id $app.wingetId --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
                ForEach-Object { Info ([string]$_) }
            Info "winget exit code: $LASTEXITCODE"
        }
        $found = Resolve-InstalledPath $app $null
        if ($found) {
            Ok "verified: $found"
            $verified += $app.name
        }
        else {
            Bad "still missing after install: $($app.verifyPath)"
            Info 'install it from the vendor site by hand, then re-run this phase'
            $failures += $app.name
        }
        continue
    }

    try { $target = Get-SafeChildPath $Destination $app.name "app.name '$($app.name)'" }
    catch {
        Bad ([string]$_.Exception.Message)
        $failures += $app.name
        continue
    }
    if (Test-Path $target) {
        # Re-verify on every run: a folder that exists but no longer holds the declared exe
        # (interrupted extraction, user deleted files) must not read as healthy.
        $found = Resolve-InstalledPath $app $target
        if ($found) {
            Ok "already installed: $found"
            $verified += $app.name
        }
        else {
            Bad "folder exists but $($app.exe) is missing - delete $target and re-run"
            $failures += $app.name
        }
        continue
    }
    if (-not $app.url) { Bad 'manifest entry has no url'; $failures += $app.name; continue }

    $fileName = Split-Path ([uri]$app.url).AbsolutePath -Leaf
    if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName -match '[\\/:*?"<>|]' -or $fileName -eq '.' -or $fileName -eq '..') {
        Bad "url does not end in a usable file name: $($app.url)"
        $failures += $app.name
        continue
    }
    $archive = Join-Path $cache $fileName

    # download
    if (Test-Path $archive) {
        Ok "cached: $fileName"
    } elseif ($Cmdlet.ShouldProcess($app.url, "download $fileName")) {
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            Invoke-WebRequest -Uri $app.url -OutFile $archive -TimeoutSec 1800 -UseBasicParsing -ErrorAction Stop
            $sw.Stop()
            Ok ("downloaded {0:N1} MB in {1:N0}s" -f ((Get-Item $archive).Length/1MB), $sw.Elapsed.TotalSeconds)
        } catch {
            Bad "download failed: $($_.Exception.Message.Split("`n")[0])"
            $failures += $app.name; continue
        }
    } else { continue }

    # verify - this is the security gate
    if ($app.sha256) {
        $actual = (Get-FileHash $archive -Algorithm SHA256).Hash
        if ($actual -eq $app.sha256.ToUpperInvariant()) {
            Ok 'SHA256 verified'
        } else {
            Bad 'SHA256 MISMATCH - refusing to install'
            Info "expected $($app.sha256.ToUpperInvariant())"
            Info "actual   $actual"
            # a mismatch means the download is corrupt or tampered with; never promote it
            if ($Cmdlet.ShouldProcess($archive, 'delete the failed download')) {
                Remove-Item $archive -Force -ErrorAction SilentlyContinue
            }
            $failures += $app.name; continue
        }
    } else {
        if (-not $AllowUnverified) {
            Bad 'no sha256 in manifest - refusing (pass -AllowUnverified to override)'
            $failures += $app.name; continue
        }
        Warn 'no sha256 provided - installing UNVERIFIED download'
    }

    # extract - pick the tool that actually supports this container
    $staging = Join-Path $cache ("_x_" + $app.name)
    if ($Cmdlet.ShouldProcess($target, "extract $fileName")) {
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Force -Path $staging | Out-Null

        $ext = [IO.Path]::GetExtension($fileName).ToLowerInvariant()
        $extracted = $false
        if ($sevenZip) {
            & $sevenZip x $archive "-o$staging" -y 2>&1 | Out-Null
            $extracted = ($LASTEXITCODE -eq 0)
            if (-not $extracted) { Bad "extraction failed (exit $LASTEXITCODE) via $sevenZip" }
        }
        elseif ($ext -eq '.zip') {
            # No external tool needed for ZIP. .NET's ZipFile is far quicker than
            # Expand-Archive on a large archive (the MarkText asset alone is ~166 MB);
            # Expand-Archive is kept as the fallback in case ZipFile rejects an entry.
            try {
                Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                [System.IO.Compression.ZipFile]::ExtractToDirectory($archive, $staging)
                $extracted = $true
            }
            catch {
                try {
                    Expand-Archive -Path $archive -DestinationPath $staging -Force -ErrorAction Stop
                    $extracted = $true
                }
                catch { Bad "ZIP extraction failed: $($_.Exception.Message.Split("`n")[0])" }
            }
        }
        elseif ($ext -eq '.7z') {
            if ($sevenZr) {
                & $sevenZr x $archive "-o$staging" -y 2>&1 | Out-Null
                $extracted = ($LASTEXITCODE -eq 0)
                if (-not $extracted) { Bad "extraction failed (exit $LASTEXITCODE) via 7zr" }
            }
            else {
                Bad 'a .7z asset needs 7-Zip, and the 7zr.exe download did not succeed'
                Info 'install 7-Zip (e.g. scoop install 7zip) and re-run'
            }
        }
        else {
            try {
                Expand-Archive -Path $archive -DestinationPath $staging -Force -ErrorAction Stop
                $extracted = $true
            }
            catch { Bad "no extractor for '$ext': $($_.Exception.Message.Split("`n")[0])" }
        }
        if (-not $extracted) { $failures += $app.name; continue }

        # collapse a single top-level directory so the layout is always <dest>\<app>\<files>
        $entries = @(Get-ChildItem $staging -Force)
        $source = if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) { $entries[0].FullName } else { $staging }
        Move-Item -Path $source -Destination $target -Force
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
        Ok "installed to $target"

        # Readback before anything else claims success. The archive checksum only proves the
        # DOWNLOAD was intact; it says nothing about whether the extracted layout matches the
        # 'exe' the manifest promises, which is a separate and historically broken assumption.
        $found = Resolve-InstalledPath $app $target
        if ($found) {
            Ok "verified: $found"
            $verified += $app.name
        }
        elseif ($WhatIfPreference) {
            Warn 'would verify the declared exe (nothing extracted in a dry run)'
        }
        else {
            Bad "extracted, but $($app.exe) is not there - the manifest 'exe' path is wrong"
            Info 'list the folder and fix that entry; a wrong path used to only skip the shortcut'
            $failures += $app.name
            continue
        }

        # Config presets ("configFiles" in the manifest): <destination file name> -> <path
        # relative to the skill root>. Written ONLY on a fresh install, on purpose: re-running
        # the installer must not overwrite settings the user has since tuned by hand.
        #
        # The preset files are copied as raw bytes so their encoding survives. That matters
        # here: TrafficMonitor decides how to read its ini by looking for a UTF-8 BOM, so a
        # preset rewritten without one turns every Chinese label into mojibake.
        if ($app.configFiles) {
            $skillRoot = Split-Path -Path (Resolve-Path -LiteralPath $Manifest).Path -Parent
            foreach ($prop in $app.configFiles.PSObject.Properties) {
                $destName = $prop.Name
                $srcRel = [string]$prop.Value
                $srcFile = Join-Path $skillRoot $srcRel
                if (-not (Test-Path -LiteralPath $srcFile)) {
                    Warn "config preset missing, skipped: $srcRel"
                    continue
                }
                try { $dstFile = Get-SafeChildPath $target $destName "configFiles '$destName'" }
                catch { Bad ([string]$_.Exception.Message); continue }
                if ($Cmdlet.ShouldProcess($dstFile, "write $destName from preset")) {
                    try {
                        [System.IO.File]::Copy($srcFile, $dstFile, $true)
                        Ok "config: $destName <- $srcRel"
                    }
                    catch { Warn "could not write $destName : $($_.Exception.Message)" }
                }
            }
        }
    }

    # shortcut
    if (-not $SkipShortcuts -and $app.exe) {
        $exePath = Join-Path $target $app.exe
        if (Test-Path $exePath) {
            $smDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Portable Tools'
            if ($Cmdlet.ShouldProcess($smDir, "create shortcut for $($app.name)")) {
                New-Item -ItemType Directory -Force -Path $smDir | Out-Null
                $lnk = Join-Path $smDir ("$($app.name).lnk")
                $ws = New-Object -ComObject WScript.Shell
                $sc = $ws.CreateShortcut($lnk)
                $sc.TargetPath = $exePath
                $sc.WorkingDirectory = Split-Path $exePath -Parent
                $sc.Save()
                Ok "shortcut: $lnk"
            }
        } else {
            # In a dry run nothing was extracted, so the exe cannot exist yet. Reporting it as
            # "not found after extraction" reads like a manifest fault and sent a real
            # investigation down the wrong path - measured on a `-WhatIf` run.
            if ($WhatIfPreference) {
                Warn "would create a shortcut to $($app.exe) (cannot verify in a dry run)"
            } else {
                Warn "exe not found after extraction: $($app.exe) - skipping shortcut"
            }
        }
    }

    # CLI on PATH
    if ($app.addToPath) {
        $cliDir = Join-Path $target $app.addToPath
        if (Test-Path $cliDir) {
            $userPath = [Environment]::GetEnvironmentVariable('Path','User')
            $parts = @($userPath -split ';' | Where-Object { $_ })
            if ($parts -contains $cliDir) {
                Ok "already on PATH: $cliDir"
            } elseif ($Cmdlet.ShouldProcess('User PATH', "add $cliDir")) {
                [Environment]::SetEnvironmentVariable('Path', (($cliDir) + ';' + ($parts -join ';')), 'User')
                Ok "added to PATH: $cliDir"
            }
        } else {
            Warn "addToPath directory does not exist: $($app.addToPath)"
        }
    }
}

# ------------------------------------------------------------------- summary
Write-Output "`n===== summary ====="
$skipNote = if ($skippedOptional.Count -gt 0) {
    " ($($skippedOptional.Count) optional skipped: $((@($skippedOptional | ForEach-Object { $_.name })) -join ', '))"
} else { '' }
if ($failures.Count -eq 0) {
    # A dry run must not claim it installed anything: measured, `-WhatIf` printed
    # "all selected apps installed" while having written nothing at all.
    if ($WhatIfPreference) {
        Write-Output "DRY RUN (-WhatIf): nothing was written. Re-run without -WhatIf to install.$skipNote"
    } else {
        # Report how many were actually read back. "no failure recorded" and "every app is
        # verifiably on disk" are different claims, and only the second one is useful.
        Write-Output "all selected apps installed and verified ($($verified.Count)/$($apps.Count))$skipNote"
        Write-Output 'Open a NEW terminal for any PATH change to take effect.'
    }
} else {
    Write-Output "failed ($($failures.Count)): $($failures -join ', ')$skipNote"
    Write-Output "verified ($($verified.Count)/$($apps.Count)): $(@($verified) -join ', ')"
    exit 1
}