# Build FableSetup.exe - one self-contained installer for the fable system.
# Embeds the whole kit (SrcRoot) as a zip resource inside a tiny C# stub
# compiled with the .NET Framework csc.exe that every Windows box ships.
# No dependencies, no separate archive to manage.
#   pwsh -File tools\build-exe.ps1                          # SrcRoot = parent of tools\; OutFile = <repo root>\FableSetup.exe
#   pwsh -File tools\build-exe.ps1 -SrcRoot <kit> -OutFile <exe>
# Refuses a SrcRoot without kit-manifest.json: the exe must embed a kit that
# passes its own integrity gate, so regenerate the manifest (make-manifest.ps1)
# and run the selftest (run-selftest.ps1) before building.
param(
    [string]$SrcRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$OutFile = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FableSetup.exe')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path (Join-Path $SrcRoot 'install.ps1'))) { throw "not a kit root: '$SrcRoot' has no install.ps1" }
if (-not (Test-Path (Join-Path $SrcRoot 'kit-manifest.json'))) { throw "no kit-manifest.json in '$SrcRoot' - regenerate it first (tools\make-manifest.ps1): the exe must embed a gate-passing kit" }
# the manifest must be FRESH, not merely present - a stale one bakes an exe that fails its own gate
$mfChk = Get-Content (Join-Path $SrcRoot 'kit-manifest.json') -Raw | ConvertFrom-Json
foreach ($f in $mfChk.files) {
    $p = Join-Path $SrcRoot $f.path
    if (-not (Test-Path -LiteralPath $p)) { throw "manifest lists missing file '$($f.path)' - regenerate the manifest, run the selftest, then rebuild" }
    if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $f.sha256) { throw "manifest is stale for '$($f.path)' - regenerate with tools\make-manifest.ps1, run the selftest, then rebuild" }
}
# hard guarantee: private content never rides in the payload - the exe embeds SrcRoot verbatim,
# so a SrcRoot carrying a private\ or memory\ directory refuses to build at all
foreach ($forbidden in 'private', 'memory') {
    if (Test-Path (Join-Path $SrcRoot $forbidden)) { throw "SrcRoot contains a '$forbidden\' directory - private content never enters the exe payload; remove it, regenerate the manifest, and rebuild" }
}
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw "csc.exe not found under $env:WINDIR\Microsoft.NET - .NET Framework 4.x is required to build (it ships with Windows)" }
$stub = Join-Path $PSScriptRoot 'setup-stub.cs'
if (-not (Test-Path $stub)) { throw "setup-stub.cs missing beside build-exe.ps1" }

$work = Join-Path $env:TEMP ("fable-build-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
try {
    $payload = Join-Path $work 'payload.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($SrcRoot, $payload)

    # payload sanity before it gets baked in: every entry CRC-reads to the end
    $z = [IO.Compression.ZipFile]::OpenRead($payload)
    $buf = New-Object byte[] 81920
    $entries = 0
    foreach ($e in $z.Entries) { $s = $e.Open(); while (($s.Read($buf, 0, $buf.Length)) -gt 0) {}; $s.Dispose(); $entries++ }
    $hasInstaller = ($z.Entries.FullName -contains 'install.ps1') -and ($z.Entries.FullName -contains 'kit-manifest.json')
    $z.Dispose()
    if (-not $hasInstaller) { throw "payload zip missing install.ps1/kit-manifest.json at its root - CreateFromDirectory got the wrong SrcRoot?" }

    if (Test-Path $OutFile) { Remove-Item -LiteralPath $OutFile -Force }
    & $csc /nologo /target:exe ("/out:" + $OutFile) ("/resource:" + $payload + ",payload.zip") $stub
    if ($LASTEXITCODE -ne 0) { throw "csc failed (exit $LASTEXITCODE)" }
    Write-Host ("built {0} ({1:N0} bytes; payload {2} entries, CRC-read clean)" -f $OutFile, (Get-Item -LiteralPath $OutFile).Length, $entries)
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
