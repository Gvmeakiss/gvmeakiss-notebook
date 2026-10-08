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
  Logical languages to ensure. Default: python node go cmake dotnet mingw
  Accepted: python node go rust java cmake dotnet mingw

.PARAMETER SkipMirrors
  Do not write package-manager mirror configuration.

.PARAMETER SkipRust
  Do not install the Rust toolchain even if 'rust' is requested.

.EXAMPLE
  pwsh -File setup-langs.ps1
  pwsh -File setup-langs.ps1 -Packages python,node,go

.NOTES
  Requires Scoop. See the README for the bootstrap step.
  ASCII-only on purpose.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$Packages = @('python','node','go','cmake','dotnet','mingw'),
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
if (-not $scoop) {
    Fail2 'scoop not found. Install it first (see README "Bootstrap"):'
    Write-Output "            Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    Write-Output "            irm get.scoop.sh | iex"
    exit 1
}
Ok "scoop: $($scoop.Source)"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Warn2 'git not on PATH - scoop needs git for its buckets'
}

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
        $env:RUSTUP_DIST_SERVER = if ($env:RUSTUP_DIST_SERVER) { $env:RUSTUP_DIST_SERVER } else { 'https://rsproxy.cn' }
        $env:RUSTUP_UPDATE_ROOT = if ($env:RUSTUP_UPDATE_ROOT) { $env:RUSTUP_UPDATE_ROOT } else { 'https://rsproxy.cn/rustup' }
        [Environment]::SetEnvironmentVariable('RUSTUP_DIST_SERVER', $env:RUSTUP_DIST_SERVER, 'User')
        [Environment]::SetEnvironmentVariable('RUSTUP_UPDATE_ROOT', $env:RUSTUP_UPDATE_ROOT, 'User')
        Ok "RUSTUP_DIST_SERVER=$env:RUSTUP_DIST_SERVER"

        $dl = Join-Path $env:TEMP 'rustup-init.exe'
        $url = "$env:RUSTUP_DIST_SERVER/rustup/dist/x86_64-pc-windows-gnu/rustup-init.exe"
        if ($Cmdlet.ShouldProcess($url, 'download rustup-init')) {
            try {
                Invoke-WebRequest -Uri $url -OutFile $dl -TimeoutSec 300 -UseBasicParsing -ErrorAction Stop
                Ok "downloaded rustup-init ($([math]::Round((Get-Item $dl).Length/1MB,1)) MB)"
            } catch {
                Fail2 "download failed: $($_.Exception.Message.Split("`n")[0])"
                Write-Output '            fallback mirrors: https://mirrors.ustc.edu.cn/rust-static/rustup/dist/x86_64-pc-windows-gnu/rustup-init.exe'
            }
        }
        if (Test-Path $dl) {
            if ($Cmdlet.ShouldProcess('rustup-init', 'install stable GNU toolchain')) {
                & $dl -y --no-modify-path --default-host x86_64-pc-windows-gnu `
                      --default-toolchain stable --profile default 2>&1 |
                    Select-Object -Last 3 | ForEach-Object { "            $_" }
                $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
                $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
                if (@($userPath -split ';') -notcontains $cargoBin) {
                    [Environment]::SetEnvironmentVariable('Path', "$cargoBin;$userPath", 'User')
                    Ok "added $cargoBin to user PATH"
                }
                if (Test-Path (Join-Path $cargoBin 'rustc.exe')) { Ok 'rustc installed' } else { Fail2 'rustc not found after install' }
            }
        }
    }
    # cargo registry mirror
    if (-not $SkipMirrors) {
        $cargoDir = Join-Path $env:USERPROFILE '.cargo'
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
    $env:PATH = "$env:USERPROFILE\scoop\shims;$env:USERPROFILE\.cargo\bin;$env:PATH"

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
