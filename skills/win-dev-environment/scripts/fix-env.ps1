<#
.SYNOPSIS
  Repair the recurring Windows development-environment defects, user-level only.

.DESCRIPTION
  Each check is a defect observed in the field that produces a *misleading* symptom -
  the tool looks missing or "not installed" when it is in fact present and misconfigured.
  The script is idempotent: safe to run repeatedly.

  Every action is printed and, with -WhatIf, only simulated. Nothing is ever deleted
  outside the specific stubs listed below.

.PARAMETER WhatIf
  Print the intended actions without performing them.

.PARAMETER SkipAliasRemoval
  Do not remove Microsoft Store "App Execution Alias" stubs.

.PARAMETER SkipCredentialFix
  Do not touch git credential configuration.

.EXAMPLE
  pwsh -File fix-env.ps1 -WhatIf
  pwsh -File fix-env.ps1

.NOTES
  User-level only: no elevation required, no machine-wide registry writes.
  ASCII-only on purpose.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipAliasRemoval,
    [switch]$SkipCredentialFix
)

$ErrorActionPreference = 'Continue'
$script:changed = 0
$script:checked = 0

# $PSCmdlet only exists inside functions that declare [CmdletBinding()]. Helper functions
# here are plain functions, so they capture this reference instead of $PSCmdlet - calling
# .ShouldProcess() on a null $PSCmdlet fails silently under $ErrorActionPreference='Continue'.
$Cmdlet = $PSCmdlet

# A GUI/agent parent process may have been started before PATH was configured, so its
# inherited environment can be stale: commands that ARE installed look missing. Rebuild
# the process PATH from the registry (Machine + User) so every probe sees the real state.
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPathRaw = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:PATH = (@($machinePath, $userPathRaw) | Where-Object { $_ }) -join ';'

function Step  { param([string]$Msg) Write-Output "`n--- $Msg" }
function Ok    { param([string]$Msg) Write-Output "    ok      $Msg" }
function Note  { param([string]$Msg) Write-Output "    note    $Msg" }
function Fix   { param([string]$Msg) $script:changed++; Write-Output "    FIXED   $Msg" }
function Skip  { param([string]$Msg) Write-Output "    skip    $Msg" }
function Would { param([string]$Msg) $script:changed++; Write-Output "    WOULD   $Msg" }

function Set-UserPathEntry {
    param([string]$Path, [string]$Position = 'prepend')
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($current -split ';' | Where-Object { $_ })
    if ($parts -contains $Path) {
        Ok "already on user PATH: $Path"
    } else {
        $new = if ($Position -eq 'prepend') { @($Path) + $parts } else { $parts + @($Path) }
        if ($Cmdlet.ShouldProcess("User PATH", "add $Path")) {
            [Environment]::SetEnvironmentVariable('Path', ($new -join ';'), 'User')
            Fix "added to user PATH: $Path"
        } else { Would "add to user PATH: $Path" }
    }
}

function Remove-StalePathEntry {
    param([string]$Path)
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($current -split ';' | Where-Object { $_ })
    if ($parts -notcontains $Path) { return }
    if ($Cmdlet.ShouldProcess("User PATH", "remove $Path")) {
        [Environment]::SetEnvironmentVariable('Path', (($parts | Where-Object { $_ -ne $Path }) -join ';'), 'User')
        Fix "removed stale user PATH entry: $Path"
    } else { Would "remove stale user PATH entry: $Path" }
}

function Broadcast-EnvironmentChange {
    if ($Cmdlet.ShouldProcess('Explorer', 'broadcast WM_SETTINGCHANGE')) {
        try {
            $sig = @'
using System;
using System.Runtime.InteropServices;
public class EnvBroadcast {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam,
      string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
'@
            if (-not ('EnvBroadcast' -as [type])) { Add-Type -TypeDefinition $sig -ErrorAction Stop }
            $res = [UIntPtr]::Zero
            [void][EnvBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero,
                'Environment', 2, 5000, [ref]$res)
            Ok 'broadcast environment change to running processes'
        } catch {
            Note "could not broadcast (new shells still pick it up): $($_.Exception.Message)"
        }
    }
}

Write-Output '===== fix-env: Windows development environment repair ====='
if ($WhatIfPreference) { Write-Output 'DRY RUN (-WhatIf): nothing will be changed' }

# --------------------------------------------------------------- 1. scoop shims
Step '1. Scoop shims on PATH'
# Scoop installs every command into <root>\shims. If that directory is absent from the
# user PATH, every scoop-installed tool reports "not recognized" while being installed -
# the single most common false "missing toolchain" report.
$scoopRoot = Join-Path $env:USERPROFILE 'scoop'
$shims = Join-Path $scoopRoot 'shims'
if (Test-Path $shims) {
    Set-UserPathEntry -Path $shims -Position 'prepend'
} else {
    Skip "no scoop installation at $scoopRoot"
}

# ------------------------------------------------- 2. Store app-execution aliases
Step '2. Microsoft Store App Execution Alias stubs'
# Windows ships 0-byte reparse points named python.exe / python3.exe in WindowsApps.
# They win over any PATH entry, so a correctly installed Python still prints
# "Python was not found but can be installed from the Microsoft Store".
if ($SkipAliasRemoval) {
    Skip 'disabled by -SkipAliasRemoval'
} else {
    $winApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    $stubs = @('python.exe', 'python3.exe', 'python3.7.exe')
    $found = @()
    foreach ($n in $stubs) {
        $p = Join-Path $winApps $n
        if (Test-Path $p) {
            $item = Get-Item $p -Force -ErrorAction SilentlyContinue
            $isReparse = $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
            if ($isReparse -or ($item -and $item.Length -eq 0)) {
                $found += $p
            } else {
                Note "not a stub, leaving alone: $p"
            }
        }
    }
    if ($found.Count -eq 0) {
        Ok 'no python Store stubs present'
    } else {
        foreach ($p in $found) {
            if ($Cmdlet.ShouldProcess($p, 'remove App Execution Alias stub')) {
                try {
                    Remove-Item $p -Force -ErrorAction Stop
                    Fix "removed Store stub: $(Split-Path $p -Leaf)"
                } catch {
                    Note "could not remove $p : $($_.Exception.Message)"
                }
            } else { Would "remove Store stub: $(Split-Path $p -Leaf)" }
        }
    }
    # Real python shim must exist; scoop manifests sometimes create only python3.
    $pyExe = Join-Path $scoopRoot 'apps\python\current\python.exe'
    $pyShim = Join-Path $shims 'python.exe'
    if ((Test-Path $pyExe) -and -not (Test-Path $pyShim)) {
        if ($Cmdlet.ShouldProcess($pyShim, 'create python shim')) {
            $scoopCmd = Join-Path $shims 'scoop.cmd'
            if (Test-Path $scoopCmd) {
                & $scoopCmd shim add python $pyExe 2>&1 | ForEach-Object { "            $_" }
                if (Test-Path $pyShim) { Fix 'created python shim' } else { Note 'scoop shim add did not produce python.exe' }
            } else { Note "scoop.cmd not found; create the shim manually: $pyShim -> $pyExe" }
        } else { Would "create python shim -> $pyExe" }
    } elseif (Test-Path $pyShim) {
        Ok 'python shim present'
    }
}

# --------------------------------------------------------- 3. stale PATH entries
Step '3. Stale / duplicate PATH entries'
$userParts = @(([Environment]::GetEnvironmentVariable('Path', 'User')) -split ';' | Where-Object { $_ })
$dupNames = @($userParts | Group-Object | Where-Object Count -gt 1 | ForEach-Object { $_.Name })
foreach ($d in $dupNames) {
    Note "duplicate user PATH entry (left as-is, harmless): $d"
}
$dead = @($userParts | Where-Object { -not (Test-Path $_) })
# Two of these are standard tool directories that only appear after first use.
$expectedLater = @(
    (Join-Path $env:USERPROFILE 'go\bin'),
    (Join-Path $env:USERPROFILE '.dotnet\tools')
)
foreach ($p in $dead) {
    if ($expectedLater -contains $p) {
        if ($Cmdlet.ShouldProcess($p, 'create standard tool directory')) {
            New-Item -ItemType Directory -Force -Path $p | Out-Null
            Fix "created standard tool directory: $($p.Replace($env:USERPROFILE,'~'))"
        } else { Would "create standard tool directory: $($p.Replace($env:USERPROFILE,'~'))" }
    } else {
        Note "PATH entry does not exist: $p"
    }
}
# pip console scripts land in the scoop persist dir, which is not on PATH by default.
$pipScripts = Join-Path $scoopRoot 'persist\python\Scripts'
if (Test-Path $pipScripts) { Set-UserPathEntry -Path $pipScripts -Position 'prepend' }

# ------------------------------------------------------------ 4. missing dirs
Step '4. Standard tool directories'
foreach ($p in @(
    (Join-Path $env:USERPROFILE 'go\bin'),
    (Join-Path $env:USERPROFILE '.dotnet\tools')
)) {
    if (Test-Path $p) { Ok "exists: $($p.Replace($env:USERPROFILE,'~'))" }
    elseif ($Cmdlet.ShouldProcess($p, 'create directory')) {
        New-Item -ItemType Directory -Force -Path $p | Out-Null
        Fix "created: $($p.Replace($env:USERPROFILE,'~'))"
    } else { Would "create: $($p.Replace($env:USERPROFILE,'~'))" }
}

# --------------------------------------------------- 5. git credential hygiene
Step '5. Git credential helper configuration'
# `git-credential-manager configure` can leave behind an EMPTY credential.helper entry
# plus a quoting-broken absolute path. An empty entry makes git ignore the real helper
# and fall back to interactive prompting, which looks like "credentials are broken".
if ($SkipCredentialFix) {
    Skip 'disabled by -SkipCredentialFix'
} else {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        Skip 'git not on PATH'
    } else {
        $helpers = @(& git config --global --get-all credential.helper 2>$null)
        $empties = @($helpers | Where-Object { $_ -eq '' -or $_ -eq $null })
        $broken  = @($helpers | Where-Object { $_ -match '\\\s' -or $_ -match '^[A-Za-z]:/.*\\\\' })
        Write-Output "    current credential.helper entries: $($helpers.Count)"
        foreach ($h in $helpers) { Write-Output "      [$h]" }
        if ($empties.Count -gt 0) {
            Note 'empty credential.helper entry present - it makes git ignore the real helper'
            Write-Output '          remove it with: git config --global --unset-all credential.helper   (then re-add the intended one)'
        }
        if ($broken.Count -gt 0) {
            Note "quoting-broken credential.helper path: $($broken -join ', ')"
            Write-Output '          remove it with: git config --global --unset-all credential.helper'
        }
        if ($empties.Count -eq 0 -and $broken.Count -eq 0) { Ok 'credential.helper looks sane' }

        # system-level file is a separate trap and is easy to miss
        $sysCfg = Join-Path (Split-Path (Split-Path $git.Source -Parent) -Parent) 'etc\gitconfig'
        if (Test-Path $sysCfg) {
            $sysHelpers = @(& git config --system --get-all credential.helper 2>$null)
            $sysEmpty = @($sysHelpers | Where-Object { $_ -eq '' -or $_ -eq $null })
            if ($sysEmpty.Count -gt 0) {
                Note "system gitconfig has an empty credential.helper: $sysCfg"
                Write-Output "          remove it with: git config --system --unset-all credential.helper"
            } else { Ok 'system gitconfig credential.helper looks sane' }
        }
    }
}

# ------------------------------------------------------- 6. Rust GNU binutils
Step '6. Rust GNU target prerequisites (dlltool)'
# rustc for x86_64-pc-windows-gnu invokes dlltool while linking proc-macro crates.
# Missing it fails deep inside a dependency build with a misleading message:
#   error calling dlltool 'dlltool.exe': program not found
$rustup = Get-Command rustup -ErrorAction SilentlyContinue
if (-not $rustup) {
    Skip 'rustup not installed'
} else {
    $hostLine = "$(& rustup show active-toolchain 2>$null)"
    Write-Output "    active toolchain: $hostLine"
    if ($hostLine -match 'windows-gnu') {
        $dlltool = Get-Command dlltool -ErrorAction SilentlyContinue
        if ($dlltool) {
            Ok "dlltool available: $($dlltool.Source)"
        } else {
            Note 'GNU toolchain active but dlltool NOT on PATH - GNU Rust linking will fail'
            Write-Output '          install a MinGW binutils distribution (e.g. scoop install mingw) so dlltool.exe is on PATH'
        }
    } else {
        Ok 'MSVC toolchain - dlltool not required'
    }
}

# ---------------------------------------------------------------- broadcast
Step '7. Notify running processes'
Broadcast-EnvironmentChange

Write-Output "`n===== summary ====="
Write-Output "checks run: $script:checked"
Write-Output "changes:    $script:changed"
if ($WhatIfPreference) { Write-Output 'DRY RUN - re-run without -WhatIf to apply' }
Write-Output 'Already-open terminals keep their old environment; open a new one.'
