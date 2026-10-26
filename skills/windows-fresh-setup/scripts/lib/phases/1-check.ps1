# Phase 'check' - dot-sourced by setup.ps1 in execution order.
#
# The guard below ($phases -contains ...) is kept inside this file on purpose: dot-sourcing
# runs it in setup.ps1's own scope, so the block still sees that script's variables and
# helpers, and the phase only runs when it was selected.

if ($phases -contains 'check') {
    Say '--- check/bootstrap: prerequisites ---' White
    $okAll = $true

    if ($isPS7) { Ok "PowerShell $($PSVersionTable.PSVersion) (Core)" }
    else {
        Warn "running on Windows PowerShell $($PSVersionTable.PSVersion) - this plan prefers PowerShell 7"
        $scoopNow = Get-Command 'scoop' -ErrorAction SilentlyContinue
        if ($scoopNow) { if (-not (Scoop-Install @('pwsh'))) { $okAll = $false } }
        else { Warn 'install PowerShell 7 later with: scoop install pwsh   (or: winget install Microsoft.PowerShell)' }
    }

    if (-not (Get-Command 'scoop' -ErrorAction SilentlyContinue)) {
        if (-not $needsScoop) {
            # Measured: `-Profile minimal` failed here on an elevated shell because scoop was
            # missing - yet minimal only needs winget and portable zips, never scoop.
            Warn 'scoop missing - not needed for the selected phases (apps/link use winget and portable zips)'
        }
        elseif ($isAdmin) {
            # Measured: scoop's installer prints "Running the installer as administrator is
            # disabled by default ... Abort." and exits non-zero, which made -Phase check FAIL
            # on every elevated session. Report the real remedy instead of retrying it.
            Warn 'scoop missing and this session is ELEVATED - scoop refuses to install as administrator'
            Warn '  open a NORMAL user terminal and run:  irm get.scoop.sh | iex'
            Warn '  then re-run:  setup.ps1 -Profile dev'
            $okAll = $false
        }
        elseif ($PSCmdlet.ShouldProcess('Scoop', 'install from the official script (user-level)')) {
            Step 'scoop missing - installing it (user-level, no elevation)'
            try {
                Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
                Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
                Reset-Path
                if (Get-Command 'scoop' -ErrorAction SilentlyContinue) { Ok 'scoop installed' } else { Bad 'scoop installed but not on PATH - open a new terminal and re-run'; $okAll = $false }
            }
            catch { Bad "scoop install failed: $($_.Exception.Message)"; $okAll = $false }
        }
    }
    else { Ok 'scoop present' }

    # git comes first for the dev phase: scoop buckets need it.
    if ($needsScoop) {
        if (-not (Scoop-Install @('git'))) { $okAll = $false }
    }

    # 7-Zip is attempted through scoop because the apps phase needs an extractor, but it is
    # NOT allowed to depend on scoop alone. Measured on a real machine: scoop never bootstrapped,
    # so 7-Zip was never installed while this phase still counted the bundle as handled, and the
    # user ended up installing it from 7-zip.org by hand. The winget entry in apps.json is the
    # independent second path; the verdict is a readback of the binary, never the exit code.
    if (Get-Command 'scoop' -ErrorAction SilentlyContinue) {
        if (-not (Scoop-Install @('7zip'))) { Warn '7-Zip not installed by scoop - falling back to winget' }
    }
    if (-not (Test-ArchiveTool)) {
        if (-not (Invoke-Step 'install-portable.ps1' @('-Only', '7-Zip') '7-Zip fallback (winget entry)')) {
            Warn 'winget fallback reported a failure'
        }
        Reset-Path
    }
    if (Test-ArchiveTool) { Ok '7-Zip present' }
    else { Bad '7-Zip missing after scoop AND winget - install it from 7-zip.org, then re-run'; $okAll = $false }

    if (Test-Path $gitExe) {
        if ($PSCmdlet.ShouldProcess('git config --global core.longpaths', 'set true')) {
            & $gitExe config --global core.longpaths true 2>&1 | Out-Null
            Ok 'git core.longpaths = true (AI repos nest deeply)'
        }
    }
    $lp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction SilentlyContinue).LongPathsEnabled
    if ($lp -eq 1) { Ok 'LongPathsEnabled already 1' }
    elseif ($isAdmin) {
        if ($PSCmdlet.ShouldProcess('HKLM FileSystem\LongPathsEnabled', 'set 1')) {
            Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Ok 'LongPathsEnabled = 1 (needs reboot)'
        }
    }
    else { Warn 'LongPathsEnabled = 0 and not elevated - git core.longpaths covers git, but pip/HF caches prefer the machine setting' }

    $dev = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
    if ($dev -eq 1) { Ok 'developer mode already on' }
    elseif ($isAdmin) {
        if ($PSCmdlet.ShouldProcess('Developer Mode', 'enable (symlinks without elevation)')) {
            # Same hazard as the tune loop below: -Force on an existing key wipes its values.
            $amKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
            if (-not (Test-Path $amKey)) { New-Item -Path $amKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Ok 'developer mode enabled (needed by HF cache / pnpm symlinks)'
        }
    }
    else { Warn 'developer mode off and not elevated - some AI tooling cannot create symlinks' }

    if ($isAdmin) { Ok 'elevated: machine-level changes are possible' } else { Warn 'not elevated: run as administrator for tune/long-paths/dev-mode' }

    $net = Test-Connection -ComputerName 'github.com' -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($net) { Ok 'github.com reachable' } else { Warn 'github.com not reachable - mirrors or a proxy are required'; $okAll = $false }

    $drive = (Get-Item $env:USERPROFILE).PSDrive
    $freeGB = [math]::Round((Get-PSDrive $drive.Name).Free / 1GB, 1)
    if ($freeGB -ge 30) { Ok "free space on $($drive.Name): $freeGB GB" } else { Warn "only $freeGB GB free - toolchain + apps + AI caches want 30 GB+"; $okAll = $false }

    $wu = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue)
    Ok "windows build $($wu.CurrentBuild).$($wu.UBR) (judge patch level by UBR, not Get-HotFix)"

    Record 'check' $okAll 'bootstrap: pwsh/scoop/git/7z/longpaths/devmode'
}