# verify-env section: rust - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

# --------------------------------------------------------------------- rust
if ($Languages -contains 'rust') {
    Write-Output "`n--- rust"
    if (-not (Have 'cargo')) {
        Record 'rust' 'present' $false 'cargo not on PATH'
    } else {
        Record 'rust' 'version' $true (& rustc --version 2>&1 | Select-Object -First 1)
        $tc = "$(& rustup show active-toolchain 2>$null)"
        Record 'rust' 'toolchain' $true "$tc"
        $proj = Join-Path $root 'rustproj'
        Push-Location $root
        & cargo new rustproj --quiet 2>&1 | Out-Null
        Push-Location $proj
        # rand pulls in getrandom, whose build script needs dlltool on the GNU target -
        # this is precisely the case that fails with a misleading error when binutils
        # is missing, so it is the right smoke test rather than an empty crate.
        $add = & cargo add rand --quiet 2>&1 | Select-Object -Last 1
        Record 'rust' 'cargo add' ($LASTEXITCODE -eq 0) "$add"
        @'
fn main() {
    let n: u32 = rand::random();
    println!("cargo build+run ok {}", n % 1000);
}
'@ | Set-Content -Path 'src\main.rs' -Encoding UTF8
        $build = & cargo build 2>&1 | Select-Object -Last 1
        Record 'rust' 'build (with deps)' ($LASTEXITCODE -eq 0) "$build"
        if ($LASTEXITCODE -eq 0) {
            $run = & cargo run --quiet 2>&1 | Select-Object -Last 1
            Record 'rust' 'run' ($LASTEXITCODE -eq 0) "$run"
        }
        Pop-Location
        Pop-Location
    }
}
