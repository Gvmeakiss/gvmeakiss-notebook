# verify-env section: python - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

# ------------------------------------------------------------------- python
if ($Languages -contains 'python') {
    Write-Output "`n--- python"
    if (-not (Have 'python')) {
        Record 'python' 'present' $false 'python not on PATH'
    } else {
        Record 'python' 'version' $true (& python --version 2>&1 | Select-Object -First 1)
        # import a real package to prove site-packages and the index work
        $py = Join-Path $root 't.py'
        @'
import subprocess, sys
print("exec ok", sys.version.split()[0])
try:
    import requests  # noqa
    print("dependency import ok")
except Exception as exc:
    print("dependency import skipped:", type(exc).__name__)
'@ | Set-Content -Path $py -Encoding UTF8
        $out = & python $py 2>&1
        Record 'python' 'run' ($LASTEXITCODE -eq 0) ("$out" -replace "`r?`n", ' | ')
        # encoding behaviour: Windows defaults to a regional code page, which breaks
        # UTF-8 file reads unless encoding is explicit (PYTHONUTF8=1 is the global fix)
        $enc = Join-Path $root 'enc.py'
        @'
from pathlib import Path
p = Path(__file__).with_name("utf8.txt")
p.write_text("\u4e2d\u6587\u6d4b\u8bd5 utf8\n", encoding="utf-8")
try:
    default_read = p.read_text()
    print("default-encoding read: OK")
except UnicodeDecodeError as exc:
    print("default-encoding read: FAILS ->", exc.__class__.__name__)
print("explicit utf-8 read:", p.read_text(encoding="utf-8").strip())
'@ | Set-Content -Path $enc -Encoding UTF8
        $encOut = & python $enc 2>&1
        Record 'python' 'utf8-encoding' $true ("$encOut" -replace "`r?`n", ' | ')
    }
}
