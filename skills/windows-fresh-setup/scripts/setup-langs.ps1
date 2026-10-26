<#
.SYNOPSIS
  Install common language toolchains on Windows, user-level, and point their package
  managers at China-accessible mirrors.

.DESCRIPTION
  Uses Scoop (user-level, no elevation) as the installation channel. A non-admin account
  cannot install machine-wide MSIs, so anything requiring elevation is deliberately routed
  to a user-level equivalent - most notably Rust, which would need the MSVC build tools
  (admin) for its default target and instead uses the GNU target backed by MinGW.

  Idempotent: already-installed packages are skipped by scoop itself.

.PARAMETER Packages
  Logical languages to ensure. Default: python node go rust cmake dotnet mingw uv
  Accepted: python node go rust java cmake dotnet mingw uv
  rust is in the default set on purpose: SKILL.md lists it as part of the toolchain and
  verify-env.ps1 checks it, so leaving it out made a default run fail its own acceptance
  test. Skip it with -SkipRust if you do not want the ~1 GB download.

.PARAMETER SkipMirrors
  Do not write package-manager mirror configuration.

.PARAMETER SkipRust
  Do not install the Rust toolchain even if 'rust' is requested.

.EXAMPLE
  pwsh -File setup-langs.ps1
  pwsh -File setup-langs.ps1 -Packages python,node,go

.NOTES
  Requires Scoop. Scoop is installed by `setup.ps1 -Phase check`, so a standalone run on a
  machine without it reports a precondition failure - see README section 4.1.
  ASCII-only on purpose.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$Packages = @('python','node','go','rust','cmake','dotnet','mingw','uv'),
    [switch]$SkipMirrors,
    [switch]$SkipRust
)

$ErrorActionPreference = 'Continue'
$script:failures = @()

# $PSCmdlet only exists inside functions that declare [CmdletBinding()]. Helper functions
# here are plain functions, so they capture this reference instead of $PSCmdlet - calling
# .ShouldProcess() on a null $PSCmdlet fails silently under $ErrorActionPreference='Continue'.
$Cmdlet = $PSCmdlet

# Rebuild PATH from the registry (Machine + User): a GUI/agent parent can carry a stale
# environment in which already-installed tools appear missing.
$env:PATH = (@(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User')
) | Where-Object { $_ }) -join ';'

function Step { param([string]$M) Write-Output "`n===== $M" }
function Ok   { param([string]$M) Write-Output "    ok      $M" }
function Warn2{ param([string]$M) Write-Output "    WARN    $M" }
function Fail2{ param([string]$M) $script:failures += $M; Write-Output "    FAIL    $M" }

Write-Output '===== setup-langs: user-level toolchain bootstrap ====='

# ---------------------------------------------------------------- preconditions
Step '0. Preconditions'
$scoop = Get-Command scoop -ErrorAction SilentlyContinue
if (-not $scoop) {
    $shims = Join-Path $env:USERPROFILE 'scoop\shims'
    if (Test-Path (Join-Path $shims 'scoop.cmd')) {
        $env:PATH = "$shims;$env:PATH"
        $scoop = Get-Command scoop -ErrorAction SilentlyContinue
    }
}
# -WhatIf must survive a missing precondition: a dry run exists to show what WOULD happen,
# so hard-exiting here made `-WhatIf` unusable on a fresh machine - which is exactly the
# machine a dry run is for. (Measured: `setup-langs.ps1 -WhatIf` exited 1 with
# "scoop not found" before printing a single planned action.) In a real run the missing
# dependency still fails, and the exit code at the end reports it.
$scoopAvailable = [bool]$scoop
$scoopSource = '(not found)'
if ($scoopAvailable) { $scoopSource = $scoop.Source }

if (-not $scoopAvailable) {
    Fail2 'scoop not found - cannot install toolchains. Install it first:'
    Write-Output "            Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    Write-Output "            irm get.scoop.sh | iex"
    if (-not $WhatIfPreference) { exit 1 }
    Write-Output '            (-WhatIf: continuing so the remaining planned actions are still shown)'
} else {
    Ok "scoop: $scoopSource"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Warn2 'git not on PATH - scoop needs git for its buckets'
}

# Without scoop, every scoop call site below would dereference a null command. Skip the
# blocks that need it instead of failing one line at a time with unhelpful errors.
# Under -WhatIf the planned actions are still listed, because a preview that shows nothing
# is not a preview - and scoop is installed by `setup.ps1 -Phase check`, so on a fresh
# machine the missing dependency is expected rather than exceptional.
if (-not $scoopAvailable) {

# ---------------------------------------------------------------- buckets
Step '1. Buckets'
foreach ($b in @('main', 'extras', 'java')) {
    Warn2 "would add bucket $b (cannot check: scoop unavailable)"
}

# ---------------------------------------------------------------- install
Step '2. Install toolchains'
$map = [ordered]@{
    python = @('python')
    node   = @('nodejs')
    go     = @('go')
    java   = @('temurin21-jdk')
    cmake  = @('cmake')
    dotnet = @('dotnet-sdk')
    mingw  = @('mingw')
    uv     = @('uv')
}
foreach ($p in $Packages) {
    if ($p -eq 'rust') { continue }
    if (-not $map.Contains($p)) { Warn2 "unknown package '$p' - skipped"; continue }
    foreach ($pkg in $map[$p]) {
        Warn2 "would scoop install $pkg (cannot install: scoop unavailable)"
    }
}

} else {

# ---------------------------------------------------------------- buckets
Step '1. Buckets'
foreach ($b in @('main', 'extras', 'java')) {
    $existing = @(& scoop bucket list 2>&1)
    if ($existing -match "(?m)^\s*$b\s") { Ok "bucket $b present" }
    elseif ($Cmdlet.ShouldProcess("bucket $b", 'add')) {
        & scoop bucket add $b 2>&1 | ForEach-Object { "            $_" }
    }
}

# ---------------------------------------------------------------- install
Step '2. Install toolchains'
$map = [ordered]@{
    python = @('python')
    node   = @('nodejs')
    go     = @('go')
    java   = @('temurin21-jdk')
    cmake  = @('cmake')
    dotnet = @('dotnet-sdk')
    mingw  = @('mingw')
    uv     = @('uv')
}
foreach ($p in $Packages) {
    if ($p -eq 'rust') { continue }
    if (-not $map.Contains($p)) { Warn2 "unknown package '$p' - skipped"; continue }
    foreach ($pkg in $map[$p]) {
        if ($Cmdlet.ShouldProcess($pkg, 'scoop install')) {
            Write-Output "    installing $pkg ..."
            & scoop install $pkg 2>&1 | Select-Object -Last 4 | ForEach-Object { "            $_" }
            if ($LASTEXITCODE -eq 0) { Ok "$pkg installed" } else { Fail2 "$pkg install failed (exit $LASTEXITCODE)" }
        }
    }
}

}   # end of the "scoop is available" guard opened in step 0

# ---------------------------------------------------------------- rust
if (($Packages -contains 'rust') -and -not $SkipRust) {
    Step '3. Rust toolchain (user-level, GNU target)'
    # The scoop 'rust' manifest ships an MSI. MSI installs are machine-scoped and need
    # elevation, so on a non-admin account they fail or leave a broken install. rustup
    # installs entirely under the user profile instead, and the GNU target reuses the
    # MinGW binutils already installed above - no Visual Studio Build Tools required.
    if (Get-Command rustup -ErrorAction SilentlyContinue) {
        Ok 'rustup already present'
    } else {
        # China mirror for the distribution server; override for other regions.
        # SetEnvironmentVariable writes the USER environment, so it is a real change and needs a
        # ShouldProcess guard - a dry run must not leave RUSTUP_* behind in the user profile.
        $distServer = if ($env:RUSTUP_DIST_SERVER) { $env:RUSTUP_DIST_SERVER } else { 'https://rsproxy.cn' }
        $updateRoot = if ($env:RUSTUP_UPDATE_ROOT) { $env:RUSTUP_UPDATE_ROOT } else { 'https://rsproxy.cn/rustup' }
        if ($Cmdlet.ShouldProcess('user environment', "set RUSTUP_DIST_SERVER=$distServer and RUSTUP_UPDATE_ROOT=$updateRoot")) {
            $env:RUSTUP_DIST_SERVER = $distServer
            $env:RUSTUP_UPDATE_ROOT = $updateRoot
            [Environment]::SetEnvironmentVariable('RUSTUP_DIST_SERVER', $distServer, 'User')
            [Environment]::SetEnvironmentVariable('RUSTUP_UPDATE_ROOT', $updateRoot, 'User')
            Ok "RUSTUP_DIST_SERVER=$distServer"
        }
        else {
            Write-Output "    would   set RUSTUP_DIST_SERVER=$distServer / RUSTUP_UPDATE_ROOT=$updateRoot (user scope)"
        }

        # Per-run download directory. A fixed %TEMP%\rustup-init.exe may be a leftover from an
        # earlier partial or failed download, and the old code executed whatever file happened to
        # be at that path. A unique directory means the binary we run is the one we just fetched;
        # nothing is executed when the download fails.
        $dlDir = Join-Path $env:TEMP ('wfs-rustup-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        $dl = Join-Path $dlDir 'rustup-init.exe'
        $url = "$distServer/rustup/dist/x86_64-pc-windows-gnu/rustup-init.exe"
        $downloaded = $false
        if ($Cmdlet.ShouldProcess($url, 'download rustup-init')) {
            try {
                New-Item -ItemType Directory -Force -Path $dlDir -ErrorAction Stop | Out-Null
                Invoke-WebRequest -Uri $url -OutFile $dl -TimeoutSec 300 -UseBasicParsing -ErrorAction Stop
                $dlSize = (Get-Item -LiteralPath $dl).Length
                if ($dlSize -lt 1MB) { throw "download is only $dlSize bytes - treating it as truncated" }
                $downloaded = $true
                Ok "downloaded rustup-init ($([math]::Round($dlSize/1MB,1)) MB, per-run temp dir)"
            } catch {
                Fail2 "download failed: $($_.Exception.Message.Split("`n")[0])"
                Write-Output '            fallback mirrors: https://mirrors.ustc.edu.cn/rust-static/rustup/dist/x86_64-pc-windows-gnu/rustup-init.exe'
            }
        }
        if ($downloaded) {
            # Verify before executing: a valid Authenticode signature is the only check available
            # here (the manifest carries no hash for this download). An unsigned or invalid file
            # is never run, no matter how it got downloaded.
            try {
                $sig = Get-AuthenticodeSignature -LiteralPath $dl -ErrorAction Stop
                $sigOk = ($sig.Status -eq 'Valid')
                $sigWho = if ($sig.SignerCertificate) { ($sig.SignerCertificate.Subject -split ',')[0] } else { '(no signer)' }
            }
            catch { $sigOk = $false; $sigWho = "(signature check failed: $($_.Exception.Message.Split(""`n"")[0]))" }
            $dlHash = (Get-FileHash -LiteralPath $dl -Algorithm SHA256).Hash
            if (-not $sigOk) {
                Fail2 "rustup-init is not validly signed ($sigWho) - refusing to execute it"
                Fail2 "  sha256: $dlHash  url: $url"
                Warn2 'install rustup by hand from https://rustup.rs and re-run this phase'
                $downloaded = $false
            }
            else {
                Ok "rustup-init signature valid ($sigWho)"
            }
        }
        if ($downloaded) {
            if ($Cmdlet.ShouldProcess('rustup-init', 'install stable GNU toolchain')) {
                & $dl -y --no-modify-path --default-host x86_64-pc-windows-gnu `
                      --default-toolchain stable --profile default 2>&1 |
                    Select-Object -Last 3 | ForEach-Object { "            $_" }
                $cargoBin = if ($env:CARGO_HOME) { Join-Path $env:CARGO_HOME 'bin' } else { Join-Path $env:USERPROFILE '.cargo\bin' }
                $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
                if (@($userPath -split ';') -notcontains $cargoBin) {
                    [Environment]::SetEnvironmentVariable('Path', "$cargoBin;$userPath", 'User')
                    Ok "added $cargoBin to user PATH"
                }
                if (Test-Path (Join-Path $cargoBin 'rustc.exe')) { Ok 'rustc installed' } else { Fail2 'rustc not found after install' }
            }
        }
        # The per-run download directory is removed on every exit path: leaving a 20 MB
        # rustup-init.exe in %TEMP% is exactly what made the old fixed path dangerous.
        if ($dlDir -and (Test-Path -LiteralPath $dlDir)) { Remove-Item -LiteralPath $dlDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # cargo registry mirror
    if (-not $SkipMirrors) {
        # Honour CARGO_HOME. scoop's rustup package points CARGO_HOME at its own persist
        # directory, so ~\.cargo is not always where cargo actually reads config.toml -
        # writing the mirror to the wrong place is a silent no-op.
        $cargoDir = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $env:USERPROFILE '.cargo' }
        New-Item -ItemType Directory -Force -Path $cargoDir | Out-Null
        $cfg = Join-Path $cargoDir 'config.toml'
        if (-not (Test-Path $cfg)) {
            if ($Cmdlet.ShouldProcess($cfg, 'write cargo mirror config')) {
                @'
[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[registries.rsproxy]
index = "sparse+https://rsproxy.cn/index/"

[net]
git-fetch-with-cli = true
'@ | Set-Content -Path $cfg -Encoding UTF8
                Ok "wrote $cfg"
            }
        } else { Ok 'cargo config.toml already exists (left untouched)' }
    }
}

# ---------------------------------------------------------------- mirrors
if (-not $SkipMirrors) {
    Step '4. Package-manager mirrors'
    $cargoBinDir = if ($env:CARGO_HOME) { Join-Path $env:CARGO_HOME 'bin' } else { Join-Path $env:USERPROFILE '.cargo\bin' }
    $env:PATH = "$env:USERPROFILE\scoop\shims;$cargoBinDir;$env:PATH"

    if (Get-Command python -ErrorAction SilentlyContinue) {
        if ($Cmdlet.ShouldProcess('pip', 'set Tsinghua index-url')) {
            & python -m pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple 2>&1 | Out-Null
            & python -m pip config set global.trusted-host pypi.tuna.tsinghua.edu.cn 2>&1 | Out-Null
            Ok 'pip -> pypi.tuna.tsinghua.edu.cn'
        }
    }
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        if ($Cmdlet.ShouldProcess('npm', 'set npmmirror registry')) {
            & npm config set registry https://registry.npmmirror.com 2>&1 | Out-Null
            Ok 'npm -> registry.npmmirror.com'
        }
    }
    if (Get-Command go -ErrorAction Continue) {
        if ($Cmdlet.ShouldProcess('go', 'set goproxy.cn')) {
            & go env -w GOPROXY=https://goproxy.cn,direct 2>&1 | Out-Null
            & go env -w GOSUMDB=sum.golang.google.cn 2>&1 | Out-Null
            Ok 'go -> goproxy.cn'
        }
    }
    # NuGet mirror as a secondary source; primary stays nuget.org for correctness.
    $nugetCfg = Join-Path $env:APPDATA 'NuGet\NuGet.Config'
    if (-not (Test-Path $nugetCfg)) {
        if ($Cmdlet.ShouldProcess($nugetCfg, 'write NuGet sources')) {
            New-Item -ItemType Directory -Force -Path (Split-Path $nugetCfg -Parent) | Out-Null
            @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
    <add key="huawei" value="https://repo.huaweicloud.com/repository/nuget/v3/index.json" protocolVersion="3" />
  </packageSources>
</configuration>
'@ | Set-Content -Path $nugetCfg -Encoding UTF8
            Ok "wrote $nugetCfg"
        }
    } else { Ok 'NuGet.Config already exists (left untouched)' }
}

Write-Output "`n===== summary ====="
if ($script:failures.Count -eq 0) {
    Write-Output 'all requested packages installed and mirrors configured'
} else {
    Write-Output "failures ($($script:failures.Count)):"
    $script:failures | ForEach-Object { "  - $_" }
}
Write-Output 'Open a NEW terminal before using the tools, then run verify-env.ps1.'

# Exit code matters: setup.ps1 decides pass/fail from it (Invoke-Step tests $LASTEXITCODE),
# so returning 0 after printing "failures (3)" made a broken toolchain look like a clean run.
# Measured before this fix: the script had no exit statement at all and returned 0 whether or
# not every package installed.
if ($script:failures.Count -gt 0) { exit 1 }
exit 0