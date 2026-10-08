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
  Path to a JSON manifest. See README "Manifest format".

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
    [switch]$SkipShortcuts
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
if ($Only) {
    # PowerShell's -File argument parsing does NOT split "A,B" into an array: the whole
    # string arrives as one element. Accept comma-separated text as well as a real array
    # so both of these work:
    #   pwsh -File install-portable.ps1 -Manifest m.json -Only A,B
    #   pwsh -Command "& ./install-portable.ps1 -Manifest m.json -Only A,B"
    $wanted = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $apps = @($apps | Where-Object { $n = $_.name; $wanted -contains $n })
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

# ------------------------------------------------------------------- 7-Zip
# Resolve an extractor: prefer an installed 7-Zip, else fetch the standalone 7zr.exe.
# 7zr handles both .zip and .7z, so one binary covers every manifest entry.
$sevenZip = $null
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
if (-not $sevenZip) {
    $sevenZip = Join-Path $cache '7zr.exe'
    if (Test-Path $sevenZip) {
        Ok "using standalone extractor: $sevenZip"
    } else {
        $sevenZipUrl = 'https://www.7-zip.org/a/7zr.exe'
        if ($Cmdlet.ShouldProcess($sevenZipUrl, 'download 7zr.exe')) {
            try {
                Invoke-WebRequest -Uri $sevenZipUrl -OutFile $sevenZip -TimeoutSec 120 -UseBasicParsing -ErrorAction Stop
                Ok 'fetched standalone 7zr.exe'
            } catch {
                Bad "cannot fetch 7zr.exe: $($_.Exception.Message.Split("`n")[0])"
                Write-Output '         install 7-Zip (e.g. scoop install 7zip) and re-run'
                exit 1
            }
        }
    }
} else { Ok "extractor: $sevenZip" }

$failures = @()

foreach ($app in $apps) {
    Write-Output "`n--- $($app.name)"
    $target = Join-Path $Destination $app.name
    if (Test-Path $target) {
        Ok "already installed at $target (delete the folder to reinstall)"
        continue
    }
    if (-not $app.url) { Bad 'manifest entry has no url'; $failures += $app.name; continue }

    $fileName = Split-Path ([uri]$app.url).AbsolutePath -Leaf
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

    # extract
    $staging = Join-Path $cache ("_x_" + $app.name)
    if ($Cmdlet.ShouldProcess($target, "extract $fileName")) {
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        & $sevenZip x $archive "-o$staging" -y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Bad "extraction failed (exit $LASTEXITCODE)"; $failures += $app.name; continue }

        # collapse a single top-level directory so the layout is always <dest>\<app>\<files>
        $entries = @(Get-ChildItem $staging -Force)
        $source = if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) { $entries[0].FullName } else { $staging }
        Move-Item -Path $source -Destination $target -Force
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
        Ok "installed to $target"
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
            Warn "exe not found after extraction: $($app.exe) - skipping shortcut"
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
if ($failures.Count -eq 0) {
    Write-Output 'all selected apps installed'
    Write-Output 'Open a NEW terminal for any PATH change to take effect.'
} else {
    Write-Output "failed ($($failures.Count)): $($failures -join ', ')"
    exit 1
}
