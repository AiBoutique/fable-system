# make-manifest.ps1 - regenerate kit-manifest.json over every file in the kit
# (except the manifest itself). Run from anywhere:
#   powershell -File tools\make-manifest.ps1 -KitRoot <kit folder> -KitVersion r6
param(
    [Parameter(Mandatory = $true)][string]$KitRoot,
    [Parameter(Mandatory = $true)][string]$KitVersion
)
$ErrorActionPreference = 'Stop'
# normalize first: a relative or trailing-backslash -KitRoot would silently corrupt
# every manifest path (Substring arithmetic below assumes an absolute, clean root)
$KitRoot = (Resolve-Path -LiteralPath $KitRoot).Path.TrimEnd('\')
function Get-Sha256([string]$p) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fs = [System.IO.File]::OpenRead($p)
        try { return ([System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '') }
        finally { $fs.Dispose() }
    } finally { $sha.Dispose() }
}
# No -Force here, deliberately: hidden files stay unlisted so build-exe.ps1's reverse
# sweep (which DOES use -Force) refuses them loudly instead of shipping them listed.
# Exclusion is by full path: a NESTED file named kit-manifest.json is kit content and
# must be listed, or it installs as an UNLISTED refusal (r31).
$paths = @(Get-ChildItem $KitRoot -Recurse -File |
    Where-Object { $_.FullName -ne (Join-Path $KitRoot 'kit-manifest.json') } |
    ForEach-Object { $_.FullName })
# ordinal sort: a culture-sensitive Sort-Object can order the same names differently
# across locales, producing spurious manifest diffs for identical trees
[System.Array]::Sort($paths, [System.StringComparer]::Ordinal)
$files = foreach ($p in $paths) {
        $fi = Get-Item -LiteralPath $p
        New-Object PSObject -Property @{
            path   = $fi.FullName.Substring($KitRoot.Length + 1)
            sha256 = Get-Sha256 $fi.FullName
            bytes  = $fi.Length
        }
    }
$claudeVer = ''
try { $claudeVer = ((& claude --version) 2>$null | Out-String).Trim() } catch { }
$doc = New-Object PSObject -Property @{
    kitVersion = $KitVersion
    builtAt    = (Get-Date -Format 'yyyy-MM-dd')
    builtWith  = $claudeVer
    files      = @($files | Select-Object path, sha256, bytes)
}
$json = ConvertTo-Json -InputObject $doc -Depth 8
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $KitRoot 'kit-manifest.json'), $json, $enc)
Write-Host "manifest: $(@($files).Count) files, kit $KitVersion"
