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
$files = Get-ChildItem $KitRoot -Recurse -File |
    Where-Object { $_.Name -ne 'kit-manifest.json' } |
    Sort-Object FullName |
    ForEach-Object {
        New-Object PSObject -Property @{
            path   = $_.FullName.Substring($KitRoot.Length + 1)
            sha256 = Get-Sha256 $_.FullName
            bytes  = $_.Length
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
