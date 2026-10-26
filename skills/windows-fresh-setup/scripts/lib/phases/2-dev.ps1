# Phase 'dev' - dot-sourced by setup.ps1 in execution order.
#
# The guard below ($phases -contains ...) is kept inside this file on purpose: dot-sourcing
# runs it in setup.ps1's own scope, so the block still sees that script's variables and
# helpers, and the phase only runs when it was selected.

if ($phases -contains 'dev') {
    Say '--- dev: toolchain + editors + AI mirrors ---' White
    $ok = $true

    # Only git here. 7-Zip used to be re-attempted in this phase too, which made two phases
    # own the same tool and neither of them prove it: the check phase already ensures it with a
    # winget fallback and a readback, so repeating a scoop-only install here just adds a second
    # way to report failure for the same missing binary.
    if (-not (Scoop-Install @('git'))) { $ok = $false }
    # Do NOT pass the package list through -File as a comma string: -File does not split
    # comma lists, so setup-langs would see one bogus package name and skip everything.
    # Install the requested packages here (array binding works in-process), then let
    # setup-langs.ps1 add its defaults plus the mirror configuration.
    if (-not (Scoop-Install $Languages)) { $ok = $false }
    if (-not (Invoke-Step 'setup-langs.ps1' @() 'languages (defaults) + mirrors + rust')) { $ok = $false }

    if (-not $NoEditor) {
        Scoop-Install @('extras') -Bucket | Out-Null
        if (-not (Scoop-Install @('extras/vscode', 'extras/windows-terminal'))) { Warn 'editor install failed - install VS Code manually from code.visualstudio.com if needed' }
    }
    else { Warn 'NoEditor: skipped VS Code + Windows Terminal' }

    if (-not (Invoke-Step 'fix-env.ps1' @() 'repair PATH, Store stubs, credential helper')) { $ok = $false }

    # AI-specific mirror. pip/npm/go/cargo mirrors are configured by setup-langs.ps1.
    if ($PSCmdlet.ShouldProcess('HF_ENDPOINT', 'set to https://hf-mirror.com (user)')) {
        [Environment]::SetEnvironmentVariable('HF_ENDPOINT', 'https://hf-mirror.com', 'User')
        Ok 'HF_ENDPOINT = https://hf-mirror.com  (HuggingFace downloads via the mirror)'
    }
    # Report what is ACTUALLY configured. Every mirror in setup-langs.ps1 is guarded by
    # "is this tool on PATH yet", so a toolchain that failed to install leaves the machine
    # only half-mirrored - while a hardcoded success line would still claim otherwise.
    # This was measured: nodejs failed to download, so `npm config set registry` never ran,
    # yet the summary still announced npm=registry.npmmirror.com. Read each one back.
    Warn 'mirror state (read back, not assumed):'
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if ($npmCmd) { Warn "  npm   -> $((& npm config get registry 2>&1 | Select-Object -First 1))" }
    else { Warn '  npm   -> NOT configured (npm not on PATH; install nodejs, then re-run -Phase dev)' }
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pyCmd) { Warn "  pip   -> $(((& python -m pip config get global.index-url 2>&1) | Select-Object -First 1))" }
    else { Warn '  pip   -> NOT configured (python not on PATH)' }
    $goCmd = Get-Command go -ErrorAction SilentlyContinue
    if ($goCmd) { Warn "  go    -> $((& go env GOPROXY 2>&1 | Select-Object -First 1))" }
    else { Warn '  go    -> NOT configured (go not on PATH)' }
    # cargo honours CARGO_HOME; scoop's rustup package points it at its own persist dir,
    # so ~/.cargo is NOT always where the config has to live.
    $cargoHome = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $env:USERPROFILE '.cargo' }
    if (Test-Path (Join-Path $cargoHome 'config.toml')) { Warn "  cargo -> rsproxy.cn  ($cargoHome\config.toml)" }
    else { Warn "  cargo -> NOT configured (no config.toml under $cargoHome; needs rust)" }
    Warn "  hf    -> $([Environment]::GetEnvironmentVariable('HF_ENDPOINT', 'User'))"
    Warn 'GPU stack (CUDA/torch) is vendor-specific and NOT automated - install the driver, then the matching torch build'
    Record 'dev' $ok 'toolchain + editors + mirrors'
    Warn 'open a NEW terminal afterwards: the current one still has the old PATH'
}