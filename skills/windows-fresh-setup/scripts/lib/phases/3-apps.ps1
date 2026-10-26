# Phase 'apps' - dot-sourced by setup.ps1 in execution order.
#
# The guard below ($phases -contains ...) is kept inside this file on purpose: dot-sourcing
# runs it in setup.ps1's own scope, so the block still sees that script's variables and
# helpers, and the phase only runs when it was selected.

if ($phases -contains 'apps') {
    Say '--- apps: portable software (SHA256 verified) ---' White
    if (-not (Test-Path $Manifest)) {
        Bad "manifest not found: $Manifest"; Record 'apps' $false 'manifest missing'
    }
    else {
        # Optional entries in the manifest (e.g. the Markdown editor) are skipped by default;
        # the manifest's own notes say to ask the user first, so this flag is how that
        # intent gets expressed. See install-portable.ps1 for the mechanics.
        $ipArgs = @('-Manifest', $Manifest, '-Destination', $Destination)
        if ($IncludeOptionalApps) { $ipArgs += '-IncludeOptional' }
        $a = Invoke-Step 'install-portable.ps1' $ipArgs 'download, verify, unpack'
        Invoke-Step 'check-software.ps1' @('-PortableRoot', $Destination) 'inventory' | Out-Null
        Record 'apps' $a 'portable apps installed'
    }
}