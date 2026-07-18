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
# normalize first (same reason as make-manifest.ps1): the unlisted-file sweep below derives each
# manifest key by chopping $SrcRoot off an ABSOLUTE FullName, and .NET's CreateFromDirectory
# resolves relative paths against the process CWD, not the PowerShell location. A relative
# -SrcRoot (which run-selftest.ps1 passes) otherwise mangles every key into a false stray.
if (-not (Test-Path -LiteralPath $SrcRoot)) { throw "SrcRoot not found: '$SrcRoot'" }
$SrcRoot = (Resolve-Path -LiteralPath $SrcRoot).Path.TrimEnd('\')
$OutFile = [IO.Path]::GetFullPath($OutFile, (Get-Location).Path)
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
# ...and the guarantee needs the REVERSE sweep too: the loop above only proves every
# LISTED file is present and fresh, while CreateFromDirectory below zips the directory
# verbatim - including hidden files, which make-manifest does not enumerate. Without
# this, an unlisted stray (a personal note, a desktop.ini) would ride into a published
# exe and every install from it would then fail the installer's own set-equality gate.
# Reparse points are the sweep's blind spot and must be refused BEFORE it runs:
# Get-ChildItem -Recurse does not traverse a junction/symlink, but the zip writer below
# DOES follow it - so a junction under SrcRoot smuggles its target's contents into the
# payload past both this sweep and the private\/memory\ check above (execution-proven
# 2026-07-18: enumerator saw 0 files, CreateFromDirectory zipped the linked file).
if ((Get-Item -LiteralPath $SrcRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw "SrcRoot '$SrcRoot' is itself a reparse point - build from the real directory"
}
foreach ($d in (Get-ChildItem -LiteralPath $SrcRoot -Recurse -Directory -Force)) {
    if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $rel = $d.FullName.Substring($SrcRoot.Length + 1)
        throw "REPARSE POINT in SrcRoot: '$rel' - a junction or symlink is followed by the zip writer but NOT by the integrity sweep, so its target would ride into the exe unlisted. Remove it and rebuild"
    }
}
$listed = @{}
foreach ($f in $mfChk.files) { $listed[$f.path.ToLowerInvariant()] = $true }
foreach ($onDisk in (Get-ChildItem -LiteralPath $SrcRoot -Recurse -File -Force)) {
    $rel = $onDisk.FullName.Substring($SrcRoot.Length + 1)
    if ($rel -eq 'kit-manifest.json') { continue }   # the manifest never lists itself
    if (-not $listed.ContainsKey($rel.ToLowerInvariant())) {
        throw "UNLISTED FILE in SrcRoot: '$rel' is not in kit-manifest.json - it would be embedded in the exe and then refused by the installer's integrity gate. Remove the stray (or regenerate the manifest if it is genuine kit content), then rebuild"
    }
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
