# verify-env section: java - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

# --------------------------------------------------------------------- java
if ($Languages -contains 'java') {
    Write-Output "`n--- java"
    if (-not (Have 'javac')) {
        Record 'java' 'present' $false 'javac not on PATH'
    } else {
        Record 'java' 'version' $true (& javac -version 2>&1 | Select-Object -First 1)
        $proj = Join-Path $root 'javaproj'
        New-Item -ItemType Directory -Force -Path $proj | Out-Null
        @'
public class Hello {
    public static void main(String[] args) {
        System.out.println("javac+java ok " + System.getProperty("java.version"));
    }
}
'@ | Set-Content -Path (Join-Path $proj 'Hello.java') -Encoding UTF8
        Push-Location $proj
        & javac Hello.java 2>&1 | Out-Null
        $compiled = ($LASTEXITCODE -eq 0)
        Record 'java' 'javac' $compiled ''
        if ($compiled) {
            $run = & java -cp . Hello 2>&1 | Select-Object -Last 1
            Record 'java' 'run' ($LASTEXITCODE -eq 0) "$run"
            & jar --create --file hello.jar --main-class Hello Hello.class 2>&1 | Out-Null
            if (Test-Path 'hello.jar') {
                $jr = & java -jar hello.jar 2>&1 | Select-Object -Last 1
                # Running the jar is the check; the file merely existing proves packaging only.
                Record 'java' 'jar' ($LASTEXITCODE -eq 0) "$jr"
            }
            else { Record 'java' 'jar' $false 'jar not created by jar --create' }
        }
        Pop-Location
    }
}
