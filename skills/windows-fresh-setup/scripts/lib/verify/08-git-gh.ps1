# verify-env section: git/gh - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

# ------------------------------------------------------------------ git/gh
Write-Output "`n--- supporting tools"
if (Have 'git') { Record 'git' 'version' $true (& git --version 2>&1 | Select-Object -First 1) }
else { Record 'git' 'present' $false 'git not on PATH' }
if (Have 'gh') { Record 'gh' 'version' $true (& gh --version 2>&1 | Select-Object -First 1) }
else { Record 'gh' 'present' $false 'gh not on PATH (optional)' -Optional }
if (Have 'ssh') {
    $sshOut = & ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -T git@github.com 2>&1
    $authed = "$sshOut" -match 'successfully authenticated'
    $sshDetail = if ($authed) { "$sshOut" } else { 'no SSH key on the account; git over HTTPS or gh auth also work - informational only' }
    # SSH access is one of several ways to authenticate. Its absence is a configuration
    # choice, not a broken toolchain, so it must not fail the whole verification.
    Record 'ssh' 'github auth' $authed $sshDetail -Optional
}
